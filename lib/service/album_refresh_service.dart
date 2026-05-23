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
    if (_isRunning) return null;
    _isRunning = true;
    _progressRunId++;

    try {
      if (clearCacheFirst) {
        return _runFullRebuild(recentPhotoLimit);
      }
      return _runIncrementalScan(recentPhotoLimit);
    } catch (error) {
      _progressNotifier.value = AlbumRefreshProgress.running(
        stage: AlbumRefreshStage.failed,
        progress: 1,
        title: '刷新失败',
        message: error.toString(),
        runId: _progressRunId,
      );
      rethrow;
    } finally {
      _progressNotifier.value = AlbumRefreshProgress.idle();
      _isRunning = false;
    }
  }

  // ── 增量扫描（"下一批 N 张" 路径）───────────────────────────────
  Future<AlbumRefreshResult> _runIncrementalScan(int? recentPhotoLimit) async {
    final batchSize = math.max(10, recentPhotoLimit ?? 100);
    final isRemainingScan = batchSize >= 0x7fffffff;
    final scopeLabel = isRemainingScan ? '剩余所有照片' : '$batchSize 张新照片';

    _setProgress(
      AlbumRefreshStage.scanning,
      0.04,
      '正在准备相册预处理',
      '正在读取系统相册索引，目标：$scopeLabel',
    );

    // step 1: stop-early 扫描，只找新照片
    var lastProgressUpdate = DateTime.fromMillisecondsSinceEpoch(0);
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
        _setProgress(
          AlbumRefreshStage.scanning,
          progress,
          '从最新照片往前检查',
          '已检查 ${scanProgress.scannedCount}/${scanProgress.totalCount} 张，新增候选 ${scanProgress.candidateCount} 张，可入库 ${scanProgress.acceptedCount} 张',
        );
      },
    );

    _setProgress(
      AlbumRefreshStage.queueing,
      0.64,
      '正在写入预处理结果',
      '从最新往前检查了 ${scanResult.scannedCount} 张，可入库 ${scanResult.insertedCount} 张',
    );

    // 构建兼容的 PhotoScanSummary
    final summary = PhotoScanSummary(
      totalBefore: math.max(0, scanResult.totalAfter - scanResult.insertedCount),
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
      // 没有新照片 → 直接触发 AI 处理未分析的照片
      final aiRunning = AIService().isAnalyzing;
      if (!aiRunning) {
        unawaited(_runAiPipeline(maxPhotos: batchSize));
      }
      _setProgress(
        AlbumRefreshStage.handoff,
        aiRunning ? 0.95 : 1.0,
        '本轮没有可入库新照片',
        aiRunning ? 'AI 队列正在运行' : '已转去检查未完成的后台 AI 队列',
      );
      return AlbumRefreshResult(
        scanSummary: summary,
        requeuedCount: 0,
        recentPhotoLimit: batchSize,
        clearCacheFirst: false,
        aiAlreadyRunning: aiRunning,
      );
    }

    // step 2: 有新照片 → requeue（标记为未分析）
    await PhotoService().requeuePhotosForAiByIds(scanResult.insertedPhotoIds);
    _scheduleMediaIndexRefresh(batchSize: batchSize);

    _setProgress(
      AlbumRefreshStage.clustering,
      0.72,
      '正在更新相册索引',
      '已加入 ${scanResult.insertedCount} 张照片，正在重建事件分类',
    );

    // step 3: 事件聚类
    await EventService().runClustering();

    // step 4: 触发 AI 打标
    final aiRunning = AIService().isAnalyzing;
    if (!aiRunning) {
      unawaited(_runAiPipeline(maxPhotos: batchSize));
    }
    _setProgress(
      AlbumRefreshStage.handoff,
      0.95,
      '预处理完成',
      aiRunning ? 'AI 队列正在继续处理' : '已交给后台 AI 队列',
    );

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
    _setProgress(
      AlbumRefreshStage.scanning,
      0.04,
      '正在准备安全重建',
      '正在安全结束当前 AI 任务',
    );

    await AIService().stopAnalysisAndWait();

    _setProgress(
      AlbumRefreshStage.scanning,
      0.12,
      '正在读取系统相册',
      recentPhotoLimit == null ? '范围：全部照片' : '范围：最近 $recentPhotoLimit 张',
    );

    final scanSummary = await PhotoService().rebuildAllCachedData(
      maxAssets: recentPhotoLimit,
    );

    _setProgress(
      AlbumRefreshStage.clustering,
      0.68,
      '正在重建事件分类',
      '照片 ${scanSummary.totalAfter} 张',
    );

    await EventService().runClustering();
    _scheduleMediaIndexRefresh(batchSize: recentPhotoLimit ?? 300);

    final aiRunning = AIService().isAnalyzing;
    if (!aiRunning) {
      unawaited(_runAiPipeline(maxPhotos: recentPhotoLimit));
    }
    _setProgress(
      AlbumRefreshStage.handoff,
      0.95,
      '安全重建完成',
      aiRunning ? 'AI 队列正在继续处理' : '已交给后台 AI 队列',
    );

    // 延迟一小段时间后重置进度状态，让用户看到完成消息
    Future.delayed(const Duration(milliseconds: 1500), () {
      _progressNotifier.value = AlbumRefreshProgress.idle();
    });

    return AlbumRefreshResult(
      scanSummary: scanSummary,
      requeuedCount: 0,
      recentPhotoLimit: recentPhotoLimit,
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

  Future<void> _runAiPipeline({int? maxPhotos}) async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      await AIService().analyzePhotosInBackground(maxPhotos: maxPhotos);
    } catch (error) {
      debugPrint('❌ 后台 AI 管线执行失败: $error');
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
