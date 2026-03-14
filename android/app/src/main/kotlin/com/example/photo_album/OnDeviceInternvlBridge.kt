package com.example.photo_album

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.File
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max
import kotlin.math.min
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Android 侧的 InternVL 设备探测桥。
 *
 * 这个类当前只做两件事：
 * 1. 告诉 Flutter 当前手机的 CPU / RAM / ABI 情况，方便判断能不能扛住 1B Q4 级别模型。
 * 2. 明确告诉上层：仓库目前还没有接入 Android 原生 llama.cpp / GGML 推理后端。
 *
 * 这里刻意不伪造“本地已可运行”的状态，避免让 UI 或业务层误以为模型已经真正集成。
 * 真正要把 InternVL 直接跑在手机里，后续还需要在 Android 侧补 JNI / NDK 推理实现。
 */
class OnDeviceInternvlBridge(private val context: Context) {

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private val deployedRoot = "/data/local/tmp/llama.cpp"
    private val installRoot = "$deployedRoot/install-android-baseline"
    private val cliPath = "$installRoot/bin/llama-mtmd-cli"
    private val libDir = "$installRoot/lib"
    private val modelPath = "$deployedRoot/InternVL3-1B-Instruct-Q4_K_M.gguf"
    private val mmprojPath = "$deployedRoot/mmproj-F16.gguf"
    private val linkerPath by lazy {
        sequenceOf(
            "/system/bin/linker64",
            "/apex/com.android.runtime/bin/linker64",
        ).firstOrNull { File(it).exists() } ?: "/system/bin/linker64"
    }

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        return when (call.method) {
            "probeDevice" -> {
                result.success(buildDeviceProfile())
                true
            }

            "getBackendStatus" -> {
                result.success(buildBackendStatus())
                true
            }

            "getCliDeploymentStatus" -> {
                result.success(buildCliDeploymentStatus())
                true
            }

            "runCliExperiment" -> {
                @Suppress("UNCHECKED_CAST")
                val arguments = call.arguments as? Map<String, Any?>
                if (arguments == null) {
                    result.error("invalid_arguments", "缺少 CLI 实验参数", null)
                } else {
                    backgroundExecutor.execute {
                        val payload = runCliExperiment(arguments)
                        mainHandler.post {
                            result.success(payload)
                        }
                    }
                }
                true
            }

            else -> false
        }
    }

    /**
     * 生成“手机是否适合承载 InternVL-3-1B Q4”所需的基础画像。
     *
     * 这些值不是绝对结论，而是用于给 Flutter 层提供一份接近真实的工程判断：
     * - RAM 够不够
     * - 线程数应该压到多少
     * - 当前仓库是否能用 NPU
     */
    private fun buildDeviceProfile(): Map<String, Any> {
        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        val totalRamMb = (memoryInfo.totalMem / (1024L * 1024L)).toInt()
        val availableProcessors = Runtime.getRuntime().availableProcessors()
        val primaryAbi = Build.SUPPORTED_ABIS.firstOrNull().orEmpty()
        val recommendedThreads = min(max(availableProcessors / 2, 2), 6)

        // 经验值说明：
        // 1B Q4 主模型 + mmproj + KV Cache + 图像编码中间张量，移动端一般至少要预留 2GB 左右可用内存。
        // 真机总 RAM 小于 6GB 时，虽然不一定绝对跑不起来，但非常容易遇到：
        // - 首次加载慢
        // - 被系统回收
        // - 多图推理时抖动明显
        val likelyEnoughRamFor1BQ4 = totalRamMb >= 6 * 1024
        val likelyEnoughRamForVision = totalRamMb >= 8 * 1024

        val pressureLevel = when {
            totalRamMb < 4 * 1024 -> "extreme"
            totalRamMb < 6 * 1024 -> "high"
            totalRamMb < 8 * 1024 -> "medium"
            else -> "manageable"
        }

        val recommendedContextSize = when {
            totalRamMb >= 12 * 1024 -> 4096
            totalRamMb >= 8 * 1024 -> 3072
            else -> 2048
        }

        val summary = buildString {
            append("ABI=")
            append(primaryAbi.ifEmpty { "unknown" })
            append(", RAM≈")
            append(totalRamMb)
            append("MB, CPU线程=")
            append(availableProcessors)
            append(", 建议推理线程=")
            append(recommendedThreads)
            append(", 压力等级=")
            append(pressureLevel)
        }

        return mapOf(
            "primaryAbi" to primaryAbi,
            "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
            "totalRamMb" to totalRamMb,
            "memoryClassMb" to activityManager.memoryClass,
            "largeMemoryClassMb" to activityManager.largeMemoryClass,
            "availableProcessors" to availableProcessors,
            "recommendedThreads" to recommendedThreads,
            "recommendedContextSize" to recommendedContextSize,
            "likelyEnoughRamFor1BQ4" to likelyEnoughRamFor1BQ4,
            "likelyEnoughRamForVision" to likelyEnoughRamForVision,
            // 当前仓库没有接 NNAPI / QNN / MediaTek NeuroPilot 等后端，因此这里明确返回 false。
            "npuAvailableThroughApp" to false,
            "pressureLevel" to pressureLevel,
            "summary" to summary,
        )
    }

    /**
     * 返回当前仓库对“手机本地 InternVL”的真实后端状态。
     *
     * 为什么要单独暴露这个接口：
     * 设备足够强 != 应用已经具备本地运行能力。
     * 目前项目只有 HTTP 方式的 LLM 调用，没有 Android 原生 GGUF 推理后端。
     */
    private fun buildBackendStatus(): Map<String, Any> {
        val deployment = buildCliDeploymentStatus()
        val cliReady = deployment["isRunnable"] == true

        return mapOf(
            "backendIntegrated" to cliReady,
            "backendName" to if (cliReady) "llama.cpp-cli" else "none",
            "supportsDirectOnDeviceInternvl" to cliReady,
            "reason" to if (cliReady) {
                "已检测到手机侧 llama-mtmd-cli、主模型和 mmproj 文件，当前可以直接在 App 内发起单次本地 InternVL CLI 推理。"
            } else {
                "当前仓库已具备 Android 侧 CLI 调用通道，但手机上的 llama.cpp 可执行文件或模型文件尚未部署完整。"
            },
            "nextStep" to if (cliReady) {
                "优先在“本地 InternVL 实验”页直接执行单图 CLI 测试；如需长期稳定服务化，再单独排查 llama-server 的 Illegal instruction 问题。"
            } else {
                "先把 llama-mtmd-cli、依赖动态库、InternVL GGUF 和 mmproj 推送到 /data/local/tmp/llama.cpp，再回到实验页直接测试。"
            }
        )
    }

    private fun buildCliDeploymentStatus(): Map<String, Any> {
        val cliFile = File(cliPath)
        val libDirectory = File(libDir)
        val modelFile = File(modelPath)
        val mmprojFile = File(mmprojPath)
        val installDirectory = File(installRoot)
        val linkerFile = File(linkerPath)

        val missingItems = buildList {
            if (!installDirectory.exists()) add("install-android-baseline 目录缺失")
            if (!cliFile.exists()) add("llama-mtmd-cli 缺失")
            if (!libDirectory.exists()) add("动态库目录缺失")
            if (!modelFile.exists()) add("InternVL 主模型缺失")
            if (!mmprojFile.exists()) add("mmproj 文件缺失")
            if (!linkerFile.exists()) add("Android linker64 缺失")
        }

        val isRunnable = missingItems.isEmpty()

        return mapOf(
            "deployedRoot" to deployedRoot,
            "installRoot" to installRoot,
            "cliPath" to cliPath,
            "linkerPath" to linkerPath,
            "modelPath" to modelPath,
            "mmprojPath" to mmprojPath,
            "cliExists" to cliFile.exists(),
            "libDirExists" to libDirectory.exists(),
            "modelExists" to modelFile.exists(),
            "mmprojExists" to mmprojFile.exists(),
            "isRunnable" to isRunnable,
            "summary" to if (isRunnable) {
                "已检测到本地 CLI 可执行链路，将通过 Android linker64 包装启动，规避 App 进程直接 exec 外部二进制的权限限制。"
            } else {
                "本地 CLI 依赖尚未部署完整：${missingItems.joinToString("；")}"
            },
            "missingItems" to missingItems,
        )
    }

    private fun runCliExperiment(arguments: Map<String, Any?>): Map<String, Any> {
        val deployment = buildCliDeploymentStatus()
        if (deployment["isRunnable"] != true) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to (deployment["summary"]?.toString()
                    ?: "本地 CLI 尚未准备好"),
                "exitCode" to -1,
                "durationMs" to 0L,
            )
        }

        val imagePath = arguments["imagePath"]?.toString()?.trim().orEmpty()
        val prompt = arguments["prompt"]?.toString()?.trim().orEmpty()
        val threads = (arguments["threads"] as? Number)?.toInt()?.coerceIn(1, 8) ?: 4
        val contextSize = (arguments["contextSize"] as? Number)?.toInt()?.coerceIn(512, 4096) ?: 2048
        val maxTokens = (arguments["maxTokens"] as? Number)?.toInt()?.coerceIn(16, 256) ?: 96
        val timeoutMs = (arguments["timeoutMs"] as? Number)?.toLong()?.coerceAtLeast(10_000L) ?: 180_000L

        if (imagePath.isEmpty() || !File(imagePath).exists()) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to "测试图片不存在或不可访问：$imagePath",
                "exitCode" to -1,
                "durationMs" to 0L,
            )
        }

        if (prompt.isEmpty()) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to "测试指令不能为空",
                "exitCode" to -1,
                "durationMs" to 0L,
            )
        }

        val command = listOf(
            linkerPath,
            cliPath,
            "--model", modelPath,
            "--mmproj", mmprojPath,
            "--image", imagePath,
            "--prompt", prompt,
            "-c", contextSize.toString(),
            "-n", maxTokens.toString(),
            "-t", threads.toString(),
            "--no-mmproj-offload",
        )

        val startTime = System.currentTimeMillis()
        return try {
            val process = ProcessBuilder(command)
                .directory(File(deployedRoot))
                .redirectErrorStream(true)
                .apply {
                    environment()["LD_LIBRARY_PATH"] = libDir
                }
                .start()

            val finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            val rawOutput = process.inputStream.bufferedReader().use { it.readText() }
            val durationMs = System.currentTimeMillis() - startTime

            if (!finished) {
                process.destroyForcibly()
                mapOf(
                    "success" to false,
                    "answer" to "",
                    "rawOutput" to rawOutput,
                    "error" to "本地 CLI 推理超时，已超过 ${timeoutMs}ms",
                    "exitCode" to -1,
                    "durationMs" to durationMs,
                )
            } else {
                val exitCode = process.exitValue()
                val answer = extractAnswer(rawOutput)
                mapOf(
                    "success" to (exitCode == 0 && answer.isNotBlank()),
                    "answer" to answer,
                    "rawOutput" to rawOutput,
                    "error" to if (exitCode == 0) "" else "CLI 退出码异常：$exitCode",
                    "exitCode" to exitCode,
                    "durationMs" to durationMs,
                )
            }
        } catch (error: Throwable) {
            mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to buildString {
                    append(error.message ?: error.toString())
                    append("；当前已改为通过 ")
                    append(linkerPath)
                    append(" 启动 CLI。若这里仍失败，说明手机系统策略已阻止当前部署位置执行，需要改为 JNI/原生库集成路线。")
                },
                "exitCode" to -1,
                "durationMs" to (System.currentTimeMillis() - startTime),
            )
        }
    }

    private fun extractAnswer(rawOutput: String): String {
        if (rawOutput.isBlank()) {
            return ""
        }

        val lines = rawOutput.lines()
        val assistantIndex = lines.indexOfLast { it.trim() == "assistant" }
        val candidateLines = if (assistantIndex >= 0 && assistantIndex + 1 < lines.size) {
            lines.subList(assistantIndex + 1, lines.size)
        } else {
            lines
        }

        return candidateLines
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .filterNot {
                it.startsWith("main:") ||
                    it.startsWith("system_info:") ||
                    it.startsWith("llama_model_loader:") ||
                    it.startsWith("llama_context:") ||
                    it.startsWith("llama_perf_") ||
                    it.startsWith("encode_image_with_clip:") ||
                    it.startsWith("load_image_size:") ||
                    it.startsWith("print_image_embed") ||
                    it.startsWith("clip_model_load:") ||
                    it.startsWith("clip_image_load_from_bytes:") ||
                    it.startsWith("clip:") ||
                    it.startsWith("common_init_from_params:") ||
                    it.startsWith("sampler seed:")
            }
            .joinToString("\n")
            .trim()
    }
}