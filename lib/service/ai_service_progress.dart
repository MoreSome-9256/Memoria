part of 'ai_service.dart';

class AIAnalysisProgress {
  const AIAnalysisProgress({
    required this.isRunning,
    required this.isPaused,
    required this.isStopping,
    required this.total,
    required this.completed,
    required this.failed,
    required this.currentStep,
    required this.elapsedMs,
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
    );
  }

  factory AIAnalysisProgress.paused({
    required int total,
    required int completed,
    required int failed,
    required String currentStep,
    int elapsedMs = 0,
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
    );
  }

  factory AIAnalysisProgress.stopping({
    required int total,
    required int completed,
    required int failed,
    required String currentStep,
    int elapsedMs = 0,
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

  AIAnalysisProgress copyWith({
    bool? isRunning,
    bool? isPaused,
    bool? isStopping,
    int? total,
    int? completed,
    int? failed,
    String? currentStep,
    int? elapsedMs,
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
    if (total <= 0) {
      return 0;
    }
    return (completed / total).clamp(0, 1).toDouble();
  }

  bool get isVisible => (isRunning || isPaused || isStopping) && total > 0;
}
