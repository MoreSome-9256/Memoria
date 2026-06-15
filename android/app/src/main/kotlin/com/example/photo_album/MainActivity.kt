package com.example.photo_album

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
	private val CHANNEL = "memoria/android_settings"
	private val FILE_MANAGER_CHANNEL = "memoria/file_manager"

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

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			FILE_MANAGER_CHANNEL,
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"saveToDownloadsAndOpen" -> {
					val filePath = call.argument<String>("filePath")
					if (filePath == null) {
						result.error("INVALID_ARGS", "filePath is required", null)
						return@setMethodCallHandler
					}
					try {
						val uri = saveToDownloads(filePath)
						if (uri != null) {
							openDownloadsInFileManager()
							result.success(uri.toString())
						} else {
							result.error("SAVE_FAILED", "Failed to save file to Downloads", null)
						}
					} catch (e: Exception) {
						result.error("SAVE_FAILED", e.message, null)
					}
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun saveToDownloads(filePath: String): Uri? {
		val sourceFile = File(filePath)
		if (!sourceFile.exists()) return null

		val fileName = sourceFile.name
		val mimeType = "video/mp4"

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
			val contentValues = ContentValues().apply {
				put(MediaStore.Downloads.DISPLAY_NAME, fileName)
				put(MediaStore.Downloads.MIME_TYPE, mimeType)
				put(MediaStore.Downloads.RELATIVE_PATH, "Download/Memoria")
				put(MediaStore.Downloads.IS_PENDING, 1)
			}

			val resolver = contentResolver
			val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
			val uri = resolver.insert(collection, contentValues) ?: return null

			try {
				val outputStream = resolver.openOutputStream(uri)
					?: throw IllegalStateException("Unable to open Downloads output stream")
				outputStream.use { output ->
					FileInputStream(sourceFile).use { input ->
						input.copyTo(output)
					}
				}
				resolver.update(
					uri,
					ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
					null,
					null,
				)
			} catch (error: Exception) {
				resolver.delete(uri, null, null)
				throw error
			}
			return uri
		} else {
			val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
			val memoriaDir = File(downloadsDir, "Memoria")
			if (!memoriaDir.exists()) {
				memoriaDir.mkdirs()
			}
			val destFile = File(memoriaDir, fileName)
			sourceFile.copyTo(destFile, overwrite = true)
			return Uri.fromFile(destFile)
		}
	}

	private fun openDownloadsInFileManager() {
		val downloadsRoot = DocumentsContract.buildRootUri(
			"com.android.providers.downloads.documents",
			"downloads",
		)
		val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
			addCategory(Intent.CATEGORY_OPENABLE)
			type = "video/mp4"
			putExtra(DocumentsContract.EXTRA_INITIAL_URI, downloadsRoot)
			addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
		}
		startActivity(intent)
	}

	private fun keepScreenOnWhileInUse() {
		window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
	}
}
