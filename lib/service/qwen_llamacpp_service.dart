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
  static const String _qwenModelAsset = String.fromEnvironment(
    'LOCAL_QWEN35_08B_GGUF_ASSET',
    defaultValue: 'assets/local_vlm/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf',
  );

  final LlamadartLocalEngineService _engine;
  final LocalQwenBundledModelService _bundledModelService =
      LocalQwenBundledModelService();
  String? _activeModelPath;

  String get configuredModelPath =>
      _qwenModelPath.trim().isNotEmpty ? _qwenModelPath.trim() : _legacyModelPath.trim();

  String get modelPath => _activeModelPath ?? configuredModelPath;

  Future<LocalVlmStructuredResponse> analyzeImagesStructured({
    required String prompt,
    required List<LocalVlmImagePayload> images,
    int maxTokens = 384,
    double temperature = 0.35,
  }) async {
    if (images.isEmpty) {
      throw ArgumentError('至少需要一张图片');
    }

    final resolvedModelPath = await _resolveRuntimeModelPath();

    _activeModelPath = resolvedModelPath;

    for (final image in images) {
      if (!File(image.path).existsSync()) {
        throw StateError('图片不存在: ${image.path}');
      }
    }

    await _engine.ensureLoaded(modelPath: resolvedModelPath);

    final raw = await _engine.generateVisionText(
      prompt: prompt,
      imagePaths: images.map((item) => item.path).toList(growable: false),
      maxTokens: maxTokens,
      temperature: temperature,
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
  }

  Future<String> _resolveRuntimeModelPath() async {
    final configuredModel = configuredModelPath;

    if (configuredModel.isNotEmpty) {
      if (!File(configuredModel).existsSync()) {
        throw StateError('模型文件不存在: $configuredModel');
      }
      return configuredModel;
    }

    final bundled = await _bundledModelService.ensureReady(
      modelAssetPath: _qwenModelAsset,
    );
    return bundled.modelPath;
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
