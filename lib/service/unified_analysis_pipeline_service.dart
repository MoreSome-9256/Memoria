import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/entity/photo_entity.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../storage/vector_index/vector_index_constants.dart';
import '../utils/media_type_helper.dart';
import '../utils/ai_score_helper.dart';
import 'analysis_pipeline_queue.dart';
import 'unified_analysis_progress.dart';
import 'unified_analysis_progress_store.dart';
import 'ai_background_task_service.dart';
import 'ai_service.dart';
import 'app_ai_settings_service.dart';
import 'photo_service.dart';
import 'album_selection_preference_service.dart';
import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_embedding_service.dart';
import 'mobileclip_litert_service.dart';
import 'mobileclip_tag_service.dart';
import 'event_service.dart';
import 'junk_photo_filter_service.dart';
import 'junk_photo_cleanup_service.dart';
import 'media_analysis_image_reader.dart';
import 'media_embedding_service.dart';
import 'photo_attribute_background_service.dart';
import 'video_cache_service.dart';

const String _foregroundStopRequestedKey =
    'foreground_unified_pipeline_stop_requested';

class UnifiedAnalysisPipelineService {
  UnifiedAnalysisPipelineService._internal();

  static final UnifiedAnalysisPipelineService _instance =
      UnifiedAnalysisPipelineService._internal();
  factory UnifiedAnalysisPipelineService() => _instance;

  final _progressNotifier = ValueNotifier<UnifiedAnalysisProgress>(
    UnifiedAnalysisProgress.idle(),
  );
  static const int _handoffBatchSize = 10;
  AnalysisPipelineQueue _queue = AnalysisPipelineQueue();

  bool _isRunning = false;
  bool _stopRequested = false;
  bool _scanCompletedNormally = false;
  bool _analysisEnabled = true;
  bool _suppressForegroundTaskChannelCalls = false;
  int _scanCompleted = 0;
  int _scanTotal = 0;
  int _aiCompleted = 0;
  int _aiTotal = 0;
  int _aiFailed = 0;
  DateTime? _startedAt;
  final Set<int> _activeCandidatePhotoIds = <int>{};

  ValueListenable<UnifiedAnalysisProgress> get progressListenable =>
      _progressNotifier;
  bool get isRunning => _isRunning;

  Future<void> startUnifiedPipeline({
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
    _queue = AnalysisPipelineQueue();
    _scanCompleted = 0;
    _scanTotal = 0;
    _aiCompleted = 0;
    _aiTotal = 0;
    _aiFailed = 0;
    _activeCandidatePhotoIds.clear();
    _startedAt = DateTime.now();

    debugPrint('[pipeline] ======== 统一流水线启动 ========');
    debugPrint(
      '[pipeline] clearCacheFirst=$clearCacheFirst analyzeWithAi=$analyzeWithAi',
    );

    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw StateError('统一相册流水线只允许在 foreground task 中运行。');
      }
      await UnifiedAnalysisProgressStore.instance.clear();
      _updateProgress(
        stage: UnifiedAnalysisStage.scanning,
        message: analyzeWithAi ? '已交给前台服务：正在缓存并串行分析媒体' : '已交给前台服务：正在更新相册缓存',
      );
      await AiBackgroundTaskService.instance.startUnifiedPipelineWorker(
        clearCacheFirst: clearCacheFirst,
        analyzeWithAi: analyzeWithAi,
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      _progressNotifier.value = UnifiedAnalysisProgress.idle();
      return;
    } catch (error) {
      debugPrint('[pipeline] ❌ 流水线失败: $error');
      _updateProgress(
        stage: UnifiedAnalysisStage.failed,
        message: '流水线失败: $error',
      );
      rethrow;
    } finally {
      _isRunning = false;
      _queue.close();
      debugPrint('[pipeline] ======== 统一流水线结束 ========');
    }
  }

  Future<void> runInsideForegroundService({
    bool clearCacheFirst = false,
    bool analyzeWithAi = true,
    Uint8List? storeReferenceBytes,
  }) async {
    UnifiedAnalysisProgressStore.instance.markForegroundIsolate();
    _isRunning = true;
    _stopRequested = false;
    _scanCompletedNormally = false;
    _analysisEnabled = analyzeWithAi;
    _suppressForegroundTaskChannelCalls = false;
    _queue = AnalysisPipelineQueue();
    _scanCompleted = 0;
    _scanTotal = 0;
    _aiCompleted = 0;
    _aiTotal = 0;
    _aiFailed = 0;
    _activeCandidatePhotoIds.clear();
    _startedAt = DateTime.now();

    try {
      _updateProgress(
        stage: UnifiedAnalysisStage.warmingUp,
        message: '前台服务已启动，正在连接数据库…',
      );
      await ObjectBoxService().ensureInitialized(
        referenceBytes: storeReferenceBytes,
        preferAttach: true,
      );
      await PhotoService().init();

      if (analyzeWithAi) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_foregroundStopRequestedKey, false);

        if (clearCacheFirst) {
          await _runFullRebuildPipeline(requestPermission: false);
        } else {
          await _runIncrementalPipeline(requestPermission: false);
        }

        await AiBackgroundTaskService.instance.stop();
      } else if (clearCacheFirst) {
        await _runFullRebuildPipeline(
          requestPermission: storeReferenceBytes == null,
        );
      } else {
        await _runIncrementalPipeline(
          requestPermission: storeReferenceBytes == null,
        );
      }
    } catch (error) {
      debugPrint('[pipeline] ❌ 流水线失败: $error');
      _updateProgress(
        stage: UnifiedAnalysisStage.failed,
        message: '流水线失败: $error',
      );
      rethrow;
    } finally {
      _isRunning = false;
      _queue.close();
      debugPrint('[pipeline] ======== 前台服务流水线结束 ========');
    }
  }

  void stopPipeline() {
    _stopRequested = true;
    unawaited(_writeForegroundStopRequested(true));
    _queue.clear();

    final currentStage = _progressNotifier.value.stage;
    final isTerminal =
        currentStage == UnifiedAnalysisStage.completed ||
        currentStage == UnifiedAnalysisStage.failed ||
        currentStage == UnifiedAnalysisStage.stopped;

    if (!isTerminal) {
      _updateProgress(
        stage: UnifiedAnalysisStage.stopped,
        message: '已停止：不再扫描新项目，未完成的 AI 候选会保留以便后续恢复。',
      );
    }
    debugPrint('[pipeline] 已请求停止生产者和消费者，保留未完成 AI 候选');
  }

  Future<int> deleteCurrentTaskAndClearAnalysisData() async {
    _stopRequested = true;
    await _writeForegroundStopRequested(true);
    _queue.clear();

    await AiBackgroundTaskService.instance.stop();
    await AiBackgroundTaskService.instance.clearPendingUnifiedPipelineRequest();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final clearedCount = await PhotoService().clearAllAiAnalysisData();
    try {
      await PhotoManager.clearFileCache();
      await VideoCacheService.instance.clearAllCache();
    } catch (error) {
      debugPrint('[pipeline] 清理媒体读取缓存失败: $error');
    }

    _scanCompleted = 0;
    _scanTotal = 0;
    _aiCompleted = 0;
    _aiTotal = 0;
    _aiFailed = 0;
    _scanCompletedNormally = false;
    _isRunning = false;
    await UnifiedAnalysisProgressStore.instance.clear();

    debugPrint('[pipeline] 已删除当前任务并清空 AI 分析字段 cleared=$clearedCount');
    return clearedCount;
  }

  Future<void> startPendingAnalysisCandidates() async {
    await startUnifiedPipeline(clearCacheFirst: false, analyzeWithAi: true);
  }

  Future<void> _runIncrementalPipeline({bool requestPermission = true}) async {
    if (_analysisEnabled) {
      await Future.wait(<Future<void>>[
        _runProducer(requestPermission: requestPermission),
        _runConsumer(),
      ]);
    } else {
      await _runProducer(requestPermission: requestPermission);
    }
    await _onPipelineCompleted();
  }

  Future<void> _runFullRebuildPipeline({bool requestPermission = true}) async {
    debugPrint('[pipeline] 全量重建模式：先清空再重建');

    _updateProgress(stage: UnifiedAnalysisStage.scanning, message: '正在清空缓存…');
    await PhotoService().clearAllCachedData();

    await _runIncrementalPipeline(requestPermission: requestPermission);
  }

  Future<void> _runProducer({
    bool enqueueForConsumer = true,
    bool requestPermission = true,
  }) async {
    final settings = await AppAiSettingsService.instance.load();
    final requestType = _resolveRequestType(settings);

    if (requestPermission) {
      await PhotoManager.setIgnorePermissionCheck(false);
      final permission = await PhotoManager.requestPermissionExtend(
        requestOption: PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: requestType,
            mediaLocation: false,
          ),
        ),
      );
      debugPrint(
        '[pipeline] 相册权限: state=$permission hasAccess=${permission.hasAccess} '
        'limited=${permission.isLimited} requestType=${requestType.value}',
      );
      if (!permission.hasAccess) {
        throw const PhotoScanException(
          PhotoScanError.permissionDenied,
          '没有相册权限，foreground task 无法读取系统相册。',
        );
      }
    } else {
      await PhotoManager.setIgnorePermissionCheck(true);
      debugPrint(
        '[pipeline] foreground task 使用 UI 已授予的相册权限 requestType=${requestType.value}',
      );
    }

    final albSel = await AlbumSelectionPreferenceService().loadSelection();
    final selectedIds = albSel.selectedAlbumIds.toSet();

    final targetAlbums = await _resolveProducerTargetAlbums(
      requestType: requestType,
      selectedIds: selectedIds,
    );
    debugPrint('[pipeline] 目标相册: count=${targetAlbums.length}');
    if (targetAlbums.isEmpty) {
      _queue.close();
      final message = selectedIds.isEmpty
          ? '没有找到可读取的系统相册。'
          : '当前白名单相册没有匹配到系统相册：${selectedIds.join(", ")}。请重新选择白名单相册。';
      throw PhotoScanException(PhotoScanError.noAlbum, message);
    }

    final totalCount = await _estimateTotalCount(targetAlbums);
    _scanTotal = totalCount;

    debugPrint('[pipeline] 预估总数=$_scanTotal');
    if (_scanTotal <= 0) {
      _queue.close();
      throw const PhotoScanException(
        PhotoScanError.noEligiblePhoto,
        '目标相册中没有可读取的图片或视频。',
      );
    }

    _updateProgress(
      stage: UnifiedAnalysisStage.scanning,
      message: '生产者开始扫描 $_scanTotal 个媒体',
    );

    var scanned = 0;
    var accepted = 0;
    var skipped = 0;
    const pageSize = 50;
    final handoffBatch = <PipelineQueueItem>[];
    final seenAssetIds = <String>{};

    for (final album in targetAlbums) {
      if (_stopRequested || await _readForegroundStopRequested()) break;

      final albumCount = await album.assetCountAsync;
      debugPrint(
        '[pipeline] 扫描相册 id=${album.id} name=${album.name} count=$albumCount',
      );
      for (var pageIndex = 0; ; pageIndex++) {
        if (_stopRequested || await _readForegroundStopRequested()) break;

        final page = await album.getAssetListPaged(
          page: pageIndex,
          size: pageSize,
        );

        if (page.isEmpty) {
          if (pageIndex == 0) {
            debugPrint('[pipeline] 相册分页为空 id=${album.id} name=${album.name}');
          }
          break;
        }

        page.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
        final reachedEstimatedEnd =
            page.length < pageSize || (pageIndex + 1) * pageSize >= albumCount;

        for (final asset in page) {
          if (_stopRequested || await _readForegroundStopRequested()) break;
          if (!seenAssetIds.add(asset.id)) {
            continue;
          }
          scanned++;
          _scanCompleted = scanned;

          final photo = await _buildAndSavePhotoEntity(asset);
          if (photo != null) {
            accepted++;
            if (_analysisEnabled &&
                !photo.isAiAnalyzed &&
                !_isJunkQuarantined(photo) &&
                !_activeCandidatePhotoIds.contains(photo.id)) {
              handoffBatch.add(
                PipelineQueueItem(
                  photoId: photo.id,
                  photo: photo,
                  enqueuedAt: DateTime.now(),
                ),
              );
              if (handoffBatch.length >= _handoffBatchSize) {
                _handoffBatchToAi(
                  handoffBatch,
                  enqueueForConsumer: enqueueForConsumer,
                );
              }
            }

            _updateProgress(
              stage: UnifiedAnalysisStage.scanning,
              message: '生产者正在更新相册缓存 $scanned/$_scanTotal',
            );
          }
          if (photo == null) {
            skipped++;
            _updateProgress(
              stage: UnifiedAnalysisStage.scanning,
              message: '生产者正在更新相册缓存 $scanned/$_scanTotal',
            );
          }
        }
        if (reachedEstimatedEnd) {
          break;
        }
      }
    }

    if (handoffBatch.isNotEmpty) {
      _handoffBatchToAi(handoffBatch, enqueueForConsumer: enqueueForConsumer);
    }
    _scanCompletedNormally = !_stopRequested;
    _queue.close();
    debugPrint(
      '[pipeline] 生产者结束: scanned=$scanned accepted=$accepted skipped=$skipped pendingAi=$_aiTotal stopped=$_stopRequested',
    );
  }

  bool _isJunkQuarantined(PhotoEntity photo) {
    return JunkPhotoFilterService.isQuarantined(photo.aiTags);
  }

  Future<void> _runConsumer() async {
    _updateProgress(
      stage: UnifiedAnalysisStage.warmingUp,
      message: 'AI 模型正在预热，请稍候…',
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
      message: _aiTotal > 0 ? '消费者开始打标签 $_aiTotal 个媒体' : '消费者已预热，等待生产者投递',
    );

    while (!_queue.isClosed || _queue.isNotEmpty) {
      if (_stopRequested || await _readForegroundStopRequested()) {
        break;
      }
      final item = await _queue.dequeue();
      if (item == null) {
        break;
      }

      try {
        await _processSinglePhoto(item.photo, backend: backend, liteRt: liteRt);
        _aiCompleted++;
        _activeCandidatePhotoIds.remove(item.photoId);

        _updateProgress(
          stage: UnifiedAnalysisStage.processing,
          message: '消费者已完成 $_aiCompleted/$_aiTotal，失败 $_aiFailed',
        );
      } catch (error) {
        debugPrint('[pipeline] 处理失败 photoId=${item.photoId}: $error');
        _aiFailed++;
        _activeCandidatePhotoIds.remove(item.photoId);
        _updateProgress(
          stage: UnifiedAnalysisStage.processing,
          message:
              '消费者已完成 $_aiCompleted/$_aiTotal，失败 $_aiFailed，队列 ${_queue.size}',
        );
      }
    }

    debugPrint('[pipeline] 消费者结束: completed=$_aiCompleted failed=$_aiFailed');
  }

  void _handoffBatchToAi(
    List<PipelineQueueItem> batch, {
    bool enqueueForConsumer = true,
  }) {
    if (batch.isEmpty || !_analysisEnabled) {
      batch.clear();
      return;
    }
    final batchSize = batch.length;
    _aiTotal += batchSize;
    final photoIds = batch.map((item) => item.photoId).toList(growable: false);
    PhotoService().markAiAnalysisCandidatesByIds(photoIds);
    _activeCandidatePhotoIds.addAll(photoIds);
    if (enqueueForConsumer) {
      for (final item in batch) {
        _queue.enqueue(item);
      }
    }
    debugPrint(
      enqueueForConsumer
          ? '[pipeline] 已按 $batchSize 张一组移交前台服务串行 AI，total=$_aiTotal queue=${_queue.size}'
          : '[pipeline] 已按 $batchSize 张一组标记 AI 候选，total=$_aiTotal',
    );
    batch.clear();
  }

  Future<PhotoEntity?> _buildAndSavePhotoEntity(AssetEntity asset) async {
    return await PhotoService().buildAndSaveSinglePhoto(
      asset,
      filterProfile: await _resolveFilterProfile(),
    );
  }

  Future<void> _processSinglePhoto(
    PhotoEntity photo, {
    required MobileClipBackend backend,
    required MobileClipLiteRtService liteRt,
  }) async {
    final mediaKind = MediaTypeHelper.fromStorageValue(
      photo.mediaKind,
      path: photo.path,
    );
    final isVideoLike =
        mediaKind == MemoriaMediaKind.video ||
        mediaKind == MemoriaMediaKind.dynamicImage;
    final embeddingService = MobileClipEmbeddingService();
    late final List<double> embedding;
    late final String embeddingModelVersion;
    late final MediaEmbeddingRecord embeddingRecord;
    late final List<double> tagEmbedding;
    if (mediaKind == MemoriaMediaKind.image) {
      final originalInput = await _readAnalysisImageInputFromAsset(photo);
      final originalBytes = originalInput.analysisImageBytes;
      await embeddingService.resolvePhotoEmbedding(
        photo: photo,
        preferredImageBytes: originalBytes,
        backend: backend,
      );
      embedding = photo.imageEmbedding ?? const <double>[];
      embeddingModelVersion = buildPhotoEmbeddingModelVersion(backend);
      embeddingRecord = MediaEmbeddingRecord(
        vector: embedding,
        modelVersion: embeddingModelVersion,
        modelFamily: kPhotoEmbeddingModelFamily,
        mediaKind: mediaKind,
        textSpace: MediaEmbeddingTextSpace.mobileClip2Text,
        frameSource: 'none',
        frameCount: 0,
        frameTimestampsUs: const <int>[],
        isRepeatedFrame: false,
      );
      tagEmbedding = embedding;
    } else {
      final mediaInput = await _readAnalysisImageInputFromAsset(photo);
      final mediaEmbedding = await MediaEmbeddingService()
          .embedPreparedMediaBytes(
            kind: mediaKind,
            imageOrThumbnailBytes: mediaInput.imageBytes,
            backend: backend,
            liteRt: liteRt,
            frameBytes: mediaInput.videoFrameBytes,
            frameDiagnostics: mediaInput.frameDiagnostics,
          );
      embedding = mediaEmbedding.embedding;
      embeddingModelVersion = mediaEmbedding.modelVersion;
      embeddingRecord = mediaEmbedding.toRecord();
      tagEmbedding = const <double>[];
      _logMediaEmbeddingDiagnostics(photo, embeddingRecord);
    }
    if (embedding.isEmpty) {
      throw StateError('embedding is empty');
    }

    final tagService = MobileClipTagService();
    final rawTags = tagEmbedding.isEmpty
        ? <String>['视频']
        : await tagService.retrieveTags(tagEmbedding);
    final tags = isVideoLike ? const <String>['视频'] : rawTags;

    final settings = await AppAiSettingsService.instance.load();
    PhotoService().updatePhotoInTransaction(photo.id, (p) {
      if (p == null) return;
      p.imageEmbedding = embedding;
      p.aiTags = tags;
      if (!settings.faceAnalysisEnabled) {
        p.joyScore = AIScoreHelper.calculateJoyScore(
          faceCount: 0,
          maxSmileProb: 0,
          tags: tags,
        );
      }
    });

    PhotoEmbeddingIndexRepository().upsertEmbedding(
      photoId: photo.id,
      vector: embedding,
      modelVersion: embeddingModelVersion,
      embeddingMetaJson: embeddingRecord.toMetaJson(),
    );

    await PhotoAttributeBackgroundService.instance().enqueueAttributeTask(
      photoId: photo.id,
      types: _attributeTypesForAnalyzedPhoto(photo, settings: settings),
    );
    await PhotoAttributeBackgroundService.instance().waitUntilIdle();

    PhotoService().updatePhotoInTransaction(photo.id, (p) {
      if (p == null) return;
      p.isAiAnalyzed = true;
      p.isAiAnalysisCandidate = false;
    });
  }

  @visibleForTesting
  Set<PhotoAttributeType> attributeTypesForAnalyzedPhotoForTesting(
    PhotoEntity photo, {
    AppAiSettings settings = AppAiSettings.defaults,
  }) {
    return _attributeTypesForAnalyzedPhoto(photo, settings: settings);
  }

  Set<PhotoAttributeType> _attributeTypesForAnalyzedPhoto(
    PhotoEntity photo, {
    required AppAiSettings settings,
  }) {
    final types = <PhotoAttributeType>{PhotoAttributeType.location};
    final mediaKind = MediaTypeHelper.fromStorageValue(
      photo.mediaKind,
      path: photo.path,
    );
    if (mediaKind == MemoriaMediaKind.image) {
      types.add(PhotoAttributeType.caption);
      if (settings.ocrEnabled) {
        types.add(PhotoAttributeType.ocr);
      }
      if (settings.faceAnalysisEnabled) {
        types.add(PhotoAttributeType.faceDetection);
      }
    }
    return types;
  }

  void _logMediaEmbeddingDiagnostics(
    PhotoEntity photo,
    MediaEmbeddingRecord record,
  ) {
    debugPrint(
      '[pipeline] media embedding photoId=${photo.id} '
      'kind=${record.mediaKind.name} model=${record.modelVersion} '
      'frameSource=${record.frameSource} frameCount=${record.frameCount} '
      'isRepeatedFrame=${record.isRepeatedFrame}',
    );
  }

  Future<MediaAnalysisImageInput> _readAnalysisImageInputFromAsset(
    PhotoEntity photo,
  ) async {
    final asset = await AssetEntity.fromId(photo.assetId);
    if (asset == null) {
      throw StateError('asset unavailable for image photoId=${photo.id}');
    }
    final input = await MediaAnalysisImageReader.instance.readAsset(asset);
    if (input == null || input.analysisImageBytes.isEmpty) {
      throw StateError('image reader returned empty data photoId=${photo.id}');
    }
    return input;
  }

  Future<void> _onPipelineCompleted() async {
    if (_stopRequested || await _readForegroundStopRequested()) {
      _updateProgress(
        stage: UnifiedAnalysisStage.stopped,
        message: '任务已停止，未完成的 AI 候选已保留。',
      );
      return;
    }

    if (_analysisEnabled) {
      _updateProgress(
        stage: UnifiedAnalysisStage.flushing,
        message: '标签已完成，正在批量检测低价值离群图片…',
      );
      await _publishPostFilterJunkReport();
    }

    if (_analysisEnabled && _aiTotal > 0) {
      _updateProgress(
        stage: UnifiedAnalysisStage.flushing,
        message: '正在补齐 OCR、人脸、caption 与欢乐值…',
      );
      await PhotoAttributeBackgroundService.instance().waitUntilIdle();

      _updateProgress(
        stage: UnifiedAnalysisStage.flushing,
        message: '正在刷新事件聚类…',
      );
      try {
        await EventService().runClustering();
      } catch (error) {
        debugPrint('[pipeline] 事件聚类失败，不影响低价值候选发布: $error');
      }
    }

    _updateProgress(
      stage: UnifiedAnalysisStage.completed,
      message: _analysisEnabled && _aiTotal > 0
          ? '已完成 $_aiCompleted/$_aiTotal 张照片，失败 $_aiFailed'
          : '相册缓存已更新，没有新的待分析图片',
    );
  }

  Future<void> _publishPostFilterJunkReport() async {
    await JunkPhotoCleanupService().evaluateAnalyzedPhotosForPending();
    await AIService().refreshJunkCleanupReportFromDatabase();
  }

  Future<void> _writeForegroundStopRequested(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_foregroundStopRequestedKey, value);
  }

  Future<bool> _readForegroundStopRequested() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_foregroundStopRequestedKey) ?? false;
  }

  void _updateProgress({
    required UnifiedAnalysisStage stage,
    required String message,
  }) {
    final elapsedMs = _startedAt != null
        ? DateTime.now().difference(_startedAt!).inMilliseconds
        : 0;
    final startedAtMs = _startedAt?.millisecondsSinceEpoch ?? 0;

    final isTerminal =
        stage == UnifiedAnalysisStage.completed ||
        stage == UnifiedAnalysisStage.failed ||
        stage == UnifiedAnalysisStage.stopped;

    final progress = UnifiedAnalysisProgress(
      stage: stage,
      isRunning: !isTerminal,
      scanCompleted: _scanCompleted,
      scanTotal: _scanTotal,
      aiCompleted: _aiCompleted,
      aiTotal: _aiTotal,
      aiFailed: _aiFailed,
      queueSize: _queue.size,
      message: message,
      elapsedMs: elapsedMs,
      startedAtMs: startedAtMs,
      scanDone: _scanCompletedNormally,
      scanStopped:
          stage == UnifiedAnalysisStage.stopped ||
          (_queue.isClosed && !_scanCompletedNormally),
      analysisEnabled: _analysisEnabled,
    );
    _progressNotifier.value = progress;

    debugPrint(
      '[pipeline-progress] stage=$stage scan=$_scanCompleted/$_scanTotal ai=$_aiCompleted/$_aiTotal msg=$message',
    );

    unawaited(UnifiedAnalysisProgressStore.instance.publish(progress));

    if (!_suppressForegroundTaskChannelCalls) {
      unawaited(
        AiBackgroundTaskService.instance.updateNotification(
          title: _analysisEnabled ? 'Memoria 正在缓存并分析媒体' : 'Memoria 正在更新相册缓存',
          text: message,
        ),
      );
    }
  }

  Future<List<AssetPathEntity>> _resolveProducerTargetAlbums({
    required RequestType requestType,
    required Set<String> selectedIds,
  }) async {
    if (selectedIds.isNotEmpty) {
      final albums = await PhotoManager.getAssetPathList(
        type: requestType,
        filterOption: _createDateDescFilter(),
      );
      await _logAlbumCandidates(
        albums,
        label: 'selected',
        selectedIds: selectedIds,
      );
      return albums.where((a) => _isSelectedAlbum(a, selectedIds)).toList();
    }

    final allAlbum = await _loadAllAlbumIfUsable(requestType);
    if (allAlbum != null) {
      return <AssetPathEntity>[allAlbum];
    }

    final physicalAlbums = await _loadNonEmptyAlbums(requestType);
    if (physicalAlbums.isNotEmpty) {
      debugPrint(
        '[pipeline] onlyAll 为空，改用真实相册列表 count=${physicalAlbums.length}',
      );
      return physicalAlbums;
    }

    if (requestType != RequestType.image) {
      debugPrint('[pipeline] ${requestType.value} 未读到媒体，回退 image 相册读取');
      final imageAllAlbum = await _loadAllAlbumIfUsable(RequestType.image);
      if (imageAllAlbum != null) {
        return <AssetPathEntity>[imageAllAlbum];
      }
      final imageAlbums = await _loadNonEmptyAlbums(RequestType.image);
      if (imageAlbums.isNotEmpty) {
        debugPrint('[pipeline] image 真实相册列表 count=${imageAlbums.length}');
        return imageAlbums;
      }
    }

    return const <AssetPathEntity>[];
  }

  Future<AssetPathEntity?> _loadAllAlbumIfUsable(
    RequestType requestType,
  ) async {
    final albums = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: requestType,
      filterOption: _createDateDescFilter(),
    );
    await _logAlbumCandidates(
      albums,
      label: 'onlyAll:${requestType.value}',
      selectedIds: const <String>{},
    );
    if (albums.isEmpty) {
      return null;
    }
    final album = albums.first;
    final count = await album.assetCountAsync;
    return count > 0 ? album : null;
  }

  Future<List<AssetPathEntity>> _loadNonEmptyAlbums(
    RequestType requestType,
  ) async {
    final albums = await PhotoManager.getAssetPathList(
      type: requestType,
      filterOption: _createDateDescFilter(),
    );
    await _logAlbumCandidates(
      albums,
      label: 'all:${requestType.value}',
      selectedIds: const <String>{},
    );
    final result = <AssetPathEntity>[];
    for (final album in albums) {
      if (await album.assetCountAsync > 0) {
        result.add(album);
      }
    }
    return result;
  }

  FilterOptionGroup _createDateDescFilter() {
    return FilterOptionGroup(
      orders: <OrderOption>[
        OrderOption(type: OrderOptionType.createDate, asc: false),
      ],
    );
  }

  Future<void> _logAlbumCandidates(
    List<AssetPathEntity> albums, {
    required String label,
    required Set<String> selectedIds,
  }) async {
    debugPrint(
      '[pipeline] 系统相册[$label]: count=${albums.length} selected=${selectedIds.join(",")}',
    );
    for (final album in albums.take(8)) {
      debugPrint(
        '[pipeline]   album id=${album.id} name=${album.name} count=${await album.assetCountAsync}',
      );
    }
  }

  Future<int> _estimateTotalCount(List<AssetPathEntity> albums) async {
    var total = 0;
    for (final album in albums) {
      total += await album.assetCountAsync;
    }
    return total;
  }

  RequestType _resolveRequestType(AppAiSettings settings) {
    return settings.includeVideos ? RequestType.common : RequestType.image;
  }

  bool _isSelectedAlbum(AssetPathEntity album, Set<String> selectedIds) {
    final id = album.id.toLowerCase();
    final name = album.name.toLowerCase();
    for (final selected in selectedIds) {
      final value = selected.toLowerCase().trim();
      if (value.isEmpty) {
        continue;
      }
      if (id == value || name == value) {
        return true;
      }
      if (id.contains(value) || name.contains(value)) {
        return true;
      }
      if ((value == 'camera' || value == 'dcim') &&
          (name.contains('相机') || name.contains('camera'))) {
        return true;
      }
    }
    return false;
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
    );
  }
}
