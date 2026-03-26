import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:llamadart/llamadart.dart';

enum LocalVlmComputeBackend {
  vulkan,
  cpu,
}

class LocalVlmGenerationStats {
  const LocalVlmGenerationStats({
    required this.elapsed,
    required this.chunkCount,
    required this.charCount,
    required this.charsPerSecond,
    required this.firstChunkLatency,
  });

  final Duration elapsed;
  final int chunkCount;
  final int charCount;
  final double charsPerSecond;
  final Duration? firstChunkLatency;
}

/// 基于 llamadart 的本地 FFI 推理服务。
///
/// 这个服务只负责模型生命周期与多模态推理，不关心 UI 层或业务结构化输出。
class LlamadartLocalEngineService {
  LlamadartLocalEngineService._internal();

  static const String _logName = 'LocalVLM';
  static const int _gpuLayers = int.fromEnvironment(
    'LOCAL_LLAMADART_GPU_LAYERS',
    defaultValue: 0,
  );
  static const bool _preferVulkanBackend = bool.fromEnvironment(
    'LOCAL_LLAMADART_PREFER_VULKAN',
    defaultValue: true,
  );
  static const bool _androidCpuGuardEnabled = bool.fromEnvironment(
    'LOCAL_LLAMADART_ANDROID_CPU_GUARD',
    defaultValue: true,
  );
  static const String _androidCpuAnyRequiredFeatures = String.fromEnvironment(
    'LOCAL_LLAMADART_ANDROID_CPU_ANY_FEATURES',
    defaultValue: 'asimddp,i8mm,dotprod',
  );
  static const int _generationTimeoutSeconds = int.fromEnvironment(
    'LOCAL_LLAMADART_GENERATION_TIMEOUT_SECONDS',
    defaultValue: 180,
  );

  static final LlamadartLocalEngineService _instance =
      LlamadartLocalEngineService._internal();

  factory LlamadartLocalEngineService() => _instance;

  LlamaEngine? _engine;
  String? _loadedModelPath;
  String? _loadedMmprojPath;
  LocalVlmComputeBackend? _loadedBackend;
  LocalVlmGenerationStats? _lastGenerationStats;

  bool get isLoaded => _engine != null;
  LocalVlmGenerationStats? get lastGenerationStats => _lastGenerationStats;

  static String _formatBytes(int bytes) {
    final kb = bytes / 1024;
    final mb = kb / 1024;
    final gb = mb / 1024;
    if (gb >= 1) {
      return '${gb.toStringAsFixed(2)} GB';
    }
    if (mb >= 1) {
      return '${mb.toStringAsFixed(2)} MB';
    }
    if (kb >= 1) {
      return '${kb.toStringAsFixed(2)} KB';
    }
    return '$bytes B';
  }

  static int _safeCurrentRss() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return -1;
    }
  }

  static void _log(String message) {
    developer.log(message, name: _logName);
  }

  static LocalVlmComputeBackend _defaultBackend() {
    return _preferVulkanBackend
        ? LocalVlmComputeBackend.vulkan
        : LocalVlmComputeBackend.cpu;
  }

  static GpuBackend _gpuBackend(LocalVlmComputeBackend backend) {
    return backend == LocalVlmComputeBackend.vulkan
        ? GpuBackend.vulkan
        : GpuBackend.cpu;
  }

  static String _backendLabel(LocalVlmComputeBackend backend) {
    return backend == LocalVlmComputeBackend.vulkan ? 'vulkan' : 'cpu';
  }

  static bool looksLikeOom(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('outofmemory') ||
        text.contains('out of memory') ||
        text.contains('oom') ||
        text.contains('scudo oom') ||
        text.contains('cannot allocate') ||
        text.contains('std::bad_alloc') ||
        text.contains('memory');
  }

  static String describeRuntimeMemory() {
    final rss = _safeCurrentRss();
    if (rss < 0) {
      return 'currentRss=unavailable';
    }
    return 'currentRss=${_formatBytes(rss)}';
  }

  static Set<String> _readAndroidCpuFeatures() {
    try {
      final cpuInfo = File('/proc/cpuinfo').readAsStringSync();
      final lines = cpuInfo.split('\n');
      final featureLines = lines.where(
        (line) => line.toLowerCase().startsWith('features'),
      );
      final result = <String>{};
      for (final line in featureLines) {
        final idx = line.indexOf(':');
        if (idx < 0 || idx + 1 >= line.length) {
          continue;
        }
        final flags = line
            .substring(idx + 1)
            .trim()
            .toLowerCase()
            .split(RegExp(r'\s+'));
        for (final item in flags) {
          if (item.isNotEmpty) {
            result.add(item);
          }
        }
      }
      return result;
    } catch (_) {
      return const <String>{};
    }
  }

  static void _runAndroidCpuGuardIfNeeded() {
    if (!_androidCpuGuardEnabled || !Platform.isAndroid) {
      return;
    }

    final required = _androidCpuAnyRequiredFeatures
        .split(',')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (required.isEmpty) {
      return;
    }

    final available = _readAndroidCpuFeatures();
    _log(
      'cpu guard check: requiredAny=${required.join('|')}, '
      'availableFlagsCount=${available.length}',
    );

    if (available.isEmpty) {
      _log('cpu guard skipped: /proc/cpuinfo features unavailable');
      return;
    }

    final matched = required.where(available.contains).toList(growable: false);
    if (matched.isNotEmpty) {
      _log('cpu guard passed: matched=${matched.join(',')}');
      return;
    }

    throw StateError(
      '检测到当前 Android CPU 可能不支持本地 llama 内核所需指令，已阻止加载避免 SIGILL 崩溃。\n'
      '需要特性(任意一个): ${required.join(', ')}\n'
      '当前设备未命中这些特性。\n'
      '可选方案：切换云端推理，或更换兼容 CPU 指令集的 llamadart/llama 二进制。',
    );
  }

  Future<void> ensureLoaded({
    required String modelPath,
    String? mmprojPath,
    LocalVlmComputeBackend? backend,
  }) async {
    final normalizedModelPath = modelPath.trim();
    final normalizedMmprojPath = mmprojPath?.trim() ?? '';
    final selectedBackend = backend ?? _defaultBackend();

    if (normalizedModelPath.isEmpty) {
      throw ArgumentError('modelPath 不能为空');
    }

    final alreadyLoaded =
        _engine != null &&
        _loadedModelPath == normalizedModelPath &&
      _loadedMmprojPath == normalizedMmprojPath &&
      _loadedBackend == selectedBackend;
    if (alreadyLoaded) {
      _log('ensureLoaded skipped: engine already loaded; ${describeRuntimeMemory()}');
      return;
    }

    if (_engine != null) {
      await dispose();
    }

    _runAndroidCpuGuardIfNeeded();

    final engine = LlamaEngine(LlamaBackend());
    final modelFile = File(normalizedModelPath);
    final mmprojFile =
        normalizedMmprojPath.isNotEmpty ? File(normalizedMmprojPath) : null;
    final modelSize = modelFile.existsSync() ? _formatBytes(modelFile.lengthSync()) : 'missing';
    final mmprojSize = mmprojFile != null && mmprojFile.existsSync()
        ? _formatBytes(mmprojFile.lengthSync())
        : (normalizedMmprojPath.isEmpty ? 'not-set' : 'missing');

    _log(
      'loadModel start: model=$normalizedModelPath ($modelSize), '
      'mmproj=${normalizedMmprojPath.isEmpty ? '(none)' : normalizedMmprojPath} ($mmprojSize), '
      'gpuLayers=$_gpuLayers, backend=${_backendLabel(selectedBackend)}, '
      '${describeRuntimeMemory()}',
    );
    try {
      await engine.loadModel(
        normalizedModelPath,
        modelParams: ModelParams(
          gpuLayers: _gpuLayers,
          preferredBackend: _gpuBackend(selectedBackend),
        ),
      );
    } catch (error) {
      _log('loadModel failed: $error; ${describeRuntimeMemory()}');
      throw StateError(
        '模型加载失败: $normalizedModelPath\n'
        '建议检查: 模型/mmproj 是否匹配、文件是否完整、量化是否受当前 llama 版本支持。\n'
        '当前参数: gpuLayers=$_gpuLayers, preferredBackend=${_backendLabel(selectedBackend)}\n'
        '内存信息: ${describeRuntimeMemory()}\n'
      );
    }

    if (normalizedMmprojPath.isNotEmpty) {
      _log('loadMultimodalProjector start: $normalizedMmprojPath; ${describeRuntimeMemory()}');
      await engine.loadMultimodalProjector(normalizedMmprojPath);
      _log('loadMultimodalProjector done: ${describeRuntimeMemory()}');
    }

    _engine = engine;
    _loadedModelPath = normalizedModelPath;
    _loadedMmprojPath = normalizedMmprojPath;
    _loadedBackend = selectedBackend;
    _log('ensureLoaded done: ${describeRuntimeMemory()}');
  }

  Future<String> generateVisionText({
    required String prompt,
    required List<String> imagePaths,
    int maxTokens = 256,
    double temperature = 0.2,
    void Function(String delta, String accumulated)? onPartialOutput,
  }) async {
    final engine = _engine;
    if (engine == null) {
      throw StateError('llamadart 引擎尚未加载，请先调用 ensureLoaded');
    }
    if (imagePaths.isEmpty) {
      throw ArgumentError('至少需要一张图片');
    }

    final messages = <LlamaChatMessage>[
      LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: <LlamaContentPart>[
          ...imagePaths.map((path) => LlamaImageContent(path: path)),
          LlamaTextContent(prompt),
        ],
      ),
    ];

    _log(
      'generateVisionText start: images=${imagePaths.length}, '
      'maxTokens=$maxTokens, temp=$temperature, ${describeRuntimeMemory()}',
    );

    final response = engine.create(
      messages,
      params: GenerationParams(
        maxTokens: maxTokens,
        temp: temperature,
      ),
    );

    final timeout = Duration(seconds: _generationTimeoutSeconds);
    _log('generateVisionText timeoutSec=$_generationTimeoutSeconds');
    final stopwatch = Stopwatch()..start();
    var chunkCount = 0;
    var charCount = 0;
    var lastProgressLogMs = 0;
    int? firstChunkLatencyMs;

    final buffer = StringBuffer();
    try {
      await for (final chunk in response.timeout(timeout)) {
        chunkCount++;
        firstChunkLatencyMs ??= stopwatch.elapsedMilliseconds;
        final content = chunk.choices.first.delta.content;
        if (content != null && content.isNotEmpty) {
          buffer.write(content);
          charCount += content.length;
          onPartialOutput?.call(content, buffer.toString());
        }

        final elapsedMs = stopwatch.elapsedMilliseconds;
        if (elapsedMs - lastProgressLogMs >= 1000) {
          final seconds = elapsedMs / 1000.0;
          final rate = seconds > 0 ? charCount / seconds : 0.0;
          _log(
            'generateVisionText stream: elapsed=${seconds.toStringAsFixed(1)}s, '
            'chunks=$chunkCount, chars=$charCount, avgRate=${rate.toStringAsFixed(1)} chars/s',
          );
          lastProgressLogMs = elapsedMs;
        }
      }
    } on TimeoutException catch (_) {
      _log('generateVisionText timeout after $_generationTimeoutSeconds seconds; ${describeRuntimeMemory()}');
      throw TimeoutException(
        '本地模型输出超时($_generationTimeoutSeconds 秒)，可能是模型在当前输入下未结束或底层执行卡住。',
        timeout,
      );
    } finally {
      stopwatch.stop();
    }

    final elapsed = stopwatch.elapsed;
    final elapsedMs = elapsed.inMilliseconds;
    final charsPerSecond = elapsedMs > 0 ? charCount * 1000.0 / elapsedMs : 0.0;
    _lastGenerationStats = LocalVlmGenerationStats(
      elapsed: elapsed,
      chunkCount: chunkCount,
      charCount: charCount,
      charsPerSecond: charsPerSecond,
      firstChunkLatency: firstChunkLatencyMs == null
          ? null
          : Duration(milliseconds: firstChunkLatencyMs),
    );

    _log('generateVisionText done: outputChars=${buffer.length}, ${describeRuntimeMemory()}');
    _log(
      'generateVisionText summary: elapsed=${(elapsedMs / 1000).toStringAsFixed(2)}s, '
      'chunks=$chunkCount, chars=$charCount, avgRate=${charsPerSecond.toStringAsFixed(1)} chars/s, '
      'firstChunkMs=${firstChunkLatencyMs ?? -1}',
    );
    return buffer.toString().trim();
  }

  Future<void> dispose() async {
    _log('dispose start: ${describeRuntimeMemory()}');
    final engine = _engine;
    _engine = null;
    _loadedModelPath = null;
    _loadedMmprojPath = null;
    _loadedBackend = null;
    if (engine != null) {
      await engine.dispose();
    }
    _log('dispose done: ${describeRuntimeMemory()}');
  }
}
