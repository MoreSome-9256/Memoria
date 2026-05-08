/// 故事生成编排中的故事构建模块，把照片集合拼装成故事草稿。

part of 'story_generation_orchestrator.dart';

extension _StoryGenerationOrchestratorStoryBuilder
    on StoryGenerationOrchestrator {
  List<String> _buildHighlights({
    required StoryGenerationRequest request,
    required List<_StoryPhotoMaterial> materials,
    required Map<int, _CaptionResult> localCaptionMap,
    required _StructuredStoryPayload? localDirectStory,
  }) {
    if (localDirectStory != null && localDirectStory.highlights.isNotEmpty) {
      return localDirectStory.highlights.take(6).toList(growable: false);
    }

    final highlights = <String>[];
    final locations = materials
        .map((material) => material.locationText)
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (locations.isNotEmpty) {
      highlights.add('地点线索：${locations.take(3).join('、')}');
    }

    for (final caption in localCaptionMap.values.take(3)) {
      if (caption.text.trim().isNotEmpty) {
        highlights.add(caption.toDisplayText());
      }
    }

    if (highlights.isEmpty) {
      final topTags = <String, int>{};
      for (final material in materials) {
        for (final tag in material.aiTags.take(3)) {
          topTags[tag] = (topTags[tag] ?? 0) + 1;
        }
      }
      final sorted = topTags.entries.toList(growable: false)
        ..sort((a, b) => b.value.compareTo(a.value));
      if (sorted.isNotEmpty) {
        highlights.add(
          '主题线索：${sorted.take(4).map((entry) => entry.key).join('、')}',
        );
      }
    }

    if (request.semanticSearchQuery?.trim().isNotEmpty == true) {
      highlights.add('搜索起点：${request.semanticSearchQuery!.trim()}');
    }

    return highlights.take(6).toList(growable: false);
  }

  List<String> _buildOutlineBullets(
    List<PhotoEntity> photos,
    List<String> highlights,
  ) {
    final bullets = <String>[
      '开头：从第 1 张图切入，建立时间与情绪',
      if (photos.length > 2) '中段：在第 2~${photos.length - 1} 张之间推进场景与转场',
      '结尾：在最后一张图上收束情绪',
    ];
    bullets.addAll(highlights.take(2));
    return bullets;
  }

  _StructuredStoryPayload _fallbackStoryPayload({
    required StoryGenerationRequest request,
    required List<PhotoEntity> photos,
    required List<_StoryPhotoMaterial> materials,
    required Map<int, _CaptionResult> localCaptionMap,
    String? rawStoryText,
  }) {
    final paragraph = rawStoryText?.trim().isNotEmpty == true
        ? rawStoryText!.trim()
        : _buildFallbackStoryParagraph(request, photos);
    return _StructuredStoryPayload(
      title: request.title,
      subtitle: request.subtitle.ifEmpty(request.selectedTheme.subtitle),
      story: paragraph,
      sections: _splitNarrativeEvenly(paragraph, photos.length),
      highlights: _buildHighlights(
        request: request,
        materials: materials,
        localCaptionMap: localCaptionMap,
        localDirectStory: null,
      ),
    );
  }

  String _buildFallbackStoryParagraph(
    StoryGenerationRequest request,
    List<PhotoEntity> photos,
  ) {
    final first = photos.first;
    final last = photos.last;
    final firstTime = _formatDateTime(first.timestamp);
    final lastTime = _formatDateTime(last.timestamp);
    final firstLocation = _locationLabel(first).ifEmpty('未知地点');
    final lastLocation = _locationLabel(last).ifEmpty(firstLocation);
    final semanticHint = request.semanticSearchQuery?.trim().isNotEmpty == true
        ? '从“${request.semanticSearchQuery!.trim()}”这条线索出发，'
        : '';
    return '${request.title.ifEmpty('我的回忆')}像一条被慢慢展开的时间线。'
        '$semanticHint我们从$firstTime的$firstLocation出发，顺着画面里的细节、人物与环境一路往后看，'
        '直到$lastTime在$lastLocation把情绪轻轻收住。'
        '这些照片不只是片段，更像一段有起伏的叙事：有当时的场景、有真实的地点、有某个瞬间的心情，也有回过头再看时才会被重新理解的意味。';
  }

  Future<StoryEntity> _saveStory({
    required StoryGenerationRequest request,
    required List<PhotoEntity> photos,
    required _StructuredStoryPayload structuredStory,
  }) async {
    final normalizedSections = _normalizeSections(
      structuredStory.sections,
      photos.length,
      structuredStory.story,
    );
    final markdown = _sectionsToMarkdown(normalizedSections);
    final story =
        StoryEntity.create(
            title: structuredStory.title.ifEmpty(request.title),
            subtitle: structuredStory.subtitle.ifEmpty(
              request.subtitle.ifEmpty(request.selectedTheme.subtitle),
            ),
            content: markdown,
            eventId: int.tryParse(request.event.id) ?? -1,
            photoIds: photos.map((photo) => photo.id).toList(growable: false),
          )
          ..isHorizontal = request.isHorizontal
          ..targetPlatform = request.targetPlatform;

    final isar = PhotoService().isar;
    await isar.writeTxn(() async {
      await isar.collection<StoryEntity>().put(story);
    });
    return story;
  }

  List<String> _normalizeSections(
    List<String> sections,
    int count,
    String story,
  ) {
    final cleaned = sections
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (count <= 0) {
      return const <String>[];
    }
    if (cleaned.length == count) {
      return cleaned;
    }
    if (cleaned.isEmpty) {
      return _splitNarrativeEvenly(story, count);
    }
    if (cleaned.length > count) {
      return cleaned.take(count).toList(growable: false);
    }

    final fallbackParts = _splitNarrativeEvenly(story, count);
    final merged = <String>[];
    for (var index = 0; index < count; index++) {
      if (index < cleaned.length && cleaned[index].isNotEmpty) {
        merged.add(cleaned[index]);
      } else {
        merged.add(fallbackParts[index]);
      }
    }
    return merged;
  }

  List<String> _splitNarrativeEvenly(String story, int count) {
    if (count <= 0) {
      return const <String>[];
    }
    final normalized = story.trim();
    if (normalized.isEmpty) {
      return List<String>.filled(count, '');
    }

    final sentences = normalized
        .split(RegExp(r'(?<=[。！？!?])'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (sentences.isEmpty) {
      return List<String>.filled(count, normalized);
    }

    final groups = List<String>.filled(count, '');
    for (var index = 0; index < sentences.length; index++) {
      final target = (index * count / sentences.length).floor().clamp(
        0,
        count - 1,
      );
      final current = groups[target];
      groups[target] = current.isEmpty
          ? sentences[index]
          : '$current ${sentences[index]}';
    }

    for (var index = 1; index < groups.length; index++) {
      if (groups[index].trim().isEmpty) {
        groups[index] = groups[index - 1];
      }
    }
    if (groups.first.trim().isEmpty) {
      groups[0] = normalized;
    }
    return groups.map((item) => item.trim()).toList(growable: false);
  }

  String _sectionsToMarkdown(List<String> sections) {
    final buffer = StringBuffer();
    for (var index = 0; index < sections.length; index++) {
      if (sections[index].trim().isNotEmpty) {
        buffer.writeln(sections[index].trim());
        buffer.writeln();
      }
      buffer.writeln('![img]($index)');
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  String _locationLabel(PhotoEntity photo) {
    final preferred = photo.locationName?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      return preferred;
    }
    final segments = <String>[
      if (photo.district?.trim().isNotEmpty == true) photo.district!.trim(),
      if (photo.city?.trim().isNotEmpty == true) photo.city!.trim(),
      if (photo.province?.trim().isNotEmpty == true) photo.province!.trim(),
    ];
    return segments.join(' ');
  }

  String _formatDateTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatPayloadMeta(OnDeviceInternvlImagePayload payload) {
    final hasLatLng = payload.latitude != null && payload.longitude != null;
    final location = payload.locationName.trim().isEmpty
        ? '未知地点'
        : payload.locationName.trim();
    if (!hasLatLng) {
      return '${payload.capturedAtIso} · $location';
    }
    return '${payload.capturedAtIso} · $location (${payload.latitude!.toStringAsFixed(5)}, ${payload.longitude!.toStringAsFixed(5)})';
  }

  Map<String, dynamic>? _tryParseJsonObject(String rawContent) {
    final direct = _tryDecodeMap(rawContent);
    if (direct != null) {
      return direct;
    }
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      multiLine: true,
    ).firstMatch(rawContent)?.group(1);
    if (fenced != null) {
      final parsed = _tryDecodeMap(fenced);
      if (parsed != null) {
        return parsed;
      }
    }
    final firstBrace = rawContent.indexOf('{');
    final lastBrace = rawContent.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return _tryDecodeMap(rawContent.substring(firstBrace, lastBrace + 1));
    }
    return null;
  }

  Map<String, dynamic>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, item) => MapEntry<String, dynamic>(key.toString(), item),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  List<Map<String, dynamic>> _extractListOfMaps(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map((item) {
          return item.map(
            (key, mapValue) =>
                MapEntry<String, dynamic>(key.toString(), mapValue),
          );
        })
        .toList(growable: false);
  }
}
