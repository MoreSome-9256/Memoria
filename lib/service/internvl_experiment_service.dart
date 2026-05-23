/// InternVL 实验服务，用于临时验证和调试视觉语言模型能力。

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;

class InternvlStructuredResponse {
  const InternvlStructuredResponse({
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
      final value = output['narrative'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return rawContent;
  }
}

/// 实验页/本地测试页里使用的本地多模态图片测试服务。
///
/// 这里刻意不直接耦合主业务里的故事生成逻辑，原因有两个：
/// 1. 这是一个独立的实验入口，应该和正式业务隔离，避免影响其他同事的流程。
/// 2. 实验页需要直接发送“图片 + 指令”，而主业务当前大多是纯文本调用。
///
/// 当前采用最实际、最容易落地的协议路线：
/// - 走 OpenAI 兼容的 `/v1/chat/completions`
/// - 文本块 + image_url(data URL) 的多模态请求格式
///
/// 这样后续无论你把 Qwen-VL / 其它兼容多模态模型跑在：
/// - 手机本机 127.0.0.1
/// - adb reverse 转发的电脑服务
/// - 局域网内另一台设备
///
/// 只要它暴露的是 OpenAI 兼容接口，这个实验页都能直接复用。
class InternvlExperimentService {
  InternvlExperimentService({Dio? dio})
    : _dio =
          dio ??
              Dio(
                BaseOptions(
                  connectTimeout: const Duration(seconds: 20),
                  receiveTimeout: const Duration(minutes: 3),
                  sendTimeout: const Duration(minutes: 3),
                  contentType: 'application/json',
                ),
              );

  final Dio _dio;

  Future<InternvlStructuredResponse> analyzeImagesStructured({
    required String serverUrl,
    required String model,
    required String prompt,
    required List<String> imagePaths,
    String? apiKey,
    int maxTokens = 256,
    double temperature = 0.2,
  }) async {
    if (imagePaths.isEmpty) {
      throw ArgumentError('至少需要一张图片');
    }

    final content = <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'text',
        'text': prompt,
      },
    ];

    for (final imagePath in imagePaths) {
      final imageFile = File(imagePath);
      if (!imageFile.existsSync()) {
        throw ArgumentError('图片不存在: $imagePath');
      }

      // 本地常驻服务对超大 data URL 更敏感，这里先把原图压到适合
      // 多模态推理的尺寸，避免服务端在接收大请求体时提前断开连接。
      final dataUrl = await _buildOptimizedImageDataUrl(imageFile);
      content.add(
        <String, dynamic>{
          'type': 'image_url',
          'image_url': <String, dynamic>{
            'url': dataUrl,
          },
        },
      );
    }

    final headers = <String, String>{};
    final normalizedApiKey = apiKey?.trim() ?? '';
    if (normalizedApiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $normalizedApiKey';
    }

    final response = await _dio.post(
      serverUrl,
      options: Options(headers: headers.isEmpty ? null : headers),
      data: <String, dynamic>{
        'model': model,
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{
            'role': 'user',
            'content': content,
          },
        ],
        'max_tokens': maxTokens,
        'temperature': temperature,
        'stream': false,
      },
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('模型服务返回了无法识别的结构');
    }

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw StateError('模型服务没有返回 choices');
    }

    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      throw StateError('choices[0] 结构异常');
    }

    final rawContent = _extractResponseText(data, firstChoice);
    if (rawContent.trim().isEmpty) {
      final preview = const JsonEncoder.withIndent('  ').convert(data);
      throw StateError(
        '模型服务返回成功，但未解析出文本内容。原始响应片段: '
        '${preview.substring(0, preview.length > 800 ? 800 : preview.length)}',
      );
    }

    return normalizeRawTextToStructuredResponse(
      rawContent: rawContent,
      model: model,
      prompt: prompt,
      imageCount: imagePaths.length,
      serverUrl: serverUrl,
    );
  }

  InternvlStructuredResponse normalizeRawTextToStructuredResponse({
    required String rawContent,
    required String model,
    required String prompt,
    required int imageCount,
    required String serverUrl,
  }) {
    final parsed = _tryParseJsonObject(rawContent);
    final usedFallback = parsed == null;
    final normalizedJson = _normalizeToStandardJson(
      parsed: parsed,
      rawContent: rawContent,
      model: model,
      prompt: prompt,
      imageCount: imageCount,
      serverUrl: serverUrl,
      usedFallback: usedFallback,
    );

    return InternvlStructuredResponse(
      rawContent: rawContent,
      normalizedJson: normalizedJson,
      usedFallback: usedFallback,
    );
  }

  String _extractResponseText(
    Map<String, dynamic> data,
    Map<String, dynamic> firstChoice,
  ) {
    final message = firstChoice['message'];
    if (message is Map<String, dynamic>) {
      final fromMessageContent = _flattenMessageContent(message['content']);
      if (fromMessageContent.isNotEmpty) {
        return fromMessageContent;
      }

      final fromReasoning = _flattenMessageContent(message['reasoning_content']);
      if (fromReasoning.isNotEmpty) {
        return fromReasoning;
      }
    }

    final fromChoiceText = _flattenMessageContent(firstChoice['text']);
    if (fromChoiceText.isNotEmpty) {
      return fromChoiceText;
    }

    final fromChoiceContent = _flattenMessageContent(firstChoice['content']);
    if (fromChoiceContent.isNotEmpty) {
      return fromChoiceContent;
    }

    final fromOutputText = _flattenMessageContent(data['output_text']);
    if (fromOutputText.isNotEmpty) {
      return fromOutputText;
    }

    final fromResponse = _flattenMessageContent(data['response']);
    if (fromResponse.isNotEmpty) {
      return fromResponse;
    }

    return '';
  }

  Future<String> _buildOptimizedImageDataUrl(File imageFile) async {
    final originalBytes = await imageFile.readAsBytes();
    const maxSide = 1024;
    const jpegQuality = 82;

    try {
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) {
        return _buildOriginalDataUrl(imageFile.path, originalBytes);
      }

      final longestSide = decoded.width > decoded.height
          ? decoded.width
          : decoded.height;
      final resized = longestSide <= maxSide
          ? decoded
          : img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? maxSide : null,
              height: decoded.height > decoded.width ? maxSide : null,
              interpolation: img.Interpolation.average,
            );

      final jpegBytes = img.encodeJpg(resized, quality: jpegQuality);
      return 'data:image/jpeg;base64,${base64Encode(jpegBytes)}';
    } catch (_) {
      return _buildOriginalDataUrl(imageFile.path, originalBytes);
    }
  }

  String _buildOriginalDataUrl(String imagePath, List<int> imageBytes) {
    final imageExtension = imagePath.toLowerCase();
    final mimeType = imageExtension.endsWith('.png')
        ? 'image/png'
        : imageExtension.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(imageBytes)}';
  }

  Future<String> analyzeImages({
    required String serverUrl,
    required String model,
    required String prompt,
    required List<String> imagePaths,
    String? apiKey,
    int maxTokens = 256,
    double temperature = 0.2,
  }) async {
    final result = await analyzeImagesStructured(
      serverUrl: serverUrl,
      model: model,
      prompt: prompt,
      imagePaths: imagePaths,
      apiKey: apiKey,
      maxTokens: maxTokens,
      temperature: temperature,
    );
    return result.narrative;
  }

  /// 对一张图片发起多模态问答。
  ///
  /// 参数说明：
  /// - [serverUrl]：完整接口地址，默认建议填到 `/v1/chat/completions`
  /// - [model]：服务侧需要的模型名；对很多本地服务来说只是占位名
  /// - [prompt]：用户输入的中文指令
  /// - [imagePath]：本地图片文件路径
  /// - [apiKey]：可选；本地服务通常不需要
  Future<String> analyzeImage({
    required String serverUrl,
    required String model,
    required String prompt,
    required String imagePath,
    String? apiKey,
    int maxTokens = 256,
    double temperature = 0.2,
  }) async {
    return analyzeImages(
      serverUrl: serverUrl,
      model: model,
      prompt: prompt,
      imagePaths: <String>[imagePath],
      apiKey: apiKey,
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }

  String _flattenMessageContent(Object? contentData) {
    if (contentData is String) {
      return contentData.trim();
    }

    if (contentData is Map<String, dynamic>) {
      for (final key in const <String>[
        'text',
        'content',
        'value',
        'response',
        'output_text',
        'generated_text',
      ]) {
        final extracted = _flattenMessageContent(contentData[key]);
        if (extracted.isNotEmpty) {
          return extracted;
        }
      }
      return '';
    }

    if (contentData is Map) {
      final normalized = contentData.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      );
      return _flattenMessageContent(normalized);
    }

    if (contentData is List) {
      final buffer = StringBuffer();
      for (final part in contentData) {
        final extracted = _flattenMessageContent(part);
        if (extracted.isNotEmpty) {
          if (buffer.isNotEmpty) {
            buffer.write('\n');
          }
          buffer.write(extracted);
        }
      }
      return buffer.toString().trim();
    }

    return '';
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
      final slice = rawContent.substring(firstBrace, lastBrace + 1);
      return _tryDecodeMap(slice);
    }

    return null;
  }

  Map<String, dynamic>? _tryDecodeMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is String) {
        final nested = decoded.trim();
        if (nested.isNotEmpty && nested != text) {
          return _tryDecodeMap(nested);
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, dynamic> _normalizeToStandardJson({
    required Map<String, dynamic>? parsed,
    required String rawContent,
    required String model,
    required String prompt,
    required int imageCount,
    required String serverUrl,
    required bool usedFallback,
  }) {
    final outputFromInput = parsed == null
        ? <String, dynamic>{}
        : (parsed['output'] is Map<String, dynamic>
              ? parsed['output'] as Map<String, dynamic>
              : parsed);

    final keyFacts = _readStringList(outputFromInput, <String>[
      'key_facts',
      'facts',
      'highlights',
      'evidence',
    ]);
    final entities = _readStringList(outputFromInput, <String>[
      'visual_entities',
      'entities',
      'objects',
      'subjects',
    ]);
    final tags = _readStringList(outputFromInput, <String>[
      'style_tags',
      'tags',
      'keywords',
    ]);
    final hints = _readStringList(outputFromInput, <String>[
      'time_location_hints',
      'time_location',
      'metadata_hints',
    ]);

    final summary = _readFirstString(outputFromInput, <String>[
      'scene_summary',
      'summary',
      'brief',
    ]);
    final narrative = _readFirstString(outputFromInput, <String>[
      'narrative',
      'story',
      'answer',
      'description',
      'content',
    ]);

    final confidence = _readConfidence(outputFromInput['confidence']);

    final nestedFromNarrative = _tryParseJsonObject(
      narrative.isNotEmpty ? narrative : rawContent,
    );
    final nestedOutput = nestedFromNarrative == null
      ? null
      : (nestedFromNarrative['output'] is Map<String, dynamic>
          ? nestedFromNarrative['output'] as Map<String, dynamic>
          : nestedFromNarrative);

    final mergedSummary = summary.isNotEmpty
      ? summary
      : (nestedOutput == null
          ? ''
          : _readFirstString(nestedOutput, <String>['scene_summary', 'summary']));
    final mergedNarrative = narrative.isNotEmpty
      ? narrative
      : (nestedOutput == null
          ? rawContent
          : _readFirstString(
            nestedOutput,
            <String>['narrative', 'story', 'answer', 'description', 'content'],
          ));
    final mergedKeyFacts = keyFacts.isNotEmpty
      ? keyFacts
      : (nestedOutput == null
          ? const <String>[]
          : _readStringList(nestedOutput, <String>['key_facts', 'facts', 'highlights']));
    final mergedEntities = entities.isNotEmpty
      ? entities
      : (nestedOutput == null
          ? const <String>[]
          : _readStringList(nestedOutput, <String>['visual_entities', 'entities', 'objects']));
    final mergedStyleTags = tags.isNotEmpty
      ? tags
      : (nestedOutput == null
          ? const <String>[]
          : _readStringList(nestedOutput, <String>['style_tags', 'tags', 'keywords']));
    final mergedHints = hints.isNotEmpty
      ? hints
      : (nestedOutput == null
          ? const <String>[]
          : _readStringList(nestedOutput, <String>['time_location_hints', 'time_location', 'metadata_hints']));
    final mergedConfidence = confidence > 0
      ? confidence
      : (nestedOutput == null ? 0.0 : _readConfidence(nestedOutput['confidence']));

    return <String, dynamic>{
      'schema_version': 'memoria.vlm.output.v1',
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'source_format': usedFallback ? 'text_fallback' : 'json',
      'request': <String, dynamic>{
        'model': model,
        'server_url': serverUrl,
        'prompt': prompt,
        'image_count': imageCount,
      },
      'output': <String, dynamic>{
        'scene_summary': mergedSummary,
        'narrative': mergedNarrative.isNotEmpty ? mergedNarrative : rawContent,
        'key_facts': mergedKeyFacts,
        'visual_entities': mergedEntities,
        'style_tags': mergedStyleTags,
        'time_location_hints': mergedHints,
        'confidence': mergedConfidence,
      },
      'raw_model_output': rawContent,
      'raw_parsed_json': parsed,
    };
  }

  String _readFirstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  List<String> _readStringList(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is List) {
        final result = value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        if (result.isNotEmpty) {
          return result;
        }
      }
      if (value is String && value.trim().isNotEmpty) {
        final split = value
            .split(RegExp(r'[,，;；\n]'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        if (split.isNotEmpty) {
          return split;
        }
      }
    }
    return const <String>[];
  }

  double _readConfidence(Object? value) {
    if (value is num) {
      return value.toDouble().clamp(0.0, 1.0);
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null) {
        return parsed.clamp(0.0, 1.0);
      }
    }
    return 0.0;
  }
}