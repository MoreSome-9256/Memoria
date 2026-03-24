import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ai_service.dart';
import 'event_service.dart';
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

  factory AlbumRefreshProgress.idle() {
    return const AlbumRefreshProgress(
      stage: AlbumRefreshStage.idle,
      isRunning: false,
      progress: 0,
      title: '',
      message: '',
    );
  }

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

  Future<AlbumRefreshResult?> startRefresh({
    bool clearCacheFirst = false,
    int? recentPhotoLimit,
  }) async {
    if (_isRunning) {
      debugPrint('⏭️ 相册刷新任务已在运行，跳过重复启动');
      return null;
    }

    _isRunning = true;

    try {
      _setProgress(
        stage: AlbumRefreshStage.scanning,
        progress: 0.08,
        title: '正在扫描最近图片',
        message: _buildScopeMessage(
          recentPhotoLimit,
          fallback: '准备读取系统相册资源',
        ),
      );

      late final PhotoScanSummary scanSummary;
      if (clearCacheFirst) {
        await AIService().stopAnalysisAndWait();
        scanSummary = await PhotoService().rebuildAllCachedData(
          maxAssets: recentPhotoLimit,
        );
      } else {
        scanSummary = await PhotoService().scanAndSyncPhotos(
          maxAssets: recentPhotoLimit,
        );
      }

      _setProgress(
        stage: AlbumRefreshStage.clustering,
        progress: 0.42,
        title: '正在整理相册分类',
        message: '已同步基础照片数据，正在重建事件与分类索引',
      );
      await EventService().runClustering();

      _setProgress(
        stage: AlbumRefreshStage.queueing,
        progress: 0.62,
        title: '正在准备后台打标',
        message: '扫描完成，正在把本次照片加入 MobileCLIP 队列',
      );

      var requeuedCount = 0;
      if (!clearCacheFirst) {
        requeuedCount = await PhotoService().requeueLatestPhotosForAi(
          maxPhotos: recentPhotoLimit,
        );
      }

      final aiAlreadyRunning = AIService().isAnalyzing;
      _setProgress(
        stage: AlbumRefreshStage.handoff,
        progress: 0.84,
        title: '已转入后台继续处理',
        message: aiAlreadyRunning
            ? '后台 AI 已在运行，本次新照片已并入现有任务'
            : '后台 AI 即将继续补齐标签与 caption',
      );

      if (!aiAlreadyRunning) {
        unawaited(_runAiPipeline(maxPhotos: recentPhotoLimit));
      }

      return AlbumRefreshResult(
        scanSummary: scanSummary,
        requeuedCount: requeuedCount,
        recentPhotoLimit: recentPhotoLimit,
        clearCacheFirst: clearCacheFirst,
        aiAlreadyRunning: aiAlreadyRunning,
      );
    } catch (error) {
      _progressNotifier.value = AlbumRefreshProgress.running(
        stage: AlbumRefreshStage.failed,
        progress: 1,
        title: '相册刷新失败',
        message: error.toString(),
      );
      rethrow;
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _progressNotifier.value = AlbumRefreshProgress.idle();
      _isRunning = false;
    }
  }

  void _setProgress({
    required AlbumRefreshStage stage,
    required double progress,
    required String title,
    required String message,
  }) {
    _progressNotifier.value = AlbumRefreshProgress.running(
      stage: stage,
      progress: progress,
      title: title,
      message: message,
    );
  }

  Future<void> _runAiPipeline({int? maxPhotos}) async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await AIService().analyzePhotosInBackground(maxPhotos: maxPhotos);
      await AIService().backfillMissingCaptionsInBackground(maxPhotos: maxPhotos);
    } catch (error) {
      debugPrint('❌ 后台相册 AI 管线执行失败: $error');
    }
  }

  String _buildScopeMessage(int? recentPhotoLimit, {required String fallback}) {
    if (recentPhotoLimit == null) {
      return '$fallback（全量）';
    }
    return '$fallback（最近 $recentPhotoLimit 张）';
  }
}
