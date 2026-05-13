/// 故事生成编排中的生成阶段，负责组装最终故事文本和元数据。

part of 'story_generation_orchestrator.dart';

extension _StoryGenerationOrchestratorGeneration
    on StoryGenerationOrchestrator {
  List<StoryGenerationProgressStep> _createInitialSteps() {
    return <StoryGenerationProgressStep>[
      const StoryGenerationProgressStep(
        id: 'sort',
        title: '整理所选图片',
        status: StoryGenerationProgressStatus.pending,
      ),
      const StoryGenerationProgressStep(
        id: 'meta',
        title: '解析时间与地点',
        status: StoryGenerationProgressStatus.pending,
      ),
      const StoryGenerationProgressStep(
        id: 'clues',
        title: '提取已有线索',
        status: StoryGenerationProgressStatus.pending,
      ),
      const StoryGenerationProgressStep(
        id: 'semantic',
        title: '解析图片语义',
        status: StoryGenerationProgressStatus.pending,
      ),
      const StoryGenerationProgressStep(
        id: 'highlights',
        title: '提炼精彩片段',
        status: StoryGenerationProgressStatus.pending,
      ),
      const StoryGenerationProgressStep(
        id: 'outline',
        title: '组织故事结构',
        status: StoryGenerationProgressStatus.pending,
      ),
      const StoryGenerationProgressStep(
        id: 'write',
        title: '为你撰写故事',
        status: StoryGenerationProgressStatus.pending,
      ),
      const StoryGenerationProgressStep(
        id: 'save',
        title: '保存并整理展示',
        status: StoryGenerationProgressStatus.pending,
      ),
    ];
  }

  String? _firstInProgressStepId(List<StoryGenerationProgressStep> steps) {
    for (final step in steps) {
      if (step.status == StoryGenerationProgressStatus.inProgress) {
        return step.id;
      }
    }
    return null;
  }

  Future<void> _pauseForFlow([
    Duration duration = const Duration(milliseconds: 260),
  ]) {
    return Future<void>.delayed(duration);
  }

  String _semanticStepDetail(StoryGenerationMode mode) {
    switch (mode) {
      case StoryGenerationMode.deepseekTags:
        return '正在整理标签、OCR 与元数据语义';
      case StoryGenerationMode.localCaptionThenDeepseek:
        return '正在使用本地 VLM 为图片生成 caption';
      case StoryGenerationMode.localDirectVlm:
        return '正在使用本地 VLM 直接理解整组图片';
    }
  }

  Future<List<PhotoEntity>> _loadSelectedPhotoEntities(
    StoryGenerationRequest request,
  ) async {
    final selectedAssetIds = request.selectedPhotos
        .map((photo) => photo.id)
        .where((id) => id.trim().isNotEmpty)
        .toList(growable: false);
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final q = photoBox.query(PhotoEntity_.assetId.oneOf(selectedAssetIds)).build();
    final photos = q.find();
    q.close();

    final latestPathByAssetId = <String, String>{
      for (final photo in request.selectedPhotos)
        if (photo.path.trim().isNotEmpty) photo.id: photo.path,
    };

    for (final photo in photos) {
      final latestPath = latestPathByAssetId[photo.assetId];
      if (latestPath != null && latestPath.isNotEmpty) {
        photo.path = latestPath;
      }
    }

    if (request.preserveSelectionOrder) {
      final byAssetId = <String, PhotoEntity>{
        for (final photo in photos) photo.assetId: photo,
      };
      return request.selectedPhotos
          .map((photo) => byAssetId[photo.id])
          .whereType<PhotoEntity>()
          .toList(growable: false);
    }

    photos.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return photos;
  }

  List<String> _buildMetadataBullets(List<PhotoEntity> photos) {
    final first = photos.first;
    final last = photos.last;
    final firstDate = _formatDateTime(first.timestamp);
    final lastDate = _formatDateTime(last.timestamp);
    final locationCounts = <String, int>{};
    for (final photo in photos) {
      final location = _locationLabel(photo);
      if (location.isEmpty) {
        continue;
      }
      locationCounts[location] = (locationCounts[location] ?? 0) + 1;
    }
    final sortedLocations = locationCounts.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    return <String>[
      '时间范围：$firstDate 至 $lastDate',
      if (sortedLocations.isNotEmpty)
        '地点分布：${sortedLocations.take(3).map((entry) => '${entry.key} ${entry.value}张').join(' · ')}',
      '总素材数：${photos.length} 张',
    ];
  }

  _StoryPhotoMaterial _buildPhotoMaterial(
    PhotoEntity photo,
    Photo? requestPhoto,
  ) {
    final aiTags = TagSanitizer.sanitizeVisualTags(
      photo.aiTags ?? const <String>[],
    );
    final ocrTags = OcrPolicy.effectiveTags(photo.ocrTags ?? const <String>[]);
    final ocrSummary =
        OcrPolicy.effectiveSummary(
          tags: photo.ocrTags ?? const <String>[],
          text: photo.ocrText,
        ) ??
        '';
    final overriddenCaption = requestPhoto?.caption?.trim();
    final overriddenVlmCaption = requestPhoto?.vlmCaption?.trim();
    return _StoryPhotoMaterial(
      photo: photo,
      timeText: _formatDateTime(photo.timestamp),
      locationText: _locationLabel(photo),
      aiTags: aiTags,
      ocrTags: ocrTags,
      ocrSummary: ocrSummary,
      existingCaption: (overriddenCaption?.isNotEmpty ?? false)
          ? overriddenCaption
          : photo.aiCaption?.trim(),
      existingVlmCaption: (overriddenVlmCaption?.isNotEmpty ?? false)
          ? overriddenVlmCaption
          : null,
    );
  }

  List<String> _buildClueBullets(List<_StoryPhotoMaterial> materials) {
    final mergedTags = <String, int>{};
    for (final material in materials) {
      for (final tag in material.aiTags.take(4)) {
        mergedTags[tag] = (mergedTags[tag] ?? 0) + 1;
      }
    }
    final topTags = mergedTags.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    return <String>[
      if (topTags.isNotEmpty)
        '高频标签：${topTags.take(5).map((entry) => entry.key).join('、')}',
      if (materials.any((material) => material.ocrSummary.isNotEmpty))
        '已提取 OCR 线索 ${materials.where((material) => material.ocrSummary.isNotEmpty).length} 条',
      if (materials.any(
        (material) => material.existingCaption?.isNotEmpty == true,
      ))
        '已有 AI Caption ${materials.where((material) => material.existingCaption?.isNotEmpty == true).length} 条',
    ];
  }

  List<PhotoEntity> _samplePhotosForLocalVlm(
    List<PhotoEntity> photos, {
    required int maxCount,
  }) {
    if (photos.length <= maxCount) {
      return photos;
    }
    final sampled = <PhotoEntity>{photos.first, photos.last};
    final lastIndex = photos.length - 1;
    for (var i = 1; i < maxCount - 1; i++) {
      final index = ((lastIndex * i) / (maxCount - 1)).round();
      sampled.add(photos[index]);
    }
    final result = sampled.toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }
}
