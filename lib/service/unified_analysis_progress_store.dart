import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'unified_analysis_progress.dart';

class UnifiedAnalysisProgressStore {
  UnifiedAnalysisProgressStore._();

  static final UnifiedAnalysisProgressStore instance =
      UnifiedAnalysisProgressStore._();

  final ValueNotifier<UnifiedAnalysisProgress> progress =
      ValueNotifier<UnifiedAnalysisProgress>(UnifiedAnalysisProgress.idle());

  bool _isForegroundIsolate = false;

  void startListening() {
    FlutterForegroundTask.addTaskDataCallback(_onReceiveData);
  }

  void stopListening() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveData);
  }

  void markForegroundIsolate() {
    _isForegroundIsolate = true;
  }

  void _onReceiveData(Object data) {
    if (data is! String) return;
    
    final snapshot = _decode(data);
    if (snapshot == null) {
      debugPrint('[progress-receive] decode failed');
      return;
    }
    
    debugPrint(
      '[progress-receive] stage=${snapshot.stage} scan=${snapshot.scanCompleted}/${snapshot.scanTotal} ai=${snapshot.aiCompleted}/${snapshot.aiTotal}',
    );
    
    progress.value = snapshot;
  }

  Future<void> clear() async {
    progress.value = UnifiedAnalysisProgress.idle();
  }

  Future<void> publish(UnifiedAnalysisProgress next) async {
    final previous = progress.value;
    final merged = _merge(previous, next);
    
    if (_isForegroundIsolate) {
      final encoded = jsonEncode(_toJson(merged));
      FlutterForegroundTask.sendDataToMain(encoded);
    }
    
    progress.value = merged;
  }

  UnifiedAnalysisProgress _merge(
    UnifiedAnalysisProgress? previous,
    UnifiedAnalysisProgress next,
  ) {
    if (previous == null || previous.stage == UnifiedAnalysisStage.idle) {
      return next;
    }
    if (next.stage == UnifiedAnalysisStage.idle) {
      return next;
    }
    if (_isTerminal(previous) && !_isTerminal(next)) {
      return previous;
    }

    final scanCompleted = math.max(
      previous.scanCompleted,
      next.scanCompleted,
    );
    final scanTotal = math.max(previous.scanTotal, next.scanTotal);
    final aiCompleted = math.max(previous.aiCompleted, next.aiCompleted);
    final aiTotal = math.max(previous.aiTotal, next.aiTotal);
    final aiFailed = math.max(previous.aiFailed, next.aiFailed);
    final startedAtMs = next.startedAtMs > 0
        ? next.startedAtMs
        : previous.startedAtMs;

    final mergedStage = _mergeStage(previous, next);
    final mergedIsTerminal = mergedStage == UnifiedAnalysisStage.completed ||
        mergedStage == UnifiedAnalysisStage.failed;

    return UnifiedAnalysisProgress(
      stage: mergedStage,
      isRunning: mergedIsTerminal
          ? false
          : (next.isRunning || previous.isRunning),
      scanCompleted: scanCompleted,
      scanTotal: scanTotal,
      aiCompleted: aiCompleted,
      aiTotal: aiTotal,
      aiFailed: aiFailed,
      queueSize: next.queueSize,
      message: next.message.isNotEmpty ? next.message : previous.message,
      elapsedMs: math.max(previous.elapsedMs, next.elapsedMs),
      startedAtMs: startedAtMs,
      scanDone: previous.scanDone || next.scanDone,
      scanStopped: previous.scanStopped || next.scanStopped,
      analysisEnabled: next.analysisEnabled,
    );
  }

  UnifiedAnalysisStage _mergeStage(
    UnifiedAnalysisProgress previous,
    UnifiedAnalysisProgress next,
  ) {
    if (next.stage == UnifiedAnalysisStage.failed ||
        next.stage == UnifiedAnalysisStage.completed ||
        next.stage == UnifiedAnalysisStage.flushing) {
      return next.stage;
    }
    if (next.stage == UnifiedAnalysisStage.scanning &&
        (previous.stage == UnifiedAnalysisStage.warmingUp ||
            previous.stage == UnifiedAnalysisStage.processing)) {
      return previous.stage;
    }
    return next.stage;
  }

  bool _isTerminal(UnifiedAnalysisProgress progress) {
    return progress.stage == UnifiedAnalysisStage.completed ||
        progress.stage == UnifiedAnalysisStage.failed;
  }

  Map<String, Object?> _toJson(UnifiedAnalysisProgress p) {
    return <String, Object?>{
      'stage': p.stage.name,
      'isRunning': p.isRunning,
      'scanCompleted': p.scanCompleted,
      'scanTotal': p.scanTotal,
      'aiCompleted': p.aiCompleted,
      'aiTotal': p.aiTotal,
      'aiFailed': p.aiFailed,
      'queueSize': p.queueSize,
      'message': p.message,
      'elapsedMs': p.elapsedMs,
      'startedAtMs': p.startedAtMs,
      'scanDone': p.scanDone,
      'scanStopped': p.scanStopped,
      'analysisEnabled': p.analysisEnabled,
    };
  }

  UnifiedAnalysisProgress? _decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      
      return UnifiedAnalysisProgress(
        stage: _stageFromName(json['stage'] as String?),
        isRunning: json['isRunning'] == true,
        scanCompleted: json['scanCompleted'] as int? ?? 0,
        scanTotal: json['scanTotal'] as int? ?? 0,
        aiCompleted: json['aiCompleted'] as int? ?? 0,
        aiTotal: json['aiTotal'] as int? ?? 0,
        aiFailed: json['aiFailed'] as int? ?? 0,
        queueSize: json['queueSize'] as int? ?? 0,
        message: json['message'] as String? ?? '',
        elapsedMs: json['elapsedMs'] as int? ?? 0,
        startedAtMs: json['startedAtMs'] as int? ?? 0,
        scanDone: json['scanDone'] == true,
        scanStopped: json['scanStopped'] == true,
        analysisEnabled: json['analysisEnabled'] != false,
      );
    } catch (e) {
      debugPrint('[progress-decode] error=$e');
      return null;
    }
  }

  UnifiedAnalysisStage _stageFromName(String? name) {
    for (final stage in UnifiedAnalysisStage.values) {
      if (stage.name == name) {
        return stage;
      }
    }
    return UnifiedAnalysisStage.idle;
  }
}
