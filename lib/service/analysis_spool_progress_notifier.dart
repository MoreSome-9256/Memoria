/// Spool 进度轮询器 — 从 spool progress 文件中读取进度，驱动 UI。
///
/// 在主进程中使用。前台服务写入 progress.json → 本轮询器检测文件变化
/// → 通过 ValueNotifier 通知 UI 层。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analysis_spool_service.dart';

/// 简化的 UI 进度模型。
class SpoolProgress {
  final String jobId;
  final String status; // running / paused / finished / stopped / failed
  final int total;
  final int processed;
  final int succeeded;
  final int failed;
  final int skipped;
  final bool done;
  final String currentStep;

  const SpoolProgress({
    required this.jobId,
    this.status = 'idle',
    this.total = 0,
    this.processed = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.skipped = 0,
    this.done = false,
    this.currentStep = '',
  });

  bool get isRunning => status == 'running';
  bool get isFinished => status == 'finished' || done;
  bool get isStopped => status == 'stopped';
  double get fraction =>
      total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;

  factory SpoolProgress.idle() => const SpoolProgress(jobId: '');

  factory SpoolProgress.fromSnapshot(AnalysisProgressSnapshot snapshot) {
    return SpoolProgress(
      jobId: snapshot.jobId,
      status: snapshot.status,
      total: snapshot.total,
      processed: snapshot.processed,
      succeeded: snapshot.succeeded,
      failed: snapshot.failed,
      skipped: snapshot.skipped,
      currentStep: snapshot.currentStep,
    );
  }
}

/// 从 spool progress 文件轮询进度的服务。
class SpoolProgressNotifier {
  SpoolProgressNotifier._();
  static final SpoolProgressNotifier instance = SpoolProgressNotifier._();

  final ValueNotifier<SpoolProgress> progress =
      ValueNotifier<SpoolProgress>(SpoolProgress.idle());

  Timer? _poller;
  String? _currentJobId;
  int _lastVersion = 0;
  static const _pendingManifestJobIdKey = 'spool_pending_manifest_job_id';
  bool _checkDoneMarkerFirst = true;

  /// 开始轮询指定 job 的进度。
  void startPolling(String jobId) {
    _currentJobId = jobId;
    _lastVersion = 0;
    _checkDoneMarkerFirst = true;
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(milliseconds: 800), (_) {
      unawaited(_poll());
    });
    unawaited(_poll());
  }

  /// 停止轮询。
  void stopPolling() {
    _poller?.cancel();
    _poller = null;
    _currentJobId = null;
    progress.value = SpoolProgress.idle();
  }

  /// 恢复轮询（app 重启后通过 SharedPreferences 找到上次的 jobId）。
  Future<void> tryResumePolling() async {
    final prefs = await SharedPreferences.getInstance();
    final jobId = prefs.getString(_pendingManifestJobIdKey);
    if (jobId != null && jobId.isNotEmpty) {
      final spool = AnalysisSpoolService.instance;
      if (!await spool.hasDoneMarker(jobId)) {
        startPolling(jobId);
      }
    }
  }

  Future<void> _poll() async {
    final jobId = _currentJobId;
    if (jobId == null) return;

    final spool = AnalysisSpoolService.instance;

    // 优先检查 done.marker
    if (_checkDoneMarkerFirst && await spool.hasDoneMarker(jobId)) {
      progress.value = SpoolProgress(
        jobId: jobId,
        status: 'finished',
        done: true,
      );
      _poller?.cancel();
      _poller = null;
      return;
    }
    _checkDoneMarkerFirst = false;

    // 读取进度文件
    final snapshot = await spool.readProgress(jobId);
    if (snapshot == null) return;

    final spoolVersion = await spool.readSpoolVersion();
    final currentVersion = spoolVersion?.version ?? 0;
    if (currentVersion <= _lastVersion) return;
    _lastVersion = currentVersion;

    progress.value = SpoolProgress.fromSnapshot(snapshot);

    if (snapshot.status == 'finished' || snapshot.status == 'stopped') {
      _poller?.cancel();
      _poller = null;
    }
  }
}
