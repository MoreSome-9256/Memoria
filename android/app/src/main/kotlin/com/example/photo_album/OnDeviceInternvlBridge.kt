package com.example.photo_album

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.io.InterruptedIOException
import java.io.IOException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import kotlin.math.max
import kotlin.math.min
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Android 侧的本地 Qwen-VL / 多模态模型设备探测桥。
 *
 * 这个类当前只做两件事：
 * 1. 告诉 Flutter 当前手机的 CPU / RAM / ABI 情况，方便判断能不能扛住 0.8B/1B Q4 级别模型。
 * 2. 明确告诉上层：仓库目前还没有接入 Android 原生 llama.cpp / GGML 推理后端。
 *
 * 这里刻意不伪造“本地已可运行”的状态，避免让 UI 或业务层误以为模型已经真正集成。
 * 真正要把手机本地 VLM 直接跑在更底层加速后端里，后续还需要在 Android 侧补 JNI / NDK 推理实现。
 */
class OnDeviceInternvlBridge(private val context: Context) {

    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private val deployedRoot = "/data/local/tmp/llama.cpp"
    private val installRoot = "$deployedRoot/install-android-baseline"
    private val cliPath = "$installRoot/bin/llama-mtmd-cli"
    private val serverPath = "$installRoot/bin/llama-server"
    private val libDir = "$installRoot/lib"
    private val modelPathCandidates = listOf(
        "$deployedRoot/checkpoints/qwen/Qwen3.5-0.8B-Q4_K_M.gguf",
        "$deployedRoot/checkpoints/qwen/qwen3.5-0.8b-q4_k_m.gguf",
    )
    private val mmprojPathCandidates = listOf(
        "$deployedRoot/checkpoints/qwen/mmproj-F16.gguf",
        "$deployedRoot/mmproj-F16.gguf",
    )
    private val appRuntimeRoot by lazy { File(context.noBackupFilesDir, "internvl_runtime") }
    private val appRuntimeBinDir by lazy { File(appRuntimeRoot, "bin") }
    private val appRuntimeLibDir by lazy { File(appRuntimeRoot, "lib") }
    private val appRuntimeCliFile by lazy { File(appRuntimeBinDir, "llama-mtmd-cli") }
    private val appRuntimeServerFile by lazy { File(appRuntimeBinDir, "llama-server") }
    private val serverHost = "127.0.0.1"
    private val serverPort = 8080
    private val serverModelAlias = "local-qwen3.5-0.8b-vl"
    private val serverStartupTimeoutMs = 60_000L
    private val linkerPath by lazy {
        sequenceOf(
            "/system/bin/linker64",
            "/apex/com.android.runtime/bin/linker64",
        ).firstOrNull { File(it).exists() } ?: "/system/bin/linker64"
    }
    @Volatile
    private var serverProcess: Process? = null
    @Volatile
    private var serverLastError: String = ""
    @Volatile
    private var serverLogTail: String = ""

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

            "getServerDeploymentStatus" -> {
                result.success(buildServerDeploymentStatus())
                true
            }

            "getServerStatus" -> {
                result.success(buildServerStatus())
                true
            }

            "ensureServerStarted" -> {
                @Suppress("UNCHECKED_CAST")
                val arguments = call.arguments as? Map<String, Any?> ?: emptyMap()
                backgroundExecutor.execute {
                    val payload = ensureServerStarted(arguments)
                    mainHandler.post {
                        result.success(payload)
                    }
                }
                true
            }

            "stopServer" -> {
                backgroundExecutor.execute {
                    val payload = stopServer()
                    mainHandler.post {
                        result.success(payload)
                    }
                }
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
     * 生成“手机是否适合承载本地多模态 Q4 模型”所需的基础画像。
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
     * 返回当前仓库对“手机本地 Qwen-VL / 多模态模型”的真实后端状态。
     *
     * 为什么要单独暴露这个接口：
     * 设备足够强 != 应用已经具备本地运行能力。
     * 目前项目只有 HTTP 方式的 LLM 调用，没有 Android 原生 GGUF 推理后端。
     */
    private fun buildBackendStatus(): Map<String, Any> {
        val deployment = buildServerDeploymentStatus()
        val serverReady = deployment["isRunnable"] == true
        val serverReachable = isServerReachable()

        return mapOf(
            "backendIntegrated" to serverReady,
            "backendName" to if (serverReady) "llama.cpp-server" else "none",
            "supportsDirectOnDeviceInternvl" to serverReady,
            "reason" to if (serverReachable) {
                "本地 llama-server 已在手机侧启动，当前通过 127.0.0.1 的 OpenAI 兼容接口发起多模态推理，模型会随 App 进程常驻内存。"
            } else if (serverReady) {
                "已检测到手机侧 llama-server、主模型和 mmproj 文件；App 可在启动后拉起本地服务，并通过 127.0.0.1 发起推理。"
            } else {
                "当前仓库已切到本地 llama-server 常驻方案，但手机上的 llama-server 可执行文件或模型文件尚未部署完整。"
            },
            "nextStep" to if (serverReachable) {
                "直接通过实验页向 127.0.0.1:8080/v1/chat/completions 发请求即可；若要进一步提速，再继续压缩图片尺寸和输出 token 数。"
            } else if (serverReady) {
                "先由 App 在启动阶段拉起本地 llama-server；若启动失败，再排查手机上的 llama-server 二进制是否存在 Illegal instruction 或缺失依赖。"
            } else {
                "先把 llama-server、依赖动态库、Qwen3.5-0.8B GGUF 和 mmproj 推送到 /data/local/tmp/llama.cpp/checkpoints/qwen，再回到实验页直接测试。"
            }
        )
    }

    private fun buildServerDeploymentStatus(): Map<String, Any> {
        val serverFile = File(serverPath)
        val libDirectory = File(libDir)
        val modelFile = resolveExistingFile(modelPathCandidates)
        val mmprojFile = resolveExistingFile(mmprojPathCandidates)
        val installDirectory = File(installRoot)
        val linkerFile = File(linkerPath)
        val runtimeReady = appRuntimeServerFile.exists() && appRuntimeServerFile.canExecute()

        val missingItems = buildList {
            if (!installDirectory.exists()) add("install-android-baseline 目录缺失")
            if (!serverFile.exists()) add("llama-server 缺失")
            if (!libDirectory.exists()) add("动态库目录缺失")
            if (!modelFile.exists()) add("Qwen 主模型缺失")
            if (!mmprojFile.exists()) add("mmproj 文件缺失")
            if (!linkerFile.exists()) add("Android linker64 缺失")
        }

        val isRunnable = missingItems.isEmpty()

        return mapOf(
            "deployedRoot" to deployedRoot,
            "installRoot" to installRoot,
            "serverPath" to serverPath,
            "linkerPath" to linkerPath,
            "modelPath" to modelFile.path,
            "mmprojPath" to mmprojFile.path,
            "serverExists" to serverFile.exists(),
            "libDirExists" to libDirectory.exists(),
            "modelExists" to modelFile.exists(),
            "mmprojExists" to mmprojFile.exists(),
            "runtimeServerPath" to appRuntimeServerFile.absolutePath,
            "runtimeServerReady" to runtimeReady,
            "serverUrl" to "http://$serverHost:$serverPort/v1/chat/completions",
            "port" to serverPort,
            "isRunnable" to isRunnable,
            "summary" to if (isRunnable) {
                "已检测到本地 llama-server 依赖；App 可先复制到应用私有目录，再通过 Android linker64 拉起常驻服务。"
            } else {
                "本地 llama-server 依赖尚未部署完整：${missingItems.joinToString("；")}"
            },
            "missingItems" to missingItems,
        )
    }

    private fun buildServerStatus(): Map<String, Any> {
        val deployment = buildServerDeploymentStatus()
        val process = serverProcess
        val processAlive = process?.isAlive == true
        val reachable = isServerReachable()
        val ready = (deployment["isRunnable"] == true) && reachable

        return mapOf(
            "running" to (processAlive || reachable),
            "reachable" to reachable,
            "ready" to ready,
            "port" to serverPort,
            "host" to serverHost,
            "modelAlias" to serverModelAlias,
            "serverUrl" to "http://$serverHost:$serverPort",
            "chatCompletionsUrl" to "http://$serverHost:$serverPort/v1/chat/completions",
            "pid" to resolveProcessPid(process),
            "runtimeServerPath" to appRuntimeServerFile.absolutePath,
            "error" to serverLastError,
            "summary" to when {
                ready -> "本地 llama-server 已就绪，当前请求会走 127.0.0.1 HTTP 接口，模型保持常驻。"
                processAlive -> "本地 llama-server 进程已启动，正在等待端口就绪。"
                deployment["isRunnable"] == true -> "本地 llama-server 尚未启动；App 可在需要时自动拉起。"
                else -> deployment["summary"].toString()
            },
        )
    }

    private fun resolveProcessPid(process: Process?): Int {
        if (process == null) {
            return -1
        }

        return try {
            val pidMethod = Process::class.java.getMethod("pid")
            val value = pidMethod.invoke(process)
            (value as? Long)?.toInt() ?: -1
        } catch (_: Throwable) {
            -1
        }
    }

    private fun buildCliDeploymentStatus(): Map<String, Any> {
        val cliFile = File(cliPath)
        val libDirectory = File(libDir)
        val modelFile = resolveExistingFile(modelPathCandidates)
        val mmprojFile = resolveExistingFile(mmprojPathCandidates)
        val installDirectory = File(installRoot)
        val linkerFile = File(linkerPath)
        val runtimeReady = appRuntimeCliFile.exists() && appRuntimeCliFile.canExecute()

        val missingItems = buildList {
            if (!installDirectory.exists()) add("install-android-baseline 目录缺失")
            if (!cliFile.exists()) add("llama-mtmd-cli 缺失")
            if (!libDirectory.exists()) add("动态库目录缺失")
            if (!modelFile.exists()) add("Qwen 主模型缺失")
            if (!mmprojFile.exists()) add("mmproj 文件缺失")
            if (!linkerFile.exists()) add("Android linker64 缺失")
        }

        val isRunnable = missingItems.isEmpty()

        return mapOf(
            "deployedRoot" to deployedRoot,
            "installRoot" to installRoot,
            "cliPath" to cliPath,
            "linkerPath" to linkerPath,
            "modelPath" to modelFile.path,
            "mmprojPath" to mmprojFile.path,
            "cliExists" to cliFile.exists(),
            "libDirExists" to libDirectory.exists(),
            "modelExists" to modelFile.exists(),
            "mmprojExists" to mmprojFile.exists(),
            "runtimeCliPath" to appRuntimeCliFile.absolutePath,
            "runtimeCliReady" to runtimeReady,
            "isRunnable" to isRunnable,
            "summary" to if (isRunnable) {
                "已检测到本地 CLI 依赖，将优先复制到应用私有目录后再通过 Android linker64 启动，规避 /data/local/tmp 执行限制。"
            } else {
                "本地 CLI 依赖尚未部署完整：${missingItems.joinToString("；")}"
            },
            "missingItems" to missingItems,
        )
    }

    private fun resolveExistingFile(pathCandidates: List<String>): File {
        return pathCandidates
            .asSequence()
            .map(::File)
            .firstOrNull { it.exists() }
            ?: File(pathCandidates.first())
    }

    private fun ensureServerStarted(arguments: Map<String, Any?>): Map<String, Any> {
        val deployment = buildServerDeploymentStatus()
        if (deployment["isRunnable"] != true) {
            serverLastError = deployment["summary"]?.toString().orEmpty()
            return buildServerStatus()
        }

        val threads = (arguments["threads"] as? Number)?.toInt()?.coerceIn(1, 8) ?: 4
        val contextSize = (arguments["contextSize"] as? Number)?.toInt()?.coerceIn(512, 4096) ?: 2048

        synchronized(this) {
            if (isServerReachable()) {
                serverLastError = ""
                return buildServerStatus()
            }

            val current = serverProcess
            if (current == null || !current.isAlive) {
                current?.destroyForcibly()
                serverProcess = null
                serverLastError = ""
                serverLogTail = ""
                ensureRuntimeServerStaged()
                serverProcess = startServerProcess(threads, contextSize)
            }
        }

        if (!waitForServerReady(serverStartupTimeoutMs)) {
            return buildServerStatus()
        }

        serverLastError = ""
        return buildServerStatus()
    }

    private fun stopServer(): Map<String, Any> {
        synchronized(this) {
            val current = serverProcess ?: return buildServerStatus()
            current.destroy()
            if (!current.waitFor(3, TimeUnit.SECONDS)) {
                current.destroyForcibly()
            }
            serverProcess = null
        }
        return buildServerStatus()
    }

    private fun waitForServerReady(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (isServerReachable()) {
                return true
            }

            val current = serverProcess
            if (current == null) {
                serverLastError = "llama-server 未启动"
                return false
            }
            if (!current.isAlive) {
                serverProcess = null
                val logTail = serverLogTail.trim()
                serverLastError = if (logTail.isNotEmpty()) {
                    "llama-server 启动失败：$logTail"
                } else {
                    "llama-server 启动失败，退出码=${current.exitValue()}"
                }
                return false
            }

            Thread.sleep(250)
        }

        val logTail = serverLogTail.trim()
        serverLastError = if (logTail.isNotEmpty()) {
            "llama-server 启动超时：$logTail"
        } else {
            "llama-server 启动超时，端口 $serverPort 未在 ${timeoutMs}ms 内就绪"
        }
        return false
    }

    private fun isServerReachable(): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(serverHost, serverPort), 400)
                true
            }
        } catch (_: Throwable) {
            false
        }
    }

    private fun startServerProcess(threads: Int, contextSize: Int): Process {
        val modelFile = resolveExistingFile(modelPathCandidates)
        val mmprojFile = resolveExistingFile(mmprojPathCandidates)
        val command = mutableListOf(
            linkerPath,
            appRuntimeServerFile.absolutePath,
            "-m", modelFile.path,
            "--mmproj", mmprojFile.path,
            "--host", serverHost,
            "--port", serverPort.toString(),
            "--threads", threads.toString(),
            "--ctx-size", contextSize.toString(),
            "--no-webui",
            "--no-mmproj-offload",
        )

        val process = ProcessBuilder(command)
            .directory(appRuntimeRoot)
            .redirectErrorStream(true)
            .apply {
                environment()["LD_LIBRARY_PATH"] = appRuntimeLibDir.absolutePath
            }
            .start()

        Thread {
            try {
                process.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach(::appendServerLog)
                }
            } catch (_: InterruptedIOException) {
                // The process stream can be closed by another thread during stop/restart.
                // This is expected and must not crash the host app process.
            } catch (_: IOException) {
                // Ignore transient stream read errors from the background log tailer.
            } catch (_: Throwable) {
                // Never let the log collector crash the Flutter app.
            }
        }.apply {
            name = "internvl-llama-server-log"
            isDaemon = true
            start()
        }

        return process
    }

    @Synchronized
    private fun appendServerLog(line: String) {
        val trimmed = line.trim()
        if (trimmed.isEmpty()) {
            return
        }
        val combined = if (serverLogTail.isEmpty()) trimmed else "$serverLogTail\n$trimmed"
        serverLogTail = combined.takeLast(12_000)
    }

    private fun ensureRuntimeCliStaged() {
        val sourceCli = File(cliPath)
        if (!sourceCli.exists()) {
            throw IOException("llama-mtmd-cli 不存在：$cliPath")
        }

        if (!appRuntimeBinDir.exists()) {
            appRuntimeBinDir.mkdirs()
        }
        if (!appRuntimeLibDir.exists()) {
            appRuntimeLibDir.mkdirs()
        }

        copyFileIfChanged(sourceCli, appRuntimeCliFile)
        appRuntimeCliFile.setReadable(true, false)
        appRuntimeCliFile.setExecutable(true, false)

        val sourceLibDirectory = File(libDir)
        val sourceLibFiles = sourceLibDirectory.listFiles { file -> file.isFile && file.name.endsWith(".so") }
            ?: emptyArray()
        sourceLibFiles.forEach { sourceLib ->
            val targetLib = File(appRuntimeLibDir, sourceLib.name)
            copyFileIfChanged(sourceLib, targetLib)
            targetLib.setReadable(true, false)
        }
    }

    private fun ensureRuntimeServerStaged() {
        val sourceServer = File(serverPath)
        if (!sourceServer.exists()) {
            throw IOException("llama-server 不存在：$serverPath")
        }

        if (!appRuntimeBinDir.exists()) {
            appRuntimeBinDir.mkdirs()
        }
        if (!appRuntimeLibDir.exists()) {
            appRuntimeLibDir.mkdirs()
        }

        copyFileIfChanged(sourceServer, appRuntimeServerFile)
        appRuntimeServerFile.setReadable(true, false)
        appRuntimeServerFile.setExecutable(true, false)

        val sourceLibDirectory = File(libDir)
        val sourceLibFiles = sourceLibDirectory.listFiles { file -> file.isFile && file.name.endsWith(".so") }
            ?: emptyArray()
        sourceLibFiles.forEach { sourceLib ->
            val targetLib = File(appRuntimeLibDir, sourceLib.name)
            copyFileIfChanged(sourceLib, targetLib)
            targetLib.setReadable(true, false)
        }
    }

    private fun copyFileIfChanged(source: File, target: File) {
        val needsCopy = !target.exists() ||
            target.length() != source.length() ||
            target.lastModified() < source.lastModified()
        if (!needsCopy) {
            return
        }

        target.parentFile?.mkdirs()
        source.inputStream().use { input ->
            target.outputStream().use { output ->
                input.copyTo(output)
            }
        }
        target.setLastModified(source.lastModified())
    }

    private fun parseImagePaths(arguments: Map<String, Any?>): List<String> {
        val listPaths = (arguments["imagePaths"] as? List<*>)
            ?.mapNotNull { item -> item?.toString()?.trim()?.takeIf { it.isNotEmpty() } }
            ?: emptyList()
        if (listPaths.isNotEmpty()) {
            return listPaths
        }

        val single = arguments["imagePath"]?.toString()?.trim().orEmpty()
        return if (single.isEmpty()) emptyList() else listOf(single)
    }

    private fun parseImageMetadatas(arguments: Map<String, Any?>): List<Map<String, Any?>> {
        val raw = arguments["imageMetadatas"] as? List<*> ?: return emptyList()
        return raw.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            map.entries.associate { (key, value) -> key.toString() to value }
        }
    }

    private fun buildSystemPrompt(
        imagePaths: List<String>,
        imageMetadatas: List<Map<String, Any?>>,
    ): String {
        val lines = mutableListOf<String>()
        lines += "你是一个多图视觉分析助手。"
        lines += "本次输入包含 ${imagePaths.size} 张图片，请综合全部图片回答问题。"
        lines += "请将图片元数据(时间/地点)作为上下文依据，但不要编造缺失信息。"
        lines += ""
        lines += "图片元数据:"

        imagePaths.forEachIndexed { index, _ ->
            val metadata = imageMetadatas.getOrNull(index)
            val capturedAt = metadata?.get("capturedAtIso")?.toString()?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?: "未知时间"
            val locationName = metadata?.get("locationName")?.toString()?.trim()
                ?.takeIf { it.isNotEmpty() }
                ?: "未知地点"
            val latitude = (metadata?.get("latitude") as? Number)?.toDouble()
            val longitude = (metadata?.get("longitude") as? Number)?.toDouble()
            val coordinateText = if (latitude != null && longitude != null) {
                "，坐标=%.5f, %.5f".format(latitude, longitude)
            } else {
                ""
            }

            lines += "- 图片${index + 1}: 时间=$capturedAt，地点=$locationName$coordinateText"
        }

        lines += ""
        lines += "回答要求:"
        lines += "1) 请结合元数据，理解图片内容。"
        lines += "2) 结合图片与主题要求，生成一段有文采的故事。"
        return lines.joinToString("\n")
    }

    private fun composePromptWithMetadata(
        userPrompt: String,
        imagePaths: List<String>,
        imageMetadatas: List<Map<String, Any?>>,
    ): String {
        val systemPrompt = buildSystemPrompt(imagePaths, imageMetadatas)
        return buildString {
            append("[系统提示]\n")
            append(systemPrompt)
            append("\n\n[用户问题]\n")
            append(userPrompt)
        }
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

        val imagePaths = parseImagePaths(arguments)
        val imageMetadatas = parseImageMetadatas(arguments)
        val prompt = arguments["prompt"]?.toString()?.trim().orEmpty()
        val modelFile = resolveExistingFile(modelPathCandidates)
        val mmprojFile = resolveExistingFile(mmprojPathCandidates)
        val threads = (arguments["threads"] as? Number)?.toInt()?.coerceIn(1, 8) ?: 4
        val contextSize = (arguments["contextSize"] as? Number)?.toInt()?.coerceIn(512, 4096) ?: 2048
        val maxTokens = (arguments["maxTokens"] as? Number)?.toInt()?.coerceIn(16, 256) ?: 96
        val timeoutMs = (arguments["timeoutMs"] as? Number)?.toLong()?.coerceAtLeast(10_000L) ?: 180_000L

        if (!modelFile.exists()) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to "主模型缺失：${modelFile.path}",
                "exitCode" to -1,
                "durationMs" to 0L,
            )
        }

        if (!mmprojFile.exists()) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to "mmproj 缺失：${mmprojFile.path}",
                "exitCode" to -1,
                "durationMs" to 0L,
            )
        }

        if (imagePaths.isEmpty()) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to "至少需要一张可访问的图片",
                "exitCode" to -1,
                "durationMs" to 0L,
            )
        }

        val missingPath = imagePaths.firstOrNull { imagePath -> !File(imagePath).exists() }
        if (missingPath != null) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to "测试图片不存在或不可访问：$missingPath",
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

        ensureRuntimeCliStaged()

        val runtimeCliPath = appRuntimeCliFile.absolutePath
        val runtimeLibDir = appRuntimeLibDir.absolutePath
        val composedPrompt = composePromptWithMetadata(prompt, imagePaths, imageMetadatas)

        val command = mutableListOf(
            linkerPath,
            runtimeCliPath,
            "--model", modelFile.path,
            "--mmproj", mmprojFile.path,
        )
        imagePaths.forEach { imagePath ->
            command += "--image"
            command += imagePath
        }
        command += "--prompt"
        command += composedPrompt
        command += "-c"
        command += contextSize.toString()
        command += "-n"
        command += maxTokens.toString()
        command += "-t"
        command += threads.toString()
        command += "--no-mmproj-offload"

        val startTime = System.currentTimeMillis()
        return try {
            val process = ProcessBuilder(command)
                .directory(appRuntimeRoot)
                .redirectErrorStream(true)
                .apply {
                    environment()["LD_LIBRARY_PATH"] = runtimeLibDir
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
                    append("；已尝试将 CLI 复制到应用私有目录后，通过 ")
                    append(linkerPath)
                    append(" 启动。若仍失败，建议改为 JNI 方式直接集成推理内核。")
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
            .filterNot(::isDiagnosticLine)
            .joinToString("\n")
            .trim()
    }

    private fun isDiagnosticLine(line: String): Boolean {
        return line.startsWith("build:") ||
            line.startsWith("main:") ||
            line.startsWith("system_info:") ||
            line.startsWith("llama_model_loader:") ||
            line.startsWith("llama_context:") ||
            line.startsWith("llama_perf_") ||
            line.startsWith("llama_params_fit") ||
            line.startsWith("common_init_result:") ||
            line.startsWith("common_init_from_params:") ||
            line.startsWith("encode_image_with_clip:") ||
            line.startsWith("load_image_size:") ||
            line.startsWith("load_hparams:") ||
            line.startsWith("load:") ||
            line.startsWith("print_info:") ||
            line.startsWith("print_image_embed") ||
            line.startsWith("clip_model_load:") ||
            line.startsWith("clip_image_load_from_bytes:") ||
            line.startsWith("clip:") ||
            line.startsWith("sampler seed:") ||
            line.startsWith("warmup:") ||
            line.startsWith("alloc_compute_meta:") ||
            line.startsWith("decoding image batch") ||
            line.startsWith("image slice encoded") ||
            line.startsWith("image decoded") ||
            line.startsWith("For normal use cases") ||
            line.startsWith("WARN:") ||
            line == "--- vision hparams ---" ||
            line == "---"
    }
}