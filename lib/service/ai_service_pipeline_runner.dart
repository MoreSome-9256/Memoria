/// AI 管线执行器，负责按步骤调度单张照片的分析任务。

part of 'ai_service.dart';

class _AiPipelineRunner {
  _AiPipelineRunner({
    required AIService service,
    required this.batchSize,
    required this.maxPhotos,
  }) : _service = service;

  final AIService _service;
  final int batchSize;
  final int? maxPhotos;

  ValueNotifier<AIAnalysisProgress> get _progressNotifier =>
      _service._progressNotifier;
  JunkPhotoFilterService get _junkPhotoFilterService =>
      _service._junkPhotoFilterService;
  bool get _isAnalyzing => _service._isAnalyzing;
  set _isAnalyzing(bool value) => _service._isAnalyzing = value;
  bool get _pauseRequested => _service._pauseRequested;
  set _pauseRequested(bool value) => _service._pauseRequested = value;
  bool get _stopRequested => _service._stopRequested;
  set _stopRequested(bool value) => _service._stopRequested = value;
  int get _inflightCount => _service._inflightCount;
  set _inflightCount(int value) => _service._inflightCount = value;
  Completer<void>? get _analysisCompleter => _service._analysisCompleter;
  set _analysisCompleter(Completer<void>? value) =>
      _service._analysisCompleter = value;

  Future<void> _setManualStopPending(bool value) =>
      _service._setManualStopPending(value);
  Future<void> _persistRuntimeState({
    required bool isActive,
    int? total,
    int? completed,
    int? failed,
  }) {
    return _service._persistRuntimeState(
      isActive: isActive,
      total: total,
      completed: completed,
      failed: failed,
    );
  }

  Future<bool> _waitIfPaused() => _service._waitIfPaused();
  bool _consumeJunkFilterBypassForPhoto(int photoId) =>
      _service._consumeJunkFilterBypassForPhoto(photoId);
  int _resolveWorkerCount(int workItems) =>
      _service._resolveWorkerCount(workItems);
  String _formatWorkerWarmupStatus(List<int> readyWorkers, int totalWorkers) =>
      _service._formatWorkerWarmupStatus(readyWorkers, totalWorkers);
  Future<_PhotoProcessResult> _processSinglePhoto(
    _AiPhotoProcessingRequest request,
  ) => _service._processSinglePhoto(request);

  Future<_PhotoProcessResult> _applyPhotoProcessResult(
    _PhotoProcessResult result, {
    required MobileClipBackend selectedBackend,
  }) => _service._applyPhotoProcessResult(
    result,
    selectedBackend: selectedBackend,
  );

  void clearPendingJunkCleanupReport() =>
      _service.clearPendingJunkCleanupReport();
  void replacePendingJunkCleanupReport(JunkPhotoCleanupReport? report) =>
      _service.replacePendingJunkCleanupReport(report);

  Future<void> run() async {
    await _setManualStopPending(false);
    if (_isAnalyzing) {
      debugPrint('⏭️ AI 打标任务已在运行，跳过重复启动');
      return;
    }

    await _persistRuntimeState(isActive: true);

    _isAnalyzing = true;
    _pauseRequested = false;
    _stopRequested = false;
    _inflightCount = 0;
    _analysisCompleter = Completer<void>();
    clearPendingJunkCleanupReport();
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    final mobileClipEmbeddingService = MobileClipEmbeddingService();
    final mobileClipTagService = MobileClipTagService();
    final photoCaptionService = PhotoCaptionService();
    final facePipelineService = FacePipelineService();
    final ocrService = OcrService();
    final appAiSettings = await AppAiSettingsService.instance.load();
    OcrPolicy.setRuntimeEnabled(appAiSettings.ocrEnabled);
    await AiBackgroundTaskService.instance.startIfAllowed(
      title: 'Memoria 正在分析媒体',
      text: '只处理你手动添加的照片和视频',
    );

    final pendingQ = photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(false))
        .build();
    final pendingCount = pendingQ.count();
    pendingQ.close();
    final targetTotal = math.min(pendingCount, maxPhotos ?? pendingCount);
    int? processingStartedAtMs;
    int elapsedMs() {
      final startedAtMs = processingStartedAtMs;
      if (startedAtMs == null) {
        return 0;
      }
      return DateTime.now().millisecondsSinceEpoch - startedAtMs;
    }

    if (targetTotal <= 0) {
      _progressNotifier.value = AIAnalysisProgress.idle();
      _isAnalyzing = false;
      await _persistRuntimeState(isActive: false);
      if (_analysisCompleter != null && !_analysisCompleter!.isCompleted) {
        _analysisCompleter!.complete();
      }
      _analysisCompleter = null;
      return;
    }

    await mobileClipEmbeddingService.beginWorkflowSession();
    await mobileClipTagService.beginWorkflowSession();

    final selectedBackend = await mobileClipEmbeddingService
        .getSelectedBackend();
    _progressNotifier.value = AIAnalysisProgress.running(
      total: targetTotal,
      completed: 0,
      failed: 0,
      currentStep: '准备开始 AI 打标 (${selectedBackend.label})',
      elapsedMs: 0,
    );

    await Future<void>.delayed(const Duration(milliseconds: 120));
    _progressNotifier.value = AIAnalysisProgress.running(
      total: targetTotal,
      completed: 0,
      failed: 0,
      currentStep: '即将开始按需加载模型并分析图片',
      elapsedMs: elapsedMs(),
    );

    final faceOptions = FaceDetectorOptions(
      enableClassification: true,
      enableTracking: false,
    );

    var totalAnalyzed = 0;
    final affectedEventIds = <int>{};
    var failedCount = 0;
    var processedCount = 0;
    var scheduledCount = 0;
    final junkCandidates = <JunkPhotoCleanupCandidate>[];
    final attemptedPhotoIds = <int>{};
    final recentDurationsMs = ListQueue<int>();
    final pipelineProfiler = _AiPipelineRunProfiler(
      summaryEvery: math.max(4, math.min(batchSize, 8)),
    );
    var producerDone = false;
    var inflightCount = 0;
    var activeWorkerCount = 1;
    var engineBootstrapped = false;
    var warmUpCompleted = 0;
    var warmUpTotal = 0;
    var junkReportPublished = false;
    void publishJunkReportIfNeeded() {
      if (junkReportPublished || junkCandidates.isEmpty) {
        return;
      }
      junkReportPublished = true;
      replacePendingJunkCleanupReport(
        JunkPhotoCleanupReport.fromCandidates(junkCandidates),
      );
    }

    final baselineWorkItems = math.max(1, math.min(batchSize, targetTotal));
    final maxWorkerCount = _resolveWorkerCount(
      math.max(baselineWorkItems, targetTotal),
    );

    try {
      if (!engineBootstrapped) {
        const warmUpMainSteps = 3;
        warmUpTotal = warmUpMainSteps + maxWorkerCount + 1;
        warmUpCompleted = 0;

        warmUpCompleted++;
        _progressNotifier.value = AIAnalysisProgress.running(
          total: targetTotal,
          completed: processedCount,
          failed: failedCount,
          currentStep: '正在预热引擎 (1/3)：加载图像模型 ${selectedBackend.label}',
          elapsedMs: elapsedMs(),
          warmUpCompleted: warmUpCompleted,
          warmUpTotal: warmUpTotal,
        );
        await mobileClipEmbeddingService.warmUpBackend(selectedBackend);

        warmUpCompleted++;
        _progressNotifier.value = AIAnalysisProgress.running(
          total: targetTotal,
          completed: processedCount,
          failed: failedCount,
          currentStep: '正在预热引擎 (2/3)：加载标签语义模型',
          elapsedMs: elapsedMs(),
          warmUpCompleted: warmUpCompleted,
          warmUpTotal: warmUpTotal,
        );
        await mobileClipTagService.warmUp();

        warmUpCompleted++;
        _progressNotifier.value = AIAnalysisProgress.running(
          total: targetTotal,
          completed: processedCount,
          failed: failedCount,
          currentStep: '正在预热引擎 (3/3)：加载低价值过滤模板',
          elapsedMs: elapsedMs(),
          warmUpCompleted: warmUpCompleted,
          warmUpTotal: warmUpTotal,
        );
        await _junkPhotoFilterService.warmUp();

        final readyWorkers = <int>[];
        for (var index = 1; index <= maxWorkerCount; index++) {
          readyWorkers.add(index);
          warmUpCompleted++;
          _progressNotifier.value = AIAnalysisProgress.running(
            total: targetTotal,
            completed: processedCount,
            failed: failedCount,
            currentStep:
                '正在预热并行引擎：${_formatWorkerWarmupStatus(readyWorkers, maxWorkerCount)}',
            elapsedMs: elapsedMs(),
            warmUpCompleted: warmUpCompleted,
            warmUpTotal: warmUpTotal,
          );
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }

        activeWorkerCount = 1;

        warmUpCompleted++;
        _progressNotifier.value = AIAnalysisProgress.running(
          total: targetTotal,
          completed: processedCount,
          failed: failedCount,
          currentStep:
              '引擎预热完成：${_formatWorkerWarmupStatus(readyWorkers, maxWorkerCount)}，初始并发 $activeWorkerCount / $maxWorkerCount',
          elapsedMs: elapsedMs(),
          warmUpCompleted: warmUpCompleted,
          warmUpTotal: warmUpTotal,
        );
        engineBootstrapped = true;
      }

      debugPrint(
        '🤖 启动常驻 worker pool，max=$maxWorkerCount，active=$activeWorkerCount，目标=$targetTotal',
      );

      Future<void> produceWork() async {
        try {
          while (true) {
            final shouldContinue = await _waitIfPaused();
            if (!shouldContinue || _stopRequested) {
              break;
            }

            if (scheduledCount >= targetTotal) {
              break;
            }

            final remainingToSchedule = targetTotal - scheduledCount;
            final currentBatchSize = math.min(batchSize, remainingToSchedule);
            final maxBuffered = math.max(
              maxWorkerCount * 2,
              currentBatchSize * 2,
            );
            if (_service._analysisQueue.length >= maxBuffered) {
              await Future<void>.delayed(const Duration(milliseconds: 35));
              continue;
            }

            final pendingFetchWatch = Stopwatch()..start();
            var candidateLimit = math.max(
              currentBatchSize * 4,
              maxBuffered * 2,
            );
            var fetchedCount = 0;
            final photosToAnalyze = <PhotoEntity>[];
            while (true) {
              final pendingQ = photoBox
                  .query(PhotoEntity_.isAiAnalyzed.equals(false))
                  .order(PhotoEntity_.timestamp, flags: Order.descending)
                  .build();
              final fetchedCandidates = pendingQ
                  .find()
                  .take(candidateLimit)
                  .toList(growable: false);
              pendingQ.close();
              fetchedCount = fetchedCandidates.length;

              photosToAnalyze
                ..clear()
                ..addAll(
                  fetchedCandidates
                      .where(
                        (photo) =>
                            !attemptedPhotoIds.contains(photo.id) &&
                            !_service._analysisQueuedPhotoIds.contains(photo.id),
                      )
                      .take(currentBatchSize),
                );

              final exhaustedWindow = fetchedCandidates.length < candidateLimit;
              if (photosToAnalyze.isNotEmpty || exhaustedWindow) {
                break;
              }

              candidateLimit = math.min(candidateLimit * 2, targetTotal * 2);
            }
            pendingFetchWatch.stop();
            pipelineProfiler.recordPendingFetch(
              fetchMs: pendingFetchWatch.elapsedMicroseconds / 1000.0,
              fetchedCandidates: fetchedCount,
              scheduledPhotos: photosToAnalyze.length,
            );

            if (photosToAnalyze.isEmpty) {
              break;
            }

            for (final photo in photosToAnalyze) {
              _service._analysisQueue.addLast(photo);
              _service._analysisQueuedPhotoIds.add(photo.id);
            }
            scheduledCount += photosToAnalyze.length;

            _progressNotifier.value = AIAnalysisProgress.running(
              total: targetTotal,
              completed: processedCount,
              failed: failedCount,
              currentStep: '任务已入队 $scheduledCount / $targetTotal，等待 workers 处理',
              elapsedMs: elapsedMs(),
              warmUpCompleted: warmUpCompleted,
              warmUpTotal: warmUpTotal,
            );
          }
        } finally {
          producerDone = true;
        }
      }

      Future<void> tuneActiveWorkerCount() async {
        var lastAdjustedAtMs = 0;
        while (true) {
          if (_stopRequested) {
            break;
          }

          if (producerDone && _service._analysisQueue.isEmpty && inflightCount <= 0) {
            break;
          }

          await Future<void>.delayed(const Duration(milliseconds: 450));

          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - lastAdjustedAtMs < 900) {
            continue;
          }

          final backlog = _service._analysisQueue.length;
          final currentActive = activeWorkerCount;
          final averageDurationMs = recentDurationsMs.isEmpty
              ? null
              : (recentDurationsMs.reduce((a, b) => a + b) /
                        recentDurationsMs.length)
                    .round();

          var nextActive = currentActive;
          final canScaleUp = currentActive < maxWorkerCount;
          final canScaleDown = currentActive > 1;

          if (backlog >= currentActive * 2 && canScaleUp) {
            nextActive = currentActive + 1;
          } else if (backlog == 0 &&
              inflightCount <= currentActive - 1 &&
              canScaleDown) {
            nextActive = currentActive - 1;
          } else if (averageDurationMs != null &&
              averageDurationMs > 5200 &&
              backlog <= currentActive &&
              canScaleDown) {
            nextActive = currentActive - 1;
          } else if (averageDurationMs != null &&
              averageDurationMs < 1800 &&
              backlog > currentActive &&
              canScaleUp) {
            nextActive = currentActive + 1;
          }

          if (nextActive == currentActive) {
            continue;
          }

          activeWorkerCount = nextActive;
          lastAdjustedAtMs = nowMs;
          debugPrint(
            '⚙️ 自适应并发调节: active=$activeWorkerCount/$maxWorkerCount backlog=$backlog inflight=$inflightCount avgMs=${averageDurationMs ?? -1}',
          );
        }
      }

      final sharedFaceDetector = appAiSettings.faceAnalysisEnabled
          ? FaceDetector(options: faceOptions)
          : null;
      final faceDetectorLock = _SimpleMutex();

      final workers = List<Future<void>>.generate(maxWorkerCount, (
        workerIndex,
      ) async {
        try {
          while (true) {
            final shouldContinue = await _waitIfPaused();
            if (!shouldContinue || _stopRequested) {
              break;
            }

            if (workerIndex >= activeWorkerCount) {
              if (producerDone && _service._analysisQueue.isEmpty && inflightCount <= 0) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 45));
              continue;
            }

            PhotoEntity? photo;
            if (_service._analysisQueue.isNotEmpty) {
              photo = _service._analysisQueue.removeFirst();
              _service._analysisQueuedPhotoIds.remove(photo.id);
              attemptedPhotoIds.add(photo.id);
            }

            if (photo == null) {
              if (producerDone) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 30));
              continue;
            }

            processingStartedAtMs ??= DateTime.now().millisecondsSinceEpoch;
            final skipJunkFilter = _consumeJunkFilterBypassForPhoto(photo.id);
            final photoStartedAtMs = DateTime.now().millisecondsSinceEpoch;
            inflightCount++;
            _inflightCount = inflightCount;

            _progressNotifier.value = AIAnalysisProgress.running(
              total: targetTotal,
              completed: processedCount,
              failed: failedCount,
              currentStep:
                  '并行处理中 (worker ${workerIndex + 1}) 第 ${processedCount + 1} / $targetTotal 张',
              elapsedMs: elapsedMs(),
              warmUpCompleted: warmUpCompleted,
              warmUpTotal: warmUpTotal,
            );

            try {
              final result = await _applyPhotoProcessResult(
                await _processSinglePhoto(
                  _AiPhotoProcessingRequest(
                    photo: photo,
                    selectedBackend: selectedBackend,
                    mobileClipEmbeddingService: mobileClipEmbeddingService,
                    mobileClipTagService: mobileClipTagService,
                    photoCaptionService: photoCaptionService,
                    facePipelineService: facePipelineService,
                    ocrService: ocrService,
                    faceDetector: sharedFaceDetector,
                    junkPhotoFilterService: _junkPhotoFilterService,
                    skipJunkFilter: skipJunkFilter,
                    stopRequested: _stopRequested,
                    ocrEnabled: appAiSettings.ocrEnabled,
                    faceAnalysisEnabled: appAiSettings.faceAnalysisEnabled,
                    faceDetectorLock: faceDetectorLock,
                  ),
                ),
                selectedBackend: selectedBackend,
              );

              final spentMs =
                  DateTime.now().millisecondsSinceEpoch - photoStartedAtMs;
              result.profile.wallMs = spentMs.toDouble();
              pipelineProfiler.recordPhoto(result.profile);
              if (recentDurationsMs.length >= 18) {
                recentDurationsMs.removeFirst();
              }
              recentDurationsMs.addLast(spentMs);

              if (result.didSucceed) {
                totalAnalyzed++;
                if (result.junkCandidate != null) {
                  junkCandidates.add(result.junkCandidate!);
                }
                if (result.eventId != null) {
                  affectedEventIds.add(result.eventId!);
                }
              } else {
                failedCount++;
              }

              processedCount++;
            } finally {
              inflightCount = math.max(0, inflightCount - 1);
              _inflightCount = inflightCount;
            }

            if (_stopRequested) {
              _progressNotifier.value = AIAnalysisProgress.stopping(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: '正在结束本轮打标…',
                elapsedMs: elapsedMs(),
                warmUpCompleted: warmUpCompleted,
                warmUpTotal: warmUpTotal,
              );
            } else if (_pauseRequested) {
              _progressNotifier.value = AIAnalysisProgress.paused(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: '已暂停，随时可以继续',
                elapsedMs: elapsedMs(),
                warmUpCompleted: warmUpCompleted,
                warmUpTotal: warmUpTotal,
              );
            } else {
              _progressNotifier.value = AIAnalysisProgress.running(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: processedCount >= targetTotal
                    ? '正在收尾整理结果'
                    : '已完成 $processedCount / $targetTotal 张 (并发 $activeWorkerCount / $maxWorkerCount)',
                elapsedMs: elapsedMs(),
                warmUpCompleted: warmUpCompleted,
                warmUpTotal: warmUpTotal,
              );
            }

            if (_stopRequested) {
              break;
            }
          }
        } finally {
          // FaceDetector is shared; closed after all workers complete
        }
      });

      await Future.wait(<Future<void>>[
        produceWork(),
        tuneActiveWorkerCount(),
        ...workers,
      ]);
      await sharedFaceDetector?.close();

      publishJunkReportIfNeeded();

      if (affectedEventIds.isNotEmpty) {
        await EventService().refreshEventSmartInfo(affectedEventIds.toList());
      }
      debugPrint("✅ AI 分析完成，总计处理: $totalAnalyzed 张");
    } finally {
      await AiBackgroundTaskService.instance.stop();
      pipelineProfiler.logFinalSummary();
      await mobileClipTagService.endWorkflowSession();
      await mobileClipEmbeddingService.endWorkflowSession();
      publishJunkReportIfNeeded();

      final remainingQ = photoBox
          .query(PhotoEntity_.isAiAnalyzed.equals(false))
          .build();
      final remainingPending = remainingQ.count();
      remainingQ.close();
      if (remainingPending > 0 && !_stopRequested) {
        _progressNotifier.value = AIAnalysisProgress.paused(
          total: remainingPending,
          completed: 0,
          failed: 0,
          currentStep: _stopRequested
              ? '已暂停，剩余 $remainingPending 张待打标'
              : '本轮结束，剩余 $remainingPending 张待打标，点击继续',
          elapsedMs: elapsedMs(),
          warmUpCompleted: warmUpCompleted,
          warmUpTotal: warmUpTotal,
        );
      } else {
        _progressNotifier.value = AIAnalysisProgress.idle();
      }

      _isAnalyzing = false;
      _pauseRequested = false;
      _stopRequested = false;
      _inflightCount = 0;
      await _persistRuntimeState(isActive: false);
      if (_analysisCompleter != null && !_analysisCompleter!.isCompleted) {
        _analysisCompleter!.complete();
      }
      _analysisCompleter = null;
    }
  }
}
