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
    final vlm = SmolVlm2Service();
    await vlm.loadModel();
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      onProgress(index, photos.length, photo, Map<int, _CaptionResult>.from(captions));
      try {
        final imageBytes = await File(photo.path).readAsBytes();
        final result = await vlm.captionImage(imageBytes: imageBytes);
        if (result.text.isNotEmpty) {
          captions[photo.id] = _CaptionResult.localVlm(result.text);
        }
      } catch (_) {
        final existingCaption = photo.aiCaption?.trim();
        if (existingCaption != null && existingCaption.isNotEmpty) {
          captions[photo.id] = _CaptionResult.existingAiFallback(existingCaption);
        }
      }
      onProgress(index + 1, photos.length, photo, Map<int, _CaptionResult>.from(captions));
    }
    return captions;
  }

  Future<_StructuredStoryPayload> _generateLocalDirectStory({
    required StoryGenerationRequest request,
    required List<PhotoEntity> photos,
  }) async {
    final vlm = SmolVlm2Service();
    await vlm.loadModel();
    final imageBytesList = <Uint8List>[];
    for (final photo in photos) {
      imageBytesList.add(await File(photo.path).readAsBytes());
    }
    final result = await vlm.describeImages(
      imageBytesList: imageBytesList,
      prompt: '请根据这些照片写一篇中文故事。',
    );
    return _StructuredStoryPayload(
      title: request.title,
      subtitle: request.subtitle,
      story: result.text,
      sections: _splitNarrativeEvenly(result.text, photos.length),
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

}
