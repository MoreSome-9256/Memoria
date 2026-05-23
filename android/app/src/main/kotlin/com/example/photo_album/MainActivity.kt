package com.example.photo_album

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val ANALYSIS_METHOD_CHANNEL = "memoria/analysis"
        const val ANALYSIS_EVENT_CHANNEL = "memoria/analysis_progress"
        const val ENGINE_CACHE_KEY = "analysis_engine"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        FlutterEngineCache.getInstance().put(ENGINE_CACHE_KEY, flutterEngine)

        val analysisService = ForegroundAnalysisService.getInstance()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ANALYSIS_METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enqueueImages" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    val images = call.argument<List<Map<String, String?>>>("images") ?: emptyList()
                    if (analysisService != null) {
                        analysisService.enqueueTask(taskId, images, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ANALYSIS_METHOD_CHANNEL))
                    }
                    val intent = Intent(this, ForegroundAnalysisService::class.java).apply {
                        action = "com.example.photo_album.ACTION_START"
                        putExtra("taskId", taskId)
                    }
                    startForegroundServiceCompat(intent)
                    result.success(true)
                }
                "startAnalysis" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    val intent = Intent(this, ForegroundAnalysisService::class.java).apply {
                        action = "com.example.photo_album.ACTION_START"
                        putExtra("taskId", taskId)
                    }
                    startForegroundServiceCompat(intent)
                    result.success(true)
                }
                "pauseAnalysis" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    val intent = Intent(this, ForegroundAnalysisService::class.java).apply {
                        action = "com.example.photo_album.ACTION_PAUSE"
                        putExtra("taskId", taskId)
                    }
                    startService(intent)
                    result.success(true)
                }
                "resumeAnalysis" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    val intent = Intent(this, ForegroundAnalysisService::class.java).apply {
                        action = "com.example.photo_album.ACTION_RESUME"
                        putExtra("taskId", taskId)
                    }
                    startService(intent)
                    result.success(true)
                }
                "cancelAnalysis" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    val intent = Intent(this, ForegroundAnalysisService::class.java).apply {
                        action = "com.example.photo_album.ACTION_CANCEL"
                        putExtra("taskId", taskId)
                    }
                    startService(intent)
                    result.success(true)
                }
                "getState" -> {
                    result.success(null)
                }
                "getUnfinishedTasks" -> {
                    result.success(emptyList<Map<String, Any>>())
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ANALYSIS_EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                analysisService?.setEventSink(events)
            }

            override fun onCancel(arguments: Any?) {
                analysisService?.setEventSink(null)
            }
        })
    }

    private fun startForegroundServiceCompat(intent: Intent) {
        try {
            startForegroundService(intent)
        } catch (e: Exception) {
            startService(intent)
        }
    }
}
