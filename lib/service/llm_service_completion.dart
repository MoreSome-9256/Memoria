part of 'llm_service.dart';

extension LLMServiceCompletion on LLMService {
  Future<String?> completeText({
    required String prompt,
    String systemPrompt = LLMService._defaultTextSystemPrompt,
    bool jsonMode = false,
    double? temperature,
    double? topP,
    Duration? requestTimeout,
  }) {
    return _chatCompletion(
      prompt,
      systemPrompt: systemPrompt,
      jsonMode: jsonMode,
      temperature: temperature,
      topP: topP,
      requestTimeout: requestTimeout,
    );
  }

  Future<String?> generatePhotoCaption({
    required Uint8List imageBytes,
    required String mimeType,
    required List<String> tags,
    required List<String> ocrTags,
    required String ocrText,
    required String? location,
    required DateTime takenAt,
    required bool isTextHeavy,
    required int faceCount,
  }) async {
    final prompt = _buildPhotoCaptionPrompt(
      tags: tags,
      ocrTags: ocrTags,
      ocrText: ocrText,
      location: location,
      takenAt: takenAt,
      isTextHeavy: isTextHeavy,
      faceCount: faceCount,
    );

    final text = await _multimodalChatCompletion(
      prompt: prompt,
      imageBytes: imageBytes,
      mimeType: mimeType,
    );
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    return text.trim();
  }

  Future<String?> generateBlogText(String prompt) async {
    try {
      final text = await _chatCompletion(prompt);
      if (text == null || text.isEmpty) {
        print('LLM 返回为空');
        return null;
      }

      print('LLM 成功生成博客内容');
      return text.trim();
    } catch (e) {
      print('LLM 博客生成失败: $e');
      return null;
    }
  }

  Future<String?> _chatCompletion(
    String prompt, {
    String systemPrompt = LLMService._defaultTextSystemPrompt,
    bool jsonMode = false,
    double? temperature,
    double? topP,
    Duration? requestTimeout,
  }) async {
    final baseUrl = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final apiPath = _apiPath.startsWith('/') ? _apiPath : '/$_apiPath';
    final isChatCompletions = apiPath.contains('/chat/completions');
    final requestBody = _buildRequestBody(
      prompt: prompt,
      systemPrompt: systemPrompt,
      useChatCompletions: isChatCompletions,
      jsonMode: jsonMode,
      temperature: temperature,
      topP: topP,
    );

    final headers = <String, String>{};
    if (_apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer $_apiKey';
    }

    final response = await _dio.post(
      '$baseUrl$apiPath',
      options: Options(
        headers: headers.isEmpty ? null : headers,
        receiveTimeout: requestTimeout,
        sendTimeout: requestTimeout,
      ),
      data: requestBody,
    );

    final data = response.data;
    print('[LLM RESPONSE STATUS] ${response.statusCode}');
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final outputText = _extractResponseText(data);
    if (outputText != null && outputText.isNotEmpty) {
      return outputText;
    }

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      return null;
    }

    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }

    final message = first['message'];
    if (message is! Map<String, dynamic>) {
      return null;
    }

    final content = message['content'];
    if (content is String) {
      return content;
    }

    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is Map<String, dynamic> && item['text'] is String) {
          buffer.write(item['text'] as String);
        }
      }
      return buffer.toString();
    }

    return null;
  }

  Future<String?> _multimodalChatCompletion({
    required String prompt,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final baseUrl = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final apiPath = _apiPath.startsWith('/') ? _apiPath : '/$_apiPath';
    final isChatCompletions = apiPath.contains('/chat/completions');
    final requestBody = _buildVisionRequestBody(
      prompt: prompt,
      imageBytes: imageBytes,
      mimeType: mimeType,
      useChatCompletions: isChatCompletions,
    );

    final response = await _dio.post(
      '$baseUrl$apiPath',
      options: Options(headers: {'Authorization': 'Bearer $_apiKey'}),
      data: requestBody,
    );

    final data = response.data;
    print('[LLM VISION RESPONSE STATUS] ${response.statusCode}');
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final outputText = _extractResponseText(data);
    if (outputText != null && outputText.isNotEmpty) {
      return outputText;
    }

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      return null;
    }

    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }

    final message = first['message'];
    if (message is! Map<String, dynamic>) {
      return null;
    }

    final content = message['content'];
    if (content is String) {
      return content;
    }
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is Map<String, dynamic> && item['text'] is String) {
          buffer.write(item['text'] as String);
        }
      }
      return buffer.toString();
    }

    return null;
  }

  Map<String, dynamic> _buildRequestBody({
    required String prompt,
    required String systemPrompt,
    required bool useChatCompletions,
    bool jsonMode = false,
    double? temperature,
    double? topP,
  }) {
    final resolvedTemperature = temperature ?? (jsonMode ? 0.1 : 0.7);
    if (useChatCompletions) {
      final body = <String, dynamic>{
        'model': _modelName,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': prompt},
        ],
        'temperature': resolvedTemperature,
      };
      if (topP != null) {
        body['top_p'] = topP;
      }
      if (jsonMode) {
        body['response_format'] = {'type': 'json_object'};
      }
      return body;
    }

    final body = <String, dynamic>{
      'model': _modelName,
      'input': [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': systemPrompt},
            {'type': 'input_text', 'text': prompt},
          ],
        },
      ],
      'temperature': resolvedTemperature,
    };
    if (topP != null) {
      body['top_p'] = topP;
    }
    if (jsonMode) {
      body['text'] = {
        'format': {'type': 'json_object'},
      };
    }
    return body;
  }

  Map<String, dynamic> _buildVisionRequestBody({
    required String prompt,
    required Uint8List imageBytes,
    required String mimeType,
    required bool useChatCompletions,
  }) {
    const systemText = '你是一个谨慎的中文图片描述助手。只能描述图中可见事实，不要脑补职业、关系、剧情和身份。';
    final imageDataUrl = 'data:$mimeType;base64,${base64Encode(imageBytes)}';

    if (useChatCompletions) {
      return {
        'model': _visionModelName,
        'messages': [
          {'role': 'system', 'content': systemText},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {'url': imageDataUrl},
              },
            ],
          },
        ],
      };
    }

    return {
      'model': _visionModelName,
      'input': [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': systemText},
            {'type': 'input_text', 'text': prompt},
            {'type': 'input_image', 'image_url': imageDataUrl},
          ],
        },
      ],
    };
  }

  String _buildPhotoCaptionPrompt({
    required List<String> tags,
    required List<String> ocrTags,
    required String ocrText,
    required String? location,
    required DateTime takenAt,
    required bool isTextHeavy,
    required int faceCount,
  }) {
    final dateText =
        '${takenAt.month}/${takenAt.day} ${takenAt.hour.toString().padLeft(2, '0')}:${takenAt.minute.toString().padLeft(2, '0')}';
    final tagsText = tags.isEmpty ? 'none' : tags.join(', ');
    final ocrTagsText = ocrTags.isEmpty ? 'none' : ocrTags.join(', ');
    final trimmedOcr = ocrText.trim();
    final ocrSnippet = trimmedOcr.isEmpty
        ? 'none'
        : trimmedOcr.substring(
            0,
            trimmedOcr.length > 80 ? 80 : trimmedOcr.length,
          );

    return '''
Write one short Chinese caption for this photo.

Facts:
- Time: $dateText
- Location: ${location ?? 'unknown'}
- Visual tags: $tagsText
- OCR tags: $ocrTagsText
- OCR snippet: $ocrSnippet
- Face count: $faceCount
- Text-heavy image: ${isTextHeavy ? 'yes' : 'no'}

Rules:
1. Output exactly one sentence.
2. Keep it concise.
3. Only describe visible facts.
4. Do not invent identities, relationships, or plot.
5. If it is mostly screenshot or document content, describe it as screen/document content.
6. If location is uncertain, do not make one up.
''';
  }

  String? _extractResponseText(Map<String, dynamic> data) {
    final direct = data['output_text'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }

    final output = data['output'];
    if (output is! List) {
      return null;
    }

    final buffer = StringBuffer();
    for (final item in output) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final content = item['content'];
      if (content is! List) {
        continue;
      }
      for (final part in content) {
        if (part is! Map<String, dynamic>) {
          continue;
        }

        final text = part['text'];
        if (text is String) {
          buffer.write(text);
        }
      }
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }
}
