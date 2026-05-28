import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/entity/photo_entity.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../storage/vector_index/vector_index_constants.dart';
import 'analysis_pipeline_queue.dart';
import 'unified_analysis_progress.dart';
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
import '../utils/media_type_helper.dart';

const String _foregroundProducerRunningKey =
    'foreground_unified_pipeline_producer_running';
const String _foregroundStopRequestedKey =
    'foreground_unified_pipeline_stop_requested';

Future<void> _foregroundProducerIsolateEntry(
  Map<String, Object?> config,
) async {
  _ensureBackgroundMessenger(config);
  _attachObjectBoxStore(config);
  await PhotoService().init();
  final service = UnifiedAnalysisPipelineService();
  await service._runForegroundProducerOnly(
    clearCacheFirst: config['clearCacheFirst'] == true,
    analyzeWithAi: config['analyzeWithAi'] != false,
  );
}

void _ensureBackgroundMessenger(Map<String, Object?> config) {
  final rootIsolateToken = config['rootIsolateToken'];
  if (rootIsolateToken is! RootIsolateToken) {
    throw StateError('Foreground worker missing root isolate token');
  }
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
  DartPluginRegistrant.ensureInitialized();
}

void _attachObjectBoxStore(Map<String, Object?> config) {
  final referenceBytes = config['storeReferenceBytes'];
  if (referenceBytes is! Uint8List || referenceBytes.isEmpty) {
    throw StateError('Foreground worker missing ObjectBox store reference');
  }
  ObjectBoxService().attachReferenceBytes(referenceBytes);
}

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
      final settings = await AppAiSettingsService.instance.load();
      if (settings.androidForegroundServiceEnabled &&
          (Platform.isAndroid || Platform.isIOS)) {

        _updateProgress(
          stage: UnifiedAnalysisStage.scanning,
          message: analyzeWithAi
              ? '已交给前台服务：正在缓存并串行分析媒体'
              : '已交给前台服务：正在更新相册缓存',
        );
        await AiBackgroundTaskService.instance.startUnifiedPipelineWorker(
          clearCacheFirst: clearCacheFirst,
          analyzeWithAi: analyzeWithAi,
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        _progressNotifier.value = UnifiedAnalysisProgress.idle();
        return;
      }

      await runInsideForegroundService(
        clearCacheFirst: clearCacheFirst,
        analyzeWithAi: analyzeWithAi,
      );
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

  Future<void> runInsideForegroundService({
    bool clearCacheFirst = false,
    bool analyzeWithAi = true,
    Uint8List? storeReferenceBytes,
    RootIsolateToken? rootIsolateToken,
  }) async {
    _isRunning = true;
    _stopRequested = false;
    _scanCompletedNormally = false;
    _analysisEnabled = analyzeWithAi;
    _suppressForegroundTaskChannelCalls = storeReferenceBytes != null;
    _queue = AnalysisPipelineQueue(capacity: 200, highWaterMark: 160);
    _scanCompleted = 0;
    _scanTotal = 0;
    _aiCompleted = 0;
    _aiTotal = 0;
    _aiFailed = 0;
    _activeCandidatePhotoIds.clear();
    _junkCandidates.clear();
    _startedAt = DateTime.now();

    try {
      if (analyzeWithAi) {
        await _runForegroundProducerConsumerIsolates(
          clearCacheFirst: clearCacheFirst,
          analyzeWithAi: analyzeWithAi,
          storeReferenceBytes: storeReferenceBytes,
          rootIsolateToken: rootIsolateToken,
        );
      } else if (clearCacheFirst) {
        if (storeReferenceBytes != null) {
          ObjectBoxService().attachReferenceBytes(storeReferenceBytes);
        }
        await PhotoService().init();
        await _runFullRebuildPipeline(
          requestPermission: storeReferenceBytes == null,
        );
      } else {
        if (storeReferenceBytes != null) {
          ObjectBoxService().attachReferenceBytes(storeReferenceBytes);
        }
        await PhotoService().init();
        await _runIncrementalPipeline(
          requestPermission: storeReferenceBytes == null,
        );
      }
    } catch (error) {
      debugPrint('[pipeline] ❌ 流水线失败: $error');
      _progressNotifier.value = UnifiedAnalysisProgress.idle();
      rethrow;
    } finally {
      _isRunning = false;
      _queue.close();
      debugPrint('[pipeline] ======== 前台服务流水线结束 ========');
    }
  }

  Future<void> _runForegroundProducerConsumerIsolates({
    required bool clearCacheFirst,
    required bool analyzeWithAi,
    Uint8List? storeReferenceBytes,
    RootIsolateToken? rootIsolateToken,
  }) async {
    final referenceBytes =
        storeReferenceBytes ?? ObjectBoxService().storeReferenceBytes;
    final token = rootIsolateToken ?? RootIsolateToken.instance;
    if (token == null) {
      throw StateError('Foreground pipeline missing root isolate token');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_foregroundProducerRunningKey, true);
    await prefs.setBool(_foregroundStopRequestedKey, false);
    final config = <String, Object?>{
      'clearCacheFirst': clearCacheFirst,
      'analyzeWithAi': analyzeWithAi,
      'storeReferenceBytes': referenceBytes,
      'rootIsolateToken': token,
    };

    await Future.wait(<Future<void>>[
      Isolate.run(() => _foregroundProducerIsolateEntry(config)),
      _runForegroundConsumerOnly(),
    ]);
  }

  Future<void> _runForegroundProducerOnly({
    required bool clearCacheFirst,
    required bool analyzeWithAi,
  }) async {
    _isRunning = true;
    _stopRequested = false;
    _scanCompletedNormally = false;
    _analysisEnabled = analyzeWithAi;
    _suppressForegroundTaskChannelCalls = true;
    _queue = AnalysisPipelineQueue(capacity: 1, highWaterMark: 1);
    _scanCompleted = 0;
    _scanTotal = 0;
    _aiCompleted = 0;
    _aiTotal = 0;
    _aiFailed = 0;
    _activeCandidatePhotoIds.clear();
    _junkCandidates.clear();
    _startedAt = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_foregroundProducerRunningKey, true);
    try {
      if (clearCacheFirst) {
        _updateProgress(
          stage: UnifiedAnalysisStage.scanning,
          message: '正在清空缓存…',
        );
        await PhotoService().clearAllCachedData();
      }
      await _runProducer(
        enqueueForConsumer: false,
        requestPermission: false,
      );
    } finally {
      await prefs.setBool(_foregroundProducerRunningKey, false);
      _isRunning = false;
      _queue.close();
    }
  }

  Future<void> _runForegroundConsumerOnly() async {
    _isRunning = true;
    _stopRequested = false;
    _scanCompletedNormally = true;
    _analysisEnabled = true;
    _suppressForegroundTaskChannelCalls = true;
    _queue = AnalysisPipelineQueue(capacity: 1, highWaterMark: 1);
    _scanCompleted = 0;
    _scanTotal = 0;
    _aiCompleted = 0;
    _aiTotal = PhotoService().countPendingAnalysisCandidates();
    _aiFailed = 0;
    _activeCandidatePhotoIds.clear();
    _junkCandidates.clear();
    _startedAt = DateTime.now();

    try {
      await _runSerialConsumerFromDatabase();
      await _onPipelineCompleted();
    } finally {
      _isRunning = false;
      _queue.close();
    }
  }

  void stopPipeline() {
    _stopRequested = true;
    unawaited(_writeForegroundStopRequested(true));
    _queue.clear();
    _clearStoppedCandidates();
    debugPrint('[pipeline] 已请求停止扫描和 AI 消费者');
  }

  Future<void> startPendingAnalysisCandidates() async {
    if (_isRunning) {
      debugPrint('[pipeline] 流水线已在运行，忽略恢复请求');
      return;
    }

    _isRunning = true;
    _stopRequested = false;
    _scanCompletedNormally = true;
    _analysisEnabled = true;
    _queue = AnalysisPipelineQueue(capacity: 200, highWaterMark: 160);
    _scanCompleted = 0;
    _scanTotal = 0;
    _aiCompleted = 0;
    _aiTotal = 0;
    _aiFailed = 0;
    _activeCandidatePhotoIds.clear();
    _junkCandidates.clear();
    _startedAt = DateTime.now();

    debugPrint('[pipeline] ======== 恢复残余 AI 任务启动 ========');
    try {
      final photos = PhotoService().loadPendingAnalysisCandidatePhotos();
      _aiTotal = photos.length;
      _updateProgress(
        stage: UnifiedAnalysisStage.processing,
        message: '正在串行处理 $_aiTotal 张未完成图片',
      );
      if (_aiTotal > 0) {
        for (final photo in photos) {
          await _queue.enqueue(
            PipelineQueueItem(
              photoId: photo.id,
              photo: photo,
              enqueuedAt: DateTime.now(),
            ),
          );
          _activeCandidatePhotoIds.add(photo.id);
        }
        _queue.close();
        await _runConsumer();
        await _onPipelineCompleted();
      }
    } finally {
      if (_stopRequested) {
        _clearStoppedCandidates();
      }
      _isRunning = false;
      _queue.close();
      _progressNotifier.value = UnifiedAnalysisProgress.idle();
      debugPrint('[pipeline] ======== 恢复残余 AI 任务结束 ========');
    }
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
      debugPrint("[pipeline] 请求相册权限 has been deprecated. Ask for permission earlier.");
    } else {
      await PhotoManager.setIgnorePermissionCheck(true);
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
    _scanTotal = totalCount;

    debugPrint('[pipeline] 预估总数=$_scanTotal');

    _updateProgress(
      stage: UnifiedAnalysisStage.scanning,
      message: '开始扫描 $_scanTotal 张照片',
    );

    var scanned = 0;
    const pageSize = 50;
    final handoffBatch = <PipelineQueueItem>[];

    for (final album in targetAlbums) {
      if (_stopRequested || await _readForegroundStopRequested()) break;

      final albumCount = await album.assetCountAsync;
      for (var offset = 0; offset < albumCount; offset += pageSize) {
        if (_stopRequested || await _readForegroundStopRequested()) break;

        final end = math.min(albumCount, offset + pageSize);
        final page = await album.getAssetListRange(start: offset, end: end);

        if (page.isEmpty) continue;

        for (final asset in page) {
          if (_stopRequested || await _readForegroundStopRequested()) break;
          scanned++;
          _scanCompleted = scanned;

          final photo = await _buildAndSavePhotoEntity(asset);
          if (photo != null) {
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
      '[pipeline] 生产者结束: scanned=$scanned pendingAi=$_aiTotal stopped=$_stopRequested',
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
    await JunkPhotoFilterService().warmUp();

    while (!_stopRequested && !await _readForegroundStopRequested()) {
      final pending = PhotoService().loadPendingAnalysisCandidatePhotos(
        limit: 1,
      );
      if (pending.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final producerRunning =
            prefs.getBool(_foregroundProducerRunningKey) ?? false;
        if (!producerRunning) {
          break;
        }
        _aiTotal = math.max(
          _aiTotal,
          PhotoService().countPendingAnalysisCandidates() + _aiCompleted,
        );
        _updateProgress(
          stage: UnifiedAnalysisStage.processing,
          message: 'AI 已预热，等待扫描线程移交任务…',
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        continue;
      }

      final photo = pending.first;
      _aiTotal = math.max(
        _aiTotal,
        PhotoService().countPendingAnalysisCandidates() + _aiCompleted,
      );
      try {
        await _processSinglePhoto(
          photo,
          settings: settings,
          backend: backend,
          liteRt: liteRt,
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
      resolveFile: true,
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
      final mediaEmbedding =
          settings.mobileViClipEnabled &&
              (mediaKind == MemoriaMediaKind.video ||
                  mediaKind == MemoriaMediaKind.dynamicImage) &&
              mediaInput.videoFrameBytes.isNotEmpty
          ? await MediaEmbeddingService().embedVideoFrameBytes(
              mediaInput.videoFrameBytes,
            )
          : await MediaEmbeddingService().embedPreparedMediaBytes(
            kind: mediaKind,
            imageOrThumbnailBytes: mediaInput.imageBytes,
            mobileViClipEnabled: settings.mobileViClipEnabled,
            backend: backend,
            liteRt: liteRt,
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
        ? <String>[JunkPhotoFilterService.junkCandidateTag]
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
    _updateProgress(
      stage: UnifiedAnalysisStage.flushing,
      message: _analysisEnabled ? '正在刷新事件聚类…' : '相册缓存已更新',
    );

    if (_analysisEnabled) {
      await EventService().runClustering();
      await _publishPostFilterJunkReport();
    }

    _updateProgress(
      stage: UnifiedAnalysisStage.completed,
      message: _analysisEnabled
          ? '已完成 $_aiCompleted/$_aiTotal 张照片，失败 $_aiFailed'
          : '相册缓存已更新',
    );

    await Future.delayed(const Duration(milliseconds: 1800));
    _progressNotifier.value = UnifiedAnalysisProgress.idle();
  }

  Future<void> _publishPostFilterJunkReport() async {
    if (_junkCandidates.isNotEmpty) {
      AIService().replacePendingJunkCleanupReport(
        JunkPhotoCleanupReport.fromCandidates(_junkCandidates),
      );
      return;
    }
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

    if (!_suppressForegroundTaskChannelCalls) {
      unawaited(
        AiBackgroundTaskService.instance.updateNotification(
          title: 'Memoria 正在分析照片',
          text: message,
        ),
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
