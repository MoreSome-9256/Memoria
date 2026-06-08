import 'package:flutter/foundation.dart';

import 'photo_service.dart';
import 'ai_background_task_service.dart';
import 'unified_analysis_pipeline_service.dart';
import 'unified_analysis_progress.dart';
import 'unified_analysis_progress_store.dart';

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
    required this.clearCacheFirst,
    required this.aiAlreadyRunning,
  });

  final PhotoScanSummary scanSummary;
  final int requeuedCount;
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
    bool useUnifiedPipeline = true,
    bool analyzeWithAi = true,
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
      '[scan] runId=$runId clearCacheFirst=$clearCacheFirst analyzeWithAi=$analyzeWithAi foregroundOnly=true',
    );
    if (!useUnifiedPipeline) {
      debugPrint(
        '[scan] useUnifiedPipeline=false 已忽略：相册流水线只允许 foreground task 路径',
      );
    }

    try {
      final result = await _runUnifiedPipeline(
        clearCacheFirst: clearCacheFirst,
        analyzeWithAi: analyzeWithAi,
      );
      debugPrint('[scan] ✅ foreground task 已启动');
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
      _progressNotifier.value = AlbumRefreshProgress.idle();
      _isRunning = false;
      debugPrint(
        '[scan] ======== AlbumRefreshService 结束 (runId=$runId) ========',
      );
    }
  }

  Future<void> stopScanningOnly() async {
    final foregroundProgress =
        UnifiedAnalysisProgressStore.instance.progress.value;
    if (!_isRunning && !foregroundProgress.isRunning) {
      return;
    }
    UnifiedAnalysisPipelineService().stopPipeline();
    await AiBackgroundTaskService.instance.stop();
    if (_isRunning) {
      _setProgress(
        AlbumRefreshStage.handoff,
        _progressNotifier.value.progress,
        '正在停止任务',
        '已停止生产者和消费者，未打标候选会保留。',
      );
    }
  }

  // ── 统一流水线（扫描 + AI 并行）──────────────────────────────
  Future<AlbumRefreshResult> _runUnifiedPipeline({
    required bool clearCacheFirst,
    required bool analyzeWithAi,
  }) async {
    debugPrint('[scan] 启动统一流水线模式');

    _setProgress(AlbumRefreshStage.scanning, 0.0, '正在启动统一流水线', '扫描和AI处理将并行执行');

    final pipelineService = UnifiedAnalysisPipelineService();

    void onProgressChanged() {
      final progress = pipelineService.progressListenable.value;
      _setProgress(
        _mapPipelineStageToRefreshStage(progress.stage),
        progress.overallFraction,
        _extractTitleFromPipelineProgress(progress),
        progress.message,
      );
    }

    pipelineService.progressListenable.addListener(onProgressChanged);

    try {
      await pipelineService.startUnifiedPipeline(
        clearCacheFirst: clearCacheFirst,
        analyzeWithAi: analyzeWithAi,
      );

      final totalAfter = PhotoService().totalPhotoCount;

      return AlbumRefreshResult(
        scanSummary: PhotoScanSummary(
          totalBefore: 0,
          totalAfter: totalAfter,
          removedCount: 0,
          insertedCount: totalAfter,
          insertedPhotoIds: const [],
          scannedCount: totalAfter,
          skippedInvalidTime: 0,
          insertedNoGps: 0,
          skippedNonCamera: 0,
        ),
        requeuedCount: 0,
        clearCacheFirst: clearCacheFirst,
        aiAlreadyRunning: false,
      );
    } finally {
      pipelineService.progressListenable.removeListener(onProgressChanged);
    }
  }

  AlbumRefreshStage _mapPipelineStageToRefreshStage(
    UnifiedAnalysisStage stage,
  ) {
    switch (stage) {
      case UnifiedAnalysisStage.idle:
        return AlbumRefreshStage.idle;
      case UnifiedAnalysisStage.warmingUp:
        return AlbumRefreshStage.scanning;
      case UnifiedAnalysisStage.scanning:
        return AlbumRefreshStage.scanning;
      case UnifiedAnalysisStage.processing:
        return AlbumRefreshStage.queueing;
      case UnifiedAnalysisStage.flushing:
        return AlbumRefreshStage.clustering;
      case UnifiedAnalysisStage.stopped:
        return AlbumRefreshStage.handoff;
      case UnifiedAnalysisStage.completed:
        return AlbumRefreshStage.handoff;
      case UnifiedAnalysisStage.failed:
        return AlbumRefreshStage.failed;
    }
  }

  String _extractTitleFromPipelineProgress(UnifiedAnalysisProgress progress) {
    switch (progress.stage) {
      case UnifiedAnalysisStage.idle:
        return '';
      case UnifiedAnalysisStage.warmingUp:
        return '正在预热引擎';
      case UnifiedAnalysisStage.scanning:
        return '正在扫描照片';
      case UnifiedAnalysisStage.processing:
        return '正在处理照片';
      case UnifiedAnalysisStage.flushing:
        return '正在刷新索引';
      case UnifiedAnalysisStage.stopped:
        return '已停止';
      case UnifiedAnalysisStage.completed:
        return '已完成';
      case UnifiedAnalysisStage.failed:
        return '处理失败';
    }
  }

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
}
