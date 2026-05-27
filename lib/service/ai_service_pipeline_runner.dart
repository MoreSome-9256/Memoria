/// AI 管线执行器，负责按步骤串行调度单张照片的分析任务。

part of 'ai_service.dart';

class _AiPipelineRunner {
  _AiPipelineRunner({
    required AIService service,
    required this.batchSize,
    required this.maxPhotos,
    required this.photoIds,
    required this.manageForegroundService,
  }) : _service = service;

  final AIService _service;
  final int batchSize;
  final int? maxPhotos;
  final List<int>? photoIds;
  final bool manageForegroundService;

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

    final requestedPhotoIds = photoIds
        ?.where((id) => id > 0)
        .toSet()
        .toList(growable: false);
    final pendingCount = _countPending(photoBox, requestedPhotoIds);
    final targetTotal = math.min(pendingCount, maxPhotos ?? pendingCount);
    final effectiveBatchSize = batchSize > 0
        ? math.min(math.max(1, batchSize), targetTotal)
        : math.max(1, targetTotal);
    int? processingStartedAtMs;
    int elapsedMs() {
      final startedAtMs = processingStartedAtMs;
      if (startedAtMs == null) return 0;
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
    var warmUpCompleted = 0;
    var warmUpTotal = 3;
    var totalAnalyzed = 0;
    final affectedEventIds = <int>{};
    var failedCount = 0;
    var processedCount = 0;
    final junkCandidates = <JunkPhotoCleanupCandidate>[];
    final attemptedPhotoIds = <int>{};
    final pipelineProfiler = _AiPipelineRunProfiler(
      summaryEvery: math.max(4, math.min(effectiveBatchSize, 8)),
    );
    var junkReportPublished = false;

    void publishJunkReportIfNeeded() {
      if (junkReportPublished || junkCandidates.isEmpty) return;
      junkReportPublished = true;
      replacePendingJunkCleanupReport(
        JunkPhotoCleanupReport.fromCandidates(junkCandidates),
      );
    }

    FaceDetector? sharedFaceDetector;

    try {
      _progressNotifier.value = AIAnalysisProgress.running(
        total: targetTotal,
        completed: 0,
        failed: 0,
        currentStep: '正在预热引擎 (1/$warmUpTotal)：加载图像模型 ${selectedBackend.label}',
        elapsedMs: 0,
        warmUpCompleted: warmUpCompleted,
        warmUpTotal: warmUpTotal,
      );
      await mobileClipEmbeddingService.warmUpBackend(selectedBackend);
      warmUpCompleted++;

      _progressNotifier.value = AIAnalysisProgress.running(
        total: targetTotal,
        completed: processedCount,
        failed: failedCount,
        currentStep: '正在预热引擎 (2/$warmUpTotal)：加载标签语义模型',
        elapsedMs: elapsedMs(),
        warmUpCompleted: warmUpCompleted,
        warmUpTotal: warmUpTotal,
      );
      await mobileClipTagService.warmUp(
        onProgress: (completed, total, message) async {
          warmUpTotal = 2 + math.max(1, total);
          warmUpCompleted = 1 + completed;
          _progressNotifier.value = AIAnalysisProgress.running(
            total: targetTotal,
            completed: processedCount,
            failed: failedCount,
            currentStep: '正在预热引擎：$message',
            elapsedMs: elapsedMs(),
            warmUpCompleted: warmUpCompleted,
            warmUpTotal: warmUpTotal,
          );
        },
      );

      _progressNotifier.value = AIAnalysisProgress.running(
        total: targetTotal,
        completed: processedCount,
        failed: failedCount,
        currentStep: '正在预热引擎：加载低价值过滤模板',
        elapsedMs: elapsedMs(),
        warmUpCompleted: warmUpCompleted,
        warmUpTotal: warmUpTotal,
      );
      await _junkPhotoFilterService.warmUp();
      warmUpCompleted = warmUpTotal;

      _progressNotifier.value = AIAnalysisProgress.running(
        total: targetTotal,
        completed: processedCount,
        failed: failedCount,
        currentStep: '引擎预热完成，开始串行分析',
        elapsedMs: elapsedMs(),
        warmUpCompleted: warmUpCompleted,
        warmUpTotal: warmUpTotal,
      );

      sharedFaceDetector = appAiSettings.faceAnalysisEnabled
          ? FaceDetector(
              options: FaceDetectorOptions(
                enableClassification: true,
                enableTracking: false,
              ),
            )
          : null;

      while (processedCount < targetTotal) {
        final shouldContinue = await _waitIfPaused();
        if (!shouldContinue || _stopRequested) break;

        final remaining = targetTotal - processedCount;
        final fetchLimit = math.min(effectiveBatchSize, remaining);
        final fetchWatch = Stopwatch()..start();
        final photos = _fetchNextPendingBatch(
          photoBox: photoBox,
          requestedPhotoIds: requestedPhotoIds,
          attemptedPhotoIds: attemptedPhotoIds,
          limit: fetchLimit,
          targetTotal: targetTotal,
        );
        fetchWatch.stop();
        pipelineProfiler.recordPendingFetch(
          fetchMs: fetchWatch.elapsedMicroseconds / 1000.0,
          fetchedCandidates: photos.length,
          scheduledPhotos: photos.length,
        );

        if (photos.isEmpty) break;

        for (final photo in photos) {
          final shouldContinue = await _waitIfPaused();
          if (!shouldContinue || _stopRequested) break;

          attemptedPhotoIds.add(photo.id);
          processingStartedAtMs ??= DateTime.now().millisecondsSinceEpoch;
          final skipJunkFilter = _consumeJunkFilterBypassForPhoto(photo.id);
          final photoStartedAtMs = DateTime.now().millisecondsSinceEpoch;
          _inflightCount = 1;

          _progressNotifier.value = AIAnalysisProgress.running(
            total: targetTotal,
            completed: processedCount,
            failed: failedCount,
            currentStep: '串行处理中第 ${processedCount + 1} / $targetTotal 张',
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
                ),
              ),
              selectedBackend: selectedBackend,
            );

            final spentMs =
                DateTime.now().millisecondsSinceEpoch - photoStartedAtMs;
            result.profile.wallMs = spentMs.toDouble();
            pipelineProfiler.recordPhoto(result.profile);

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
            _inflightCount = 0;
          }

          _progressNotifier.value = _stopRequested
              ? AIAnalysisProgress.stopping(
                  total: targetTotal,
                  completed: processedCount,
                  failed: failedCount,
                  currentStep: '正在结束本轮打标…',
                  elapsedMs: elapsedMs(),
                  warmUpCompleted: warmUpCompleted,
                  warmUpTotal: warmUpTotal,
                )
              : _pauseRequested
              ? AIAnalysisProgress.paused(
                  total: targetTotal,
                  completed: processedCount,
                  failed: failedCount,
                  currentStep: '已暂停，随时可以继续',
                  elapsedMs: elapsedMs(),
                  warmUpCompleted: warmUpCompleted,
                  warmUpTotal: warmUpTotal,
                )
              : AIAnalysisProgress.running(
                  total: targetTotal,
                  completed: processedCount,
                  failed: failedCount,
                  currentStep: processedCount >= targetTotal
                      ? '正在收尾整理结果'
                      : '已完成 $processedCount / $targetTotal 张',
                  elapsedMs: elapsedMs(),
                  warmUpCompleted: warmUpCompleted,
                  warmUpTotal: warmUpTotal,
                );

          if (_stopRequested) break;
        }
      }

      publishJunkReportIfNeeded();

      if (affectedEventIds.isNotEmpty) {
        await EventService().refreshEventSmartInfo(affectedEventIds.toList());
      }
      debugPrint('✅ AI 分析完成，总计处理: $totalAnalyzed 张');
    } finally {
      if (manageForegroundService) {
        await AiBackgroundTaskService.instance.stop();
      }
      try {
        await sharedFaceDetector?.close();
      } catch (_) {}
      pipelineProfiler.logFinalSummary();
      await mobileClipTagService.endWorkflowSession();
      await mobileClipEmbeddingService.endWorkflowSession();
      publishJunkReportIfNeeded();

      final remainingPending = _countPending(photoBox, null);
      if (remainingPending > 0 && !_stopRequested) {
        _progressNotifier.value = AIAnalysisProgress.paused(
          total: remainingPending,
          completed: 0,
          failed: 0,
          currentStep: '本轮结束，剩余 $remainingPending 张待打标，点击继续',
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

  int _countPending(dynamic photoBox, List<int>? requestedPhotoIds) {
    final query = requestedPhotoIds != null && requestedPhotoIds.isNotEmpty
        ? photoBox
              .query(
                PhotoEntity_.isAiAnalyzed
                    .equals(false)
                    .and(PhotoEntity_.id.oneOf(requestedPhotoIds)),
              )
              .build()
        : photoBox.query(PhotoEntity_.isAiAnalyzed.equals(false)).build();
    try {
      return query.count();
    } finally {
      query.close();
    }
  }

  List<PhotoEntity> _fetchNextPendingBatch({
    required dynamic photoBox,
    required List<int>? requestedPhotoIds,
    required Set<int> attemptedPhotoIds,
    required int limit,
    required int targetTotal,
  }) {
    var candidateLimit = math.max(limit * 4, 16);
    while (true) {
      final query = requestedPhotoIds != null && requestedPhotoIds.isNotEmpty
          ? photoBox
                .query(
                  PhotoEntity_.isAiAnalyzed
                      .equals(false)
                      .and(PhotoEntity_.id.oneOf(requestedPhotoIds)),
                )
                .order(PhotoEntity_.timestamp, flags: Order.descending)
                .build()
          : photoBox
                .query(PhotoEntity_.isAiAnalyzed.equals(false))
                .order(PhotoEntity_.timestamp, flags: Order.descending)
                .build();
      final candidates = query
          .find()
          .take(candidateLimit)
          .toList(growable: false);
      query.close();

      final selected = candidates
          .where((photo) => !attemptedPhotoIds.contains(photo.id))
          .take(limit)
          .toList(growable: false);
      if (selected.isNotEmpty || candidates.length < candidateLimit) {
        return selected;
      }
      candidateLimit = math.min(
        candidateLimit * 2,
        math.max(targetTotal * 2, 32),
      );
    }
  }
}
