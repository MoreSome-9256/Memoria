import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unified_analysis_progress.dart';

class UnifiedAnalysisProgressStore {
  UnifiedAnalysisProgressStore._();

  static final UnifiedAnalysisProgressStore instance =
      UnifiedAnalysisProgressStore._();

  static const String _snapshotKey =
      'foreground_unified_pipeline_progress_snapshot';
  static const String _updatedAtKey =
      'foreground_unified_pipeline_progress_updated_at';
  static const Duration _pollInterval = Duration(milliseconds: 700);
  static const Duration _terminalVisibleDuration = Duration(seconds: 12);

  final ValueNotifier<UnifiedAnalysisProgress> progress =
      ValueNotifier<UnifiedAnalysisProgress>(UnifiedAnalysisProgress.idle());

  Timer? _poller;
  int _lastUpdatedAt = -1;

  void startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(_pollInterval, (_) => unawaited(_poll()));
    unawaited(_poll());
  }

  void stopPolling() {
    _poller?.cancel();
    _poller = null;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_snapshotKey);
    await prefs.remove(_updatedAtKey);
    _lastUpdatedAt = -1;
    progress.value = UnifiedAnalysisProgress.idle();
  }

  Future<void> publish(UnifiedAnalysisProgress next) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = _decode(prefs.getString(_snapshotKey));
    final merged = _merge(previous, next);
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setString(_snapshotKey, jsonEncode(_toJson(merged)));
    await prefs.setInt(_updatedAtKey, now);
    _lastUpdatedAt = now;
    progress.value = merged;
  }

  Future<void> _poll() async {
    final prefs = await SharedPreferences.getInstance();
    final updatedAt = prefs.getInt(_updatedAtKey) ?? -1;
    final snapshot = _decode(prefs.getString(_snapshotKey));
    if (snapshot == null) {
      if (progress.value.isVisible) {
        progress.value = UnifiedAnalysisProgress.idle();
      }
      _lastUpdatedAt = updatedAt;
      return;
    }

    final ageMs = DateTime.now().millisecondsSinceEpoch - updatedAt;
    final isTerminal =
        snapshot.stage == UnifiedAnalysisStage.completed ||
        snapshot.stage == UnifiedAnalysisStage.failed;
    if (isTerminal && ageMs > _terminalVisibleDuration.inMilliseconds) {
      await clear();
      return;
    }

    if (updatedAt != _lastUpdatedAt || progress.value != snapshot) {
      _lastUpdatedAt = updatedAt;
      progress.value = snapshot;
    }
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

    return UnifiedAnalysisProgress(
      stage: _mergeStage(previous, next),
      isRunning: next.isRunning || previous.isRunning,
      scanCompleted: scanCompleted,
      scanTotal: scanTotal,
      aiCompleted: aiCompleted,
      aiTotal: aiTotal,
      aiFailed: aiFailed,
      queueSize: next.queueSize,
      message: next.message.isNotEmpty ? next.message : previous.message,
      elapsedMs: math.max(previous.elapsedMs, next.elapsedMs),
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
      'scanDone': p.scanDone,
      'scanStopped': p.scanStopped,
      'analysisEnabled': p.analysisEnabled,
    };
  }

  UnifiedAnalysisProgress? _decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return null;
      }
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
        scanDone: json['scanDone'] == true,
        scanStopped: json['scanStopped'] == true,
        analysisEnabled: json['analysisEnabled'] != false,
      );
    } catch (_) {
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
