/// AI 服务生命周期控制模块，负责启动、暂停、恢复和停止分析流程。

part of 'ai_service.dart';

extension AIServiceLifecycle on AIService {
  void replacePendingJunkCleanupReport(JunkPhotoCleanupReport? report) {
    _junkCleanupReportNotifier.value = report;
  }

  void clearPendingJunkCleanupReport() {
    replacePendingJunkCleanupReport(null);
  }

  Future<void> setAutoResume(bool enabled) async {
    _autoResumeEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AIService._autoResumeKey, enabled);
  }

  void _syncProgressNotification() {
    final progress = _progressNotifier.value;
    unawaited(
      AIProgressNotificationService().syncProgress(
        isVisible: progress.isVisible,
        isRunning: progress.isRunning,
        isPaused: progress.isPaused,
        isStopping: progress.isStopping,
        completed: progress.completed,
        total: progress.total,
        failed: progress.failed,
        currentStep: progress.currentStep,
        fraction: progress.fraction,
      ),
    );

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (progress.isVisible) {
      if (nowMs - _lastRuntimeHeartbeatPersistAtMs >= 1500) {
        _lastRuntimeHeartbeatPersistAtMs = nowMs;
        unawaited(
          _persistRuntimeState(
            isActive: true,
            total: progress.total,
            completed: progress.completed,
            failed: progress.failed,
          ),
        );
      }
    } else {
      _lastRuntimeHeartbeatPersistAtMs = 0;
      unawaited(_persistRuntimeState(isActive: false));
    }
  }

  void _handleForegroundAction(String action) {
    debugPrint(
      '🎛️ 收到通知动作: $action (isAnalyzing=$_isAnalyzing, pauseRequested=$_pauseRequested, inflight=$_inflightCount)',
    );
    if (action == AIProgressNotificationService.actionPause) {
      pauseAnalysis();
      return;
    }
    if (action == AIProgressNotificationService.actionResume) {
      resumeAnalysis();
    }
  }

  Future<bool> getAutoResumePreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AIService._autoResumeKey) ?? false;
  }

  Future<void> loadAutoResumePreference() async {
    final prefs = await SharedPreferences.getInstance();
    _autoResumeEnabled = prefs.getBool(AIService._autoResumeKey) ?? false;
  }

  void markJunkCandidatesAsKept(Iterable<int> photoIds) {
    final normalized = photoIds.where((id) => id > 0);
    _junkFilterBypassPhotoIds.addAll(normalized);
  }

  bool _consumeJunkFilterBypassForPhoto(int photoId) {
    return _junkFilterBypassPhotoIds.remove(photoId);
  }

  void pauseAnalysis() {
    if (!_isAnalyzing || _pauseRequested) {
      debugPrint(
        '⏸️ 忽略暂停请求: isAnalyzing=$_isAnalyzing pauseRequested=$_pauseRequested',
      );
      return;
    }
    _pauseRequested = true;
    final current = _progressNotifier.value;
    if (current.isVisible) {
      final inflight = _inflightCount;
      _progressNotifier.value = current.copyWith(
        isRunning: false,
        isPaused: true,
        currentStep: inflight > 0 ? '暂停中，等待当前 $inflight 个任务收尾…' : '已暂停，随时可以继续',
      );
      debugPrint('⏸️ 已进入暂停请求态，当前在途任务: $inflight');
    }
  }

  void resumeAnalysis() {
    unawaited(_setManualStopPending(false));
    if (_isAnalyzing && !_pauseRequested) {
      debugPrint('▶️ 忽略继续请求：当前任务未暂停');
      return;
    }

    final current = _progressNotifier.value;

    // 常规暂停恢复：任务仍在运行，仅解除 pause gate。
    if (_isAnalyzing && _pauseRequested) {
      _pauseRequested = false;
      if (current.isVisible) {
        _progressNotifier.value = current.copyWith(
          isRunning: true,
          isPaused: false,
          currentStep: '继续后台打标中',
        );
      }
      return;
    }

    // 冷启动暂停态：应用重启后未自动恢复时，手动点击“继续”应直接拉起分析。
    if (!_isAnalyzing && current.isPaused && current.total > 0) {
      _pauseRequested = false;
      _stopRequested = false;
      _progressNotifier.value = current.copyWith(
        isRunning: true,
        isPaused: false,
        currentStep: '正在手动启动后台打标…',
      );
      unawaited(analyzePhotosInBackground());
    }
  }

  void stopAnalysis() {
    final current = _progressNotifier.value;
    if (!_isAnalyzing) {
      if (current.isPaused && current.total > 0) {
        _pauseRequested = false;
        _stopRequested = false;
        _progressNotifier.value = AIAnalysisProgress.idle();
        unawaited(_persistRuntimeState(isActive: false));
        unawaited(_setManualStopPending(true));
      }
      return;
    }
    _stopRequested = true;
    _pauseRequested = false;
    unawaited(_setManualStopPending(true));
    if (current.isVisible) {
      _progressNotifier.value = current.copyWith(
        isRunning: false,
        isPaused: false,
        isStopping: true,
        currentStep: '正在结束本轮打标…',
      );
    }
  }

  Future<void> stopAnalysisAndWait({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isAnalyzing) {
      return;
    }

    stopAnalysis();
    final analysisFuture = _analysisCompleter?.future;
    if (analysisFuture == null) {
      return;
    }

    try {
      await analysisFuture.timeout(timeout);
    } on TimeoutException {
      debugPrint('⚠️ 等待 AI 打标任务结束超时，继续执行后续流程');
    }
  }

  Future<void> resumePendingAnalysisIfNeeded() async {
    if (_isAnalyzing) {
      return;
    }

    await loadAutoResumePreference();

    final pending = await PhotoService().isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(false)
        .count();
    if (pending <= 0) {
      await AIProgressNotificationService().clearProgressNotificationSurfaces();
      await _persistRuntimeState(isActive: false);
      return;
    }

    final runtimeSnapshot = await _readRuntimeSnapshot();
    final runtimeActive = runtimeSnapshot.isActive;
    final restoredCompleted = runtimeSnapshot.completed.clamp(0, pending);
    final manuallyStopped = await _readManualStopPending();

    if (manuallyStopped) {
      _progressNotifier.value = AIAnalysisProgress.idle();
      return;
    }

    // 用户关闭自动恢复时，启动后只展示可手动恢复的暂停态，不自动续跑。
    if (!_autoResumeEnabled) {
      debugPrint('⏸️ 检测到 $pending 张未完成照片，但自动恢复已禁用，显示暂停状态');
      _progressNotifier.value = AIAnalysisProgress.paused(
        total: pending,
        completed: restoredCompleted,
        failed: runtimeSnapshot.failed,
        currentStep: runtimeActive ? '检测到上次任务，自动恢复已关闭，点击手动继续' : '已暂停 - 点击手动启动',
        elapsedMs: 0,
      );
      return;
    }

    if (runtimeActive) {
      _progressNotifier.value = AIAnalysisProgress.running(
        total: pending,
        completed: restoredCompleted,
        failed: runtimeSnapshot.failed,
        currentStep: '检测到上次打标任务，正在重连并恢复…',
        elapsedMs: 0,
      );
      debugPrint('🔁 检测到历史运行态(runtime=$runtimeActive)，尝试恢复 AI 打标');
      unawaited(_runFullAiPipelineInBackground());
      return;
    }

    debugPrint('🔁 检测到 $pending 张未完成照片，自动续跑 AI 打标任务');
    unawaited(_runFullAiPipelineInBackground());
  }

  Future<void> _runFullAiPipelineInBackground() async {
    try {
      await analyzePhotosInBackground();
    } catch (error) {
      debugPrint('❌ 自动续跑 AI 管线失败: $error');
      // 为了稳定，我们可以考虑清理掉未完成的状态，避免下次启动时再次触发续跑。然后提示用户，重新启动 AI 打标。
      await stopAnalysisAndWait();
      debugPrint('⚠️ 自动续跑 AI 管线失败，已停止分析任务');
      debugPrint('⚠️ 请重新启动 AI 打标任务');
    }
  }

  Future<void> _setManualStopPending(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AIService._manualStopPendingKey, value);
  }

  Future<bool> _readManualStopPending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AIService._manualStopPendingKey) ?? false;
  }

  Future<void> _persistRuntimeState({
    required bool isActive,
    int? total,
    int? completed,
    int? failed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AIService._runtimeActiveKey, isActive);
    if (!isActive) {
      await prefs.remove(AIService._runtimeHeartbeatAtKey);
      await prefs.remove(AIService._runtimeTotalKey);
      await prefs.remove(AIService._runtimeCompletedKey);
      await prefs.remove(AIService._runtimeFailedKey);
      return;
    }

    await prefs.setInt(
      AIService._runtimeHeartbeatAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (total != null) {
      await prefs.setInt(AIService._runtimeTotalKey, total);
    }
    if (completed != null) {
      await prefs.setInt(AIService._runtimeCompletedKey, completed);
    }
    if (failed != null) {
      await prefs.setInt(AIService._runtimeFailedKey, failed);
    }
  }

  Future<_RuntimeSnapshot> _readRuntimeSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getBool(AIService._runtimeActiveKey) ?? false;
    final heartbeatAtMs = prefs.getInt(AIService._runtimeHeartbeatAtKey) ?? 0;
    final ageMs = DateTime.now().millisecondsSinceEpoch - heartbeatAtMs;
    final recent =
        heartbeatAtMs > 0 && ageMs <= const Duration(hours: 1).inMilliseconds;
    return _RuntimeSnapshot(
      isActive: active && recent,
      total: prefs.getInt(AIService._runtimeTotalKey) ?? 0,
      completed: prefs.getInt(AIService._runtimeCompletedKey) ?? 0,
      failed: prefs.getInt(AIService._runtimeFailedKey) ?? 0,
    );
  }

  Future<bool> _waitIfPaused() async {
    while (_pauseRequested && !_stopRequested) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return !_stopRequested;
  }
}
