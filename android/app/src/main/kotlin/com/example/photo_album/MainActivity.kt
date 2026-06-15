package com.example.photo_album

import android.content.Intent
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "memoria/android_settings"

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		keepScreenOnWhileInUse()
	}

	override fun onResume() {
		super.onResume()
		keepScreenOnWhileInUse()
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			CHANNEL,
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"openBatteryOptimizationSettings" -> {
					startActivity(
						Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
							.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
					)
					result.success(null)
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun keepScreenOnWhileInUse() {
		window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
	}
}
