/// 故事生成编排的本地运行时支撑，管理任务状态和执行环境。

part of 'story_generation_orchestrator.dart';

extension _StoryGenerationOrchestratorLocalRuntime
    on StoryGenerationOrchestrator {
  Future<Map<int, _CaptionResult>> _generateLocalCaptions(
    List<PhotoEntity> photos, {
    required void Function(
      int completed,
      int total,
      PhotoEntity currentPhoto,
      Map<int, _CaptionResult> completedCaptions,
    )
    onProgress,
  }) async {
    final captions = <int, _CaptionResult>{};
    final runtime = await _prepareLocalRuntime();
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      final payload = OnDeviceInternvlImagePayload(
        path: photo.path,
        capturedAtIso: DateTime.fromMillisecondsSinceEpoch(
          photo.timestamp,
        ).toIso8601String(),
        locationName: _locationLabel(photo).ifEmpty('未知地点'),
        latitude: photo.latitude,
        longitude: photo.longitude,
      );

      onProgress(
        index,
        photos.length,
        photo,
        Map<int, _CaptionResult>.from(captions),
      );

      try {
        final prompt = _buildLocalCaptionPrompt(<OnDeviceInternvlImagePayload>[
          payload,
        ]);
        final structured = await _runLocalStructuredTask(
          prompt: prompt,
          payloads: <OnDeviceInternvlImagePayload>[payload],
          maxTokens: 192,
          temperature: 0.2,
          cliTimeoutMs: 240000,
          requestTimeout: const Duration(minutes: 4),
          preparedRuntime: runtime,
          allowCliFallback: true,
        );

        final parsed = _tryParseJsonObject(structured.rawContent);
        String caption = '';
        final rawItems = _extractListOfMaps(parsed?['captions']);
        if (rawItems.isNotEmpty) {
          caption = rawItems.first['caption']?.toString().trim() ?? '';
        }
        if (caption.isEmpty) {
          caption = structured.narrative.trim();
        }
        if (caption.isNotEmpty) {
          captions[photo.id] = _CaptionResult.localVlm(caption);
        }
      } catch (_) {
        final existingCaption = photo.aiCaption?.trim();
        if (existingCaption != null && existingCaption.isNotEmpty) {
          captions[photo.id] = _CaptionResult.existingAiFallback(
            existingCaption,
          );
        }
      }

      onProgress(
        index + 1,
        photos.length,
        photo,
        Map<int, _CaptionResult>.from(captions),
      );
    }

    return captions;
  }

  Future<_StructuredStoryPayload> _generateLocalDirectStory({
    required StoryGenerationRequest request,
    required List<PhotoEntity> photos,
  }) async {
    final runtime = await _prepareLocalRuntime();
    final payloads = photos
        .map(
          (photo) => OnDeviceInternvlImagePayload(
            path: photo.path,
            capturedAtIso: DateTime.fromMillisecondsSinceEpoch(
              photo.timestamp,
            ).toIso8601String(),
            locationName: _locationLabel(photo).ifEmpty('未知地点'),
            latitude: photo.latitude,
            longitude: photo.longitude,
          ),
        )
        .toList(growable: false);

    final prompt = _buildLocalStoryPrompt(request, payloads);
    final structured = await _runLocalStructuredTask(
      prompt: prompt,
      payloads: payloads,
      maxTokens: 480,
      temperature: 0.35,
      cliTimeoutMs: 240000,
      requestTimeout: const Duration(minutes: 4),
      preparedRuntime: runtime,
      allowCliFallback: true,
    );

    final parsed = _tryParseJsonObject(structured.rawContent);
    if (parsed != null) {
      final payload = _StructuredStoryPayload.fromParsedJson(
        parsed,
        fallbackTitle: request.title,
        fallbackSubtitle: request.subtitle,
        sectionCount: photos.length,
      );
      if (payload.story.trim().isNotEmpty || payload.sections.isNotEmpty) {
        return payload;
      }
    }

    final storyText = structured.narrative.trim().isEmpty
        ? _buildFallbackStoryParagraph(request, photos)
        : structured.narrative.trim();
    return _StructuredStoryPayload(
      title: request.title,
      subtitle: request.subtitle,
      story: storyText,
      sections: _splitNarrativeEvenly(storyText, photos.length),
      highlights: const <String>['已使用本地 VLM 完成多图理解'],
    );
  }

  Future<_StructuredStoryPayload> _generateDeepSeekStory({
    required StoryGenerationRequest request,
    required List<PhotoEntity> photos,
    required List<_StoryPhotoMaterial> materials,
    required Map<int, _CaptionResult> localCaptionMap,
    Map<String, dynamic>? musicWorkflowAnalysis,
  }) async {
    final payload = <Map<String, dynamic>>[
      for (var index = 0; index < materials.length; index++)
        materials[index].toJson(
          index: index + 1,
          localCaptionResult: localCaptionMap[materials[index].photo.id],
        ),
    ];
    final prompt = _buildDeepSeekStoryPrompt(
      request: request,
      photoPayload: payload,
      musicWorkflowAnalysis: musicWorkflowAnalysis,
    );

    final response = await LLMService().completeText(
      prompt: prompt,
      systemPrompt:
          '你是一个中文图文故事写作助手。你的唯一任务是基于给定的图片素材事实，输出结构化 JSON。不要输出解释，不要输出 markdown，不要编造未提供的事实。',
    );
    if (response == null || response.trim().isEmpty) {
      return _fallbackStoryPayload(
        request: request,
        photos: photos,
        materials: materials,
        localCaptionMap: localCaptionMap,
      );
    }

    final parsed = _tryParseJsonObject(response);
    if (parsed == null) {
      return _fallbackStoryPayload(
        request: request,
        photos: photos,
        materials: materials,
        localCaptionMap: localCaptionMap,
        rawStoryText: response,
      );
    }
    final structuredPayload = _StructuredStoryPayload.fromParsedJson(
      parsed,
      fallbackTitle: request.title,
      fallbackSubtitle: request.subtitle,
      sectionCount: photos.length,
    );
    if (structuredPayload.story.trim().isEmpty &&
        structuredPayload.sections.isEmpty) {
      return _fallbackStoryPayload(
        request: request,
        photos: photos,
        materials: materials,
        localCaptionMap: localCaptionMap,
        rawStoryText: response,
      );
    }
    return structuredPayload;
  }

  String _buildDeepSeekStoryPrompt({
    required StoryGenerationRequest request,
    required List<Map<String, dynamic>> photoPayload,
    Map<String, dynamic>? musicWorkflowAnalysis,
  }) {
    final semanticSearchQuery = request.semanticSearchQuery?.trim();
    final orderingHint = request.preserveSelectionOrder
        ? '按用户故事队列顺序'
        : '按时间排序后';
    final semanticHint =
        semanticSearchQuery == null || semanticSearchQuery.isEmpty
        ? ''
        : '\n用户这次是通过语义搜索选图进入的，原始搜索内容是：$semanticSearchQuery。'
              '\n请把这句话当作用户想表达的主题线索和关注重点，但不要生硬地让每张图片都强行贴合搜索词。';

    final selectedTemplate = storyPromptTemplateById(request.storyTemplateId);
    final selectedTemplateExample = storyPromptTemplateExampleById(
      request.storyTemplateId,
    );
    final templateHint = selectedTemplate == null
        ? ''
        : '\n\nSelected writing template: ${selectedTemplate.category.title} / ${selectedTemplate.title}'
              '\nTemplate preview: ${selectedTemplate.preview}'
              '\nTemplate instruction: ${selectedTemplate.instruction}'
              '${selectedTemplateExample.isEmpty ? '' : '\nTemplate example for style reference only:\n$selectedTemplateExample'}';
    final musicWorkflow = musicWorkflowAnalysis?['llm_workflow'];
    final musicPromptSummary = musicWorkflow is Map
        ? musicWorkflow['prompt_summary']?.toString().trim()
        : null;
    final musicEditingHints =
        musicWorkflow is Map && musicWorkflow['editing_hints'] is List
        ? (musicWorkflow['editing_hints'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final musicHint = musicPromptSummary == null || musicPromptSummary.isEmpty
        ? ''
        : '\n\n端侧音乐分析结果（已在本地完成，不来自云端）：'
              '\n- $musicPromptSummary'
              '${musicEditingHints.isEmpty ? '' : '\n- 剪辑提示：${musicEditingHints.join('；')}'}'
              '\n请把这些音乐节奏与情绪变化用于 story、sections 和 highlights：快节奏处更适合短句与卡点，舒缓段更适合留白和情绪铺垫，但仍然必须以图片事实为准。';

    return '''
请基于下面这组$orderingHint的图片素材，生成一份适合相册故事页展示的结构化 JSON。

要求：
1. 只输出一个 JSON 对象，不要输出解释。
2. 必须严格基于给定素材写作，不要编造人物身份、关系和剧情。
3. 时间和地点信息如果存在，要自然融入故事，而不是机械罗列。
4. 要写得有文采、有画面感，但仍然要真实可信。
5. sections 数组长度必须等于图片数量 ${photoPayload.length}，并且 index 从 1 开始连续递增。
6. 每个 section.text 只负责对应那一张图片，长度建议 40-110 字。
7. story 是整篇故事正文，长度建议 220-700 字。
8. highlights 用 3-6 条短句概括故事的精彩片段或关键线索。
9. 如果某张图片包含 preferred_caption 和 preferred_caption_source，请把 preferred_caption 当作这张图最优先的视觉依据。
10. 如果 preferred_caption_source 是 "local_vlm"，不要让 tags 或 existing_caption 覆盖这条本地视觉描述。
11. existing_caption 只是本地 caption 不可用时的回退线索。
12. tags、ocr_tags 和 ocr_summary 都只是辅助线索，不能替代图片主体描述。
$semanticHint$templateHint$musicHint

输出 JSON 格式：
{
  "title": "",
  "subtitle": "",
  "story": "",
  "highlights": ["", ""],
  "sections": [
    {"index": 1, "text": ""}
  ]
}

额外要求：
- title 应更像最终故事标题，而不是搜索词原样复读。
- subtitle 可以沿用用户提供的切入点并润色。
- 如果某张图主要是文字、屏幕、文档，也要诚实表达，不要硬写成人物剧情。

用户设定：
- 主题：${request.title}
- 副标题/切入点：${request.subtitle.ifEmpty(request.selectedTheme.subtitle)}
- 生成方式：${request.mode.title}

图片素材(JSON)：
${jsonEncode(photoPayload)}
''';
  }

  String _buildLocalCaptionPrompt(List<OnDeviceInternvlImagePayload> payloads) {
    final metadataLines = <String>[
      '图片元数据：',
      for (var index = 0; index < payloads.length; index++)
        '- 图片${index + 1}：${_formatPayloadMeta(payloads[index])}',
    ];

    return <String>[
      '你是手机本地运行的图片描述助手。',
      '任务：为每张图片生成一句简短中文 caption。',
      '严格基于可见内容与元数据，不要解释，不要展示推理过程。',
      '',
      ...metadataLines,
      '',
      '只输出 JSON，不要 markdown，不要分析，不要复述要求。',
      'JSON 格式严格固定为：{"captions":[{"index":1,"caption":"..."}]}',
      'captions 数组长度必须与输入图片数量一致，index 从 1 开始。',
      'caption 长度控制在 12-40 个中文字符。',
    ].join('\n');
  }

  String _buildLocalStoryPrompt(
    StoryGenerationRequest request,
    List<OnDeviceInternvlImagePayload> payloads,
  ) {
    final metadataLines = <String>[
      '图片元数据：',
      for (var index = 0; index < payloads.length; index++)
        '- 图片${index + 1}：${_formatPayloadMeta(payloads[index])}',
    ];
    final semanticSearchQuery = request.semanticSearchQuery?.trim();

    return <String>[
      '你是手机本地运行的图像叙事写作助手。',
      '任务：结合多张图片与时间地点元数据，写一篇可用于相册展示的中文故事。',
      '不要解释，不要展示推理过程，不要复述要求。',
      '',
      '用户主题：${request.title}',
      '用户切入点：${request.subtitle.ifEmpty(request.selectedTheme.subtitle)}',
      if (semanticSearchQuery != null && semanticSearchQuery.isNotEmpty)
        '用户通过语义搜索进入，原始搜索内容：$semanticSearchQuery',
      '',
      ...metadataLines,
      '',
      '只输出 JSON，不要 markdown。',
      'JSON 格式严格固定为：{"story":"..."}',
      'story 必须是一整段中文，长度 180-360 个中文字符。',
      '故事要体现时间推进、地点变化和画面细节。',
    ].join('\n');
  }

  Future<InternvlStructuredResponse> _runLocalStructuredTask({
    required String prompt,
    required List<OnDeviceInternvlImagePayload> payloads,
    required int maxTokens,
    required double temperature,
    required int cliTimeoutMs,
    required Duration requestTimeout,
    _LocalRuntime? preparedRuntime,
    required bool allowCliFallback,
  }) async {
    final runtime = preparedRuntime ?? await _prepareLocalRuntime();
    final profile = runtime.profile;
    final server = runtime.server;
    if (server == null || !server.ready) {
      throw StateError(
        server?.error.isNotEmpty == true
            ? server!.error
            : server?.summary ?? '本地 VLM 服务尚未就绪',
      );
    }

    try {
      return await _internvlExperimentService
          .analyzeImagesStructured(
            serverUrl: server.chatCompletionsUrl,
            model: server.modelAlias,
            prompt: prompt,
            imagePaths: payloads
                .map((item) => item.path)
                .toList(growable: false),
            maxTokens: maxTokens,
            temperature: temperature,
          )
          .timeout(requestTimeout);
    } catch (error) {
      if (allowCliFallback &&
          (_looksLikeEmptyServerText(error) ||
              _looksLikeServerUnavailable(error))) {
        return _invokeLocalCliFallback(
          server: server,
          prompt: prompt,
          payloads: payloads,
          profileThreads: 1,
          profileContextSize: profile?.recommendedContextSize ?? 2048,
          maxTokens: maxTokens,
          cliTimeoutMs: cliTimeoutMs,
        );
      }
      if (_looksLikeServerPipeFailure(error)) {
        await OnDeviceInternvlService().stopServer();
        final restarted = await OnDeviceInternvlService().ensureServerStarted(
          threads: 1,
          contextSize: profile?.recommendedContextSize ?? 2048,
        );
        if (restarted == null || !restarted.ready) {
          throw StateError(
            '本地服务在接收图片时断开，且重启失败：${restarted?.error.isNotEmpty == true ? restarted!.error : restarted?.summary ?? '未知错误'}',
          );
        }
        try {
          return await _internvlExperimentService
              .analyzeImagesStructured(
                serverUrl: restarted.chatCompletionsUrl,
                model: restarted.modelAlias,
                prompt: prompt,
                imagePaths: payloads
                    .map((item) => item.path)
                    .toList(growable: false),
                maxTokens: maxTokens,
                temperature: temperature,
              )
              .timeout(requestTimeout);
        } catch (retryError) {
          if (allowCliFallback &&
              (_looksLikeEmptyServerText(retryError) ||
                  _looksLikeServerUnavailable(retryError) ||
                  _looksLikeServerPipeFailure(retryError))) {
            return _invokeLocalCliFallback(
              server: restarted,
              prompt: prompt,
              payloads: payloads,
              profileThreads: 1,
              profileContextSize: profile?.recommendedContextSize ?? 2048,
              maxTokens: maxTokens,
              cliTimeoutMs: cliTimeoutMs,
            );
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<_LocalRuntime> _prepareLocalRuntime() async {
    final profile = await OnDeviceInternvlService().probeDeviceProfile();
    final server = await OnDeviceInternvlService().ensureServerStarted(
      threads: 1,
      contextSize: profile?.recommendedContextSize ?? 2048,
    );
    return _LocalRuntime(profile: profile, server: server);
  }

  Future<InternvlStructuredResponse> _invokeLocalCliFallback({
    required OnDeviceInternvlServerStatus server,
    required String prompt,
    required List<OnDeviceInternvlImagePayload> payloads,
    required int profileThreads,
    required int profileContextSize,
    required int maxTokens,
    required int cliTimeoutMs,
  }) async {
    final cliResult = await OnDeviceInternvlService().runCliExperiment(
      images: payloads,
      prompt: prompt,
      threads: profileThreads,
      contextSize: profileContextSize,
      maxTokens: maxTokens,
      timeoutMs: cliTimeoutMs,
    );
    if (cliResult == null) {
      throw StateError('本地 CLI 兜底失败：未拿到执行结果');
    }
    if (!cliResult.success) {
      throw StateError(
        '本地 CLI 兜底失败: ${cliResult.error.isNotEmpty ? cliResult.error : 'exit=${cliResult.exitCode}'}',
      );
    }

    final rawText = cliResult.answer.trim().isNotEmpty
        ? cliResult.answer.trim()
        : cliResult.rawOutput.trim();
    if (rawText.isEmpty) {
      throw StateError('本地 CLI 兜底失败：模型没有返回可用文本');
    }

    return _internvlExperimentService.normalizeRawTextToStructuredResponse(
      rawContent: rawText,
      model: server.modelAlias,
      prompt: prompt,
      imageCount: payloads.length,
      serverUrl: server.chatCompletionsUrl,
    );
  }

  bool _looksLikeServerPipeFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('broken pipe') ||
        text.contains('socketexception') ||
        text.contains('connection reset') ||
        text.contains('connection terminated during handshake') ||
        text.contains('write failed');
  }

  bool _looksLikeServerUnavailable(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('status code of 503') ||
        text.contains('bad response') ||
        text.contains('server error') ||
        text.contains('no available slot') ||
        text.contains('loading model');
  }

  bool _looksLikeEmptyServerText(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('未解析出文本内容') ||
        text.contains('did not contain parseable text') ||
        text.contains('raw response');
  }
}
