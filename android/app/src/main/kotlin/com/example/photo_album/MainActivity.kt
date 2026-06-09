package com.example.photo_album

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.provider.MediaStore
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread
import java.io.File
import java.io.RandomAccessFile

class MainActivity : FlutterActivity() {
	private var pendingDirectoryGrantResult: MethodChannel.Result? = null
	private var pendingBatteryOptimizationResult: MethodChannel.Result? = null
	private val directoryRequestCode = 42031
	private val batteryOptimizationRequestCode = 42032

	override fun onCreate(savedInstanceState: Bundle?) {
		Log.i(TAG, "onCreate savedInstanceState=${savedInstanceState != null} taskId=$taskId intent=$intent")
		super.onCreate(savedInstanceState)
	}

	override fun onNewIntent(intent: Intent) {
		Log.i(TAG, "onNewIntent taskId=$taskId intent=$intent flags=${intent.flags}")
		super.onNewIntent(intent)
	}

	override fun onDestroy() {
		Log.i(TAG, "onDestroy isFinishing=$isFinishing changingConfig=$isChangingConfigurations taskId=$taskId")
		super.onDestroy()
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		Log.i(TAG, "configureFlutterEngine engine=$flutterEngine taskId=$taskId")
		super.configureFlutterEngine(flutterEngine)
		installForegroundTaskLifecycleLogger()

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
				"isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
				"listGrantedMedia" -> {
					val args = call.arguments as? Map<*, *>
					val treeUris = args?.get("treeUris") as? List<*>
					val sourcesWithoutChildren = (args?.get("sourcesWithoutChildren") as? List<*>)?.map { it.toString() }?.toSet() ?: emptySet()
					val limit = (args?.get("limit") as? Number)?.toInt() ?: 500
					thread(name = "memoria-list-granted-media") {
						val media = listGrantedMedia(treeUris, sourcesWithoutChildren, limit)
						runOnUiThread { result.success(media) }
					}
				}
				"readContentUriBytes" -> {
					val uriString = call.arguments as? String
					if (uriString == null) {
						result.error("invalid_uri", "Missing content uri.", null)
					} else {
						result.success(readContentUriBytes(uriString))
					}
				}
				"extractAndroidMotionPhoto" -> {
					val assetId = call.arguments as? String
					thread(name = "memoria-motion-photo") {
						val path = assetId?.let(::extractAndroidMotionPhoto)
						runOnUiThread { result.success(path) }
					}
				}
				else -> result.notImplemented()
			}
		}

		// Foreground service is managed by flutter_foreground_task plugin
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

	private fun listGrantedMedia(
		treeUriValues: List<*>?,
		sourcesWithoutChildren: Set<String>,
		limit: Int,
	): List<Map<String, Any?>> {
		if (treeUriValues.isNullOrEmpty()) {
			return emptyList()
		}
		val media = mutableListOf<Map<String, Any?>>()
		val effectiveLimit = limit.coerceAtLeast(1)
		for (value in treeUriValues) {
			val uriStr = value as? String ?: continue
			val treeUri = Uri.parse(uriStr)
			val root = DocumentFile.fromTreeUri(this, treeUri) ?: continue
			val traverseChildren = uriStr !in sourcesWithoutChildren
			collectDocumentMedia(root, "", media, traverseChildren)
		}
		return media
			.sortedByDescending { it["modifiedMs"] as? Long ?: 0L }
			.take(effectiveLimit)
	}

	private fun collectDocumentMedia(
		document: DocumentFile,
		relativePath: String,
		out: MutableList<Map<String, Any?>>,
		traverseChildren: Boolean = true,
	) {
		if (document.isDirectory) {
			for (child in document.listFiles()) {
				val childName = child.name ?: continue
				if (child.isDirectory && !traverseChildren) continue
				val childPath = if (relativePath.isEmpty()) childName else "$relativePath/$childName"
				collectDocumentMedia(child, childPath, out, traverseChildren)
			}
			return
		}
		val mimeType = document.type ?: return
		if (!mimeType.startsWith("image/") && !mimeType.startsWith("video/")) {
			return
		}
		out.add(
			mapOf(
				"uri" to document.uri.toString(),
				"displayName" to (document.name ?: relativePath),
				"relativePath" to relativePath,
				"mimeType" to mimeType,
				"modifiedMs" to document.lastModified(),
				"size" to document.length(),
				"width" to 0,
				"height" to 0,
			),
		)
	}

	private fun readContentUriBytes(uriString: String): ByteArray? {
		return try {
			contentResolver.openInputStream(Uri.parse(uriString)).use { input ->
				input?.readBytes()
			}
		} catch (_: Exception) {
			null
		}
	}

	private fun extractAndroidMotionPhoto(assetId: String): String? {
		val numericId = assetId.toLongOrNull() ?: return null
		val uri = Uri.withAppendedPath(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, numericId.toString())
		val source = cacheDir.resolve("motion_photo_source_$numericId")
		val output = cacheDir.resolve("motion_photo_$numericId.mp4")
		return try {
			contentResolver.openInputStream(uri)?.use { input ->
				source.outputStream().use { input.copyTo(it) }
			} ?: return null
			val videoOffset = findEmbeddedMp4Offset(source) ?: return null
			RandomAccessFile(source, "r").use { input ->
				input.seek(videoOffset)
				output.outputStream().use { out ->
					val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
					while (true) {
						val read = input.read(buffer)
						if (read <= 0) break
						out.write(buffer, 0, read)
					}
				}
			}
			output.takeIf { it.length() > 16 }?.absolutePath
		} catch (error: Exception) {
			Log.w(TAG, "Motion Photo extraction failed assetId=$assetId", error)
			null
		} finally {
			source.delete()
		}
	}

	private fun findEmbeddedMp4Offset(file: File): Long? {
		RandomAccessFile(file, "r").use { input ->
			val length = input.length()
			if (length < 16) return null
			val scanSize = minOf(length, 32L * 1024L * 1024L).toInt()
			val start = length - scanSize
			val bytes = ByteArray(scanSize)
			input.seek(start)
			input.readFully(bytes)
			for (index in 4 until bytes.size - 8) {
				if (bytes[index] != 'f'.code.toByte() ||
					bytes[index + 1] != 't'.code.toByte() ||
					bytes[index + 2] != 'y'.code.toByte() ||
					bytes[index + 3] != 'p'.code.toByte()
				) continue
				val boxSize =
					((bytes[index - 4].toInt() and 0xff) shl 24) or
					((bytes[index - 3].toInt() and 0xff) shl 16) or
					((bytes[index - 2].toInt() and 0xff) shl 8) or
					(bytes[index - 1].toInt() and 0xff)
				if (boxSize < 8) continue
				val offset = start + index - 4
				if (offset > 0 && length - offset > 16) return offset
			}
		}
		return null
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

}

private const val TAG = "MemoriaMainActivity"

private var foregroundTaskLifecycleLoggerInstalled = false

private fun installForegroundTaskLifecycleLogger() {
	if (foregroundTaskLifecycleLoggerInstalled) {
		return
	}
	foregroundTaskLifecycleLoggerInstalled = true
	FlutterForegroundTaskPlugin.addTaskLifecycleListener(
		object : FlutterForegroundTaskLifecycleListener {
			override fun onEngineCreate(flutterEngine: FlutterEngine?) {
				Log.i(TAG, "foreground task FlutterEngine create engine=$flutterEngine")
			}

			override fun onTaskStart(starter: FlutterForegroundTaskStarter) {
				Log.i(TAG, "foreground task start starter=$starter")
			}

			override fun onTaskRepeatEvent() = Unit

			override fun onTaskDestroy() {
				Log.i(TAG, "foreground task destroy")
			}

			override fun onEngineWillDestroy() {
				Log.i(TAG, "foreground task FlutterEngine willDestroy")
			}
		},
	)
}
