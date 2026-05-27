import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ai_service.dart';
import 'ai_background_task_service.dart';
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
    final isFullImport = recentPhotoLimit == null;
    final batchSize = isFullImport ? null : math.max(10, recentPhotoLimit);
    final scopeLabel = isFullImport ? '剩余所有照片' : '$batchSize 张新照片';

    debugPrint(
      '[scan] _runIncrementalScan: batchSize=$batchSize isFullImport=$isFullImport',
    );

    _setProgress(
      AlbumRefreshStage.scanning,
      0.04,
      '正在读取图片',
      '从最新项目开始读取，目标：$scopeLabel；读到目标数量或没有更多新项目后交给 AI。',
    );
    debugPrint('[scan] ▶ stage=scanning progress=0.04');

    // step 1: 预扫描完整授权相册，边构建边写入缓存数据库。
    final scanStart = DateTime.now();
    var cacheForegroundStarted = false;
    debugPrint('[scan] 开始调用 scanBatchPhotos…');
    try {
      cacheForegroundStarted = await AiBackgroundTaskService.instance
          .startAlbumCacheForeground(text: '正在更新相册缓存……');
      final scanResult = await PhotoService().scanBatchPhotos(
        batchSize: batchSize,
        onProgress: (scanProgress) {
          final progress = 0.08 + 0.52 * scanProgress.scannedFraction;
          final scannedText = scanProgress.totalCount > 0
              ? '${scanProgress.scannedCount}/${scanProgress.totalCount}'
              : '${scanProgress.scannedCount}';
          final eta = _formatRemainingTime(
            startedAt: scanStart,
            completed: scanProgress.scannedCount,
            total: scanProgress.totalCount,
          );
          final message = eta.isEmpty
              ? '正在更新相册缓存……($scannedText)'
              : '正在更新相册缓存……($scannedText)，预计剩余 $eta';
          _setProgress(
            AlbumRefreshStage.scanning,
            progress,
            '正在更新相册缓存',
            message,
          );
          unawaited(
            AiBackgroundTaskService.instance.updateNotification(
              title: 'Memoria 正在更新相册缓存',
              text: message,
            ),
          );
          debugPrint(
            '[scan]   缓存进度: scanned=$scannedText inserted=${scanProgress.acceptedCount} progress=${progress.toStringAsFixed(3)}',
          );
        },
      );
      return await _finishIncrementalScan(
        scanResult: scanResult,
        scanStart: scanStart,
        batchSize: batchSize,
        isFullImport: isFullImport,
      );
    } finally {
      if (cacheForegroundStarted) {
        await AiBackgroundTaskService.instance.stop();
      }
    }
  }

  Future<AlbumRefreshResult> _finishIncrementalScan({
    required BatchScanResult scanResult,
    required DateTime scanStart,
    required int? batchSize,
    required bool isFullImport,
  }) async {
    final scanMs = DateTime.now().difference(scanStart).inMilliseconds;
    debugPrint(
      '[scan] scanBatchPhotos 完成: scannedCount=${scanResult.scannedCount} insertedCount=${scanResult.insertedCount} totalAfter=${scanResult.totalAfter} 耗时=${scanMs}ms',
    );

    final handoffPhotoIds = PhotoService().loadPendingAiPhotoIds(
      limit: batchSize,
    );

    _setProgress(
      AlbumRefreshStage.queueing,
      0.64,
      '正在移交 AI',
      '筛选出 ${handoffPhotoIds.length} 个图片正在移交给AI处理',
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

    if (handoffPhotoIds.isEmpty) {
      debugPrint('[scan] 没有待移交 AI 的照片 (aiRunning=${AIService().isAnalyzing})');
      final aiRunning = AIService().isAnalyzing;
      _setProgress(
        AlbumRefreshStage.handoff,
        aiRunning ? 0.95 : 1.0,
        '没有待处理图片',
        aiRunning ? 'AI 队列正在运行' : '相册缓存已更新',
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

    debugPrint('[scan] 筛选出 ${handoffPhotoIds.length} 张待 AI 处理照片，开始 requeue');
    // step 2: 有新照片 → requeue（标记为未分析）
    await PhotoService().requeuePhotosForAiByIds(handoffPhotoIds);
    _scheduleMediaIndexRefresh(
      batchSize: isFullImport
          ? math.max(handoffPhotoIds.length, 300)
          : batchSize!,
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
          maxPhotos: handoffPhotoIds.length,
          photoIds: handoffPhotoIds,
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
      requeuedCount: handoffPhotoIds.length,
      recentPhotoLimit: batchSize,
      clearCacheFirst: false,
      aiAlreadyRunning: aiRunning,
    );
  }

  // ── 全量重建（"安全重建" 路径）───────────────────────────────────
  Future<AlbumRefreshResult> _runFullRebuild(int? recentPhotoLimit) async {
    debugPrint('[scan] _runFullRebuild: recentPhotoLimit=$recentPhotoLimit');
    final isFullImport = recentPhotoLimit == null;
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

  String _formatRemainingTime({
    required DateTime startedAt,
    required int completed,
    required int total,
  }) {
    if (completed <= 0 || total <= 0 || completed >= total) {
      return '';
    }
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    if (elapsedMs <= 0) {
      return '';
    }
    final remainingMs = (elapsedMs / completed * (total - completed)).round();
    if (remainingMs < 1000) {
      return '不到 1 秒';
    }
    final seconds = (remainingMs / 1000).round();
    if (seconds < 60) {
      return '$seconds 秒';
    }
    final minutes = seconds ~/ 60;
    final restSeconds = seconds % 60;
    if (minutes < 60) {
      return restSeconds == 0 ? '$minutes 分钟' : '$minutes 分 $restSeconds 秒';
    }
    final hours = minutes ~/ 60;
    final restMinutes = minutes % 60;
    return restMinutes == 0 ? '$hours 小时' : '$hours 小时 $restMinutes 分钟';
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
