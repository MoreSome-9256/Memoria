import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ai_service.dart';
import 'event_service.dart';
import '../storage/objectbox/media_asset_repository.dart';
import 'media_asset_sync_service.dart';
import 'media_embedding_index_service.dart';
import 'photo_service.dart';

enum AlbumRefreshStage { idle, scanning, clustering, queueing, handoff, failed }

class AlbumRefreshProgress {
  const AlbumRefreshProgress({
    required this.stage,
    required this.isRunning,
    required this.progress,
    required this.title,
    required this.message,
    required this.runId,
  });

  factory AlbumRefreshProgress.idle() => const AlbumRefreshProgress(
    stage: AlbumRefreshStage.idle,
    isRunning: false,
    progress: 0,
    title: '',
    message: '',
    runId: 0,
  );

  factory AlbumRefreshProgress.running({
    required AlbumRefreshStage stage,
    required double progress,
    required String title,
    required String message,
    required int runId,
  }) {
    return AlbumRefreshProgress(
      stage: stage,
      isRunning: true,
      progress: progress.clamp(0, 1).toDouble(),
      title: title,
      message: message,
      runId: runId,
    );
  }

  final AlbumRefreshStage stage;
  final bool isRunning;
  final double progress;
  final String title;
  final String message;
  final int runId;

  bool get isVisible => isRunning;
}

class AlbumRefreshResult {
  const AlbumRefreshResult({
    required this.scanSummary,
    required this.requeuedCount,
    required this.recentPhotoLimit,
    required this.clearCacheFirst,
    required this.aiAlreadyRunning,
  });

  final PhotoScanSummary scanSummary;
  final int requeuedCount;
  final int? recentPhotoLimit;
  final bool clearCacheFirst;
  final bool aiAlreadyRunning;
}

class AlbumRefreshService {
  AlbumRefreshService._internal();

  static final AlbumRefreshService _instance = AlbumRefreshService._internal();
  factory AlbumRefreshService() => _instance;

  final ValueNotifier<AlbumRefreshProgress> _progressNotifier =
      ValueNotifier<AlbumRefreshProgress>(AlbumRefreshProgress.idle());
  bool _isRunning = false;
  int _progressRunId = 0;

  ValueListenable<AlbumRefreshProgress> get progressListenable =>
      _progressNotifier;
  bool get isRunning => _isRunning;

  // ── ★ 唯一入口 ──────────────────────────────────────────────────
  Future<AlbumRefreshResult?> startRefresh({
    bool clearCacheFirst = false,
    int? recentPhotoLimit,
  }) async {
    if (_isRunning) {
      debugPrint('[scan] ⛔ 扫描已在运行，忽略重复请求');
      return null;
    }
    _isRunning = true;
    _progressRunId++;
    final runId = _progressRunId;

    debugPrint('[scan] ======== AlbumRefreshService 开始 ========');
    debugPrint(
      '[scan] runId=$runId clearCacheFirst=$clearCacheFirst recentPhotoLimit=$recentPhotoLimit',
    );

    try {
      if (clearCacheFirst) {
        final result = await _runFullRebuild(recentPhotoLimit);
        debugPrint(
          '[scan] ✅ 全量重建完成: totalAfter=${result.scanSummary.totalAfter}',
        );
        return result;
      }
      final result = await _runIncrementalScan(recentPhotoLimit);
      debugPrint(
        '[scan] ✅ 增量扫描完成: inserted=${result.requeuedCount} aiAlreadyRunning=${result.aiAlreadyRunning}',
      );
      return result;
    } catch (error) {
      debugPrint('[scan] ❌ 扫描失败: $error');
      debugPrint('[scan] ❌ 堆栈: ${StackTrace.current}');
      _progressNotifier.value = AlbumRefreshProgress.running(
        stage: AlbumRefreshStage.failed,
        progress: 1,
        title: '刷新失败',
        message: error.toString(),
        runId: runId,
      );
      rethrow;
    } finally {
      // 短暂停留让用户看到 handoff 完成消息，再回到 idle
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      _progressNotifier.value = AlbumRefreshProgress.idle();
      _isRunning = false;
      debugPrint(
        '[scan] ======== AlbumRefreshService 结束 (runId=$runId) ========',
      );
    }
  }

  // ── 增量扫描（"下一批 N 张" 路径）───────────────────────────────
  Future<AlbumRefreshResult> _runIncrementalScan(int? recentPhotoLimit) async {
    final batchSize = math.max(10, recentPhotoLimit ?? 100);
    final isRemainingScan = batchSize >= 0x7fffffff;
    final scopeLabel = isRemainingScan ? '剩余所有照片' : '$batchSize 张新照片';

    debugPrint(
      '[scan] _runIncrementalScan: batchSize=$batchSize isRemainingScan=$isRemainingScan',
    );

    _setProgress(
      AlbumRefreshStage.scanning,
      0.04,
      '正在读取图片',
      '从最新项目开始读取，目标：$scopeLabel；读到目标数量或没有更多新项目后交给 AI。',
    );
    debugPrint('[scan] ▶ stage=scanning progress=0.04');

    // step 1: stop-early 扫描，只找新照片
    var lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    final scanStart = DateTime.now();
    debugPrint('[scan] 开始调用 scanBatchPhotos…');
    final scanResult = await PhotoService().scanBatchPhotos(
      batchSize: batchSize,
      onProgress: (scanProgress) {
        final now = DateTime.now();
        if (now.difference(lastProgressUpdate).inMilliseconds < 220 &&
            scanProgress.scannedCount < scanProgress.totalCount) {
          return;
        }
        lastProgressUpdate = now;
        final baseFraction = isRemainingScan
            ? scanProgress.scannedFraction
            : math.max(
                scanProgress.scannedFraction * 0.35,
                scanProgress.acceptedFraction,
              );
        final progress = 0.08 + 0.52 * baseFraction.clamp(0, 1).toDouble();
        final acceptedText = isRemainingScan
            ? '${scanProgress.acceptedCount} 个'
            : '${scanProgress.acceptedCount}/${scanProgress.targetNew} 个';
        _setProgress(
          AlbumRefreshStage.scanning,
          progress,
          '正在读取图片',
          '已读取 ${scanProgress.scannedCount}/${scanProgress.totalCount} 项，找到 $acceptedText 可加入 AI 的新项目。',
        );
        debugPrint(
          '[scan]   扫描进度: scanned=${scanProgress.scannedCount}/${scanProgress.totalCount} accepted=${scanProgress.acceptedCount}/${scanProgress.targetNew} progress=${progress.toStringAsFixed(3)}',
        );
      },
    );
    final scanMs = DateTime.now().difference(scanStart).inMilliseconds;
    debugPrint(
      '[scan] scanBatchPhotos 完成: scannedCount=${scanResult.scannedCount} insertedCount=${scanResult.insertedCount} totalAfter=${scanResult.totalAfter} 耗时=${scanMs}ms',
    );

    _setProgress(
      AlbumRefreshStage.queueing,
      0.64,
      '正在整理图片列表',
      '读取完成：检查 ${scanResult.scannedCount} 项，整理出 ${scanResult.insertedCount} 个新项目，正在写入 AI 队列。',
    );

    // 构建兼容的 PhotoScanSummary
    final summary = PhotoScanSummary(
      totalBefore: math.max(
        0,
        scanResult.totalAfter - scanResult.insertedCount,
      ),
      totalAfter: scanResult.totalAfter,
      removedCount: 0,
      insertedCount: scanResult.insertedCount,
      insertedPhotoIds: scanResult.insertedPhotoIds,
      scannedCount: scanResult.scannedCount,
      skippedInvalidTime: scanResult.skippedInvalidTime,
      insertedNoGps: scanResult.insertedNoGps,
      skippedNonCamera: scanResult.skippedNonCamera,
      skippedScreenshot: scanResult.skippedScreenshot,
    );

    if (!scanResult.hasNewPhotos) {
      debugPrint('[scan] 没有新照片，直接触发 AI (aiRunning=${AIService().isAnalyzing})');
      final aiRunning = AIService().isAnalyzing;
      if (!aiRunning) {
        unawaited(
          _runAiPipeline(maxPhotos: isRemainingScan ? null : batchSize),
        );
      }
      _setProgress(
        AlbumRefreshStage.handoff,
        aiRunning ? 0.95 : 1.0,
        '本轮没有可入库新照片',
        aiRunning ? 'AI 队列正在运行' : '已转去检查未完成的后台 AI 队列',
      );
      debugPrint('[scan] ▶ stage=handoff (无新照片) aiRunning=$aiRunning');
      return AlbumRefreshResult(
        scanSummary: summary,
        requeuedCount: 0,
        recentPhotoLimit: batchSize,
        clearCacheFirst: false,
        aiAlreadyRunning: aiRunning,
      );
    }

    debugPrint('[scan] 有新照片 ${scanResult.insertedCount} 张，开始 requeue');
    // step 2: 有新照片 → requeue（标记为未分析）
    await PhotoService().requeuePhotosForAiByIds(scanResult.insertedPhotoIds);
    _scheduleMediaIndexRefresh(
      batchSize: isRemainingScan
          ? math.max(scanResult.insertedCount, 300)
          : batchSize,
    );
    debugPrint('[scan] requeue 完成');

    _setProgress(
      AlbumRefreshStage.clustering,
      0.72,
      '正在更新相册索引',
      '已加入 ${scanResult.insertedCount} 个项目，正在更新事件、时间和索引信息。',
    );
    debugPrint('[scan] ▶ stage=clustering progress=0.72');

    // step 3: 事件聚类
    final clusterStart = DateTime.now();
    await EventService().runClustering();
    final clusterMs = DateTime.now().difference(clusterStart).inMilliseconds;
    debugPrint('[scan] 事件聚类完成 耗时=${clusterMs}ms');

    // step 4: 触发 AI 打标
    final aiRunning = AIService().isAnalyzing;
    debugPrint('[scan] AI 状态: isAnalyzing=$aiRunning');
    if (!aiRunning) {
      unawaited(
        _runAiPipeline(
          maxPhotos: scanResult.insertedPhotoIds.length,
          photoIds: scanResult.insertedPhotoIds,
        ),
      );
      debugPrint('[scan] _runAiPipeline 已触发 (unawaited)');
    }
    _setProgress(
      AlbumRefreshStage.handoff,
      0.95,
      '已交付 AI',
      aiRunning
          ? 'AI 队列正在继续处理；这批图片已经写入待处理列表。'
          : '图片列表已交给后台 AI 服务，接下来会调度标签、OCR、人脸和地理位置处理。',
    );
    debugPrint('[scan] ▶ stage=handoff progress=0.95 aiRunning=$aiRunning');

    return AlbumRefreshResult(
      scanSummary: summary,
      requeuedCount: scanResult.insertedCount,
      recentPhotoLimit: batchSize,
      clearCacheFirst: false,
      aiAlreadyRunning: aiRunning,
    );
  }

  // ── 全量重建（"安全重建" 路径）───────────────────────────────────
  Future<AlbumRefreshResult> _runFullRebuild(int? recentPhotoLimit) async {
    debugPrint('[scan] _runFullRebuild: recentPhotoLimit=$recentPhotoLimit');
    final isFullImport =
        recentPhotoLimit == null || recentPhotoLimit >= 0x7fffffff;
    _setProgress(
      AlbumRefreshStage.scanning,
      0.04,
      '正在准备安全重建',
      '正在安全结束当前 AI 任务',
    );

    await AIService().endCurrentRoundSafely();
    debugPrint('[scan] AI 已安全结束并消费阶段性结果');

    _setProgress(
      AlbumRefreshStage.scanning,
      0.12,
      '正在读取系统相册',
      isFullImport ? '范围：全部照片' : '范围：最近 $recentPhotoLimit 张',
    );
    debugPrint('[scan] ▶ stage=scanning (全量) progress=0.12');

    final rebuildStart = DateTime.now();
    final scanSummary = await PhotoService().rebuildAllCachedData(
      maxAssets: isFullImport ? null : recentPhotoLimit,
    );
    final rebuildMs = DateTime.now().difference(rebuildStart).inMilliseconds;
    debugPrint(
      '[scan] 全量重建完成: totalAfter=${scanSummary.totalAfter} 耗时=${rebuildMs}ms',
    );

    _setProgress(
      AlbumRefreshStage.clustering,
      0.68,
      '正在重建事件分类',
      '照片 ${scanSummary.totalAfter} 张',
    );
    debugPrint('[scan] ▶ stage=clustering (全量) progress=0.68');

    final clusterStart = DateTime.now();
    await EventService().runClustering();
    debugPrint(
      '[scan] 聚类完成 耗时=${DateTime.now().difference(clusterStart).inMilliseconds}ms',
    );
    _scheduleMediaIndexRefresh(
      batchSize: isFullImport ? 300 : recentPhotoLimit,
    );

    final aiRunning = AIService().isAnalyzing;
    debugPrint('[scan] AI 状态: isAnalyzing=$aiRunning');
    if (!aiRunning) {
      unawaited(
        _runAiPipeline(maxPhotos: isFullImport ? null : recentPhotoLimit),
      );
    }
    _setProgress(
      AlbumRefreshStage.handoff,
      0.95,
      '安全重建完成',
      aiRunning ? 'AI 队列正在继续处理' : '已交给后台 AI 队列',
    );
    debugPrint(
      '[scan] ▶ stage=handoff (全量) progress=0.95 aiRunning=$aiRunning',
    );

    return AlbumRefreshResult(
      scanSummary: scanSummary,
      requeuedCount: 0,
      recentPhotoLimit: isFullImport ? null : recentPhotoLimit,
      clearCacheFirst: true,
      aiAlreadyRunning: aiRunning,
    );
  }

  // ── 辅助方法 ─────────────────────────────────────────────────────
  void _setProgress(
    AlbumRefreshStage stage,
    double progress,
    String title,
    String message,
  ) {
    _progressNotifier.value = AlbumRefreshProgress.running(
      stage: stage,
      progress: progress,
      title: title,
      message: message,
      runId: _progressRunId,
    );
  }

  Future<void> _runAiPipeline({int? maxPhotos, List<int>? photoIds}) async {
    debugPrint(
      '[scan] _runAiPipeline: maxPhotos=$maxPhotos photoIds=${photoIds?.length}',
    );
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      await AIService().analyzePhotosInBackground(
        maxPhotos: maxPhotos,
        photoIds: photoIds,
      );
      debugPrint('[scan] ✅ _runAiPipeline 完成');
    } catch (error, stackTrace) {
      debugPrint('[scan] ❌ 后台 AI 管线执行失败: $error');
      debugPrint('[scan] ❌ 堆栈: $stackTrace');
    }
  }

  void _scheduleMediaIndexRefresh({required int batchSize}) {
    unawaited(
      Future<void>(() async {
        try {
          final repo = MediaAssetRepository();
          if (repo.isEmpty) {
            final mediaSummary = await MediaAssetSyncService().reconcile(
              pageSize: math.max(100, math.min(300, batchSize)),
            );
            debugPrint(
              '🧭 ObjectBox media first reconcile: discovered=${mediaSummary.discovered} '
              'upsert=${mediaSummary.insertedOrUpdated} removed=${mediaSummary.removed} '
              'limited=${mediaSummary.limitedAccess}',
            );
          }
          final pending = repo.countPending();
          if (pending > 0) {
            await MediaEmbeddingIndexService().encodePending(
              maxConcurrency: 2,
              batchSize: batchSize,
              inputSize: 336,
            );
          }
        } catch (error) {
          debugPrint('Media asset index refresh skipped: $error');
        }
      }),
    );
  }
}
