package com.example.photo_album

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"memoria/android_settings",
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
}
