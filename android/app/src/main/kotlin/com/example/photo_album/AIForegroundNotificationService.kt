package com.example.photo_album

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AIForegroundNotificationService : Service() {
    override fun onCreate() {
        super.onCreate()
        isRunning = true
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        var startMode = START_STICKY
        when (intent?.action) {
            ACTION_SYNC -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
                val text = intent.getStringExtra(EXTRA_TEXT) ?: ""
                val progress = intent.getIntExtra(EXTRA_PROGRESS, 0).coerceIn(0, 100)
                val isPaused = intent.getBooleanExtra(EXTRA_IS_PAUSED, false)
                showOrUpdateNotification(title, text, progress, isPaused)
            }

            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                isRunning = false
                startMode = START_NOT_STICKY
            }

            ACTION_BUTTON -> {
                val action = intent.getStringExtra(EXTRA_BUTTON_ACTION)
                if (!action.isNullOrBlank()) {
                    AINotificationActionDispatcher.emit(action)
                }
            }
        }

        return startMode
    }

    private fun showOrUpdateNotification(
        title: String,
        text: String,
        progress: Int,
        isPaused: Boolean,
    ) {
        ensureChannel()

        val buttonAction = if (isPaused) ACTION_RESUME else ACTION_PAUSE
        val actionLabel = if (isPaused) "继续" else "暂停"
        val actionIntent = Intent(this, AIForegroundNotificationService::class.java).apply {
            this.action = ACTION_BUTTON
            putExtra(EXTRA_BUTTON_ACTION, buttonAction)
        }
        val actionPendingIntent = PendingIntent.getService(
            this,
            if (isPaused) 2 else 1,
            actionIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag(),
        )

        val openAlbumIntent = Intent(this, MainActivity::class.java).apply {
            this.action = ACTION_OPEN_ALBUM
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val openAlbumPendingIntent = PendingIntent.getActivity(
            this,
            3,
            openAlbumIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or pendingIntentImmutableFlag(),
        )

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(100, progress, false)
            .setContentIntent(openAlbumPendingIntent)
            .setAutoCancel(false)
            .addAction(0, actionLabel, actionPendingIntent)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        startForeground(NOTIFICATION_ID, notification)
        isRunning = true
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "展示 AI 打标任务进度与控制按钮"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun pendingIntentImmutableFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }

    companion object {
        const val CHANNEL_ID = "ai_progress_channel"
        private const val CHANNEL_NAME = "AI 打标进度"
        private const val NOTIFICATION_ID = 43001

        const val ACTION_SYNC = "memoria.ai.notification.SYNC"
        const val ACTION_STOP = "memoria.ai.notification.STOP"
        private const val ACTION_BUTTON = "memoria.ai.notification.BUTTON"
        const val ACTION_OPEN_ALBUM = "memoria.ai.notification.OPEN_ALBUM"

        const val ACTION_PAUSE = "pause"
        const val ACTION_RESUME = "resume"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_IS_PAUSED = "isPaused"
        private const val EXTRA_BUTTON_ACTION = "buttonAction"

        private const val DEFAULT_TITLE = "AI 打标进行中"

        @Volatile
        var isRunning: Boolean = false
    }
}
