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
            currentStep: progress.currentStep,
            elapsedMs: progress.elapsedMs,
            warmUpCompleted: progress.warmUpCompleted,
            warmUpTotal: progress.warmUpTotal,
            isPaused: progress.isPaused,
            isStopping: progress.isStopping,
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

  void _startRuntimeProgressPolling() {
    _runtimeProgressPoller ??= Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => unawaited(_refreshProgressFromRuntimeState()),
    );
    unawaited(_refreshProgressFromRuntimeState());
    unawaited(SpoolProgressNotifier.instance.tryResumePolling());
  }

  Future<void> _refreshProgressFromRuntimeState() async {
    if (_isAnalyzing) {
      return;
    }

    // 1. 检查 spool 是否有活跃任务
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJobId = prefs.getString('spool_pending_manifest_job_id');
      if (pendingJobId != null && pendingJobId.isNotEmpty) {
        final spool = AnalysisSpoolService.instance;
        if (await spool.hasDoneMarker(pendingJobId)) {
          // 已完成但未消费的 job — 尽快消费
          unawaited(consumeSpoolResults(pendingJobId));
        } else {
          final manifest = await spool.readManifest(pendingJobId);
          if (manifest != null) {
            final snapshot = await spool.readProgress(pendingJobId);
            final processed = snapshot?.processed ?? 0;
            final isPaused = snapshot?.status == 'paused';
            _progressNotifier.value = AIAnalysisProgress(
              isRunning: !isPaused,
              isPaused: isPaused,
              isStopping: false,
              total: manifest.totalItems,
              completed: processed,
              failed: snapshot?.failed ?? 0,
              currentStep: isPaused
                  ? '后台分析已暂停'
                  : '后台分析中 $processed/${manifest.totalItems}',
              elapsedMs: 0,
            );
            return;
          }
        }
      }
    } catch (_) {}

    // 2. Fallback 到 SharedPreferences 历史
    final snapshot = await _readRuntimeSnapshot();
    if (!snapshot.isActive || snapshot.total <= 0) {
      if (_progressNotifier.value.isVisible) {
        _progressNotifier.value = AIAnalysisProgress.idle();
      }
      return;
    }
    _progressNotifier.value = AIAnalysisProgress(
      isRunning: !snapshot.isPaused && !snapshot.isStopping,
      isPaused: snapshot.isPaused,
      isStopping: snapshot.isStopping,
      total: snapshot.total,
      completed: snapshot.completed,
      failed: snapshot.failed,
      currentStep: snapshot.currentStep,
      elapsedMs: snapshot.elapsedMs,
      warmUpCompleted: snapshot.warmUpCompleted,
      warmUpTotal: snapshot.warmUpTotal,
    );
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

    // 1. 检查 spool 中是否有进行中的任务
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJobId = prefs.getString('spool_pending_manifest_job_id');
      if (pendingJobId != null && pendingJobId.isNotEmpty) {
        final spool = AnalysisSpoolService.instance;
        if (await spool.hasDoneMarker(pendingJobId)) {
          debugPrint('[spool] 检测到已完成的任务 jobId=$pendingJobId，开始消费');
          await consumeSpoolResults(pendingJobId);
        } else {
          // 有进行中的任务，显示进度而不是干预
          final manifest = await spool.readManifest(pendingJobId);
          if (manifest != null) {
            final snapshot = await spool.readProgress(pendingJobId);
            final processed = snapshot?.processed ?? 0;
            _progressNotifier.value = AIAnalysisProgress.running(
              total: manifest.totalItems,
              completed: processed,
              failed: snapshot?.failed ?? 0,
              currentStep: '后台分析中 $processed/${manifest.totalItems}',
              elapsedMs: 0,
            );
            return;
          }
        }
      }
    } catch (error) {
      debugPrint('[spool] spool 检查失败: $error');
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
    String? currentStep,
    int? elapsedMs,
    int? warmUpCompleted,
    int? warmUpTotal,
    bool? isPaused,
    bool? isStopping,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AIService._runtimeActiveKey, isActive);
    if (!isActive) {
      await prefs.remove(AIService._runtimeHeartbeatAtKey);
      await prefs.remove(AIService._runtimeTotalKey);
      await prefs.remove(AIService._runtimeCompletedKey);
      await prefs.remove(AIService._runtimeFailedKey);
      await prefs.remove(AIService._runtimeStepKey);
      await prefs.remove(AIService._runtimeElapsedMsKey);
      await prefs.remove(AIService._runtimeWarmUpCompletedKey);
      await prefs.remove(AIService._runtimeWarmUpTotalKey);
      await prefs.remove(AIService._runtimePausedKey);
      await prefs.remove(AIService._runtimeStoppingKey);
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
    if (currentStep != null) {
      await prefs.setString(AIService._runtimeStepKey, currentStep);
    }
    if (elapsedMs != null) {
      await prefs.setInt(AIService._runtimeElapsedMsKey, elapsedMs);
    }
    if (warmUpCompleted != null) {
      await prefs.setInt(
        AIService._runtimeWarmUpCompletedKey,
        warmUpCompleted,
      );
    }
    if (warmUpTotal != null) {
      await prefs.setInt(AIService._runtimeWarmUpTotalKey, warmUpTotal);
    }
    if (isPaused != null) {
      await prefs.setBool(AIService._runtimePausedKey, isPaused);
    }
    if (isStopping != null) {
      await prefs.setBool(AIService._runtimeStoppingKey, isStopping);
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
      currentStep:
          prefs.getString(AIService._runtimeStepKey) ?? '后台 AI 正在处理',
      elapsedMs: prefs.getInt(AIService._runtimeElapsedMsKey) ?? 0,
      warmUpCompleted:
          prefs.getInt(AIService._runtimeWarmUpCompletedKey) ?? 0,
      warmUpTotal: prefs.getInt(AIService._runtimeWarmUpTotalKey) ?? 0,
      isPaused: prefs.getBool(AIService._runtimePausedKey) ?? false,
      isStopping: prefs.getBool(AIService._runtimeStoppingKey) ?? false,
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
