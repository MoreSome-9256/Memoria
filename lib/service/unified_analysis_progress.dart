enum UnifiedAnalysisStage {
  idle,
  warmingUp,
  scanning,
  processing,
  flushing,
  completed,
  failed,
}

class UnifiedAnalysisProgress {
  const UnifiedAnalysisProgress({
    required this.stage,
    required this.isRunning,
    required this.scanCompleted,
    required this.scanTotal,
    required this.aiCompleted,
    required this.aiTotal,
    required this.aiFailed,
    required this.queueSize,
    required this.message,
    required this.elapsedMs,
    this.scanDone = false,
    this.scanStopped = false,
    this.analysisEnabled = true,
  });

  factory UnifiedAnalysisProgress.idle() => const UnifiedAnalysisProgress(
    stage: UnifiedAnalysisStage.idle,
    isRunning: false,
    scanCompleted: 0,
    scanTotal: 0,
    aiCompleted: 0,
    aiTotal: 0,
    aiFailed: 0,
    queueSize: 0,
    message: '',
    elapsedMs: 0,
    scanDone: false,
    scanStopped: false,
    analysisEnabled: true,
  );

  factory UnifiedAnalysisProgress.warmingUp({
    required int warmUpCompleted,
    required int warmUpTotal,
    required String message,
  }) => UnifiedAnalysisProgress(
    stage: UnifiedAnalysisStage.warmingUp,
    isRunning: true,
    scanCompleted: 0,
    scanTotal: 0,
    aiCompleted: 0,
    aiTotal: 0,
    aiFailed: 0,
    queueSize: 0,
    message: message,
    elapsedMs: 0,
    scanDone: false,
    scanStopped: false,
    analysisEnabled: true,
  );

  factory UnifiedAnalysisProgress.scanning({
    required int scanCompleted,
    required int scanTotal,
    required int queueSize,
    required String message,
    required int elapsedMs,
  }) => UnifiedAnalysisProgress(
    stage: UnifiedAnalysisStage.scanning,
    isRunning: true,
    scanCompleted: scanCompleted,
    scanTotal: scanTotal,
    aiCompleted: 0,
    aiTotal: 0,
    aiFailed: 0,
    queueSize: queueSize,
    message: message,
    elapsedMs: elapsedMs,
    scanDone: false,
    scanStopped: false,
    analysisEnabled: true,
  );

  factory UnifiedAnalysisProgress.processing({
    required int scanCompleted,
    required int scanTotal,
    required int aiCompleted,
    required int aiTotal,
    required int aiFailed,
    required int queueSize,
    required String message,
    required int elapsedMs,
  }) => UnifiedAnalysisProgress(
    stage: UnifiedAnalysisStage.processing,
    isRunning: true,
    scanCompleted: scanCompleted,
    scanTotal: scanTotal,
    aiCompleted: aiCompleted,
    aiTotal: aiTotal,
    aiFailed: aiFailed,
    queueSize: queueSize,
    message: message,
    elapsedMs: elapsedMs,
    scanDone: false,
    scanStopped: false,
    analysisEnabled: true,
  );

  final UnifiedAnalysisStage stage;
  final bool isRunning;
  final int scanCompleted;
  final int scanTotal;
  final int aiCompleted;
  final int aiTotal;
  final int aiFailed;
  final int queueSize;
  final String message;
  final int elapsedMs;
  final bool scanDone;
  final bool scanStopped;
  final bool analysisEnabled;

  bool get isVisible =>
      isRunning ||
      stage == UnifiedAnalysisStage.completed ||
      stage == UnifiedAnalysisStage.failed ||
      scanStopped;
  bool get isScanning => stage == UnifiedAnalysisStage.scanning;
  bool get isProcessing => stage == UnifiedAnalysisStage.processing;
  bool get hasCacheWork =>
      isRunning &&
      scanTotal > 0 &&
      !scanStopped &&
      (!scanDone || scanCompleted < scanTotal);
  bool get hasAiWork =>
      analysisEnabled &&
      isRunning &&
      (stage == UnifiedAnalysisStage.warmingUp ||
          stage == UnifiedAnalysisStage.processing ||
          aiTotal > 0);

  double get scanFraction =>
      scanTotal > 0 ? (scanCompleted / scanTotal).clamp(0, 1) : 0;

  double get aiFraction =>
      aiTotal > 0 ? (aiCompleted / aiTotal).clamp(0, 1) : 0;

  double get overallFraction {
    if (stage == UnifiedAnalysisStage.completed) return 1;
    if (scanTotal <= 0) return 0;
    if (!analysisEnabled || aiTotal <= 0) {
      return scanFraction;
    }
    final scanWeight = 0.4;
    final aiWeight = 0.6;
    final weighted = scanFraction * scanWeight + aiFraction * aiWeight;
    return weighted.clamp(0, 1);
  }

  double? get averageSecondsPerItem {
    final scanAvg = _averageSeconds(completed: scanCompleted);
    final aiAvg = _averageSeconds(completed: aiCompleted);
    if (scanAvg == null) return aiAvg;
    if (aiAvg == null) return scanAvg;
    return scanAvg > aiAvg ? scanAvg : aiAvg;
  }

  Duration? get estimatedRemainingDuration {
    final scanRemaining = _estimatedRemaining(
      completed: scanCompleted,
      total: scanTotal,
    );
    final aiRemaining = _estimatedRemaining(
      completed: aiCompleted,
      total: aiTotal,
    );
    if (scanRemaining == null) return aiRemaining;
    if (aiRemaining == null) return scanRemaining;
    return scanRemaining > aiRemaining ? scanRemaining : aiRemaining;
  }

  Duration get elapsed => Duration(milliseconds: elapsedMs);

  double? _averageSeconds({required int completed}) {
    if (completed <= 0 || elapsedMs <= 0) return null;
    return elapsedMs / 1000.0 / completed;
  }

  Duration? _estimatedRemaining({
    required int completed,
    required int total,
  }) {
    final avg = _averageSeconds(completed: completed);
    final remaining = total - completed;
    if (avg == null || remaining <= 0) return null;
    return Duration(milliseconds: (avg * remaining * 1000).round());
  }

  UnifiedAnalysisProgress copyWith({
    UnifiedAnalysisStage? stage,
    bool? isRunning,
    int? scanCompleted,
    int? scanTotal,
    int? aiCompleted,
    int? aiTotal,
    int? aiFailed,
    int? queueSize,
    String? message,
    int? elapsedMs,
    bool? scanDone,
    bool? scanStopped,
    bool? analysisEnabled,
  }) {
    return UnifiedAnalysisProgress(
      stage: stage ?? this.stage,
      isRunning: isRunning ?? this.isRunning,
      scanCompleted: scanCompleted ?? this.scanCompleted,
      scanTotal: scanTotal ?? this.scanTotal,
      aiCompleted: aiCompleted ?? this.aiCompleted,
      aiTotal: aiTotal ?? this.aiTotal,
      aiFailed: aiFailed ?? this.aiFailed,
      queueSize: queueSize ?? this.queueSize,
      message: message ?? this.message,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      scanDone: scanDone ?? this.scanDone,
      scanStopped: scanStopped ?? this.scanStopped,
      analysisEnabled: analysisEnabled ?? this.analysisEnabled,
    );
  }
}
