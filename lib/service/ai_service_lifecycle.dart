/// AI 服务生命周期控制模块，负责启动、暂停、恢复和停止分析流程。

part of 'ai_service.dart';

extension AIServiceLifecycle on AIService {
  void replacePendingJunkCleanupReport(JunkPhotoCleanupReport? report) {
    _junkCleanupReportNotifier.value = report;
  }

  void clearPendingJunkCleanupReport() {
    replacePendingJunkCleanupReport(null);
  }

  Future<JunkPhotoCleanupReport?> refreshJunkCleanupReportFromDatabase({
    bool replaceExisting = true,
  }) async {
    final current = latestJunkCleanupReport;
    if (!replaceExisting && current != null && current.hasCandidates) {
      return current;
    }
    final photos = await PhotoService().loadPendingJunkCandidatePhotos();
    if (photos.isEmpty) {
      clearPendingJunkCleanupReport();
      return null;
    }
    final candidates = <JunkPhotoCleanupCandidate>[];
    final recoveredReasonTagsByPhotoId = <int, List<String>>{};
    for (final photo in photos) {
      var reasons = JunkPhotoFilterService.hitsFromTags(
        photo.aiTags ?? const <String>[],
      );
      if (reasons.isEmpty && (photo.imageEmbedding?.isNotEmpty ?? false)) {
        final decision = await _junkPhotoFilterService.evaluatePhoto(
          imageEmbedding: photo.imageEmbedding!,
        );
        reasons = decision.hits;
        final reasonTags = JunkPhotoFilterService.reasonTagsForHits(reasons);
        if (reasonTags.isNotEmpty) {
          recoveredReasonTagsByPhotoId[photo.id] = reasonTags;
        }
      }
      candidates.add(
        JunkPhotoCleanupCandidate(
          photoId: photo.id,
          assetId: photo.assetId,
          path: photo.path,
          timestamp: photo.timestamp,
          reasons: reasons,
        ),
      );
    }
    if (recoveredReasonTagsByPhotoId.isNotEmpty) {
      for (final entry in recoveredReasonTagsByPhotoId.entries) {
        PhotoService().updatePhotoInTransaction(entry.key, (photo) {
          if (photo == null) return;
          final tags = <String>{...?photo.aiTags, ...entry.value};
          photo.aiTags = tags.toList(growable: false);
        });
      }
    }
    final report = JunkPhotoCleanupReport.fromCandidates(candidates);
    replacePendingJunkCleanupReport(report);
    return report;
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
          return;
        } else {
          final manifest = await spool.readManifest(pendingJobId);
          if (manifest != null) {
            final snapshot = await spool.readProgress(pendingJobId);
            final control = await spool.readControl(pendingJobId);
            final processed = snapshot?.processed ?? 0;
            final isPaused =
                control.pauseRequested || snapshot?.status == 'paused';
            final isStopping =
                control.stopRequested || snapshot?.status == 'stopping';
            final serviceRunning =
                await AiBackgroundTaskService.instance.isRunning;
            final shouldRestartWorker =
                !isPaused &&
                !isStopping &&
                !serviceRunning &&
                await _shouldAutoRestartSpoolWorker();
            final serviceOffline = !isPaused && !isStopping && !serviceRunning;
            final currentStep = serviceOffline && !shouldRestartWorker
                ? '后台服务未运行，任务已保留；点击继续后恢复'
                : snapshot != null && snapshot.currentStep.isNotEmpty
                ? snapshot.currentStep
                : isStopping
                ? '正在结束本轮，等待当前图片收尾'
                : isPaused
                ? '后台分析已暂停'
                : '后台分析中 $processed/${manifest.totalItems}';
            _publishProgressIfChanged(
              AIAnalysisProgress(
                isRunning:
                    !isPaused &&
                    !isStopping &&
                    (!serviceOffline || shouldRestartWorker),
                isPaused: isPaused || (serviceOffline && !shouldRestartWorker),
                isStopping: isStopping,
                total: manifest.totalItems,
                completed: processed,
                failed: snapshot?.failed ?? 0,
                currentStep: currentStep,
                elapsedMs: _elapsedMsForSpoolProgress(manifest, snapshot),
                warmUpCompleted: snapshot?.warmUpCompleted ?? 0,
                warmUpTotal: snapshot?.warmUpTotal ?? 0,
              ),
            );
            if (shouldRestartWorker) {
              debugPrint(
                '[spool] runtime poll 检测到前台服务离线，重新拉起 job=$pendingJobId',
              );
              await AiBackgroundTaskService.instance.startAnalysisWorker();
            }
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
    _publishProgressIfChanged(
      AIAnalysisProgress(
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
      ),
    );
  }

  Future<bool> getAutoResumePreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AIService._autoResumeKey) ?? false;
  }

  void _publishProgressIfChanged(AIAnalysisProgress next) {
    final current = _progressNotifier.value;
    if (current.isRunning == next.isRunning &&
        current.isPaused == next.isPaused &&
        current.isStopping == next.isStopping &&
        current.total == next.total &&
        current.completed == next.completed &&
        current.failed == next.failed &&
        current.currentStep == next.currentStep &&
        current.elapsedMs == next.elapsedMs &&
        current.warmUpCompleted == next.warmUpCompleted &&
        current.warmUpTotal == next.warmUpTotal) {
      return;
    }
    _progressNotifier.value = next;
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
    final current = _progressNotifier.value;
    if (!_isAnalyzing) {
      if (!current.isVisible || current.isPaused) {
        return;
      }
      _progressNotifier.value = current.copyWith(
        isRunning: false,
        isPaused: true,
        currentStep: '正在暂停后台分析…',
      );
      unawaited(_requestCurrentSpoolPause());
      return;
    }
    if (!_isAnalyzing || _pauseRequested) {
      debugPrint(
        '⏸️ 忽略暂停请求: isAnalyzing=$_isAnalyzing pauseRequested=$_pauseRequested',
      );
      return;
    }
    _pauseRequested = true;
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
    final current = _progressNotifier.value;
    if (!_isAnalyzing && current.isPaused && current.total > 0) {
      _pauseRequested = false;
      _stopRequested = false;
      _progressNotifier.value = current.copyWith(
        isRunning: true,
        isPaused: false,
        currentStep: '正在继续后台打标…',
      );
      unawaited(_resumeCurrentSpoolOrStart());
      return;
    }
    if (_isAnalyzing && !_pauseRequested) {
      debugPrint('▶️ 忽略继续请求：当前任务未暂停');
      return;
    }

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
    if (!_isAnalyzing) {
      unawaited(_setManualStopPending(true));
      if (current.isVisible) {
        _progressNotifier.value = current.copyWith(
          isRunning: false,
          isPaused: false,
          isStopping: true,
          currentStep: '正在结束本轮，等待当前图片收尾…',
        );
      }
      unawaited(_requestCurrentSpoolStop());
      return;
    }
    unawaited(AiBackgroundTaskService.instance.stop());
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
    stopAnalysis();
    await stopAnalysisAndWait(timeout: timeout);
    await _cleanupCurrentJobSpool(allowPartial: true);
    await AiBackgroundTaskService.instance.stop();
    _progressNotifier.value = AIAnalysisProgress.idle();
    await _persistRuntimeState(isActive: false);
  }

  Future<void> stopAnalysisAndWait({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isAnalyzing) {
      await _requestCurrentSpoolStop();
      final finished = await _waitForCurrentSpoolDone(timeout: timeout);
      if (!finished) {
        debugPrint('⚠️ 等待 spool 前台任务结束超时，准备消费已有阶段性结果');
      }
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
          // 有进行中的 spool 任务：恢复 UI；如果前台服务已被系统杀死，
          // 且任务不是暂停/结束态，则重新拉起 worker 继续同一个 manifest。
          final manifest = await spool.readManifest(pendingJobId);
          if (manifest != null) {
            final snapshot = await spool.readProgress(pendingJobId);
            final control = await spool.readControl(pendingJobId);
            final processed = snapshot?.processed ?? 0;
            final isPaused =
                control.pauseRequested || snapshot?.status == 'paused';
            final isStopping =
                control.stopRequested || snapshot?.status == 'stopping';
            final serviceRunning =
                await AiBackgroundTaskService.instance.isRunning;
            final shouldRestartWorker =
                !isPaused &&
                !isStopping &&
                !serviceRunning &&
                await _shouldAutoRestartSpoolWorker();
            final serviceOffline = !isPaused && !isStopping && !serviceRunning;
            final currentStep = serviceOffline && !shouldRestartWorker
                ? '后台服务未运行，任务已保留；点击继续后恢复'
                : snapshot != null && snapshot.currentStep.isNotEmpty
                ? snapshot.currentStep
                : isStopping
                ? '正在结束本轮，等待当前图片收尾'
                : isPaused
                ? '后台分析已暂停'
                : '后台分析中 $processed/${manifest.totalItems}';
            _publishProgressIfChanged(
              AIAnalysisProgress(
                isRunning:
                    !isPaused &&
                    !isStopping &&
                    (!serviceOffline || shouldRestartWorker),
                isPaused: isPaused || (serviceOffline && !shouldRestartWorker),
                isStopping: isStopping,
                total: manifest.totalItems,
                completed: processed,
                failed: snapshot?.failed ?? 0,
                currentStep: currentStep,
                elapsedMs: _elapsedMsForSpoolProgress(manifest, snapshot),
                warmUpCompleted: snapshot?.warmUpCompleted ?? 0,
                warmUpTotal: snapshot?.warmUpTotal ?? 0,
              ),
            );
            SpoolProgressNotifier.instance.startPolling(pendingJobId);
            if (shouldRestartWorker) {
              debugPrint(
                '[spool] pending job=$pendingJobId 未完成且前台服务不在线，重新拉起 worker',
              );
              await AiBackgroundTaskService.instance.startAnalysisWorker();
            }
            return;
          }
        }
      }
    } catch (error) {
      debugPrint('[spool] spool 检查失败: $error');
    }

    final pendingIds = PhotoService().loadPendingAnalysisCandidateIds();
    final pending = pendingIds.length;
    if (pending <= 0) {
      await refreshJunkCleanupReportFromDatabase();
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
      currentStep: manuallyStopped ? '有未完成任务，点击继续开始' : '检测到上次任务，点击继续后恢复',
      elapsedMs: 0,
    );
  }

  Future<void> _startForegroundTaskAndRun() async {
    if (PhotoService().countPendingAnalysisCandidates() <= 0) {
      return;
    }
    await analyzePhotosInBackground();
  }

  Future<void> _requestCurrentSpoolPause() async {
    final jobId = await _readPendingSpoolJobId();
    if (jobId == null) return;
    await AnalysisSpoolService.instance.requestPause(jobId);
  }

  Future<void> _requestCurrentSpoolStop() async {
    final jobId = await _readPendingSpoolJobId();
    if (jobId == null) return;
    await AnalysisSpoolService.instance.requestStop(jobId);
  }

  Future<bool> _shouldAutoRestartSpoolWorker() async {
    final settings = await AppAiSettingsService.instance.load();
    if (!settings.autoResumeAnalysis) {
      return false;
    }
    return !await _readManualStopPending();
  }

  Future<void> _resumeCurrentSpoolOrStart() async {
    final jobId = await _readPendingSpoolJobId();
    if (jobId == null) {
      await _startForegroundTaskAndRun();
      return;
    }
    final spool = AnalysisSpoolService.instance;
    if (await spool.hasDoneMarker(jobId)) {
      await consumeSpoolResults(jobId);
      return;
    }
    await spool.requestResume(jobId);
    SpoolProgressNotifier.instance.startPolling(jobId);
    await AiBackgroundTaskService.instance.startAnalysisWorker();
  }

  Future<bool> _waitForCurrentSpoolDone({required Duration timeout}) async {
    final jobId = await _readPendingSpoolJobId();
    if (jobId == null) return true;
    final spool = AnalysisSpoolService.instance;
    if (await spool.hasDoneMarker(jobId)) return true;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await spool.hasDoneMarker(jobId)) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return await spool.hasDoneMarker(jobId);
  }

  Future<void> _cleanupCurrentJobSpool({bool allowPartial = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jobId = prefs.getString('spool_pending_manifest_job_id');
      if (jobId == null || jobId.isEmpty) return;

      // 先消费未处理的 spool 结果，再清理
      await consumeSpoolResults(
        jobId,
        requireDoneMarker: !allowPartial,
        startNextPending: false,
        dismissUnfinishedItems: allowPartial,
      );
      debugPrint('[spool] 已消费并清理 job 文件和缓存 jobId=$jobId');
    } catch (e) {
      debugPrint('[spool] 清理 job 失败: $e');
      // 兜底：即使消费失败也强制删掉 job 文件
      try {
        final prefs = await SharedPreferences.getInstance();
        final jobId = prefs.getString('spool_pending_manifest_job_id');
        if (jobId != null && jobId.isNotEmpty) {
          await AnalysisSpoolService.instance.cleanupJob(jobId);
          await prefs.remove('spool_pending_manifest_job_id');
        }
      } catch (_) {}
    }
  }

  Future<String?> _readPendingSpoolJobId() async {
    final prefs = await SharedPreferences.getInstance();
    final jobId = prefs.getString('spool_pending_manifest_job_id');
    if (jobId == null || jobId.isEmpty) return null;
    return jobId;
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
      await prefs.setInt(AIService._runtimeWarmUpCompletedKey, warmUpCompleted);
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
      currentStep: prefs.getString(AIService._runtimeStepKey) ?? '后台 AI 正在处理',
      elapsedMs: prefs.getInt(AIService._runtimeElapsedMsKey) ?? 0,
      warmUpCompleted: prefs.getInt(AIService._runtimeWarmUpCompletedKey) ?? 0,
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
}

int _elapsedMsForSpoolProgress(
  AnalysisJobManifest manifest,
  AnalysisProgressSnapshot? snapshot,
) {
  final status = snapshot?.status;
  final endMs =
      status == 'paused' ||
          status == 'finished' ||
          status == 'stopped' ||
          status == 'failed'
      ? snapshot?.updatedAt ?? DateTime.now().millisecondsSinceEpoch
      : DateTime.now().millisecondsSinceEpoch;
  final startedAt = snapshot?.processingStartedAt;
  if (startedAt == null || startedAt <= 0) {
    return 0;
  }
  final elapsedMs = endMs - startedAt;
  if (elapsedMs <= 0) {
    return 0;
  }
  return elapsedMs;
}
