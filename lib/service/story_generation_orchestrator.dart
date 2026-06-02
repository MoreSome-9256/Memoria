// 故事生成编排主服务，统筹选图、生成、排队和结果交付。

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/entity/photo_entity.dart';
import '../models/entity/story_entity.dart';
import '../models/vo/photo.dart';
import '../models/vo/story_generation_models.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../utils/media_type_helper.dart';
import '../utils/ocr_policy.dart';
import '../utils/tag_sanitizer.dart';
import 'internvl_experiment_service.dart';
import 'local_vlm_description_service.dart';
import 'llm_service.dart';
import 'music_service.dart';
import 'on_device_internvl_service.dart';
import 'story_service.dart';

part 'story_generation_orchestrator_generation.dart';
part 'story_generation_orchestrator_local_runtime.dart';
part 'story_generation_orchestrator_story_builder.dart';
part 'story_generation_orchestrator_models.dart';

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
          .map(
            (photo) => _buildPhotoMaterial(
              photo,
              requestPhotoByAssetId[photo.assetId],
            ),
          )
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
        final sampledPhotos = _samplePhotosForLocalVlm(
          sortedPhotos,
          maxCount: 12,
        );
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
                detail: '正在使用本地 VLM 为图片生成 caption（共$total张，已完成$completed张）',
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
                (caption) =>
                    caption.source == _CaptionSource.existingAiFallback,
              )
              .length;
          completeStep(
            'semantic',
            detail: '本地 caption 生成完成',
            bullets: <String>[
              '本地 VLM caption $localCount 张',
              if (fallbackCount > 0) '回退已有 AI Caption $fallbackCount 张',
              ...sampledPhotos
                  .asMap()
                  .entries
                  .map((entry) {
                    final caption = sampledCaptions[entry.value.id];
                    return caption == null
                        ? '第${entry.key + 1}张：未生成 caption'
                        : '第${entry.key + 1}张：${caption.toDisplayText()}';
                  })
                  .take(4),
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
        final sampledPhotos = _samplePhotosForLocalVlm(
          sortedPhotos,
          maxCount: 9,
        );
        try {
          localDirectStory = await _generateLocalDirectStory(
            request: request,
            photos: sampledPhotos,
          );
          completeStep(
            'semantic',
            detail: '本地 VLM 已完成多图理解',
            bullets: localDirectStory.highlights
                .take(4)
                .toList(growable: false),
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
        completeStep('semantic', detail: '已整理好标签语义与元数据线索');
      }

      activateStep(
        'highlights',
        detail: '正在提炼精彩片段与故事线索',
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      Map<String, dynamic>? musicWorkflowAnalysis;
      final highlights = <String>[
        ..._buildHighlights(
          request: request,
          materials: materials,
          localCaptionMap: localCaptionMap,
          localDirectStory: localDirectStory,
        ),
      ];
      final musicPath = request.customMusicPath?.trim();
      if (musicPath != null && musicPath.isNotEmpty) {
        activateStep(
          'highlights',
          detail: '正在本地分析音乐节拍与情绪变化',
          bullets: highlights,
          previewImagePaths: sortedPhotos
              .take(3)
              .map((photo) => photo.path)
              .toList(growable: false),
        );
        musicWorkflowAnalysis = await MusicService.analyzeAudio(musicPath);
        final workflow = musicWorkflowAnalysis?['llm_workflow'];
        final promptSummary = workflow is Map
            ? workflow['prompt_summary']?.toString().trim()
            : null;
        if (promptSummary != null && promptSummary.isNotEmpty) {
          highlights.add(promptSummary);
        }
      }
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
        detail:
            request.mode == StoryGenerationMode.localDirectVlm &&
                !forceDeepSeekFallback
            ? '正在整理本地 VLM 生成的故事正文'
            : '正在调用 DeepSeek 撰写故事',
        previewImagePaths: sortedPhotos
            .take(3)
            .map((photo) => photo.path)
            .toList(growable: false),
      );
      final structuredStory =
          request.mode == StoryGenerationMode.localDirectVlm &&
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
              musicWorkflowAnalysis: musicWorkflowAnalysis,
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
      emit(headline: '故事生成完成', isCompleted: true);
      return StoryGenerationOutput(story: story, photos: sortedPhotos);
    } catch (error) {
      failStep(_firstInProgressStepId(steps) ?? 'write', error.toString());
      rethrow;
    }
  }
}
