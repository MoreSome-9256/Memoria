import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// 实验页里使用的 InternVL 图片测试服务。
///
/// 这里刻意不直接耦合主业务里的故事生成逻辑，原因有两个：
/// 1. 这是一个独立的实验入口，应该和正式业务隔离，避免影响其他同事的流程。
/// 2. 实验页需要直接发送“图片 + 指令”，而主业务当前大多是纯文本调用。
///
/// 当前采用最实际、最容易落地的协议路线：
/// - 走 OpenAI 兼容的 `/v1/chat/completions`
/// - 文本块 + image_url(data URL) 的多模态请求格式
///
/// 这样后续无论你把 InternVL 跑在：
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
    final imageFile = File(imagePath);
    if (!imageFile.existsSync()) {
      throw ArgumentError('图片不存在: $imagePath');
    }

    final imageBytes = await imageFile.readAsBytes();
    final imageExtension = imageFile.path.toLowerCase();
    final mimeType = imageExtension.endsWith('.png')
        ? 'image/png'
        : imageExtension.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    final base64Image = base64Encode(imageBytes);
    final dataUrl = 'data:$mimeType;base64,$base64Image';

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
            'content': <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'text',
                'text': prompt,
              },
              <String, dynamic>{
                'type': 'image_url',
                'image_url': <String, dynamic>{
                  'url': dataUrl,
                },
              },
            ],
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

    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      throw StateError('返回结果缺少 message');
    }

    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }

    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map<String, dynamic> && part['text'] is String) {
          buffer.write(part['text'] as String);
        }
      }
      final text = buffer.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }

    throw StateError('模型服务返回成功，但未解析出文本内容');
  }
}