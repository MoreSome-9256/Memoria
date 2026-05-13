package com.example.photo_album

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.io.InterruptedIOException
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.min

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

    private val bundledRoot by lazy { File(context.noBackupFilesDir, "local_llm") }
    private val bundledInstallRoot by lazy { File(bundledRoot, "install-android-baseline") }
    private val bundledCheckpointsRoot by lazy { File(File(bundledRoot, "checkpoints"), "qwen") }
    private val bundledCliFile by lazy { File(File(bundledInstallRoot, "bin"), "llama-mtmd-cli") }
    private val bundledServerFile by lazy { File(File(bundledInstallRoot, "bin"), "llama-server") }
    private val bundledLibDir by lazy { File(bundledInstallRoot, "lib") }
    private val bundledModelFile by lazy { File(bundledCheckpointsRoot, "Qwen3.5-0.8B-Q4_K_M.gguf") }
    private val bundledMmprojFile by lazy { File(bundledCheckpointsRoot, "mmproj-F16.gguf") }
    private val bundledVersionFile by lazy { File(bundledRoot, ".asset_version") }
    private val bundledAssetVersion = "full_local_vlm_v1"
    private val packagedAssetRoot = "local_llm"

    private val appRuntimeRoot by lazy { File(context.noBackupFilesDir, "internvl_runtime") }
    private val appRuntimeBinDir by lazy { File(appRuntimeRoot, "bin") }
    private val appRuntimeLibDir by lazy { File(appRuntimeRoot, "lib") }
    private val appRuntimeCliFile by lazy { File(appRuntimeBinDir, "llama-mtmd-cli") }
    private val appRuntimeServerFile by lazy { File(appRuntimeBinDir, "llama-server") }

    private val serverHost = "127.0.0.1"
    private val serverPort = 8080
    private val serverModelAlias = "local-qwen3.5-0.8b-vl"
    private val serverStartupTimeoutMs = 60_000L
    private val serverInferenceWarmupTimeoutMs = 12_000L
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

    @Volatile
    private var serverInferenceReady: Boolean = false

    private val warmupImageDataUrl =
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2ioAAAAASUVORK5CYII="

    private data class DeploymentPaths(
        val source: String,
        val installRoot: File,
        val cliFile: File,
        val serverFile: File,
        val libDirectory: File,
        val modelFile: File,
        val mmprojFile: File,
        val packagedFromApk: Boolean,
    )

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
                    mainHandler.post { result.success(payload) }
                }
                true
            }

            "stopServer" -> {
                backgroundExecutor.execute {
                    val payload = stopServer()
                    mainHandler.post { result.success(payload) }
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
                    result.error("invalid_arguments", "Missing CLI arguments", null)
                } else {
                    backgroundExecutor.execute {
                        val payload = runCliExperiment(arguments)
                        mainHandler.post { result.success(payload) }
                    }
                }
                true
            }

            else -> false
        }
    }

    private fun buildDeviceProfile(): Map<String, Any> {
        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        val totalRamMb = (memoryInfo.totalMem / (1024L * 1024L)).toInt()
        val availableProcessors = Runtime.getRuntime().availableProcessors()
        val primaryAbi = Build.SUPPORTED_ABIS.firstOrNull().orEmpty()
        val recommendedThreads = min(max(availableProcessors / 2, 2), 6)

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
            append(", RAM~")
            append(totalRamMb)
            append("MB, CPU threads=")
            append(availableProcessors)
            append(", suggested threads=")
            append(recommendedThreads)
            append(", pressure=")
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
            "npuAvailableThroughApp" to false,
            "pressureLevel" to pressureLevel,
            "summary" to summary,
        )
    }

    private fun buildBackendStatus(): Map<String, Any> {
        val deployment = buildServerDeploymentStatus()
        val serverReady = deployment["isRunnable"] == true
        val serverReachable = isServerReachable()

        val reason = when {
            serverReachable ->
                "The local llama-server is already reachable on 127.0.0.1 and can serve multimodal requests."
            serverReady ->
                "The device has all required local VLM files. The app can start llama-server on demand."
            else ->
                "The app does not yet have a complete local VLM runtime or model deployment on this device."
        }

        val nextStep = when {
            serverReachable ->
                "Call the local OpenAI-compatible endpoint directly for inference."
            serverReady ->
                "Start the local server from the app, then verify warmup and image inference."
            else ->
                "Install or bundle llama.cpp runtime, GGUF model, and mmproj assets before testing local VLM."
        }

        return mapOf(
            "backendIntegrated" to serverReady,
            "backendName" to if (serverReady) "llama.cpp-server" else "none",
            "supportsDirectOnDeviceInternvl" to serverReady,
            "reason" to reason,
            "nextStep" to nextStep,
        )
    }

    private fun buildServerDeploymentStatus(): Map<String, Any> {
        val linkerFile = File(linkerPath)
        val deployment = resolveDeploymentPaths()
        val runtimeReady = appRuntimeServerFile.exists() && appRuntimeServerFile.canExecute()

        val missingItems = buildList {
            if (!deployment.installRoot.exists() && !deployment.packagedFromApk) add("install-android-baseline missing")
            if (!deployment.serverFile.exists() && !deployment.packagedFromApk) add("llama-server missing")
            if (!deployment.libDirectory.exists() && !deployment.packagedFromApk) add("shared libraries missing")
            if (!deployment.modelFile.exists() && !deployment.packagedFromApk) add("Qwen GGUF missing")
            if (!deployment.mmprojFile.exists() && !deployment.packagedFromApk) add("mmproj missing")
            if (!linkerFile.exists()) add("linker64 missing")
        }

        val isRunnable = missingItems.isEmpty()
        val summary = when {
            isRunnable && deployment.packagedFromApk ->
                "Full APK assets are bundled. The app can extract them to private storage and launch llama-server."
            isRunnable ->
                "External llama.cpp runtime and models are ready. The app can stage them into private storage and launch the server."
            else ->
                "Local VLM runtime is incomplete: ${missingItems.joinToString(", ")}"
        }

        return mapOf(
            "deployedRoot" to if (deployment.source == "external") deployedRoot else bundledRoot.absolutePath,
            "installRoot" to deployment.installRoot.path,
            "serverPath" to deployment.serverFile.path,
            "linkerPath" to linkerPath,
            "modelPath" to deployment.modelFile.path,
            "mmprojPath" to deployment.mmprojFile.path,
            "serverExists" to (deployment.serverFile.exists() || deployment.packagedFromApk),
            "libDirExists" to (deployment.libDirectory.exists() || deployment.packagedFromApk),
            "modelExists" to (deployment.modelFile.exists() || deployment.packagedFromApk),
            "mmprojExists" to (deployment.mmprojFile.exists() || deployment.packagedFromApk),
            "runtimeServerPath" to appRuntimeServerFile.absolutePath,
            "runtimeServerReady" to runtimeReady,
            "serverUrl" to "http://$serverHost:$serverPort/v1/chat/completions",
            "port" to serverPort,
            "isRunnable" to isRunnable,
            "summary" to summary,
            "missingItems" to missingItems,
        )
    }

    private fun buildServerStatus(): Map<String, Any> {
        val deployment = buildServerDeploymentStatus()
        val process = serverProcess
        val processAlive = process?.isAlive == true
        val reachable = isServerReachable()
        val ready = (deployment["isRunnable"] == true) && reachable && serverInferenceReady

        val summary = when {
            ready ->
                "Local llama-server is ready. Multimodal requests will be sent to 127.0.0.1."
            processAlive ->
                "Local llama-server is running and waiting for readiness."
            deployment["isRunnable"] == true ->
                "Local runtime is ready, but the server has not been started yet."
            else -> deployment["summary"].toString()
        }

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
            "summary" to summary,
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
        val linkerFile = File(linkerPath)
        val deployment = resolveDeploymentPaths()
        val runtimeReady = appRuntimeCliFile.exists() && appRuntimeCliFile.canExecute()

        val missingItems = buildList {
            if (!deployment.installRoot.exists() && !deployment.packagedFromApk) add("install-android-baseline missing")
            if (!deployment.cliFile.exists() && !deployment.packagedFromApk) add("llama-mtmd-cli missing")
            if (!deployment.libDirectory.exists() && !deployment.packagedFromApk) add("shared libraries missing")
            if (!deployment.modelFile.exists() && !deployment.packagedFromApk) add("Qwen GGUF missing")
            if (!deployment.mmprojFile.exists() && !deployment.packagedFromApk) add("mmproj missing")
            if (!linkerFile.exists()) add("linker64 missing")
        }

        val isRunnable = missingItems.isEmpty()
        val summary = when {
            isRunnable && deployment.packagedFromApk ->
                "Full APK assets are bundled. The app can extract them and run the local CLI."
            isRunnable ->
                "External local CLI runtime is ready and can be staged into app-private storage."
            else ->
                "Local CLI runtime is incomplete: ${missingItems.joinToString(", ")}"
        }

        return mapOf(
            "deployedRoot" to if (deployment.source == "external") deployedRoot else bundledRoot.absolutePath,
            "installRoot" to deployment.installRoot.path,
            "cliPath" to deployment.cliFile.path,
            "linkerPath" to linkerPath,
            "modelPath" to deployment.modelFile.path,
            "mmprojPath" to deployment.mmprojFile.path,
            "cliExists" to (deployment.cliFile.exists() || deployment.packagedFromApk),
            "libDirExists" to (deployment.libDirectory.exists() || deployment.packagedFromApk),
            "modelExists" to (deployment.modelFile.exists() || deployment.packagedFromApk),
            "mmprojExists" to (deployment.mmprojFile.exists() || deployment.packagedFromApk),
            "runtimeCliPath" to appRuntimeCliFile.absolutePath,
            "runtimeCliReady" to runtimeReady,
            "isRunnable" to isRunnable,
            "summary" to summary,
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

    private fun resolveDeploymentPaths(): DeploymentPaths {
        val externalModelFile = resolveExistingFile(modelPathCandidates)
        val externalMmprojFile = resolveExistingFile(mmprojPathCandidates)
        val externalDeploymentReady =
            File(serverPath).exists() &&
                File(cliPath).exists() &&
                File(libDir).exists() &&
                externalModelFile.exists() &&
                externalMmprojFile.exists()
        if (externalDeploymentReady) {
            return DeploymentPaths(
                source = "external",
                installRoot = File(installRoot),
                cliFile = File(cliPath),
                serverFile = File(serverPath),
                libDirectory = File(libDir),
                modelFile = externalModelFile,
                mmprojFile = externalMmprojFile,
                packagedFromApk = false,
            )
        }

        val bundledDeploymentReady =
            bundledServerFile.exists() &&
                bundledCliFile.exists() &&
                bundledLibDir.exists() &&
                bundledModelFile.exists() &&
                bundledMmprojFile.exists()

        return DeploymentPaths(
            source = if (bundledDeploymentReady) "bundled_installed" else "bundled_assets",
            installRoot = bundledInstallRoot,
            cliFile = bundledCliFile,
            serverFile = bundledServerFile,
            libDirectory = bundledLibDir,
            modelFile = bundledModelFile,
            mmprojFile = bundledMmprojFile,
            packagedFromApk = !bundledDeploymentReady && hasPackagedLocalLlmAssets(),
        )
    }

    private fun ensureServerStarted(arguments: Map<String, Any?>): Map<String, Any> {
        ensureBundledAssetsInstalledIfNeeded()
        val deployment = buildServerDeploymentStatus()
        if (deployment["isRunnable"] != true) {
            serverLastError = deployment["summary"]?.toString().orEmpty()
            return buildServerStatus()
        }

        val threads = (arguments["threads"] as? Number)?.toInt()?.coerceIn(1, 8) ?: 4
        val contextSize =
            (arguments["contextSize"] as? Number)?.toInt()?.coerceIn(512, 4096) ?: 2048

        synchronized(this) {
            if (isServerReachable() && serverInferenceReady) {
                serverLastError = ""
                return buildServerStatus()
            }

            val current = serverProcess
            if (current == null || !current.isAlive) {
                current?.destroyForcibly()
                serverProcess = null
                serverInferenceReady = false
                serverLastError = ""
                serverLogTail = ""
                ensureRuntimeServerStaged()
                serverProcess = startServerProcess(threads, contextSize)
            }
        }

        if (!waitForServerReady(serverStartupTimeoutMs)) {
            return buildServerStatus()
        }

        serverInferenceReady = waitForServerInferenceReady(serverInferenceWarmupTimeoutMs)
        if (serverInferenceReady) {
            serverLastError = ""
        }
        return buildServerStatus()
    }

    private fun stopServer(): Map<String, Any> {
        synchronized(this) {
            val current = serverProcess
            serverProcess = null
            serverInferenceReady = false
            if (current != null) {
                try {
                    current.destroy()
                    if (!current.waitFor(1500, TimeUnit.MILLISECONDS)) {
                        current.destroyForcibly()
                    }
                } catch (_: Throwable) {
                    current.destroyForcibly()
                }
            }
        }
        serverLastError = ""
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
                serverLastError = "llama-server is not running"
                return false
            }
            if (!current.isAlive) {
                serverProcess = null
                val logTail = serverLogTail.trim()
                serverLastError = if (logTail.isNotEmpty()) {
                    "llama-server failed to start: $logTail"
                } else {
                    "llama-server failed to start, exitCode=${current.exitValue()}"
                }
                return false
            }

            Thread.sleep(250)
        }

        val logTail = serverLogTail.trim()
        serverLastError = if (logTail.isNotEmpty()) {
            "llama-server startup timed out: $logTail"
        } else {
            "llama-server did not expose port $serverPort within ${timeoutMs}ms"
        }
        return false
    }

    private fun waitForServerInferenceReady(timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val current = serverProcess
            if (current == null) {
                serverLastError = "llama-server is not running"
                return false
            }
            if (!current.isAlive) {
                serverProcess = null
                serverInferenceReady = false
                val logTail = serverLogTail.trim()
                serverLastError = if (logTail.isNotEmpty()) {
                    "llama-server warmup failed: $logTail"
                } else {
                    "llama-server warmup failed, exitCode=${current.exitValue()}"
                }
                return false
            }
            if (tryWarmupCompletion()) {
                serverLastError = ""
                return true
            }
            Thread.sleep(600)
        }

        val logTail = serverLogTail.trim()
        serverLastError = if (logTail.isNotEmpty()) {
            "llama-server is reachable but warmup timed out: $logTail"
        } else {
            "llama-server is reachable, but the model was not ready within ${timeoutMs}ms"
        }
        return false
    }

    private fun tryWarmupCompletion(): Boolean {
        val body = """
            {
              "model": "$serverModelAlias",
              "messages": [
                {
                  "role": "user",
                  "content": [
                    {"type": "text", "text": "Describe this test image in one word."},
                    {"type": "image_url", "image_url": {"url": "$warmupImageDataUrl"}}
                  ]
                }
              ],
              "max_tokens": 8,
              "temperature": 0.0,
              "stream": false
            }
        """.trimIndent()

        return try {
            val connection = (URL("http://$serverHost:$serverPort/v1/chat/completions")
                .openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 1500
                readTimeout = 4000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
            connection.outputStream.bufferedWriter(Charsets.UTF_8).use { writer ->
                writer.write(body)
            }
            val code = connection.responseCode
            if (code == 200) {
                connection.inputStream.close()
                true
            } else {
                val errorText =
                    connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
                if (code != 503 && errorText.isNotBlank()) {
                    appendServerLog("warmup_http_$code: $errorText")
                }
                false
            }
        } catch (_: Throwable) {
            false
        }
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
        val deployment = resolveDeploymentPaths()
        val modelFile = deployment.modelFile
        val mmprojFile = deployment.mmprojFile
        val command = mutableListOf(
            linkerPath,
            appRuntimeServerFile.absolutePath,
            "-m",
            modelFile.path,
            "--mmproj",
            mmprojFile.path,
            "--host",
            serverHost,
            "--port",
            serverPort.toString(),
            "--threads",
            threads.toString(),
            "--ctx-size",
            contextSize.toString(),
            "--alias",
            serverModelAlias,
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
            } catch (_: IOException) {
            } catch (_: Throwable) {
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
        ensureBundledAssetsInstalledIfNeeded()
        val deployment = resolveDeploymentPaths()
        val sourceCli = deployment.cliFile
        if (!sourceCli.exists()) {
            throw IOException("llama-mtmd-cli not found: ${sourceCli.path}")
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

        val sourceLibFiles =
            deployment.libDirectory.listFiles { file ->
                file.isFile && file.name.endsWith(".so")
            } ?: emptyArray()
        sourceLibFiles.forEach { sourceLib ->
            val targetLib = File(appRuntimeLibDir, sourceLib.name)
            copyFileIfChanged(sourceLib, targetLib)
            targetLib.setReadable(true, false)
        }
    }

    private fun ensureRuntimeServerStaged() {
        ensureBundledAssetsInstalledIfNeeded()
        val deployment = resolveDeploymentPaths()
        val sourceServer = deployment.serverFile
        if (!sourceServer.exists()) {
            throw IOException("llama-server not found: ${sourceServer.path}")
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

        val sourceLibFiles =
            deployment.libDirectory.listFiles { file ->
                file.isFile && file.name.endsWith(".so")
            } ?: emptyArray()
        sourceLibFiles.forEach { sourceLib ->
            val targetLib = File(appRuntimeLibDir, sourceLib.name)
            copyFileIfChanged(sourceLib, targetLib)
            targetLib.setReadable(true, false)
        }
    }

    private fun copyFileIfChanged(source: File, target: File) {
        val needsCopy =
            !target.exists() ||
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
        lines += "You are a multimodal photo analysis assistant."
        lines += "This request contains ${imagePaths.size} image(s). Use all images together when answering."
        lines += "Use time and location metadata as soft context, but do not invent missing facts."
        lines += ""
        lines += "Image metadata:"

        imagePaths.forEachIndexed { index, _ ->
            val metadata = imageMetadatas.getOrNull(index)
            val capturedAt =
                metadata?.get("capturedAtIso")?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                    ?: "unknown time"
            val locationName =
                metadata?.get("locationName")?.toString()?.trim()?.takeIf { it.isNotEmpty() }
                    ?: "unknown location"
            val latitude = (metadata?.get("latitude") as? Number)?.toDouble()
            val longitude = (metadata?.get("longitude") as? Number)?.toDouble()
            val coordinateText =
                if (latitude != null && longitude != null) {
                    ", coordinates=${"%.5f".format(latitude)}, ${"%.5f".format(longitude)}"
                } else {
                    ""
                }

            lines += "- Image ${index + 1}: time=$capturedAt, location=$locationName$coordinateText"
        }

        lines += ""
        lines += "Requirements:"
        lines += "1. Understand the content of the images with the metadata."
        lines += "2. Answer naturally and focus on what is actually visible."
        lines += "3. If the user asks for a story or summary, keep it coherent and vivid."
        return lines.joinToString("\n")
    }

    private fun composePromptWithMetadata(
        userPrompt: String,
        imagePaths: List<String>,
        imageMetadatas: List<Map<String, Any?>>,
    ): String {
        val systemPrompt = buildSystemPrompt(imagePaths, imageMetadatas)
        return buildString {
            append("[system]\n")
            append(systemPrompt)
            append("\n\n[user]\n")
            append(userPrompt)
        }
    }

    private fun runCliExperiment(arguments: Map<String, Any?>): Map<String, Any> {
        ensureBundledAssetsInstalledIfNeeded()
        val deployment = buildCliDeploymentStatus()
        if (deployment["isRunnable"] != true) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to (deployment["summary"]?.toString() ?: "Local CLI runtime is not ready"),
                "exitCode" to -1,
                "durationMs" to 0L,
            )
        }

        val imagePaths = parseImagePaths(arguments)
        val imageMetadatas = parseImageMetadatas(arguments)
        val prompt = arguments["prompt"]?.toString()?.trim().orEmpty()
        val activeDeployment = resolveDeploymentPaths()
        val modelFile = activeDeployment.modelFile
        val mmprojFile = activeDeployment.mmprojFile
        val threads = (arguments["threads"] as? Number)?.toInt()?.coerceIn(1, 8) ?: 4
        val contextSize =
            (arguments["contextSize"] as? Number)?.toInt()?.coerceIn(512, 4096) ?: 2048
        val maxTokens = (arguments["maxTokens"] as? Number)?.toInt()?.coerceIn(16, 256) ?: 96
        val timeoutMs =
            (arguments["timeoutMs"] as? Number)?.toLong()?.coerceAtLeast(10_000L) ?: 180_000L

        if (!modelFile.exists()) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to "Model file not found: ${modelFile.path}",
                "exitCode" to -1,
                "durationMs" to 0L,
            )
        }

        if (!mmprojFile.exists()) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to "mmproj file not found: ${mmprojFile.path}",
                "exitCode" to -1,
                "durationMs" to 0L,
            )
        }

        if (imagePaths.isEmpty()) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to "At least one image is required",
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
                "error" to "Image file is not accessible: $missingPath",
                "exitCode" to -1,
                "durationMs" to 0L,
            )
        }

        if (prompt.isEmpty()) {
            return mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to "Prompt cannot be empty",
                "exitCode" to -1,
                "durationMs" to 0L,
            )
        }

        ensureRuntimeCliStaged()

        val composedPrompt = composePromptWithMetadata(prompt, imagePaths, imageMetadatas)
        val command = mutableListOf(
            linkerPath,
            appRuntimeCliFile.absolutePath,
            "--model",
            modelFile.path,
            "--mmproj",
            mmprojFile.path,
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
                    environment()["LD_LIBRARY_PATH"] = appRuntimeLibDir.absolutePath
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
                    "error" to "Local CLI inference timed out after ${timeoutMs}ms",
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
                    "error" to if (exitCode == 0) "" else "CLI exited with code $exitCode",
                    "exitCode" to exitCode,
                    "durationMs" to durationMs,
                )
            }
        } catch (error: Throwable) {
            mapOf(
                "success" to false,
                "answer" to "",
                "rawOutput" to "",
                "error" to (error.message ?: error.toString()),
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

        val normalized = candidateLines
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .filterNot(::isDiagnosticLine)
            .joinToString("\n")
            .trim()

        extractJsonObject(normalized)?.let { return it }
        return normalized
    }

    private fun extractJsonObject(text: String): String? {
        val firstBrace = text.indexOf('{')
        val lastBrace = text.lastIndexOf('}')
        if (firstBrace < 0 || lastBrace <= firstBrace) {
            return null
        }
        return text.substring(firstBrace, lastBrace + 1).trim()
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
            line.contains("<think>") ||
            line.contains("</think>") ||
            line == "--- vision hparams ---" ||
            line == "---"
    }

    private fun hasPackagedLocalLlmAssets(): Boolean {
        return assetExists("$packagedAssetRoot/install-android-baseline/bin/llama-server") &&
            assetExists("$packagedAssetRoot/install-android-baseline/bin/llama-mtmd-cli") &&
            assetExists("$packagedAssetRoot/checkpoints/qwen/Qwen3.5-0.8B-Q4_K_M.gguf") &&
            assetExists("$packagedAssetRoot/checkpoints/qwen/mmproj-F16.gguf")
    }

    private fun ensureBundledAssetsInstalledIfNeeded() {
        if (!hasPackagedLocalLlmAssets()) {
            return
        }

        val versionMatches =
            bundledVersionFile.exists() &&
                bundledVersionFile.readText().trim() == bundledAssetVersion
        val installationReady =
            bundledServerFile.exists() &&
                bundledCliFile.exists() &&
                bundledModelFile.exists() &&
                bundledMmprojFile.exists() &&
                bundledLibDir.exists()
        if (versionMatches && installationReady) {
            return
        }

        bundledRoot.deleteRecursively()
        copyAssetTree("$packagedAssetRoot/install-android-baseline/bin", File(bundledInstallRoot, "bin"))
        copyAssetTree("$packagedAssetRoot/install-android-baseline/lib", bundledLibDir)
        copyAssetTree("$packagedAssetRoot/checkpoints/qwen", bundledCheckpointsRoot)
        bundledCliFile.setReadable(true, false)
        bundledCliFile.setExecutable(true, false)
        bundledServerFile.setReadable(true, false)
        bundledServerFile.setExecutable(true, false)
        bundledVersionFile.parentFile?.mkdirs()
        bundledVersionFile.writeText(bundledAssetVersion)
    }

    private fun copyAssetTree(assetPath: String, targetDir: File) {
        val children = context.assets.list(assetPath) ?: emptyArray()
        if (children.isEmpty()) {
            copyAssetFile(assetPath, targetDir)
            return
        }

        if (!targetDir.exists()) {
            targetDir.mkdirs()
        }
        for (child in children) {
            val childAssetPath = "$assetPath/$child"
            val nestedChildren = context.assets.list(childAssetPath) ?: emptyArray()
            if (nestedChildren.isEmpty()) {
                copyAssetFile(childAssetPath, File(targetDir, child))
            } else {
                copyAssetTree(childAssetPath, File(targetDir, child))
            }
        }
    }

    private fun copyAssetFile(assetPath: String, targetFile: File) {
        targetFile.parentFile?.mkdirs()
        context.assets.open(assetPath).use { input ->
            targetFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }
    }

    private fun assetExists(assetPath: String): Boolean {
        return try {
            context.assets.open(assetPath).use { true }
        } catch (_: IOException) {
            false
        }
    }
}

