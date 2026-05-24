package com.example.photo_album

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.documentfile.provider.DocumentFile
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private var pendingDirectoryGrantResult: MethodChannel.Result? = null
	private var pendingBatteryOptimizationResult: MethodChannel.Result? = null
	private val directoryRequestCode = 42031
	private val batteryOptimizationRequestCode = 42032

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"memoria/media_access",
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"requestDirectoryGrant" -> requestDirectoryGrant(result)
				"releaseDirectoryGrant" -> {
					val uriString = call.arguments as? String
					if (uriString != null) {
						releaseDirectoryGrant(uriString)
					}
					result.success(null)
				}
				"openBatteryOptimizationSettings" -> {
					openBatteryOptimizationSettings()
					result.success(null)
				}
				"requestIgnoreBatteryOptimizations" -> requestIgnoreBatteryOptimizations(result)
				else -> result.notImplemented()
			}
		}

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"memoria/ai_background_task",
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"startForegroundTask" -> {
					val args = call.arguments as? Map<*, *>
					startAiForegroundTask(
						args?.get("title") as? String,
						args?.get("text") as? String,
					)
					result.success(null)
				}
				"stopForegroundTask" -> {
					stopService(Intent(this, AiForegroundTaskService::class.java))
					result.success(null)
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun requestDirectoryGrant(result: MethodChannel.Result) {
		if (pendingDirectoryGrantResult != null) {
			result.error("busy", "A directory grant request is already running.", null)
			return
		}
		pendingDirectoryGrantResult = result
		val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
			addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
			addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
			addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
		}
		startActivityForResult(intent, directoryRequestCode)
	}

	override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
		super.onActivityResult(requestCode, resultCode, data)
		if (requestCode == batteryOptimizationRequestCode) {
			val result = pendingBatteryOptimizationResult
			pendingBatteryOptimizationResult = null
			result?.success(isIgnoringBatteryOptimizations())
			return
		}
		if (requestCode != directoryRequestCode) {
			return
		}
		val result = pendingDirectoryGrantResult
		pendingDirectoryGrantResult = null
		if (result == null) {
			return
		}
		if (resultCode != Activity.RESULT_OK || data?.data == null) {
			result.success(null)
			return
		}
		val uri = data.data!!
		val flags = data.flags and
			(Intent.FLAG_GRANT_READ_URI_PERMISSION or
				Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
		try {
			contentResolver.takePersistableUriPermission(
				uri,
				flags and Intent.FLAG_GRANT_READ_URI_PERMISSION,
			)
		} catch (_: SecurityException) {
		}
		val document = DocumentFile.fromTreeUri(this, uri)
		result.success(
			mapOf(
				"uri" to uri.toString(),
				"displayName" to (document?.name ?: uri.toString()),
			),
		)
	}

	private fun releaseDirectoryGrant(uriString: String) {
		try {
			contentResolver.releasePersistableUriPermission(
				Uri.parse(uriString),
				Intent.FLAG_GRANT_READ_URI_PERMISSION,
			)
		} catch (_: SecurityException) {
		}
	}

	private fun openBatteryOptimizationSettings() {
		val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
		} else {
			Intent(Settings.ACTION_SETTINGS)
		}
		startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
	}

	private fun requestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
			result.success(true)
			return
		}
		if (isIgnoringBatteryOptimizations()) {
			result.success(true)
			return
		}
		if (pendingBatteryOptimizationResult != null) {
			result.error("busy", "A battery optimization request is already running.", null)
			return
		}
		pendingBatteryOptimizationResult = result
		try {
			val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
				data = Uri.parse("package:$packageName")
			}
			startActivityForResult(intent, batteryOptimizationRequestCode)
		} catch (error: Exception) {
			pendingBatteryOptimizationResult = null
			result.error("unavailable", error.message, null)
		}
	}

	private fun isIgnoringBatteryOptimizations(): Boolean {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
			return true
		}
		val powerManager = getSystemService(PowerManager::class.java)
		return powerManager?.isIgnoringBatteryOptimizations(packageName) == true
	}

	private fun startAiForegroundTask(title: String?, text: String?) {
		val intent = Intent(this, AiForegroundTaskService::class.java).apply {
			putExtra("title", title)
			putExtra("text", text)
		}
		ContextCompat.startForegroundService(this, intent)
	}
}
