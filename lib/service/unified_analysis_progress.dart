import 'package:flutter/foundation.dart';

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

  bool get isVisible => isRunning || stage == UnifiedAnalysisStage.completed;
  bool get isScanning => stage == UnifiedAnalysisStage.scanning;
  bool get isProcessing => stage == UnifiedAnalysisStage.processing;

  double get scanFraction =>
      scanTotal > 0 ? (scanCompleted / scanTotal).clamp(0, 1) : 0;

  double get aiFraction =>
      aiTotal > 0 ? (aiCompleted / aiTotal).clamp(0, 1) : 0;

  double get overallFraction {
    if (scanTotal <= 0) return 0;
    final scanWeight = 0.4;
    final aiWeight = 0.6;
    final weighted = scanFraction * scanWeight + aiFraction * aiWeight;
    return weighted.clamp(0, 1);
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
    );
  }
}
