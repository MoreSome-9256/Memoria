import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import '../models/entity/photo_entity.dart';
import '../models/entity/story_entity.dart';
import '../models/vo/photo.dart';
import '../models/vo/story_generation_models.dart';
import '../utils/ocr_policy.dart';
import '../utils/tag_sanitizer.dart';
import 'internvl_experiment_service.dart';
import 'llm_service.dart';
import 'on_device_internvl_service.dart';
import 'photo_service.dart';

const String _warmupPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wn9lW8AAAAASUVORK5CYII=';

class StoryGenerationOrchestrator {
  StoryGenerationOrchestrator._internal();

  static final StoryGenerationOrchestrator _instance =
      StoryGenerationOrchestrator._internal();

  factory StoryGenerationOrchestrator() => _instance;

  final InternvlExperimentService _internvlExperimentService =
      InternvlExperimentService();

  Future<StoryGenerationOutput> generateStory({
    required StoryGenerationRequest request,
    required void Function(StoryGenerationProgressState state) onProgress,
  }) async {
    final steps = _createInitialSteps();
    void emit({
      String? headline,
      String? errorMessage,
      bool isCompleted = false,
    }) {
      onProgress(
        StoryGenerationProgressState(
          steps: List<StoryGenerationProgressStep>.unmodifiable(steps),
          headline: headline,
          errorMessage: errorMessage,
          isCompleted: isCompleted,
        ),
      );
    }

    void activateStep(
      String id, {
      String? detail,
      List<String>? bullets,
      List<String>? previewImagePaths,
    }) {
      final index = steps.indexWhere((step) => step.id == id);
      if (index < 0) {
        return;
      }
      steps[index] = steps[index].copyWith(
        status: StoryGenerationProgressStatus.inProgress,
        detail: detail,
        bullets: bullets,
        previewImagePaths: previewImagePaths,
      );
      emit(headline: detail ?? steps[index].title);
    }

    void completeStep(
      String id, {
      String? detail,
      List<String>? bullets,
      List<String>? previewImagePaths,
    }) {
      final index = steps.indexWhere((step) => step.id == id);
      if (index < 0) {
        return;
      }
      steps[index] = steps[index].copyWith(
        status: StoryGenerationProgressStatus.completed,
        detail: detail,
        bullets: bullets,
        previewImagePaths: previewImagePaths,
      );
      emit(headline: detail ?? steps[index].title);
    }

    void failStep(String id, String detail) {
      final index = steps.indexWhere((step) => step.id == id);
      if (index < 0) {
        return;
      }
      steps[index] = steps[index].copyWith(
        status: StoryGenerationProgressStatus.failed,
        detail: detail,
      );
      emit(headline: detail, errorMessage: detail);
    }

    emit(headline: '准备开始生成故事');

    try {
      activateStep(
        'sort',
        detail: request.preserveSelectionOrder
            ? '正在整理所选图片并保持队列顺序'
            : '正在整理所选图片并按时间排序',
      );
      final selectedPhotos = await _loadSelectedPhotoEntities(request);
      if (selectedPhotos.isEmpty) {
        throw StateError('当前没有可用于生成故事的照片');
      }
      final sortedPhotos = request.preserveSelectionOrder
          ? List<PhotoEntity>.from(selectedPhotos)
          : (List<PhotoEntity>.from(selectedPhotos)
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp)));
      completeStep(
        'sort',
        detail: '已整理 ${sortedPhotos.length} 张图片',
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      await _pauseForFlow();

      activateStep(
        'meta',
        detail: '正在解析图片时间与地点',
        previewImagePaths: sortedPhotos
            .take(2)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      final metadataBullets = _buildMetadataBullets(sortedPhotos);
      completeStep(
        'meta',
        detail: '时间与地点整理完成',
        bullets: metadataBullets,
        previewImagePaths: sortedPhotos
            .take(2)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      await _pauseForFlow();

      activateStep(
        'clues',
        detail: '正在提取标签、OCR 和已有 caption',
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      final requestPhotoByAssetId = <String, Photo>{
        for (final photo in request.selectedPhotos) photo.id: photo,
      };
      final materials = sortedPhotos
          .map((photo) => _buildPhotoMaterial(photo, requestPhotoByAssetId[photo.assetId]))
          .toList(growable: false);
      completeStep(
        'clues',
        detail: '素材线索提取完成',
        bullets: _buildClueBullets(materials),
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      await _pauseForFlow();

      final localCaptionMap = <int, _CaptionResult>{};
      _StructuredStoryPayload? localDirectStory;
      var forceDeepSeekFallback = false;

      activateStep(
        'semantic',
        detail: _semanticStepDetail(request.mode),
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      if (request.mode == StoryGenerationMode.localCaptionThenDeepseek) {
        final sampledPhotos = _samplePhotosForLocalVlm(sortedPhotos, maxCount: 12);
        try {
          final sampledCaptions = await _generateLocalCaptions(
            sampledPhotos,
            onProgress: (completed, total, currentPhoto, completedCaptions) {
              final bullets = completedCaptions.entries
                  .take(3)
                  .map((entry) => entry.value.toDisplayText())
                  .toList(growable: false);
              activateStep(
                'semantic',
                detail:
                    '正在使用本地 VLM 为图片生成 caption（共$total张，已完成$completed张）',
                bullets: bullets,
                previewImagePaths: <String>[
                  currentPhoto.path,
                  ...sampledPhotos
                      .where((photo) => photo.id != currentPhoto.id)
                      .take(2)
                      .map((photo) => photo.path),
                ],
              );
            },
          );
          localCaptionMap.addAll(sampledCaptions);
          final localCount = sampledCaptions.values
              .where((caption) => caption.source == _CaptionSource.localVlm)
              .length;
          final fallbackCount = sampledCaptions.values
              .where(
                (caption) => caption.source == _CaptionSource.existingAiFallback,
              )
              .length;
          completeStep(
            'semantic',
            detail: '本地 caption 生成完成',
            bullets: <String>[
              '本地 VLM caption $localCount 张',
              if (fallbackCount > 0) '回退已有 AI Caption $fallbackCount 张',
              ...sampledPhotos.asMap().entries.map((entry) {
                final caption = sampledCaptions[entry.value.id];
                return caption == null
                    ? '第${entry.key + 1}张：未生成 caption'
                    : '第${entry.key + 1}张：${caption.toDisplayText()}';
              }).take(4),
            ],
            previewImagePaths: sampledPhotos
                .take(3)
                .map((photo) => photo.path)
                .toList(growable: false),
          );
        } catch (error) {
          completeStep(
            'semantic',
            detail: '本地 caption 暂不可用，已回退到标签故事',
            bullets: <String>[error.toString()],
          );
        }
      } else if (request.mode == StoryGenerationMode.localDirectVlm) {
        final sampledPhotos = _samplePhotosForLocalVlm(sortedPhotos, maxCount: 9);
        try {
          localDirectStory = await _generateLocalDirectStory(
            request: request,
            photos: sampledPhotos,
          );
          completeStep(
            'semantic',
            detail: '本地 VLM 已完成多图理解',
            bullets: localDirectStory.highlights.take(4).toList(growable: false),
            previewImagePaths: sampledPhotos
                .take(3)
                .map((photo) => photo.path)
                .toList(growable: false),
          );
        } catch (error) {
          forceDeepSeekFallback = true;
          completeStep(
            'semantic',
            detail: '本地 VLM 暂不可用，已回退到 DeepSeek 故事',
            bullets: <String>[error.toString()],
          );
        }
      } else {
        completeStep(
          'semantic',
          detail: '已整理好标签语义与元数据线索',
        );
      }

      activateStep(
        'highlights',
        detail: '正在提炼精彩片段与故事线索',
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      final highlights = _buildHighlights(
        request: request,
        materials: materials,
        localCaptionMap: localCaptionMap,
        localDirectStory: localDirectStory,
      );
      completeStep(
        'highlights',
        detail: '已提炼出故事亮点',
        bullets: highlights,
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      await _pauseForFlow();

      activateStep(
        'outline',
        detail: '正在组织故事结构',
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      final outlineBullets = _buildOutlineBullets(sortedPhotos, highlights);
      completeStep(
        'outline',
        detail: '故事结构组织完成',
        bullets: outlineBullets,
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      await _pauseForFlow();

      activateStep(
        'write',
        detail: request.mode == StoryGenerationMode.localDirectVlm &&
                !forceDeepSeekFallback
            ? '正在整理本地 VLM 生成的故事正文'
            : '正在调用 DeepSeek 撰写故事',
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      final structuredStory = request.mode == StoryGenerationMode.localDirectVlm &&
              !forceDeepSeekFallback
          ? localDirectStory ??
              _fallbackStoryPayload(
                request: request,
                photos: sortedPhotos,
                materials: materials,
                localCaptionMap: localCaptionMap,
              )
          : await _generateDeepSeekStory(
              request: request,
              photos: sortedPhotos,
              materials: materials,
              localCaptionMap: localCaptionMap,
            );
      completeStep(
        'write',
        detail: '故事正文生成完成',
        bullets: structuredStory.highlights.take(4).toList(growable: false),
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      await _pauseForFlow();

      activateStep(
        'save',
        detail: '正在保存故事并整理展示',
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      await _applyLocalCaptionsToPhotos(
        photos: sortedPhotos,
        localCaptionMap: localCaptionMap,
      );
      final story = await _saveStory(
        request: request,
        photos: sortedPhotos,
        structuredStory: structuredStory,
      );
      completeStep(
        'save',
        detail: '故事已保存，正在打开结果页',
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      emit(
        headline: '故事生成完成',
        isCompleted: true,
      );
      return StoryGenerationOutput(story: story, photos: sortedPhotos);
    } catch (error) {
      failStep(
        _firstInProgressStepId(steps) ?? 'write',
        error.toString(),
      );
      rethrow;
    }
  }

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

  Future<void> _pauseForFlow([Duration duration = const Duration(milliseconds: 260)]) {
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
    final isar = PhotoService().isar;
    final selectedAssetIds = request.selectedPhotos
        .map((photo) => photo.id)
        .where((id) => id.trim().isNotEmpty)
        .toList(growable: false);
    final photos = await isar
        .collection<PhotoEntity>()
        .filter()
        .anyOf(
          selectedAssetIds,
          (query, assetId) => query.assetIdEqualTo(assetId),
        )
        .findAll();

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

  Future<void> _applyLocalCaptionsToPhotos({
    required List<PhotoEntity> photos,
    required Map<int, _CaptionResult> localCaptionMap,
  }) async {
    // Local VLM captions are scoped to the current story-generation flow.
    // They should not overwrite the image's existing caption used by other features.
    return;
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
    final aiTags =
        TagSanitizer.sanitizeVisualTags(photo.aiTags ?? const <String>[]);
    final ocrTags = OcrPolicy.effectiveTags(photo.ocrTags ?? const <String>[]);
    final ocrSummary = OcrPolicy.effectiveSummary(
      tags: photo.ocrTags ?? const <String>[],
      text: photo.ocrText,
    ) ?? '';
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
    await _warmupCaptionPath(runtime);
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
        final caption = await _generateSingleLocalCaption(
          payload: payload,
          runtime: runtime,
        );
        if (caption.isNotEmpty) {
          captions[photo.id] = _CaptionResult.localVlm(caption);
        } else {
          final existingCaption = photo.aiCaption?.trim();
          if (existingCaption != null && existingCaption.isNotEmpty) {
            captions[photo.id] = _CaptionResult.existingAiFallback(
              existingCaption,
            );
          }
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

  Future<String> _generateSingleLocalCaption({
    required OnDeviceInternvlImagePayload payload,
    required _LocalRuntime runtime,
    bool allowCliFallback = true,
    int maxTokens = 96,
    double temperature = 0.15,
    Duration requestTimeout = const Duration(seconds: 90),
    int cliTimeoutMs = 120000,
  }) async {
    final prompt = _buildLocalCaptionPrompt(<OnDeviceInternvlImagePayload>[payload]);
    final structured = await _runLocalStructuredTask(
      prompt: prompt,
      payloads: <OnDeviceInternvlImagePayload>[payload],
      maxTokens: maxTokens,
      temperature: temperature,
      cliTimeoutMs: cliTimeoutMs,
      requestTimeout: requestTimeout,
      preparedRuntime: runtime,
      allowCliFallback: allowCliFallback,
    );
    final caption = _extractLocalCaptionFromStructured(structured);
    return _isValidCaptionCandidate(caption) ? caption : '';
  }

  Future<void> _warmupCaptionPath(_LocalRuntime runtime) async {
    final blankPayload = await _buildWarmupImagePayload();
    try {
      await _generateSingleLocalCaption(
        payload: blankPayload,
        runtime: runtime,
        allowCliFallback: false,
        maxTokens: 32,
        temperature: 0.0,
        requestTimeout: const Duration(seconds: 25),
        cliTimeoutMs: 20000,
      );
    } catch (_) {
      // Warmup is best-effort only. The first real image should still proceed.
    }
  }

  Future<OnDeviceInternvlImagePayload> _buildWarmupImagePayload() async {
    final warmupPath = await _ensureWarmupImageFilePath();
    return OnDeviceInternvlImagePayload(
      path: warmupPath,
      capturedAtIso: DateTime.now().toUtc().toIso8601String(),
      locationName: 'local_vlm_warmup',
    );
  }

  Future<String> _ensureWarmupImageFilePath() async {
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}memoria_local_vlm_warmup.png',
    );
    if (!await file.exists()) {
      await file.writeAsBytes(base64Decode(_warmupPngBase64), flush: true);
    }
    return file.path;
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
  }) {
    final semanticSearchQuery = request.semanticSearchQuery?.trim();
    final selectedTemplate = storyPromptTemplateById(request.storyTemplateId);
    final selectedTemplateExample = storyPromptTemplateExampleById(
      request.storyTemplateId,
    );
    final orderingHint = request.preserveSelectionOrder ? '按用户故事队列顺序' : '按时间排序后';
    final semanticHint = semanticSearchQuery == null || semanticSearchQuery.isEmpty
        ? ''
        : '\n用户这次是通过语义搜索选图进入的，原始搜索内容是：$semanticSearchQuery。'
            '\n请把这句话当作用户想表达的主题线索和关注重点，但不要生硬地让每张图片都强行贴合搜索词。';

    final templateHint = selectedTemplate == null
        ? ''
        : '\n\n本次用户额外选择了文案模板：${selectedTemplate.category.title} · ${selectedTemplate.title}'
            '\n模板预期效果：${selectedTemplate.preview}'
            '\n请在不违背图片事实的前提下，优先按下面这条模板要求来组织语言和叙事：'
            '\n${selectedTemplate.instruction}'
            '${selectedTemplateExample.isEmpty ? '' : '\n\n以下是这个模板的参考示例，请学习它的写法、节奏、情绪组织方式与镜头感，但不要照抄示例内容，也不要把示例中的具体意象、地点或人物关系直接搬到当前图片里：\n$selectedTemplateExample'}';

    return '''
请基于下面这组$orderingHint的图片素材，生成一份适合相册故事页展示的结构化 JSON。

要求：
1. 只输出一个 JSON 对象，不要输出解释。
2. 必须严格基于给定素材写作，不要编造人物身份、关系和剧情。
3. 时间和地点信息如果存在，要自然融入故事，而不是机械罗列。
4. 要写得有文采、有画面感，但仍然要真实可信。
5. sections 数组长度必须等于图片数量 ${photoPayload.length}，并且 index 从 1 开始连续递增。
6. 每个 section.text 只负责对应那一张图片，长度建议 80-140 字。
7. story 是整篇故事正文，长度建议 500-1200 字。
8. highlights 用 3-6 条短句概括故事的精彩片段或关键线索。
9. 如果某张图片同时提供 existing_caption 和 local_vlm_caption，请综合两者写作：existing_caption 更像用户已有表述，local_vlm_caption 更像本地视觉补充。
10. 如果 preferred_caption_source 是 "local_vlm"，优先相信它对画面主体与细节的判断，但不要丢掉 existing_caption 里有价值的措辞或情绪线索。
11. existing_caption 不再只是回退线索；当它和 local_vlm_caption 并存时，请把它视为同一张图的补充描述来源。
12. tags、ocr_tags 和 ocr_summary 都只是辅助线索，不能替代图片主体描述。
$semanticHint$templateHint

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
    final promptMetadataLines = <String>[
      '图片元数据：',
      for (var index = 0; index < payloads.length; index++)
        '- 图片${index + 1}：${_formatPayloadMeta(payloads[index])}',
    ];
    return <String>[
      '你是手机本地图片描述助手。',
      '请只根据图片可见内容，为每张图片写一句自然、具体、简短的中文描述。',
      '如果画面主要是风景，就写风景与环境；如果主要是人物，就写人物与场景。',
      '不要解释规则，不要复述任务，不要输出“用户要求”“任务要求”“长度要求”这类字样。',
      '',
      ...promptMetadataLines,
      '',
      '只输出 JSON。',
      '格式固定：{"captions":[{"index":1,"caption":"..."}]}',
      'caption 控制在 8-24 个中文字符，避免空话和套话。',
    ].join('\n');

    // ignore: dead_code
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
    if (!_canAttemptLocalServerRequest(server)) {
      throw StateError(
        server?.error.isNotEmpty == true
            ? server!.error
            : server?.summary ?? '本地 VLM 服务尚未就绪',
      );
    }

    final readyServer = server!;
    try {
      return await _invokeLocalServerWithWarmupRetry(
        server: readyServer,
        prompt: prompt,
        payloads: payloads,
        maxTokens: maxTokens,
        temperature: temperature,
        requestTimeout: requestTimeout,
      );
    } catch (error) {
      if (allowCliFallback &&
          (_looksLikeEmptyServerText(error) ||
              _looksLikeServerUnavailable(error))) {
        return _invokeLocalCliFallback(
          server: readyServer,
          prompt: prompt,
          payloads: payloads,
          profileThreads: profile?.recommendedThreads ?? 4,
          profileContextSize: profile?.recommendedContextSize ?? 2048,
          maxTokens: maxTokens,
          cliTimeoutMs: cliTimeoutMs,
        );
      }
      if (_looksLikeServerPipeFailure(error)) {
        await OnDeviceInternvlService().stopServer();
        final restarted = await OnDeviceInternvlService().ensureServerStarted(
          threads: profile?.recommendedThreads ?? 4,
          contextSize: profile?.recommendedContextSize ?? 2048,
        );
        if (!_canAttemptLocalServerRequest(restarted)) {
          throw StateError(
            '本地服务在接收图片时断开，且重启失败：${restarted?.error.isNotEmpty == true ? restarted!.error : restarted?.summary ?? '未知错误'}',
          );
        }
        final readyRestarted = restarted!;
        try {
          return await _invokeLocalServerWithWarmupRetry(
            server: readyRestarted,
            prompt: prompt,
            payloads: payloads,
            maxTokens: maxTokens,
            temperature: temperature,
            requestTimeout: requestTimeout,
          );
        } catch (retryError) {
          if (allowCliFallback &&
              (_looksLikeEmptyServerText(retryError) ||
                  _looksLikeServerUnavailable(retryError) ||
                  _looksLikeServerPipeFailure(retryError))) {
            return _invokeLocalCliFallback(
              server: readyRestarted,
              prompt: prompt,
              payloads: payloads,
              profileThreads: profile?.recommendedThreads ?? 4,
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

  Future<InternvlStructuredResponse> _invokeLocalServerWithWarmupRetry({
    required OnDeviceInternvlServerStatus server,
    required String prompt,
    required List<OnDeviceInternvlImagePayload> payloads,
    required int maxTokens,
    required double temperature,
    required Duration requestTimeout,
  }) async {
    Object? lastError;
    for (final wait in const <Duration>[
      Duration.zero,
      Duration(seconds: 4),
      Duration(seconds: 8),
    ]) {
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      try {
        debugPrint(
          '🦙 [Local VLM] story path -> llama-server '
          'url=${server.chatCompletionsUrl} '
          'images=${payloads.length} '
          'maxTokens=$maxTokens '
          'temperature=$temperature '
          'delayMs=${wait.inMilliseconds}',
        );
        return await _internvlExperimentService.analyzeImagesStructured(
          serverUrl: server.chatCompletionsUrl,
          model: server.modelAlias,
          prompt: prompt,
          imagePaths: payloads.map((item) => item.path).toList(growable: false),
          maxTokens: maxTokens,
          temperature: temperature,
        ).timeout(requestTimeout);
      } catch (error) {
        lastError = error;
        if (!_looksLikeServerUnavailable(error) &&
            !_looksLikeEmptyServerText(error)) {
          rethrow;
        }
      }
    }
    throw lastError ?? StateError('鏈湴 VLM 鏈嶅姟棰勭儹澶辫触');
  }

  Future<_LocalRuntime> _prepareLocalRuntime() async {
    final profile = await OnDeviceInternvlService().probeDeviceProfile();
    final server = await OnDeviceInternvlService().ensureServerStarted(
      threads: profile?.recommendedThreads ?? 4,
      contextSize: profile?.recommendedContextSize ?? 2048,
    );
    return _LocalRuntime(profile: profile, server: server);
  }

  bool _canAttemptLocalServerRequest(OnDeviceInternvlServerStatus? server) {
    return server != null && (server.ready || server.reachable || server.running);
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
    debugPrint(
      '🦙 [Local VLM] story path -> CLI fallback '
      'images=${payloads.length} '
      'maxTokens=$maxTokens '
      'timeoutMs=$cliTimeoutMs',
    );
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
    final paragraph =
        rawStoryText?.trim().isNotEmpty == true
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
    final story = StoryEntity.create(
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
      final target =
          (index * count / sentences.length).floor().clamp(0, count - 1);
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
    return value.whereType<Map>().map((item) {
      return item.map(
        (key, mapValue) => MapEntry<String, dynamic>(key.toString(), mapValue),
      );
    }).toList(growable: false);
  }

  String _extractLocalCaptionFromStructured(
    InternvlStructuredResponse structured,
  ) {
    final parsed = _tryParseJsonObject(structured.rawContent);
    final output = _extractOutputMap(parsed);
    final rawCaptions = _extractListOfMaps(
      output['captions'] ?? output['items'] ?? output['images'],
    );

    var candidate = '';
    if (rawCaptions.isNotEmpty) {
      candidate = _cleanCaptionText(
        _firstString(
              rawCaptions.first,
              const <String>['caption', 'description', 'text', 'summary'],
            ) ??
            '',
      );
    }

    if (!_isValidCaptionCandidate(candidate)) {
      final fallbackCaptions = _extractDraftCaptions(structured.rawContent);
      if (fallbackCaptions.isNotEmpty) {
        candidate = _cleanCaptionText(fallbackCaptions.first);
      }
    }

    if (!_isValidCaptionCandidate(candidate)) {
      candidate = _cleanCaptionText(_extractFinalParagraph(structured.rawContent));
    }

    if (!_isValidCaptionCandidate(candidate)) {
      candidate = _cleanCaptionText(structured.narrative);
    }

    return _isValidCaptionCandidate(candidate) ? candidate : '';
  }

  Map<String, dynamic> _extractOutputMap(Map<String, dynamic>? parsed) {
    if (parsed == null) {
      return <String, dynamic>{};
    }
    final output = parsed['output'];
    if (output is Map<String, dynamic>) {
      return output;
    }
    if (output is Map) {
      return output.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      );
    }
    return parsed;
  }

  String? _firstString(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) {
      return null;
    }
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  List<String> _extractDraftCaptions(String rawText) {
    final matches = RegExp(
      r'caption\s*\d*\s*[:\uFF1A]\s*(.+)',
      caseSensitive: false,
    ).allMatches(rawText);
    final extracted = matches
        .map((match) => _cleanCaptionText(match.group(1) ?? ''))
        .where(_isValidCaptionCandidate)
        .toList(growable: false);
    if (extracted.isNotEmpty) {
      return extracted.toSet().toList(growable: false);
    }

    final compact = _extractFinalParagraph(rawText);
    return _isValidCaptionCandidate(compact)
        ? <String>[compact]
        : const <String>[];
  }

  String _extractFinalParagraph(String rawText) {
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !_looksLikeInstructionLine(line))
        .where((line) => !_looksLikeRuntimeLogLine(line))
        .toList(growable: false);
    if (lines.isEmpty) {
      return '';
    }
    return lines.last;
  }

  bool _looksLikePromptEchoText(String text) {
    final lower = text.toLowerCase();
    return text.contains('用户要求') ||
        text.contains('任务要求') ||
        text.contains('长度要求') ||
        text.contains('回答要求') ||
        text.contains('附加要求') ||
        text.contains('图片元数据') ||
        text.contains('只输出 JSON') ||
        text.contains('不要复述要求') ||
        text.contains('可见内容与元数据') ||
        text.contains('基于图片的可见内容') ||
        lower.contains('user requirements') ||
        lower.contains('task requirements') ||
        lower.contains('output requirements') ||
        lower.contains('caption length') ||
        lower.contains('visible content') ||
        lower.contains('metadata');
  }

  bool _looksLikeInstructionLine(String line) {
    final lower = line.toLowerCase();
    return _looksLikePromptEchoText(line) ||
        lower.contains('schema_version') ||
        lower.contains('"task"') ||
        lower.contains("'task'") ||
        lower.contains('"output"') ||
        lower.contains("'output'") ||
        lower.contains('json format') ||
        lower.contains('json schema') ||
        lower.contains('captions array') ||
        lower.contains('caption length') ||
        lower.contains('facts') ||
        lower.contains('time_hint') ||
        lower.contains('location_hint') ||
        lower.contains('confidence') ||
        lower.contains('metadata') ||
        lower.contains('output requirements') ||
        lower.contains('extra requirements') ||
        lower.contains('user theme') ||
        lower.contains('user angle') ||
        lower.contains('generation mode') ||
        lower.contains('task:') ||
        lower.startsWith('1.') ||
        lower.startsWith('2.') ||
        lower.startsWith('3.') ||
        lower.startsWith('*') ||
        lower.startsWith('-');
  }

  bool _looksLikeRuntimeLogLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('load_tensors') ||
        lower.contains('llama_') ||
        lower.contains('clip_') ||
        lower.contains('sched_') ||
        lower.contains('find_slot') ||
        lower.contains('gguf') ||
        lower.contains('flash attention') ||
        lower.contains('cpu mapped model buffer') ||
        lower.contains('encoding image slice') ||
        lower.contains('<think>') ||
        lower.contains('</think>') ||
        lower.contains('```') ||
        lower.contains("'''json");
  }

  String _cleanCaptionText(String value) {
    var cleaned = value.trim();
    if (cleaned.isEmpty) {
      return '';
    }
    cleaned = cleaned.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\\n+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r'^[#*\-\d.\s:\uFF1A]+'), '').trim();
    if (_looksLikePromptEchoText(cleaned)) {
      return '';
    }

    const stopMarkers = <String>[
      '用户要求',
      '任务要求',
      '长度要求',
      '回答要求',
      '附加要求',
      '图片元数据',
      '只输出 JSON',
      '不要复述要求',
      '可见内容与元数据',
      '基于图片的可见内容',
      'schema_version',
      '"task"',
      "'task'",
      '"output"',
      "'output'",
      'json format',
      'json schema',
      'captions array',
      'caption length',
      'facts',
      'time_hint',
      'location_hint',
      'confidence',
      'metadata',
      'output requirements',
      'extra requirements',
      'user theme',
      'user angle',
      'generation mode',
      'task:',
      'load_tensors',
      'llama_',
      'clip_',
      'sched_',
      'find_slot',
      'gguf',
      'flash attention',
      'cpu mapped model buffer',
      '<think>',
      '</think>',
    ];
    for (final marker in stopMarkers) {
      final index = cleaned.toLowerCase().indexOf(marker);
      if (index >= 0) {
        cleaned = cleaned.substring(0, index).trim();
      }
    }

    cleaned = cleaned.replaceAll(RegExp("^[`\"']+|[`\"']+\$"), '').trim();
    return cleaned;
  }

  bool _isValidCaptionCandidate(String value) {
    final cleaned = value.trim();
    final lower = cleaned.toLowerCase();
    if (cleaned.isEmpty || cleaned.length > 80) {
      return false;
    }
    if (_looksLikePromptEchoText(cleaned)) {
      return false;
    }
    if (_looksLikeInstructionLine(cleaned) ||
        _looksLikeRuntimeLogLine(cleaned)) {
      return false;
    }
    if (cleaned.startsWith('{') ||
        cleaned.startsWith('[') ||
        lower.contains('"caption"') ||
        lower == 'caption' ||
        lower == 'json') {
      return false;
    }
    return RegExp(r'[\u4e00-\u9fff]').hasMatch(cleaned);
  }
}

class _StoryPhotoMaterial {
  const _StoryPhotoMaterial({
    required this.photo,
    required this.timeText,
    required this.locationText,
    required this.aiTags,
    required this.ocrTags,
    required this.ocrSummary,
    required this.existingCaption,
    required this.existingVlmCaption,
  });

  final PhotoEntity photo;
  final String timeText;
  final String locationText;
  final List<String> aiTags;
  final List<String> ocrTags;
  final String ocrSummary;
  final String? existingCaption;
  final String? existingVlmCaption;

  Map<String, dynamic> toJson({
    required int index,
    _CaptionResult? localCaptionResult,
  }) {
    final storedVlmCaption = existingVlmCaption?.trim() ?? '';
    final hasStoredVlmCaption = storedVlmCaption.isNotEmpty;
    final localCaption = localCaptionResult?.source == _CaptionSource.localVlm
        ? localCaptionResult!.text
        : storedVlmCaption;
    final preferredCaption = localCaption.trim().isNotEmpty
        ? localCaption
        : (existingCaption ?? '');
    final preferredSource = localCaption.trim().isNotEmpty
        ? _CaptionSource.localVlm.apiValue
        : localCaptionResult?.source.apiValue ??
        (hasStoredVlmCaption
            ? _CaptionSource.localVlm.apiValue
            : null) ??
        ((existingCaption?.trim().isNotEmpty ?? false)
            ? _CaptionSource.existingAiFallback.apiValue
            : _CaptionSource.none.apiValue);
    return <String, dynamic>{
      'index': index,
      'captured_at': timeText,
      'location': <String, dynamic>{
        'location_name': photo.locationName?.trim(),
        'district': photo.district?.trim(),
        'city': photo.city?.trim(),
        'province': photo.province?.trim(),
        'display_text': locationText,
      },
      'tags': aiTags,
      'ocr_tags': ocrTags,
      'ocr_summary': ocrSummary,
      'existing_caption': existingCaption ?? '',
      'local_vlm_caption': localCaption,
      'local_vlm_caption_source':
          localCaptionResult?.source.apiValue ??
          (hasStoredVlmCaption
              ? _CaptionSource.localVlm.apiValue
              : _CaptionSource.none.apiValue),
      'preferred_caption': preferredCaption,
      'preferred_caption_source': preferredSource,
    };
  }
}

enum _CaptionSource {
  localVlm('local_vlm'),
  existingAiFallback('existing_ai_fallback'),
  none('none');

  const _CaptionSource(this.apiValue);

  final String apiValue;
}

class _CaptionResult {
  const _CaptionResult._({
    required this.text,
    required this.source,
  });

  factory _CaptionResult.localVlm(String text) =>
      _CaptionResult._(text: text.trim(), source: _CaptionSource.localVlm);

  factory _CaptionResult.existingAiFallback(String text) => _CaptionResult._(
        text: text.trim(),
        source: _CaptionSource.existingAiFallback,
      );

  final String text;
  final _CaptionSource source;

  String toDisplayText() {
    if (text.trim().isEmpty) {
      return '';
    }
    switch (source) {
      case _CaptionSource.localVlm:
        return '本地 VLM：$text';
      case _CaptionSource.existingAiFallback:
        return '回退 AI Caption：$text';
      case _CaptionSource.none:
        return text;
    }
  }
}

class _StructuredStoryPayload {
  const _StructuredStoryPayload({
    required this.title,
    required this.subtitle,
    required this.story,
    required this.sections,
    required this.highlights,
  });

  final String title;
  final String subtitle;
  final String story;
  final List<String> sections;
  final List<String> highlights;

  factory _StructuredStoryPayload.fromParsedJson(
    Map<String, dynamic> json, {
    required String fallbackTitle,
    required String fallbackSubtitle,
    required int sectionCount,
  }) {
    final title =
        (json['title']?.toString().trim() ?? '').ifEmpty(fallbackTitle);
    final subtitle =
        (json['subtitle']?.toString().trim() ?? '').ifEmpty(fallbackSubtitle);
    final story = json['story']?.toString().trim() ?? '';
    final highlights = (json['highlights'] is List)
        ? (json['highlights'] as List)
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final sections = <String>[];
    if (json['sections'] is List) {
      for (final item in json['sections'] as List) {
        if (item is Map) {
          final text = item['text']?.toString().trim() ?? '';
          if (text.isNotEmpty) {
            sections.add(text);
          }
        }
      }
    }
    final normalizedSections = sections.length == sectionCount
        ? sections
        : const <String>[];
    return _StructuredStoryPayload(
      title: title,
      subtitle: subtitle,
      story: story,
      sections: normalizedSections,
      highlights: highlights,
    );
  }
}

class _LocalRuntime {
  const _LocalRuntime({
    required this.profile,
    required this.server,
  });

  final OnDeviceInternvlProfile? profile;
  final OnDeviceInternvlServerStatus? server;
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
