package com.example.photo_album

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
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
