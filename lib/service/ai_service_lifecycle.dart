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

    if (progress.isVisible) {
      final title = progress.isStopping
          ? 'AI 打标正在结束'
          : progress.isPaused
          ? 'AI 打标已暂停'
          : 'AI 打标进行中';
      final body =
          '${progress.completed}/${progress.total}${progress.failed > 0 ? ' · 失败 ${progress.failed}' : ''} · ${progress.currentStep}';
      unawaited(AiBackgroundTaskService.instance.updateNotification(
        title: title,
        text: body,
      ));
    }

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
      unawaited(AiBackgroundTaskService.instance.stop());
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
    await prefs.remove(AIService._autoResumeKey);
  }

  void markJunkCandidatesAsKept(Iterable<int> photoIds) {
    final normalized = photoIds.where((id) => id > 0);
    _junkFilterBypassPhotoIds.addAll(normalized);
  }

  void unmarkJunkCandidatesAsKept(Iterable<int> photoIds) {
    for (final photoId in photoIds.where((id) => id > 0)) {
      _junkFilterBypassPhotoIds.remove(photoId);
    }
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
      unawaited(_startForegroundTaskAndRun());
    }
  }

  void stopAnalysis() {
    final current = _progressNotifier.value;
    _clearPendingCaptionTasks();
    _clearAnalysisQueue();
    unawaited(AiBackgroundTaskService.instance.stop());
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

  Future<void> endCurrentRoundSafely({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    _clearPendingCaptionTasks();
    stopAnalysis();
    await stopAnalysisAndWait(timeout: timeout);
    await _waitForCaptionTasksToDrain(timeout: const Duration(seconds: 8));
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

    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final pendingQ = photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(false))
        .build();
    final pending = pendingQ.count();
    pendingQ.close();
    if (pending <= 0) {
      await AIProgressNotificationService().clearProgressNotificationSurfaces();
      await _persistRuntimeState(isActive: false);
      return;
    }

    final runtimeSnapshot = await _readRuntimeSnapshot();
    final restoredCompleted = runtimeSnapshot.completed.clamp(0, pending);
    final manuallyStopped = await _readManualStopPending();

    // 检查自动续跑设置
    final settings = await AppAiSettingsService.instance.load();
    if (settings.autoResumeAnalysis && !manuallyStopped) {
      debugPrint('自动续跑 AI 分析，剩余 $pending 张');
      _progressNotifier.value = AIAnalysisProgress.running(
        total: pending,
        completed: restoredCompleted,
        failed: runtimeSnapshot.failed,
        currentStep: '自动恢复上次分析任务…',
        elapsedMs: 0,
      );
      unawaited(_startForegroundTaskAndRun());
      return;
    }

    debugPrint('检测到 $pending 张未完成照片，等待用户手动继续');
    _progressNotifier.value = AIAnalysisProgress.paused(
      total: pending,
      completed: restoredCompleted,
      failed: runtimeSnapshot.failed,
      currentStep: manuallyStopped
          ? '有未完成任务，点击继续开始'
          : '检测到上次任务，点击继续后恢复',
      elapsedMs: 0,
    );
  }

  Future<void> _runFullAiPipelineInBackground() async {
    try {
      await analyzePhotosInBackground();
    } catch (error) {
      debugPrint('❌ 自动续跑 AI 管线失败: $error');
      await stopAnalysisAndWait();
      debugPrint('⚠️ 自动续跑 AI 管线失败，已停止分析任务');
      debugPrint('⚠️ 请重新启动 AI 打标任务');
    }
  }

  Future<void> _startForegroundTaskAndRun() async {
    await analyzePhotosInBackground();
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

  Future<void> _waitForCaptionTasksToDrain({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (_activeCaptionTasks > 0) {
      if (DateTime.now().isAfter(deadline)) {
        debugPrint('⚠️ 等待 caption 任务结束超时，剩余=$_activeCaptionTasks');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }
}
