import 'dart:convert';
import 'dart:io';

import 'llamadart_local_engine_service.dart';
import 'local_qwen_bundled_model_service.dart';

class LocalVlmImagePayload {
  const LocalVlmImagePayload({
    required this.path,
    required this.capturedAtIso,
    required this.locationName,
    this.latitude,
    this.longitude,
  });

  final String path;
  final String capturedAtIso;
  final String locationName;
  final double? latitude;
  final double? longitude;
}

class LocalVlmStructuredResponse {
  const LocalVlmStructuredResponse({
    required this.rawContent,
    required this.normalizedJson,
    required this.usedFallback,
  });

  final String rawContent;
  final Map<String, dynamic> normalizedJson;
  final bool usedFallback;

  String get narrative {
    final output = normalizedJson['output'];
    if (output is Map<String, dynamic>) {
      final story = output['story'];
      if (story is String && story.trim().isNotEmpty) {
        return story.trim();
      }
      final value = output['narrative'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return rawContent;
  }
}

enum QwenLocalBackendOption {
  vulkan,
  cpu,
}

extension QwenLocalBackendOptionX on QwenLocalBackendOption {
  String get label => this == QwenLocalBackendOption.vulkan ? 'Vulkan GPU' : 'CPU';

  LocalVlmComputeBackend get engineBackend =>
      this == QwenLocalBackendOption.vulkan
          ? LocalVlmComputeBackend.vulkan
          : LocalVlmComputeBackend.cpu;
}

class QwenLlamacppService {
  QwenLlamacppService({LlamadartLocalEngineService? engine})
    : _engine = engine ?? LlamadartLocalEngineService();

  static const String qwenModelAlias = 'qwen3.5-0.8b';

  static const String _qwenModelPath = String.fromEnvironment(
    'LOCAL_QWEN35_08B_GGUF_PATH',
    defaultValue: '',
  );
  static const String _legacyModelPath = String.fromEnvironment(
    'LOCAL_GGUF_MODEL_PATH',
    defaultValue: '',
  );
  static const String _qwenMmprojPath = String.fromEnvironment(
    'LOCAL_QWEN35_08B_MMPROJ_PATH',
    defaultValue: '',
  );
  static const String _legacyMmprojPath = String.fromEnvironment(
    'LOCAL_GGUF_MMPROJ_PATH',
    defaultValue: '',
  );
  static const String _qwenModelAsset = String.fromEnvironment(
    'LOCAL_QWEN35_08B_GGUF_ASSET',
    defaultValue: 'assets/local_vlm/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf',
  );
  static const String _qwenMmprojAsset = String.fromEnvironment(
    'LOCAL_QWEN35_08B_MMPROJ_ASSET',
    defaultValue: 'assets/local_vlm/mmproj-Qwen_Qwen3.5-0.8B-f16.gguf',
  );
  static const bool _keepModelResident = bool.fromEnvironment(
    'LOCAL_VLM_KEEP_MODEL_RESIDENT',
    defaultValue: false,
  );

  final LlamadartLocalEngineService _engine;
  final LocalQwenBundledModelService _bundledModelService =
      LocalQwenBundledModelService();
  String? _activeModelPath;
  String? _activeMmprojPath;

  String get configuredModelPath =>
      _qwenModelPath.trim().isNotEmpty ? _qwenModelPath.trim() : _legacyModelPath.trim();

    String get configuredMmprojPath =>
      _qwenMmprojPath.trim().isNotEmpty ? _qwenMmprojPath.trim() : _legacyMmprojPath.trim();

  String get modelPath => _activeModelPath ?? configuredModelPath;

    String get mmprojPath => _activeMmprojPath ?? configuredMmprojPath;

  LocalVlmGenerationStats? get lastGenerationStats => _engine.lastGenerationStats;

  Future<LocalVlmStructuredResponse> analyzeImagesStructured({
    required String prompt,
    required List<LocalVlmImagePayload> images,
    int maxTokens = 384,
    double temperature = 0.35,
    QwenLocalBackendOption backend = QwenLocalBackendOption.vulkan,
    void Function(String delta, String accumulated)? onPartialOutput,
  }) async {
    if (images.isEmpty) {
      throw ArgumentError('至少需要一张图片');
    }

    final runtimePaths = await _resolveRuntimeModelPaths();
    final resolvedModelPath = runtimePaths.modelPath;
    final resolvedMmprojPath = runtimePaths.mmprojPath;

    _activeModelPath = resolvedModelPath;
    _activeMmprojPath = resolvedMmprojPath;

    for (final image in images) {
      if (!File(image.path).existsSync()) {
        throw StateError('图片不存在: ${image.path}');
      }
    }

    try {
      await _engine.ensureLoaded(
        modelPath: resolvedModelPath,
        mmprojPath: resolvedMmprojPath,
        backend: backend.engineBackend,
      );

      final raw = await _engine.generateVisionText(
        prompt: prompt,
        imagePaths: images.map((item) => item.path).toList(growable: false),
        maxTokens: maxTokens,
        temperature: temperature,
        onPartialOutput: onPartialOutput,
      );

      if (raw.trim().isEmpty) {
        throw StateError('Qwen3.5-0.8B 未返回可解析文本');
      }

      final parsed = _tryParseJsonObject(raw);
      final usedFallback = parsed == null;
      final normalized = _normalize(parsed, raw, images.length);

      return LocalVlmStructuredResponse(
        rawContent: raw,
        normalizedJson: normalized,
        usedFallback: usedFallback,
      );
    } catch (error) {
      if (LlamadartLocalEngineService.looksLikeOom(error)) {
        await _engine.dispose();
        throw StateError(
          '本地模型推理疑似触发原生内存不足(OOM)。\n'
          '建议：在图库大量缩略图加载阶段避免并发触发推理，或分批推理。\n'
          '当前策略：LOCAL_VLM_KEEP_MODEL_RESIDENT=$_keepModelResident，'
          '${LlamadartLocalEngineService.describeRuntimeMemory()}\n'
          '原始错误: $error',
        );
      }
      rethrow;
    } finally {
      if (!_keepModelResident && _engine.isLoaded) {
        await _engine.dispose();
      }
    }
  }

  Future<LocalQwenBundledModelPaths> _resolveRuntimeModelPaths() async {
    final configuredModel = configuredModelPath;
    final configuredMmproj = configuredMmprojPath;

    if (configuredModel.isNotEmpty && configuredMmproj.isNotEmpty) {
      if (!File(configuredModel).existsSync()) {
        throw StateError('模型文件不存在: $configuredModel');
      }
      if (!File(configuredMmproj).existsSync()) {
        throw StateError('mmproj 文件不存在: $configuredMmproj');
      }
      return LocalQwenBundledModelPaths(
        modelPath: configuredModel,
        mmprojPath: configuredMmproj,
      );
    }

    if (configuredModel.isNotEmpty && configuredMmproj.isEmpty) {
      throw StateError('已配置模型路径但缺少 LOCAL_QWEN35_08B_MMPROJ_PATH');
    }

    if (configuredModel.isEmpty && configuredMmproj.isNotEmpty) {
      throw StateError('已配置 mmproj 路径但缺少 LOCAL_QWEN35_08B_GGUF_PATH');
    }

    return _bundledModelService.ensureReady(
      modelAssetPath: _qwenModelAsset,
      mmprojAssetPath: _qwenMmprojAsset,
    );
  }

  Map<String, dynamic> _normalize(
    Map<String, dynamic>? parsed,
    String raw,
    int imageCount,
  ) {
    final output = parsed?['output'];
    if (output is Map<String, dynamic>) {
      return <String, dynamic>{
        'schema_version': 'memoria.local_vlm.qwen.v1',
        'model': qwenModelAlias,
        'output': output,
      };
    }

    if (parsed != null && parsed['story'] is String) {
      return <String, dynamic>{
        'schema_version': 'memoria.local_vlm.qwen.v1',
        'model': qwenModelAlias,
        'output': <String, dynamic>{'story': parsed['story']},
      };
    }

    return <String, dynamic>{
      'schema_version': 'memoria.local_vlm.qwen.v1',
      'model': qwenModelAlias,
      'output': <String, dynamic>{
        if (imageCount <= 1) 'narrative': raw.trim(),
        if (imageCount > 1) 'story': raw.trim(),
      },
    };
  }

  Map<String, dynamic>? _tryParseJsonObject(String rawContent) {
    final direct = _tryDecodeMap(rawContent);
    if (direct != null) {
      return direct;
    }

    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', multiLine: true)
        .firstMatch(rawContent)
        ?.group(1);
    if (fenced != null) {
      final decoded = _tryDecodeMap(fenced);
      if (decoded != null) {
        return decoded;
      }
    }

    final firstBrace = rawContent.indexOf('{');
    final lastBrace = rawContent.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return _tryDecodeMap(rawContent.substring(firstBrace, lastBrace + 1));
    }
    return null;
  }

  Map<String, dynamic>? _tryDecodeMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
