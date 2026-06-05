import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/entity/photo_entity.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../storage/vector_index/vector_index_constants.dart';
import '../utils/media_type_helper.dart';
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
import 'ocr_service.dart';
import 'event_service.dart';
import 'junk_photo_filter_service.dart';
import 'media_analysis_image_reader.dart';
import 'media_embedding_service.dart';
import 'photo_attribute_background_service.dart';

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
  static const Duration _consumerIdleGrace = Duration(seconds: 300);
  AnalysisPipelineQueue _queue = AnalysisPipelineQueue(
    capacity: 200,
    highWaterMark: 160,
  );

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
  final List<JunkPhotoCleanupCandidate> _junkCandidates =
      <JunkPhotoCleanupCandidate>[];

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
    _queue = AnalysisPipelineQueue(capacity: 200, highWaterMark: 160);
    _scanCompleted = 0;
    _scanTotal = 0;
    _aiCompleted = 0;
    _aiTotal = 0;
    _aiFailed = 0;
    _activeCandidatePhotoIds.clear();
    _junkCandidates.clear();
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
    _queue = AnalysisPipelineQueue(capacity: 1, highWaterMark: 1);
    _scanCompleted = 0;
    _scanTotal = 0;
    _aiCompleted = 0;
    _aiTotal = 0;
    _aiFailed = 0;
    _activeCandidatePhotoIds.clear();
    _junkCandidates.clear();
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
          _updateProgress(
            stage: UnifiedAnalysisStage.scanning,
            message: '正在清空缓存…',
          );
          await PhotoService().clearAllCachedData();
        }
        await _runProducer(enqueueForConsumer: false, requestPermission: false);
        _scanCompletedNormally = !_stopRequested;

        _aiTotal = PhotoService().countPendingAnalysisCandidates();
        if (_aiTotal > 0) {
          await _runSerialConsumerFromDatabase();
        }
        await _onPipelineCompleted();

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
    _clearStoppedCandidates();

    final currentStage = _progressNotifier.value.stage;
    final isTerminal =
        currentStage == UnifiedAnalysisStage.completed ||
        currentStage == UnifiedAnalysisStage.failed;

    if (!isTerminal) {
      _updateProgress(
        stage: UnifiedAnalysisStage.processing,
        message: '正在停止：不再扫描新项目，当前图片处理完后结束。',
      );
    }
    debugPrint('[pipeline] 已请求停止扫描和 AI 消费者');
  }

  Future<int> deleteCurrentTaskAndClearAnalysisData() async {
    _stopRequested = true;
    await _writeForegroundStopRequested(true);
    _queue.clear();
    _clearStoppedCandidates();
    _junkCandidates.clear();

    await AiBackgroundTaskService.instance.stop();
    await AiBackgroundTaskService.instance.clearPendingUnifiedPipelineRequest();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final clearedCount = await PhotoService().clearAllAiAnalysisData();

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
      message: '开始扫描 $_scanTotal 张照片',
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
      for (var offset = 0; offset < albumCount; offset += pageSize) {
        if (_stopRequested || await _readForegroundStopRequested()) break;

        final end = math.min(albumCount, offset + pageSize);
        final page = await album.getAssetListRange(start: offset, end: end);

        if (page.isEmpty) {
          debugPrint(
            '[pipeline] 相册分页为空 id=${album.id} name=${album.name} range=$offset-$end',
          );
          continue;
        }

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
            if (_analysisEnabled && !photo.isAiAnalyzed) {
              handoffBatch.add(
                PipelineQueueItem(
                  photoId: photo.id,
                  photo: photo,
                  enqueuedAt: DateTime.now(),
                ),
              );
              if (handoffBatch.length >= _handoffBatchSize) {
                await _handoffBatchToAi(
                  handoffBatch,
                  enqueueForConsumer: enqueueForConsumer,
                );
              }
            }

            _updateProgress(
              stage: UnifiedAnalysisStage.scanning,
              message: _analysisEnabled
                  ? '正在更新相册缓存……($scanned/$_scanTotal)，已加入 $_aiTotal 张待处理'
                  : '正在更新相册缓存……($scanned/$_scanTotal)',
            );
          }
          if (photo == null) {
            skipped++;
            _updateProgress(
              stage: UnifiedAnalysisStage.scanning,
              message: _analysisEnabled
                  ? '正在更新相册缓存……($scanned/$_scanTotal)，已加入 $_aiTotal 张待处理'
                  : '正在更新相册缓存……($scanned/$_scanTotal)',
            );
          }
        }
      }
    }

    if (handoffBatch.isNotEmpty) {
      await _handoffBatchToAi(
        handoffBatch,
        enqueueForConsumer: enqueueForConsumer,
      );
    }
    _scanCompletedNormally = !_stopRequested;
    _queue.close();
    debugPrint(
      '[pipeline] 生产者结束: scanned=$scanned accepted=$accepted skipped=$skipped pendingAi=$_aiTotal stopped=$_stopRequested',
    );
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
    await JunkPhotoFilterService().warmUp();

    debugPrint('[pipeline] AI 引擎预热完成');

    _updateProgress(
      stage: UnifiedAnalysisStage.processing,
      message: _aiTotal > 0 ? '开始处理 $_aiTotal 张照片' : 'AI 已预热，等待扫描移交任务…',
    );

    var idleStartedAt = DateTime.now();
    while (!_queue.isClosed || _queue.isNotEmpty) {
      if (_stopRequested) {
        break;
      }
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
          liteRt: liteRt,
        );
        _aiCompleted++;
        _activeCandidatePhotoIds.remove(item.photoId);

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

    if (_stopRequested) {
      _clearStoppedCandidates();
    }
  }

  Future<void> _runSerialConsumerFromDatabase() async {
    AppAiSettings? settings;
    MobileClipBackend? backend;
    MobileClipLiteRtService? liteRt;
    var warmedUp = false;

    while (!_stopRequested && !await _readForegroundStopRequested()) {
      final pending = PhotoService().loadPendingAnalysisCandidatePhotos(
        limit: 1,
      );
      if (pending.isEmpty) {
        debugPrint('[pipeline] AI 队列为空，消费者结束');
        break;
      }

      if (!warmedUp) {
        _updateProgress(
          stage: UnifiedAnalysisStage.warmingUp,
          message: 'AI 模型正在预热，请稍候…',
        );
        settings = await AppAiSettingsService.instance.load();
        backend = await MobileClipBackendPreferenceService()
            .getSelectedBackend();
        liteRt = MobileClipLiteRtService.withRuntimeOptions(
          accelerator: settings.inferenceAccelerator,
          xnnpackThreadCount: settings.xnnpackThreadCount,
          modelBatchSize: settings.analysisBatchSize,
        );
        await liteRt.warmUp();
        await MobileClipTagService().warmUp();
        await JunkPhotoFilterService().warmUp();
        warmedUp = true;
      }

      final photo = pending.first;
      _aiTotal = math.max(
        _aiTotal,
        PhotoService().countPendingAnalysisCandidates() + _aiCompleted,
      );
      try {
        await _processSinglePhoto(
          photo,
          settings: settings!,
          backend: backend!,
          liteRt: liteRt!,
        );
        _aiCompleted++;
        _updateProgress(
          stage: UnifiedAnalysisStage.processing,
          message: '已完成 $_aiCompleted/$_aiTotal，失败 $_aiFailed',
        );
      } catch (error) {
        debugPrint('[pipeline] 串行处理失败 photoId=${photo.id}: $error');
        _aiFailed++;
        PhotoService().clearAiAnalysisCandidatesByIds(<int>[photo.id]);
        _updateProgress(
          stage: UnifiedAnalysisStage.processing,
          message: '已完成 $_aiCompleted/$_aiTotal，失败 $_aiFailed',
        );
      }
    }

    debugPrint('[pipeline] 消费者结束: completed=$_aiCompleted failed=$_aiFailed');

    if (_stopRequested || await _readForegroundStopRequested()) {
      _clearStoppedCandidates();
    }
  }

  Future<void> _handoffBatchToAi(
    List<PipelineQueueItem> batch, {
    bool enqueueForConsumer = true,
  }) async {
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
        await _queue.enqueue(item);
      }
    }
    debugPrint(
      enqueueForConsumer
          ? '[pipeline] 已按 $batchSize 张一组移交前台服务串行 AI，total=$_aiTotal queue=${_queue.size}'
          : '[pipeline] 已按 $batchSize 张一组标记 AI 候选，total=$_aiTotal',
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
      resolveFile: false,
    );
  }

  Future<void> _processSinglePhoto(
    PhotoEntity photo, {
    required AppAiSettings settings,
    required MobileClipBackend backend,
    required MobileClipLiteRtService liteRt,
  }) async {
    final mediaKind = MediaTypeHelper.fromStorageValue(
      photo.mediaKind,
      path: photo.path,
    );
    File? sourceFileForOcr;
    final embeddingService = MobileClipEmbeddingService();
    late final List<double> embedding;
    late final String embeddingModelVersion;
    late final List<double> tagEmbedding;
    if (mediaKind == MemoriaMediaKind.image) {
      final originalInput = await _readAnalysisImageInputFromAsset(photo);
      final originalBytes = originalInput.analysisImageBytes;
      sourceFileForOcr = originalInput.sourceFile;
      await embeddingService.resolvePhotoEmbedding(
        photo: photo,
        preferredImageBytes: originalBytes,
        backend: backend,
      );
      embedding = photo.imageEmbedding ?? const <double>[];
      embeddingModelVersion = buildPhotoEmbeddingModelVersion(backend);
      tagEmbedding = embedding;
    } else {
      final mediaInput = await _readAnalysisImageInputFromAsset(photo);
      sourceFileForOcr = mediaInput.sourceFile;
      final mediaEmbedding = await MediaEmbeddingService()
          .embedPreparedMediaBytes(
            kind: mediaKind,
            imageOrThumbnailBytes: mediaInput.imageBytes,
            backend: backend,
            liteRt: liteRt,
            frameBytes: mediaInput.videoFrameBytes,
          );
      embedding = mediaEmbedding.embedding;
      embeddingModelVersion = mediaEmbedding.modelVersion;
      tagEmbedding = embedding;
    }
    if (embedding.isEmpty) {
      throw StateError('embedding is empty');
    }

    final tagService = MobileClipTagService();
    final tags = tagEmbedding.isEmpty
        ? <String>['视频']
        : await tagService.retrieveTags(tagEmbedding);

    String? ocrText;
    List<String> ocrTags = const [];
    if (mediaKind != MemoriaMediaKind.video &&
        settings.ocrEnabled &&
        sourceFileForOcr != null &&
        OcrService.shouldRunOcr(tags, aspectRatio: photo.aspectRatio)) {
      final ocrResult = await OcrService().analyzeImageFile(sourceFileForOcr);
      ocrText = ocrResult.text;
      ocrTags = ocrResult.tags;
    }

    final junkDecision = await JunkPhotoFilterService().evaluatePhoto(
      photo: photo,
      imageEmbedding: embedding,
      ocrText: ocrText ?? '',
    );
    final finalTags = junkDecision.shouldFilter
        ? <String>[JunkPhotoFilterService.pendingJunkCandidateTag]
        : tags;
    final finalOcrTags = junkDecision.shouldFilter ? <String>[] : ocrTags;

    PhotoService().updatePhotoInTransaction(photo.id, (p) {
      if (p == null) return;
      p.imageEmbedding = embedding;
      p.aiTags = finalTags;
      p.ocrText = ocrText;
      p.ocrTags = finalOcrTags;
      p.isAiAnalyzed = true;
      p.isAiAnalysisCandidate = false;
    });

    if (junkDecision.shouldFilter) {
      _junkCandidates.add(
        JunkPhotoCleanupCandidate(
          photoId: photo.id,
          assetId: photo.assetId,
          path: photo.path,
          timestamp: photo.timestamp,
          reasons: junkDecision.hits,
        ),
      );
    }

    PhotoEmbeddingIndexRepository().upsertEmbedding(
      photoId: photo.id,
      vector: embedding,
      modelVersion: embeddingModelVersion,
    );

    unawaited(
      PhotoAttributeBackgroundService.instance().enqueueAttributeTask(
        photoId: photo.id,
        types: {PhotoAttributeType.location},
      ),
    );
  }

  Future<MediaAnalysisImageInput> _readAnalysisImageInputFromAsset(
    PhotoEntity photo,
  ) async {
    final asset = await AssetEntity.fromId(photo.assetId);
    if (asset == null) {
      throw StateError('asset unavailable for image photoId=${photo.id}');
    }
    final input = await MediaAnalysisImageReader.instance.readAsset(
      asset,
      allowFileFallback: false,
    );
    if (input == null || input.analysisImageBytes.isEmpty) {
      throw StateError('image reader returned empty data photoId=${photo.id}');
    }
    return input;
  }

  Future<void> _onPipelineCompleted() async {
    if (_analysisEnabled && _aiTotal > 0) {
      _updateProgress(
        stage: UnifiedAnalysisStage.flushing,
        message: '正在刷新事件聚类…',
      );
      await EventService().runClustering();
      await _publishPostFilterJunkReport();
    }

    _updateProgress(
      stage: UnifiedAnalysisStage.completed,
      message: _analysisEnabled && _aiTotal > 0
          ? '已完成 $_aiCompleted/$_aiTotal 张照片，失败 $_aiFailed'
          : '相册缓存已更新，没有新的待分析图片',
    );
  }

  Future<void> _publishPostFilterJunkReport() async {
    await AIService().refreshJunkCleanupReportFromDatabase();
  }

  void _clearStoppedCandidates() {
    if (_activeCandidatePhotoIds.isEmpty) {
      return;
    }
    PhotoService().clearAiAnalysisCandidatesByIds(_activeCandidatePhotoIds);
    _activeCandidatePhotoIds.clear();
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
        stage == UnifiedAnalysisStage.failed;

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
      scanStopped: _queue.isClosed && !_scanCompletedNormally,
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
      final albums = await PhotoManager.getAssetPathList(type: requestType);
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
    final albums = await PhotoManager.getAssetPathList(type: requestType);
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
      excludeExtremeAspectRatios: prefs.excludeExtremeAspectRatios,
    );
  }
}
