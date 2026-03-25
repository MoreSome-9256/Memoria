package com.example.photo_album

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 应用主入口 Activity。
 *
 * 这里额外注册一个平台通道，目的是让 Dart 层可以直接向 Android 侧查询：
 * - 手机硬件是否适合跑 InternVL-3-1B
 * - 当前仓库是否已经具备本地 GGUF 推理后端
 *
 * 这样做不需要改任何 Flutter package 版本，只依赖 Flutter 自带的 MethodChannel。
 */
class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"memoria/ai_foreground_notification",
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"sync" -> {
					val shouldRun = call.argument<Boolean>("shouldRun") ?: false
					if (!shouldRun) {
						val stopIntent = android.content.Intent(this, AIForegroundNotificationService::class.java).apply {
							action = AIForegroundNotificationService.ACTION_STOP
						}
						startService(stopIntent)
						result.success(null)
						return@setMethodCallHandler
					}

					val title = call.argument<String>("title") ?: "AI 打标进行中"
					val text = call.argument<String>("text") ?: ""
					val progress = call.argument<Int>("progress") ?: 0
					val isPaused = call.argument<Boolean>("isPaused") ?: false

					val syncIntent = android.content.Intent(this, AIForegroundNotificationService::class.java).apply {
						action = AIForegroundNotificationService.ACTION_SYNC
						putExtra(AIForegroundNotificationService.EXTRA_TITLE, title)
						putExtra(AIForegroundNotificationService.EXTRA_TEXT, text)
						putExtra(AIForegroundNotificationService.EXTRA_PROGRESS, progress)
						putExtra(AIForegroundNotificationService.EXTRA_IS_PAUSED, isPaused)
					}

					if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
						startForegroundService(syncIntent)
					} else {
						startService(syncIntent)
					}
					result.success(null)
				}
				else -> result.notImplemented()
			}
		}

		EventChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"memoria/ai_foreground_actions",
		).setStreamHandler(object : EventChannel.StreamHandler {
			override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
				AINotificationActionDispatcher.eventSink = events
			}

			override fun onCancel(arguments: Any?) {
				AINotificationActionDispatcher.eventSink = null
			}
		})

		val bridge = OnDeviceInternvlBridge(applicationContext)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"memoria/on_device_internvl",
		).setMethodCallHandler { call, result ->
			if (!bridge.handle(call, result)) {
				result.notImplemented()
			}
		}
	}
}
