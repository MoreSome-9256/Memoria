import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/entity/photo_entity.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../storage/vector_index/vector_index_constants.dart';
import 'analysis_pipeline_queue.dart';
import 'unified_analysis_progress.dart';
import 'ai_background_task_service.dart';
import 'app_ai_settings_service.dart';
import 'photo_service.dart';
import 'album_selection_preference_service.dart';
import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_embedding_service.dart';
import 'mobileclip_litert_service.dart';
import 'mobileclip_tag_service.dart';
import 'ocr_service.dart';
import 'event_service.dart';
import 'photo_attribute_background_service.dart';

class UnifiedAnalysisPipelineService {
  UnifiedAnalysisPipelineService._internal();

  static final UnifiedAnalysisPipelineService _instance =
      UnifiedAnalysisPipelineService._internal();
  factory UnifiedAnalysisPipelineService() => _instance;

  final _progressNotifier = ValueNotifier<UnifiedAnalysisProgress>(
    UnifiedAnalysisProgress.idle(),
  );
  static const int _handoffBatchSize = 10;
  static const Duration _consumerIdleGrace = Duration(seconds: 300);
  AnalysisPipelineQueue _queue = AnalysisPipelineQueue(
    capacity: 200,
    highWaterMark: 160,
  );

  bool _isRunning = false;
  bool _stopRequested = false;
  bool _scanCompletedNormally = false;
  bool _analysisEnabled = true;
  int _scanCompleted = 0;
  int _scanTotal = 0;
  int _aiCompleted = 0;
  int _aiTotal = 0;
  int _aiFailed = 0;
  DateTime? _startedAt;

  ValueListenable<UnifiedAnalysisProgress> get progressListenable =>
      _progressNotifier;
  bool get isRunning => _isRunning;

  Future<void> startUnifiedPipeline({
    int? maxPhotos,
    bool clearCacheFirst = false,
    bool analyzeWithAi = true,
  }) async {
    if (_isRunning) {
      debugPrint('[pipeline] 流水线已在运行，忽略重复请求');
      return;
    }

    _isRunning = true;
    _stopRequested = false;
    _scanCompletedNormally = false;
    _analysisEnabled = analyzeWithAi;
    _queue = AnalysisPipelineQueue(capacity: 200, highWaterMark: 160);
    _scanCompleted = 0;
    _scanTotal = 0;
    _aiCompleted = 0;
    _aiTotal = 0;
    _aiFailed = 0;
    _startedAt = DateTime.now();

    debugPrint('[pipeline] ======== 统一流水线启动 ========');
    debugPrint(
      '[pipeline] maxPhotos=$maxPhotos clearCacheFirst=$clearCacheFirst analyzeWithAi=$analyzeWithAi',
    );

    try {
      if (clearCacheFirst) {
        await _runFullRebuildPipeline(maxPhotos: maxPhotos);
      } else {
        await _runIncrementalPipeline(maxPhotos: maxPhotos);
      }
    } catch (error) {
      debugPrint('[pipeline] ❌ 流水线失败: $error');
      _progressNotifier.value = UnifiedAnalysisProgress.idle();
      rethrow;
    } finally {
      _isRunning = false;
      _queue.close();
      debugPrint('[pipeline] ======== 统一流水线结束 ========');
    }
  }

  void stopPipeline() {
    _stopRequested = true;
    _queue.close();
    debugPrint('[pipeline] 已请求停止扫描；AI 会继续处理已移交任务');
  }

  Future<void> _runIncrementalPipeline({int? maxPhotos}) async {
    final foregroundStarted = await AiBackgroundTaskService.instance
        .startAlbumCacheForeground(text: '正在准备分析流水线…');

    try {
      if (_analysisEnabled) {
        await Future.wait([
          _runProducer(maxPhotos: maxPhotos),
          _runConsumer(),
        ], eagerError: true);
      } else {
        await _runProducer(maxPhotos: maxPhotos);
        await _onPipelineCompleted();
      }
    } finally {
      if (foregroundStarted) {
        await AiBackgroundTaskService.instance.stop();
      }
    }
  }

  Future<void> _runFullRebuildPipeline({int? maxPhotos}) async {
    debugPrint('[pipeline] 全量重建模式：先清空再重建');

    _updateProgress(stage: UnifiedAnalysisStage.scanning, message: '正在清空缓存…');
    await PhotoService().clearAllCachedData();

    await _runIncrementalPipeline(maxPhotos: maxPhotos);
  }

  Future<void> _runProducer({int? maxPhotos}) async {
    final settings = await AppAiSettingsService.instance.load();
    final requestType = settings.includeVideos
        ? RequestType.common
        : RequestType.image;

    final state = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: requestType,
          mediaLocation: false,
        ),
      ),
    );

    if (!state.hasAccess) {
      debugPrint('[pipeline] 没有相册权限');
      _queue.close();
      return;
    }

    final albSel = await AlbumSelectionPreferenceService().loadSelection();
    final selectedIds = albSel.selectedAlbumIds.toSet();

    final albums = selectedIds.isEmpty
        ? await PhotoManager.getAssetPathList(onlyAll: true, type: requestType)
        : await PhotoManager.getAssetPathList(type: requestType);

    if (albums.isEmpty) {
      debugPrint('[pipeline] 没有找到相册');
      _queue.close();
      return;
    }

    final targetAlbums = selectedIds.isEmpty
        ? albums
        : albums.where((a) => _isSelectedAlbum(a, selectedIds)).toList();

    final totalCount = await _estimateTotalCount(targetAlbums);
    _scanTotal = maxPhotos != null
        ? math.min(maxPhotos, totalCount)
        : totalCount;

    debugPrint('[pipeline] 预估总数=$_scanTotal');

    _updateProgress(
      stage: UnifiedAnalysisStage.scanning,
      message: '开始扫描 $_scanTotal 张照片',
    );

    var scanned = 0;
    const pageSize = 50;
    final handoffBatch = <PipelineQueueItem>[];

    for (final album in targetAlbums) {
      if (_stopRequested) break;

      final albumCount = await album.assetCountAsync;
      for (var offset = 0; offset < albumCount; offset += pageSize) {
        if (_stopRequested) break;
        if (maxPhotos != null && scanned >= maxPhotos) break;

        final end = math.min(albumCount, offset + pageSize);
        final page = await album.getAssetListRange(start: offset, end: end);

        if (page.isEmpty) continue;

        for (final asset in page) {
          if (_stopRequested) break;
          if (maxPhotos != null && scanned >= maxPhotos) break;

          final photo = await _buildAndSavePhotoEntity(asset);
          if (photo != null) {
            scanned++;
            _scanCompleted = scanned;

            if (_analysisEnabled && !photo.isAiAnalyzed) {
              handoffBatch.add(
                PipelineQueueItem(
                  photoId: photo.id,
                  photo: photo,
                  enqueuedAt: DateTime.now(),
                ),
              );
              if (handoffBatch.length >= _handoffBatchSize) {
                await _handoffBatchToAi(handoffBatch);
              }
            }

            _updateProgress(
              stage: UnifiedAnalysisStage.scanning,
              message: _analysisEnabled
                  ? '正在更新相册缓存……($scanned/$_scanTotal)，已移交 $_aiTotal 张，队列 ${_queue.size}'
                  : '正在更新相册缓存……($scanned/$_scanTotal)',
            );
          }
        }
      }
    }

    if (handoffBatch.isNotEmpty) {
      await _handoffBatchToAi(handoffBatch);
    }
    _scanCompletedNormally = !_stopRequested;
    _queue.close();
    debugPrint(
      '[pipeline] 生产者结束: scanned=$scanned queued=$_aiTotal stopped=$_stopRequested',
    );
  }

  Future<void> _runConsumer() async {
    _updateProgress(
      stage: UnifiedAnalysisStage.warmingUp,
      message: '正在预热 AI 引擎…',
    );

    final settings = await AppAiSettingsService.instance.load();
    final backend = await MobileClipBackendPreferenceService()
        .getSelectedBackend();

    final liteRt = MobileClipLiteRtService.withRuntimeOptions(
      accelerator: settings.inferenceAccelerator,
      xnnpackThreadCount: settings.xnnpackThreadCount,
      modelBatchSize: settings.analysisBatchSize,
    );

    await liteRt.warmUp();
    await MobileClipTagService().warmUp();

    debugPrint('[pipeline] AI 引擎预热完成');

    _updateProgress(
      stage: UnifiedAnalysisStage.processing,
      message: _aiTotal > 0 ? '开始处理 $_aiTotal 张照片' : 'AI 已预热，等待扫描移交任务…',
    );

    var idleStartedAt = DateTime.now();
    while (!_queue.isClosed || _queue.isNotEmpty) {
      final item = await _dequeueWithIdleGrace(idleStartedAt);
      if (item == null) {
        if (_queue.isClosed) {
          break;
        }
        debugPrint(
          '[pipeline] AI 等待任务超过 ${_consumerIdleGrace.inSeconds}s，结束本轮',
        );
        break;
      }
      idleStartedAt = DateTime.now();

      try {
        await _processSinglePhoto(
          item.photo,
          settings: settings,
          backend: backend,
        );
        _aiCompleted++;

        _updateProgress(
          stage: UnifiedAnalysisStage.processing,
          message: '已完成 $_aiCompleted/$_aiTotal，失败 $_aiFailed',
        );
      } catch (error) {
        debugPrint('[pipeline] 处理失败 photoId=${item.photoId}: $error');
        _aiFailed++;
        _updateProgress(
          stage: UnifiedAnalysisStage.processing,
          message:
              '已完成 $_aiCompleted/$_aiTotal，失败 $_aiFailed，队列 ${_queue.size}',
        );
      }
    }

    debugPrint('[pipeline] 消费者结束: completed=$_aiCompleted failed=$_aiFailed');

    await _onPipelineCompleted();
  }

  Future<void> _handoffBatchToAi(List<PipelineQueueItem> batch) async {
    if (batch.isEmpty || !_analysisEnabled) {
      batch.clear();
      return;
    }
    if (_queue.isClosed) {
      batch.clear();
      return;
    }
    final batchSize = batch.length;
    _aiTotal += batchSize;
    for (final item in batch) {
      await _queue.enqueue(item);
    }
    debugPrint(
      '[pipeline] 已按 $batchSize 张一组移交 AI，total=$_aiTotal queue=${_queue.size}',
    );
    batch.clear();
  }

  Future<PipelineQueueItem?> _dequeueWithIdleGrace(
    DateTime idleStartedAt,
  ) async {
    if (_queue.isNotEmpty || _queue.isClosed) {
      return _queue.dequeue();
    }
    while (!_queue.isClosed && _queue.isEmpty) {
      final idleFor = DateTime.now().difference(idleStartedAt);
      if (idleFor >= _consumerIdleGrace) {
        return null;
      }
      final remaining = _consumerIdleGrace - idleFor;
      _updateProgress(
        stage: UnifiedAnalysisStage.processing,
        message:
            'AI 已预热，等待扫描移交任务…剩余等待 ${remaining.inSeconds.clamp(0, _consumerIdleGrace.inSeconds)} 秒',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return _queue.dequeue();
  }

  Future<PhotoEntity?> _buildAndSavePhotoEntity(AssetEntity asset) async {
    return await PhotoService().buildAndSaveSinglePhoto(
      asset,
      filterProfile: await _resolveFilterProfile(),
      resolveFile: true,
    );
  }

  Future<void> _processSinglePhoto(
    PhotoEntity photo, {
    required AppAiSettings settings,
    required MobileClipBackend backend,
  }) async {
    final embeddingService = MobileClipEmbeddingService();
    await embeddingService.resolvePhotoEmbedding(
      photo: photo,
      backend: backend,
    );

    final embedding = photo.imageEmbedding;
    if (embedding == null || embedding.isEmpty) {
      throw StateError('embedding is empty');
    }

    final tagService = MobileClipTagService();
    final tags = await tagService.retrieveTags(embedding);

    String? ocrText;
    List<String> ocrTags = const [];
    if (settings.ocrEnabled &&
        OcrService.shouldRunOcr(tags, aspectRatio: photo.aspectRatio)) {
      final imageFile = File(photo.path);
      final ocrResult = await OcrService().analyzeImageFile(imageFile);
      ocrText = ocrResult.text;
      ocrTags = ocrResult.tags;
    }

    PhotoService().updatePhotoInTransaction(photo.id, (p) {
      if (p == null) return;
      p.imageEmbedding = embedding;
      p.aiTags = tags;
      p.ocrText = ocrText;
      p.ocrTags = ocrTags;
      p.isAiAnalyzed = true;
    });

    PhotoEmbeddingIndexRepository().upsertEmbedding(
      photoId: photo.id,
      vector: embedding,
      modelVersion: buildPhotoEmbeddingModelVersion(backend),
    );

    unawaited(
      PhotoAttributeBackgroundService.instance().enqueueAttributeTask(
        photoId: photo.id,
        types: {PhotoAttributeType.location},
      ),
    );
  }

  Future<void> _onPipelineCompleted() async {
    _updateProgress(
      stage: UnifiedAnalysisStage.flushing,
      message: _analysisEnabled ? '正在刷新事件聚类…' : '相册缓存已更新',
    );

    if (_analysisEnabled) {
      await EventService().runClustering();
    }

    _updateProgress(
      stage: UnifiedAnalysisStage.completed,
      message: _analysisEnabled ? '已完成 $_aiCompleted 张照片' : '相册缓存已更新',
    );

    await Future.delayed(const Duration(milliseconds: 1800));
    _progressNotifier.value = UnifiedAnalysisProgress.idle();
  }

  void _updateProgress({
    required UnifiedAnalysisStage stage,
    required String message,
  }) {
    final elapsedMs = _startedAt != null
        ? DateTime.now().difference(_startedAt!).inMilliseconds
        : 0;

    _progressNotifier.value = UnifiedAnalysisProgress(
      stage: stage,
      isRunning: true,
      scanCompleted: _scanCompleted,
      scanTotal: _scanTotal,
      aiCompleted: _aiCompleted,
      aiTotal: _aiTotal,
      aiFailed: _aiFailed,
      queueSize: _queue.size,
      message: message,
      elapsedMs: elapsedMs,
      scanDone: _scanCompletedNormally,
      scanStopped: _queue.isClosed && !_scanCompletedNormally,
      analysisEnabled: _analysisEnabled,
    );

    unawaited(
      AiBackgroundTaskService.instance.updateNotification(
        title: 'Memoria 正在分析照片',
        text: message,
      ),
    );
  }

  Future<int> _estimateTotalCount(List<AssetPathEntity> albums) async {
    var total = 0;
    for (final album in albums) {
      total += await album.assetCountAsync;
    }
    return total;
  }

  bool _isSelectedAlbum(AssetPathEntity album, Set<String> selectedIds) {
    if (selectedIds.contains(album.id)) return true;
    if (selectedIds.contains(album.name)) return true;
    return selectedIds.contains(album.name.toLowerCase());
  }

  Future<PhotoScanFilterProfile> _resolveFilterProfile() async {
    final prefs = await AlbumSelectionPreferenceService().loadScanPreferences();
    int? minTs;
    if (prefs.minYear != null) {
      final y = prefs.minYear!;
      minTs = DateTime(y, 1, 1).millisecondsSinceEpoch;
    }
    const base = PhotoScanFilterProfile.userSelectedAlbums;
    return PhotoScanFilterProfile(
      requireValidDimensions: base.requireValidDimensions,
      minTimestampMs: minTs,
      minWidth: prefs.minWidth,
      minHeight: prefs.minHeight,
      minPixels: prefs.minPixels,
      excludeExtremeAspectRatios: prefs.excludeExtremeAspectRatios,
    );
  }
}
