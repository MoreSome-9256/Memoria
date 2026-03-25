package com.example.photo_album

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
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
	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		handleNavigationIntent(intent)
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		handleNavigationIntent(intent)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"memoria/ai_foreground_notification",
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"sync" -> {
					try {
						val shouldRun = call.argument<Boolean>("shouldRun") ?: false
						if (!shouldRun) {
							val stopIntent = Intent(this, AIForegroundNotificationService::class.java).apply {
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

						val syncIntent = Intent(this, AIForegroundNotificationService::class.java).apply {
							action = AIForegroundNotificationService.ACTION_SYNC
							putExtra(AIForegroundNotificationService.EXTRA_TITLE, title)
							putExtra(AIForegroundNotificationService.EXTRA_TEXT, text)
							putExtra(AIForegroundNotificationService.EXTRA_PROGRESS, progress)
							putExtra(AIForegroundNotificationService.EXTRA_IS_PAUSED, isPaused)
						}

						if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
							startForegroundService(syncIntent)
						} else {
							startService(syncIntent)
						}
						result.success(null)
					} catch (e: Exception) {
						result.error("FGS_SYNC_FAILED", e.message, null)
					}
				}
				"isIgnoringBatteryOptimizations" -> {
					val pm = getSystemService(POWER_SERVICE) as PowerManager
					result.success(pm.isIgnoringBatteryOptimizations(packageName))
				}
				"openIgnoreBatteryOptimizationSettings" -> {
					try {
						val intent = Intent(
							Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
							Uri.parse("package:$packageName"),
						).apply {
							addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						}
						startActivity(intent)
						result.success(true)
					} catch (_: Exception) {
						try {
							val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
								addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
							}
							startActivity(fallback)
							result.success(true)
						} catch (e: Exception) {
							result.error("OPEN_BATTERY_SETTINGS_FAILED", e.message, null)
						}
					}
				}
				"getAndroidFgsPolicySummary" -> {
					val summary = when {
						Build.VERSION.SDK_INT >= 35 -> "Android 15+：dataSync 前台服务在 24h 内总时长受限，系统可能在超时后终止。"
						Build.VERSION.SDK_INT >= 34 -> "Android 14：启动前台服务受运行时约束，后台场景下可能被系统拒绝。"
						else -> "当前系统版本限制较少，但仍受厂商省电策略影响。"
					}
					result.success(summary)
				}
				"isForegroundServiceRunning" -> {
					result.success(AIForegroundNotificationService.isRunning)
				}
				"consumePendingNavigationTarget" -> {
					result.success(AppNavigationDispatcher.consumePendingTarget())
				}
				else -> result.notImplemented()
			}
		}

		EventChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"memoria/app_navigation_events",
		).setStreamHandler(object : EventChannel.StreamHandler {
			override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
				AppNavigationDispatcher.eventSink = events
			}

			override fun onCancel(arguments: Any?) {
				AppNavigationDispatcher.eventSink = null
			}
		})

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

	private fun handleNavigationIntent(intent: Intent?) {
		if (intent?.action == AIForegroundNotificationService.ACTION_OPEN_ALBUM) {
			AppNavigationDispatcher.emitOrQueue("album")
		}
	}
}
