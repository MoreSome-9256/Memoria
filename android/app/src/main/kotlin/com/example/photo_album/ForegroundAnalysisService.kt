package com.example.photo_album

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class ForegroundAnalysisService : Service() {
    companion object {
        const val CHANNEL_ID = "memoria_analysis_channel"
        const val NOTIFICATION_ID = 42001
        const val TAG = "ForegroundAnalysis"
        const val METHOD_CHANNEL = "memoria/analysis"
        const val EVENT_CHANNEL = "memoria/analysis_progress"

        private var instance: ForegroundAnalysisService? = null
        fun getInstance(): ForegroundAnalysisService? = instance

        private const val ACTION_START = "com.example.photo_album.ACTION_START"
        private const val ACTION_PAUSE = "com.example.photo_album.ACTION_PAUSE"
        private const val ACTION_RESUME = "com.example.photo_album.ACTION_RESUME"
        private const val ACTION_CANCEL = "com.example.photo_album.ACTION_CANCEL"
        private const val ACTION_STOP = "com.example.photo_album.ACTION_STOP"
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val executor = Executors.newFixedThreadPool(4)
    private val tagCounts = ConcurrentHashMap<String, AtomicInteger>()
    private val activeTasks = ConcurrentHashMap<String, AtomicBoolean>()
    private val pauseFlags = ConcurrentHashMap<String, AtomicBoolean>()
    private val cancelFlags = ConcurrentHashMap<String, AtomicBoolean>()

    private var eventSink: EventChannel.EventSink? = null
    private var powerWakeLock: PowerManager.WakeLock? = null
    private val isRunning = AtomicBoolean(false)

    private data class TaskState(
        val taskId: String,
        val images: List<ImageEntry>,
        val totalCount: Int,
        val completedCount: AtomicInteger = AtomicInteger(0),
        val failedCount: AtomicInteger = AtomicInteger(0),
    )

    private data class ImageEntry(
        val imageId: String,
        val assetId: String?,
        val filePath: String?,
        val contentUri: String?,
    )

    private val tasks = ConcurrentHashMap<String, TaskState>()

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        Log.d(TAG, "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val taskId = intent.getStringExtra("taskId") ?: return START_STICKY
                handleStart(taskId)
            }
            ACTION_PAUSE -> {
                val taskId = intent.getStringExtra("taskId") ?: return START_STICKY
                handlePause(taskId)
            }
            ACTION_RESUME -> {
                val taskId = intent.getStringExtra("taskId") ?: return START_STICKY
                handleResume(taskId)
            }
            ACTION_CANCEL -> {
                val taskId = intent.getStringExtra("taskId") ?: return START_STICKY
                handleCancel(taskId)
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        instance = null
        powerWakeLock?.let {
            if (it.isHeld) it.release()
        }
        scope.cancel()
        executor.shutdown()
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
    }

    override fun onTimeout(startId: Int) {
        Log.w(TAG, "Service timeout for startId=$startId, saving state and stopping")
        for ((taskId, _) in tasks) {
            cancelFlags[taskId]?.set(true)
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    fun enqueueTask(
        taskId: String,
        images: List<Map<String, String?>>,
        methodChannel: MethodChannel,
    ) {
        val entries = images.map { img ->
            ImageEntry(
                imageId = img["imageId"] ?: "",
                assetId = img["assetId"],
                filePath = img["filePath"],
                contentUri = img["contentUri"],
            )
        }
        val task = TaskState(taskId, entries, entries.size)
        tasks[taskId] = task
        activeTasks[taskId] = AtomicBoolean(false)
        pauseFlags[taskId] = AtomicBoolean(false)
        cancelFlags[taskId] = AtomicBoolean(false)
        tagCounts[taskId] = AtomicInteger(0)

        Log.d(TAG, "Enqueued task $taskId with ${entries.size} images")
    }

    fun startTask(taskId: String, methodChannel: MethodChannel) {
        val task = tasks[taskId] ?: return
        if (!activeTasks[taskId]!!.compareAndSet(false, true)) return

        requestBatteryOptimizationExemption()
        acquireWakeLock()

        val notification = buildNotification("分析中...", 0, task.totalCount, taskId)
        startForeground(NOTIFICATION_ID, notification)
        isRunning.set(true)

        scope.launch {
            processTask(taskId, task, methodChannel)
        }
    }

    private suspend fun processTask(taskId: String, task: TaskState, channel: MethodChannel) {
        for (i in task.images.indices) {
            if (cancelFlags[taskId]?.get() == true) {
                sendProgress(taskId, task, channel, "cancelled")
                updateTaskStatus(taskId, "cancelled", channel)
                cleanupTask(taskId)
                return
            }

            while (pauseFlags[taskId]?.get() == true) {
                if (cancelFlags[taskId]?.get() == true) return
                delay(300)
            }

            val image = task.images[i]
            sendProgress(taskId, task, channel, "running", image.imageId)

            try {
                val result = processSingleImage(image)
                if (result != null) {
                    task.completedCount.incrementAndGet()
                    updateImageResult(taskId, image.imageId, "completed", result)
                } else {
                    task.failedCount.incrementAndGet()
                    updateImageResult(taskId, image.imageId, "failed", error = "Processing returned null")
                }
            } catch (e: Exception) {
                task.failedCount.incrementAndGet()
                updateImageResult(taskId, image.imageId, "failed", error = e.message ?: "Unknown error")
                Log.e(TAG, "Failed to process ${image.imageId}", e)
            }

            updateNotification(taskId, task)
        }

        val finalStatus = if (cancelFlags[taskId]?.get() == true) "cancelled"
            else if (task.failedCount.get() > 0) "completed_with_errors"
            else "completed"

        sendProgress(taskId, task, channel, finalStatus)
        updateTaskStatus(taskId, finalStatus, channel)
        cleanupTask(taskId)
    }

    private suspend fun processSingleImage(image: ImageEntry): String? {
        return withContext(Dispatchers.IO) {
            val uri = resolveImageUri(image)
            if (uri == null) {
                Log.w(TAG, "Could not resolve URI for ${image.imageId}")
                null
            } else {
                val resultMap = mapOf(
                    "imageId" to image.imageId,
                    "uri" to uri.toString(),
                    "processedAt" to System.currentTimeMillis().toString(),
                )
                com.google.gson.Gson().toJson(resultMap)
            }
        }
    }

    private fun resolveImageUri(image: ImageEntry): Uri? {
        if (image.contentUri != null) {
            return Uri.parse(image.contentUri)
        }
        if (image.filePath != null) {
            return Uri.fromFile(java.io.File(image.filePath))
        }
        return null
    }

    private fun sendProgress(
        taskId: String,
        task: TaskState,
        channel: MethodChannel,
        status: String,
        currentItemId: String? = null,
    ) {
        val completed = task.completedCount.get()
        val failed = task.failedCount.get()
        val total = task.totalCount
        val percent = if (total > 0) (completed + failed).toDouble() / total else 0.0

        val data = mapOf(
            "taskId" to taskId,
            "totalCount" to total,
            "completedCount" to completed,
            "failedCount" to failed,
            "currentItemId" to (currentItemId ?: ""),
            "percent" to percent,
            "status" to status,
        )

        GlobalScope.launch(Dispatchers.Main) {
            channel.invokeMethod("onProgress", data)
            eventSink?.success(data)
        }
    }

    private fun updateTaskStatus(taskId: String, status: String, channel: MethodChannel) {
        GlobalScope.launch(Dispatchers.Main) {
            channel.invokeMethod("onStatusChanged", mapOf("taskId" to taskId, "status" to status))
        }
    }

    private fun updateImageResult(
        taskId: String,
        imageId: String,
        status: String,
        resultJson: String? = null,
        error: String? = null,
    ) {
        GlobalScope.launch(Dispatchers.Main) {
            val data = mutableMapOf<String, Any>(
                "imageId" to imageId,
                "status" to status,
                "taskId" to taskId,
            )
            if (resultJson != null) data["resultJson"] = resultJson
            if (error != null) data["errorMessage"] = error
            try {
                val engine = FlutterEngineCache.getInstance().get("analysis_engine")
                if (engine != null) {
                    val channel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
                    channel.invokeMethod("onImageResult", data)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to send image result", e)
            }
        }
    }

    private fun cleanupTask(taskId: String) {
        activeTasks.remove(taskId)
        pauseFlags.remove(taskId)
        cancelFlags.remove(taskId)
        tagCounts.remove(taskId)

        if (activeTasks.isEmpty()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            isRunning.set(false)
            powerWakeLock?.let { if (it.isHeld) it.release() }
            stopSelf()
        }
    }

    private fun handleStart(taskId: String) {
        val engine = FlutterEngineCache.getInstance().get("analysis_engine")
        if (engine != null) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            startTask(taskId, channel)
        }
    }

    private fun handlePause(taskId: String) {
        pauseFlags[taskId]?.set(true)
    }

    private fun handleResume(taskId: String) {
        pauseFlags[taskId]?.set(false)
    }

    private fun handleCancel(taskId: String) {
        cancelFlags[taskId]?.set(true)
        pauseFlags[taskId]?.set(false)
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:$packageName")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try {
                startActivity(intent)
            } catch (e: Exception) {
                Log.w(TAG, "Cannot request battery optimization exemption", e)
            }
        }
    }

    private fun acquireWakeLock() {
        if (powerWakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            powerWakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "Memoria:AnalysisWakeLock"
            ).apply {
                setReferenceCounted(false)
                acquire(30 * 60 * 1000L)
            }
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "图片分析",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "后台图片分析任务进度"
            setShowBadge(false)
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(
        message: String,
        completed: Int,
        total: Int,
        taskId: String,
    ): Notification {
        val pauseIntent = Intent(this, ForegroundAnalysisService::class.java).apply {
            action = ACTION_PAUSE
            putExtra("taskId", taskId)
        }
        val cancelIntent = Intent(this, ForegroundAnalysisService::class.java).apply {
            action = ACTION_CANCEL
            putExtra("taskId", taskId)
        }
        val pausePendingIntent = PendingIntent.getService(
            this, 0, pauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val cancelPendingIntent = PendingIntent.getService(
            this, 1, cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val progress = if (total > 0) (completed * 100) / total else 0

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("图片分析中")
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_menu_gallery)
            .setProgress(100, progress, false)
            .setOngoing(true)
            .setSilent(true)
            .addAction(android.R.drawable.ic_media_pause, "暂停", pausePendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "取消", cancelPendingIntent)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun updateNotification(taskId: String, task: TaskState) {
        val completed = task.completedCount.get()
        val failed = task.failedCount.get()
        val total = task.totalCount
        val notification = buildNotification(
            "已完成 $completed/$total ($failed 失败)",
            completed, total, taskId
        )
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }
}
