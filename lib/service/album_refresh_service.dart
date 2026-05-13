import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ai_service.dart';
import 'event_service.dart';
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
  });

  factory AlbumRefreshProgress.idle() => const AlbumRefreshProgress(
    stage: AlbumRefreshStage.idle,
    isRunning: false,
    progress: 0,
    title: '',
    message: '',
  );

  factory AlbumRefreshProgress.running({
    required AlbumRefreshStage stage,
    required double progress,
    required String title,
    required String message,
  }) {
    return AlbumRefreshProgress(
      stage: stage,
      isRunning: true,
      progress: progress.clamp(0, 1).toDouble(),
      title: title,
      message: message,
    );
  }

  final AlbumRefreshStage stage;
  final bool isRunning;
  final double progress;
  final String title;
  final String message;

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
      );
      rethrow;
    } finally {
      _progressNotifier.value = AlbumRefreshProgress.idle();
      _isRunning = false;
    }
  }

  // ── 增量扫描（"下一批 N 张" 路径）───────────────────────────────
  Future<AlbumRefreshResult> _runIncrementalScan(int? recentPhotoLimit) async {
    final batchSize = math.max(10, math.min(1000, recentPhotoLimit ?? 100));

    _setProgress(
      AlbumRefreshStage.scanning,
      0.15,
      '正在扫描下一批照片',
      '从最新照片开始，收集最多 $batchSize 张新照片',
    );

    // step 1: stop-early 扫描，只找新照片
    final scanResult = await PhotoService().scanBatchPhotos(
      batchSize: batchSize,
    );

    _setProgress(
      AlbumRefreshStage.queueing,
      0.30,
      '已扫描 ${scanResult.scannedCount} 张',
      '新增 ${scanResult.insertedCount} 张照片',
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

    // _setProgress(
    //   AlbumRefreshStage.clustering,
    //   0.50,
    //   '正在整理相册分类',
    //   '已 requeue ${scanResult.insertedCount} 张，正在重建事件索引',
    // );

    // step 3: 事件聚类
    await EventService().runClustering();

    // step 4: 触发 AI 打标
    final aiRunning = AIService().isAnalyzing;
    if (!aiRunning) {
      unawaited(_runAiPipeline(maxPhotos: batchSize));
    }

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
    await AIService().stopAnalysisAndWait();

    _setProgress(
      AlbumRefreshStage.scanning,
      0.10,
      '正在安全重建',
      recentPhotoLimit == null ? '全部照片' : '最近 $recentPhotoLimit 张',
    );

    final scanSummary = await PhotoService().rebuildAllCachedData(
      maxAssets: recentPhotoLimit,
    );

    _setProgress(
      AlbumRefreshStage.clustering,
      0.45,
      '正在重建事件分类',
      '照片 ${scanSummary.totalAfter} 张',
    );

    await EventService().runClustering();
    _scheduleMediaIndexRefresh(batchSize: recentPhotoLimit ?? 300);

    final aiRunning = AIService().isAnalyzing;
    if (!aiRunning) {
      unawaited(_runAiPipeline(maxPhotos: recentPhotoLimit));
    }

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
          final mediaSummary = await MediaAssetSyncService().reconcile(
            pageSize: math.max(100, math.min(300, batchSize)),
          );
          debugPrint(
            '🧭 ObjectBox media reconcile: discovered=${mediaSummary.discovered} '
            'upsert=${mediaSummary.insertedOrUpdated} removed=${mediaSummary.removed} '
            'limited=${mediaSummary.limitedAccess}',
          );
          await MediaEmbeddingIndexService().encodePending(
            maxConcurrency: 2,
            batchSize: batchSize,
            inputSize: 336,
          );
        } catch (error) {
          debugPrint('Media asset index refresh skipped: $error');
        }
      }),
    );
  }
}
