/// AI 分析进度模型，描述运行状态、已处理数量和错误信息。

part of 'ai_service.dart';

class AIAnalysisProgress {
  /// 预热阶段在总进度条中所占的比例（0~1），默认为 10%。
  static const double warmUpFractionShare = 0.10;

  const AIAnalysisProgress({
    required this.isRunning,
    required this.isPaused,
    required this.isStopping,
    required this.total,
    required this.completed,
    required this.failed,
    required this.currentStep,
    required this.elapsedMs,
    this.warmUpCompleted = 0,
    this.warmUpTotal = 0,
  });

  factory AIAnalysisProgress.idle() {
    return const AIAnalysisProgress(
      isRunning: false,
      isPaused: false,
      isStopping: false,
      total: 0,
      completed: 0,
      failed: 0,
      currentStep: '',
      elapsedMs: 0,
    );
  }

  factory AIAnalysisProgress.running({
    required int total,
    required int completed,
    required int failed,
    required String currentStep,
    int elapsedMs = 0,
    int warmUpCompleted = 0,
    int warmUpTotal = 0,
  }) {
    return AIAnalysisProgress(
      isRunning: true,
      isPaused: false,
      isStopping: false,
      total: total,
      completed: completed,
      failed: failed,
      currentStep: currentStep,
      elapsedMs: elapsedMs,
      warmUpCompleted: warmUpCompleted,
      warmUpTotal: warmUpTotal,
    );
  }

  factory AIAnalysisProgress.paused({
    required int total,
    required int completed,
    required int failed,
    required String currentStep,
    int elapsedMs = 0,
    int warmUpCompleted = 0,
    int warmUpTotal = 0,
  }) {
    return AIAnalysisProgress(
      isRunning: false,
      isPaused: true,
      isStopping: false,
      total: total,
      completed: completed,
      failed: failed,
      currentStep: currentStep,
      elapsedMs: elapsedMs,
      warmUpCompleted: warmUpCompleted,
      warmUpTotal: warmUpTotal,
    );
  }

  factory AIAnalysisProgress.stopping({
    required int total,
    required int completed,
    required int failed,
    required String currentStep,
    int elapsedMs = 0,
    int warmUpCompleted = 0,
    int warmUpTotal = 0,
  }) {
    return AIAnalysisProgress(
      isRunning: false,
      isPaused: false,
      isStopping: true,
      total: total,
      completed: completed,
      failed: failed,
      currentStep: currentStep,
      elapsedMs: elapsedMs,
      warmUpCompleted: warmUpCompleted,
      warmUpTotal: warmUpTotal,
    );
  }

  final bool isRunning;
  final bool isPaused;
  final bool isStopping;
  final int total;
  final int completed;
  final int failed;
  final String currentStep;
  final int elapsedMs;
  final int warmUpCompleted;
  final int warmUpTotal;

  AIAnalysisProgress copyWith({
    bool? isRunning,
    bool? isPaused,
    bool? isStopping,
    int? total,
    int? completed,
    int? failed,
    String? currentStep,
    int? elapsedMs,
    int? warmUpCompleted,
    int? warmUpTotal,
  }) {
    return AIAnalysisProgress(
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      isStopping: isStopping ?? this.isStopping,
      total: total ?? this.total,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      currentStep: currentStep ?? this.currentStep,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      warmUpCompleted: warmUpCompleted ?? this.warmUpCompleted,
      warmUpTotal: warmUpTotal ?? this.warmUpTotal,
    );
  }

  double? get averageSecondsPerItem {
    if (completed <= 0 || elapsedMs <= 0) {
      return null;
    }
    return elapsedMs / 1000.0 / completed;
  }

  Duration? get estimatedRemainingDuration {
    final avg = averageSecondsPerItem;
    final remaining = total - completed;
    if (avg == null || remaining <= 0) {
      return null;
    }
    final etaMs = (avg * remaining * 1000).round();
    return Duration(milliseconds: etaMs);
  }

  Duration get elapsed => Duration(milliseconds: elapsedMs);

  double get fraction {
    final hasWarmUp = warmUpTotal > 0;
    final hasProcessing = total > 0;

    if (!hasWarmUp && !hasProcessing) {
      return 0;
    }

    final warmUpFraction =
        hasWarmUp ? (warmUpCompleted / warmUpTotal).clamp(0, 1) : 0.0;

    if (!hasProcessing) {
      return warmUpFraction * warmUpFractionShare;
    }

    final processingFraction = (completed / total).clamp(0, 1);
    return warmUpFraction * warmUpFractionShare +
        processingFraction * (1 - warmUpFractionShare);
  }

  bool get isVisible => (isRunning || isPaused || isStopping) && total > 0;
}
