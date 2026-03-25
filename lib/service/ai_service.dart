import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
// import 'dart:math'; // ➕ 新增：用于生成随机的假数据
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:isar/isar.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/entity/photo_entity.dart';
import '../utils/ai_score_helper.dart';
import '../utils/tag_sanitizer.dart';
import 'junk_photo_filter_service.dart';
import 'face_pipeline_service.dart';
import 'photo_service.dart';
import 'event_service.dart';
import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_embedding_service.dart';
import 'mobileclip_tag_service.dart';
import 'ocr_service.dart';
import 'photo_caption_service.dart';
import 'ai_progress_notification_service.dart';
import 'ai_foreground_service.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal() {
    _progressNotifier.addListener(_syncProgressNotification);
    AIForegroundService().bindActionHandler(_handleForegroundAction);
    AIProgressNotificationService().bindActionHandler(_handleForegroundAction);
  }

  static const Set<String> _blockedVisualTags = <String>{
    'Screenshot',
    'Cool',
    'Glasses',
    'Goggles',
    'Selfie',
    '截图',
    '自拍',
  };
  static const ThumbnailSize _mobileClipThumbnailSize = ThumbnailSize.square(
    384,
  );
  static const int _maxParallelWorkers = 8;
  static const String _autoResumeKey = 'ai_auto_resume';

  final ValueNotifier<AIAnalysisProgress> _progressNotifier =
      ValueNotifier<AIAnalysisProgress>(AIAnalysisProgress.idle());
  final ValueNotifier<JunkPhotoCleanupReport?> _junkCleanupReportNotifier =
      ValueNotifier<JunkPhotoCleanupReport?>(null);
  final JunkPhotoFilterService _junkPhotoFilterService =
      JunkPhotoFilterService();
  final Set<Id> _junkFilterBypassPhotoIds = <Id>{};

  bool _autoResumeEnabled = false;

  bool _isAnalyzing = false;
  bool _pauseRequested = false;
  bool _stopRequested = false;
  Completer<void>? _analysisCompleter;

  ValueListenable<AIAnalysisProgress> get progressListenable =>
      _progressNotifier;
  ValueListenable<JunkPhotoCleanupReport?> get junkCleanupReportListenable =>
      _junkCleanupReportNotifier;
  bool get isAnalyzing => _isAnalyzing;

  JunkPhotoCleanupReport? get latestJunkCleanupReport =>
      _junkCleanupReportNotifier.value;

  void replacePendingJunkCleanupReport(JunkPhotoCleanupReport? report) {
    _junkCleanupReportNotifier.value = report;
  }

  void clearPendingJunkCleanupReport() {
    replacePendingJunkCleanupReport(null);
  }

  bool get autoResumeEnabled => _autoResumeEnabled;

  Future<void> setAutoResume(bool enabled) async {
    _autoResumeEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoResumeKey, enabled);
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
  }

  void _handleForegroundAction(String action) {
    if (action == AIForegroundService.actionPause) {
      pauseAnalysis();
      return;
    }
    if (action == AIForegroundService.actionResume) {
      resumeAnalysis();
    }
  }

  Future<bool> getAutoResumePreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoResumeKey) ?? false;
  }

  Future<void> loadAutoResumePreference() async {
    final prefs = await SharedPreferences.getInstance();
    _autoResumeEnabled = prefs.getBool(_autoResumeKey) ?? false;
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
      return;
    }
    _pauseRequested = true;
    final current = _progressNotifier.value;
    if (current.isVisible) {
      _progressNotifier.value = current.copyWith(
        isRunning: false,
        isPaused: true,
        currentStep: '已暂停，随时可以继续',
      );
    }
  }

  void resumeAnalysis() {
    if (_isAnalyzing && !_pauseRequested) {
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
    if (!_isAnalyzing) {
      return;
    }
    _stopRequested = true;
    _pauseRequested = false;
    final current = _progressNotifier.value;
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
    final pending = await PhotoService().isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(false)
        .count();
    if (pending <= 0) {
      return;
    }
    
    await loadAutoResumePreference();
    if (!_autoResumeEnabled) {
      debugPrint('⏸️ 检测到 $pending 张未完成照片，但自动恢复已禁用，显示暂停状态');
      _progressNotifier.value = AIAnalysisProgress.paused(
        total: pending,
        completed: 0,
        failed: 0,
        currentStep: '已暂停 - 点击手动启动',
        elapsedMs: 0,
      );
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

  // 🧠 核心方法：批量分析未处理的照片（包含人脸检测和情感分析）
  Future<void> analyzePhotosInBackground({
    int batchSize = 10,
    int? maxPhotos,
  }) async {
    if (_isAnalyzing) {
      debugPrint('⏭️ AI 打标任务已在运行，跳过重复启动');
      return;
    }

    _isAnalyzing = true;
    _pauseRequested = false;
    _stopRequested = false;
    _analysisCompleter = Completer<void>();
    clearPendingJunkCleanupReport();
    final isar = PhotoService().isar;
    final mobileClipEmbeddingService = MobileClipEmbeddingService();
    final mobileClipTagService = MobileClipTagService();
    final photoCaptionService = PhotoCaptionService();
    final facePipelineService = FacePipelineService();
    final ocrService = OcrService();

    final pendingCount = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(false)
        .count();
    final targetTotal = maxPhotos == null
        ? pendingCount
        : math.min(pendingCount, maxPhotos);
    int? processingStartedAtMs;
    int _elapsedMs() {
      final startedAtMs = processingStartedAtMs;
      if (startedAtMs == null) {
        return 0;
      }
      return DateTime.now().millisecondsSinceEpoch - startedAtMs;
    }

    if (targetTotal <= 0) {
      _progressNotifier.value = AIAnalysisProgress.idle();
      _isAnalyzing = false;
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
      elapsedMs: _elapsedMs(),
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
    final attemptedPhotoIds = <Id>{};
    final queuedPhotoIds = <Id>{};
    final queue = ListQueue<PhotoEntity>();
    final recentDurationsMs = ListQueue<int>();
    var producerDone = false;
    var inflightCount = 0;
    var activeWorkerCount = 1;
    var engineBootstrapped = false;
    final baselineWorkItems = math.max(1, math.min(batchSize, targetTotal));
    final maxWorkerCount = _resolveWorkerCount(
      math.max(baselineWorkItems, targetTotal),
    );

    try {
      if (!engineBootstrapped) {
        _progressNotifier.value = AIAnalysisProgress.running(
          total: targetTotal,
          completed: processedCount,
          failed: failedCount,
          currentStep: '正在预热引擎 (1/3)：加载图像模型 ${selectedBackend.label}',
          elapsedMs: _elapsedMs(),
        );
        await mobileClipEmbeddingService.warmUpBackend(selectedBackend);

        _progressNotifier.value = AIAnalysisProgress.running(
          total: targetTotal,
          completed: processedCount,
          failed: failedCount,
          currentStep: '正在预热引擎 (2/3)：加载标签语义模型',
          elapsedMs: _elapsedMs(),
        );
        await mobileClipTagService.warmUp();

        _progressNotifier.value = AIAnalysisProgress.running(
          total: targetTotal,
          completed: processedCount,
          failed: failedCount,
          currentStep: '正在预热引擎 (3/3)：加载低价值过滤模板',
          elapsedMs: _elapsedMs(),
        );
        await _junkPhotoFilterService.warmUp();

        final readyWorkers = <int>[];
        for (var index = 1; index <= maxWorkerCount; index++) {
          readyWorkers.add(index);
          _progressNotifier.value = AIAnalysisProgress.running(
            total: targetTotal,
            completed: processedCount,
            failed: failedCount,
            currentStep:
                '正在预热并行引擎：${_formatWorkerWarmupStatus(readyWorkers, maxWorkerCount)}',
            elapsedMs: _elapsedMs(),
          );
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }

        activeWorkerCount = math.min(math.max(1, maxWorkerCount ~/ 2), maxWorkerCount);

        _progressNotifier.value = AIAnalysisProgress.running(
          total: targetTotal,
          completed: processedCount,
          failed: failedCount,
          currentStep:
              '引擎预热完成：${_formatWorkerWarmupStatus(readyWorkers, maxWorkerCount)}，初始并发 $activeWorkerCount / $maxWorkerCount',
          elapsedMs: _elapsedMs(),
        );
        engineBootstrapped = true;
      }

      debugPrint('🤖 启动常驻 worker pool，max=$maxWorkerCount，active=$activeWorkerCount，目标=$targetTotal');

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
            final maxBuffered = math.max(maxWorkerCount * 2, currentBatchSize * 2);
            if (queue.length >= maxBuffered) {
              await Future<void>.delayed(const Duration(milliseconds: 35));
              continue;
            }

            final photosToAnalyze = await isar
                .collection<PhotoEntity>()
                .filter()
                .isAiAnalyzedEqualTo(false)
                .sortByTimestampDesc()
                .limit(currentBatchSize * 4)
                .findAll()
                .then(
                  (photos) => photos
                      .where(
                        (photo) =>
                            !attemptedPhotoIds.contains(photo.id) &&
                            !queuedPhotoIds.contains(photo.id),
                      )
                      .take(currentBatchSize)
                      .toList(growable: false),
                );

            if (photosToAnalyze.isEmpty) {
              break;
            }

            for (final photo in photosToAnalyze) {
              queue.addLast(photo);
              queuedPhotoIds.add(photo.id);
            }
            scheduledCount += photosToAnalyze.length;

            _progressNotifier.value = AIAnalysisProgress.running(
              total: targetTotal,
              completed: processedCount,
              failed: failedCount,
              currentStep:
                  '任务已入队 $scheduledCount / $targetTotal，等待 workers 处理',
              elapsedMs: _elapsedMs(),
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

          if (producerDone && queue.isEmpty && inflightCount <= 0) {
            break;
          }

          await Future<void>.delayed(const Duration(milliseconds: 450));

          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - lastAdjustedAtMs < 900) {
            continue;
          }

          final backlog = queue.length;
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
          } else if (backlog == 0 && inflightCount <= currentActive - 1 && canScaleDown) {
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

      final workers = List<Future<void>>.generate(maxWorkerCount, (workerIndex) async {
        final faceDetector = FaceDetector(options: faceOptions);
        try {
          while (true) {
            final shouldContinue = await _waitIfPaused();
            if (!shouldContinue || _stopRequested) {
              break;
            }

            if (workerIndex >= activeWorkerCount) {
              if (producerDone && queue.isEmpty && inflightCount <= 0) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 45));
              continue;
            }

            PhotoEntity? photo;
            if (queue.isNotEmpty) {
              photo = queue.removeFirst();
              queuedPhotoIds.remove(photo.id);
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

            _progressNotifier.value = AIAnalysisProgress.running(
              total: targetTotal,
              completed: processedCount,
              failed: failedCount,
              currentStep:
                  '并行处理中 (worker ${workerIndex + 1}) 第 ${processedCount + 1} / $targetTotal 张',
              elapsedMs: _elapsedMs(),
            );

            try {
              final result = await _processSinglePhoto(
                photo: photo,
                isar: isar,
                selectedBackend: selectedBackend,
                mobileClipEmbeddingService: mobileClipEmbeddingService,
                mobileClipTagService: mobileClipTagService,
                photoCaptionService: photoCaptionService,
                facePipelineService: facePipelineService,
                ocrService: ocrService,
                faceDetector: faceDetector,
                skipJunkFilter: skipJunkFilter,
              );

              final spentMs =
                  DateTime.now().millisecondsSinceEpoch - photoStartedAtMs;
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
            }

            if (_stopRequested) {
              _progressNotifier.value = AIAnalysisProgress.stopping(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: '正在结束本轮打标…',
                elapsedMs: _elapsedMs(),
              );
            } else if (_pauseRequested) {
              _progressNotifier.value = AIAnalysisProgress.paused(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: '已暂停，随时可以继续',
                elapsedMs: _elapsedMs(),
              );
            } else {
              _progressNotifier.value = AIAnalysisProgress.running(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: processedCount >= targetTotal
                    ? '正在收尾整理结果'
                    : '已完成 $processedCount / $targetTotal 张 (并发 $activeWorkerCount / $maxWorkerCount)',
                elapsedMs: _elapsedMs(),
              );
            }

            if (_stopRequested) {
              break;
            }
          }
        } finally {
          await faceDetector.close();
        }
      });

      await Future.wait(<Future<void>>[produceWork(), tuneActiveWorkerCount(), ...workers]);

      if (junkCandidates.isNotEmpty) {
        replacePendingJunkCleanupReport(
          JunkPhotoCleanupReport.fromCandidates(junkCandidates),
        );
      }

      if (affectedEventIds.isNotEmpty) {
        await EventService().refreshEventSmartInfo(affectedEventIds.toList());
      }
      debugPrint("✅ AI 分析完成，总计处理: $totalAnalyzed 张");
    } finally {
      await mobileClipTagService.endWorkflowSession();
      await mobileClipEmbeddingService.endWorkflowSession();
      _progressNotifier.value = AIAnalysisProgress.idle();
      _isAnalyzing = false;
      _pauseRequested = false;
      _stopRequested = false;
      if (_analysisCompleter != null && !_analysisCompleter!.isCompleted) {
        _analysisCompleter!.complete();
      }
      _analysisCompleter = null;
    }
  }

  Future<bool> _waitIfPaused() async {
    while (_pauseRequested && !_stopRequested) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return !_stopRequested;
  }

  int _resolveWorkerCount(int workItems) {
    if (workItems <= 1) {
      return 1;
    }
    final cpuCores = Platform.numberOfProcessors;
    final suggested = cpuCores <= 2 ? 1 : math.max(2, cpuCores - 1);
    final bounded = math.min(_maxParallelWorkers, suggested);
    return math.max(1, math.min(bounded, workItems));
  }

  String _formatWorkerWarmupStatus(List<int> readyWorkers, int totalWorkers) {
    if (readyWorkers.isEmpty) {
      return 'workers无 / 共$totalWorkers';
    }
    final labels = readyWorkers.map((id) => 'workers$id').join(',');
    return '$labels / 共$totalWorkers';
  }

  Future<_PhotoProcessResult> _processSinglePhoto({
    required PhotoEntity photo,
    required Isar isar,
    required MobileClipBackend selectedBackend,
    required MobileClipEmbeddingService mobileClipEmbeddingService,
    required MobileClipTagService mobileClipTagService,
    required PhotoCaptionService photoCaptionService,
    required FacePipelineService facePipelineService,
    required OcrService ocrService,
    required FaceDetector faceDetector,
    required bool skipJunkFilter,
  }) async {
    File? analysisFile;
    try {
      final prepared = await _prepareAnalysisInput(photo);
      if (prepared == null) {
        return const _PhotoProcessResult.failed();
      }

      final embedding = await mobileClipEmbeddingService
          .embedImageBytesWithBackend(
            prepared.mobileClipBytes,
            selectedBackend,
          );

      if (!skipJunkFilter) {
        final junkDecision = await _junkPhotoFilterService.evaluatePhoto(
          photo: photo,
          imageEmbedding: embedding,
        );
        if (junkDecision.shouldFilter) {
          await _markAsAnalyzed(
            photo.id,
            const <String>[JunkPhotoFilterService.junkCandidateTag],
            embedding,
            '',
            '',
            const <String>[],
            0,
            0.0,
            0.0,
            isar,
          );
          return _PhotoProcessResult.success(
            eventId: photo.eventId,
            junkCandidate: JunkPhotoCleanupCandidate(
              photoId: photo.id,
              assetId: photo.assetId,
              path: photo.path,
              timestamp: photo.timestamp,
              reasons: junkDecision.hits,
            ),
          );
        }
      }

      final mobileClipTags = await mobileClipTagService.retrieveTags(embedding);
      final visualTags = _sanitizeVisualTags(mobileClipTags);

      analysisFile = await _createAuxiliaryAnalysisFile(
        prepared.file,
        photo.id,
      );
      final inputImage = InputImage.fromFile(analysisFile);

      var ocrResult = OcrResult.empty();
      if (OcrService.shouldRunOcr(visualTags, aspectRatio: photo.aspectRatio)) {
        ocrResult = await ocrService.analyzeImageFile(analysisFile);
      }

      final faces = await faceDetector.processImage(inputImage);
      final faceCount = faces.length;
      final maxSmileProb = faces.isNotEmpty
          ? faces
                .map((f) => f.smilingProbability ?? 0.0)
                .reduce((a, b) => a > b ? a : b)
          : 0.0;
      final joyScore = AIScoreHelper.calculateJoyScore(
        faceCount: faceCount,
        maxSmileProb: maxSmileProb,
        tags: visualTags,
      );

      await facePipelineService.rebuildFacesForPhoto(
        isar: isar,
        photo: photo,
        imageFile: analysisFile,
        faces: faces,
      );

      final caption = await photoCaptionService.generateCaption(
        imageFile: analysisFile,
        visualTags: visualTags,
        ocrTags: ocrResult.tags,
        ocrText: ocrResult.text,
        location:
            photo.locationName ??
            photo.district ??
            photo.city ??
            photo.province,
        takenAt: DateTime.fromMillisecondsSinceEpoch(photo.timestamp),
        isProbablyScreenshot: photo.isProbablyScreenshot,
        faceCount: faceCount,
      );

      await _markAsAnalyzed(
        photo.id,
        visualTags,
        embedding,
        caption,
        ocrResult.text,
        ocrResult.tags,
        faceCount,
        maxSmileProb,
        joyScore,
        isar,
      );

      return _PhotoProcessResult.success(eventId: photo.eventId);
    } catch (error) {
      debugPrint('❌ AI 分析失败 photoId=${photo.id}: $error');
      return const _PhotoProcessResult.failed();
    } finally {
      if (analysisFile != null &&
          analysisFile.path != photo.path &&
          analysisFile.existsSync()) {
        try {
          await analysisFile.delete();
        } catch (error) {
          debugPrint('⚠️ 清理临时文件失败: $error');
        }
      }
    }
  }

  List<String> _sanitizeVisualTags(List<String> source, {int maxTags = 5}) {
    final sanitized = <String>[];

    for (final tag in source) {
      final normalized = TagSanitizer.sanitizeVisualTag(tag);
      if (normalized == null || sanitized.contains(normalized)) {
        continue;
      }
      if (_blockedVisualTags.contains(normalized)) {
        continue;
      }
      if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(normalized)) {
        continue;
      }
      if (normalized.contains('智能影记') || normalized.contains('我的相册')) {
        continue;
      }
      sanitized.add(normalized);
      if (sanitized.length >= maxTags) {
        break;
      }
    }

    return TagSanitizer.sanitizeVisualTags(sanitized, maxTags: maxTags);
  }

  Future<_PreparedAnalysisInput?> _prepareAnalysisInput(
    PhotoEntity photo,
  ) async {
    final file = File(photo.path);
    if (!file.existsSync()) {
      return null;
    }

    Uint8List? mobileClipBytes;
    try {
      final asset = await AssetEntity.fromId(photo.assetId);
      mobileClipBytes = await asset?.thumbnailDataWithSize(
        _mobileClipThumbnailSize,
      );
    } catch (error) {
      debugPrint('⚠️ 读取系统缩略图失败 photoId=${photo.id}: $error');
    }

    mobileClipBytes ??= await file.readAsBytes();
    if (mobileClipBytes.isEmpty) {
      return null;
    }

    return _PreparedAnalysisInput(
      photo: photo,
      file: file,
      mobileClipBytes: mobileClipBytes,
      usedThumbnail: mobileClipBytes.lengthInBytes < file.lengthSync(),
    );
  }

  Future<File> _createAuxiliaryAnalysisFile(
    File sourceFile,
    int photoId,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final targetPath = '${tempDir.path}/temp_mlkit_$photoId.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      sourceFile.absolute.path,
      targetPath,
      minWidth: 1024,
      minHeight: 1024,
      quality: 80,
    );
    if (result == null) {
      throw Exception('压缩失败');
    }
    return File(result.path);
  }

  // 将 AI 分析结果写入数据库（增强版）
  Future<void> _markAsAnalyzed(
    Id id,
    List<String> tags,
    List<double> imageEmbedding,
    String aiCaption,
    String ocrText,
    List<String> ocrTags,
    int faceCount,
    double smileProb,
    double joyScore,
    Isar isar,
  ) async {
    await isar.writeTxn(() async {
      final p = await isar.collection<PhotoEntity>().get(id);
      if (p != null) {
        p.aiTags = tags;
        p.isAiAnalyzed = true;
        p.aiCaption = aiCaption.isEmpty ? null : aiCaption;
        p.imageEmbedding = imageEmbedding.isEmpty ? null : imageEmbedding;
        p.ocrText = ocrText.isEmpty ? null : ocrText;
        p.ocrTags = ocrTags;
        p.faceCount = faceCount;
        p.smileProb = smileProb;
        p.joyScore = joyScore;
        await isar.collection<PhotoEntity>().put(p);
      }
    });
  }

  // 📊 工具方法：获取 AI 分析进度
  Future<Map<String, int>> getAnalysisProgress() async {
    final isar = PhotoService().isar;

    final total = await isar.collection<PhotoEntity>().count();
    final analyzed = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .count();

    return {'total': total, 'analyzed': analyzed, 'pending': total - analyzed};
  }
}

class AIAnalysisProgress {
  const AIAnalysisProgress({
    required this.isRunning,
    required this.isPaused,
    required this.isStopping,
    required this.total,
    required this.completed,
    required this.failed,
    required this.currentStep,
    required this.elapsedMs,
  });

  factory AIAnalysisProgress.idle() {
    return const AIAnalysisProgress(
      isRunning: false,
      isPaused: false,
      isStopping: false,
      total: 0,
      completed: 0,
      failed: 0,
      currentStep: '',
      elapsedMs: 0,
    );
  }

  factory AIAnalysisProgress.running({
    required int total,
    required int completed,
    required int failed,
    required String currentStep,
    int elapsedMs = 0,
  }) {
    return AIAnalysisProgress(
      isRunning: true,
      isPaused: false,
      isStopping: false,
      total: total,
      completed: completed,
      failed: failed,
      currentStep: currentStep,
      elapsedMs: elapsedMs,
    );
  }

  factory AIAnalysisProgress.paused({
    required int total,
    required int completed,
    required int failed,
    required String currentStep,
    int elapsedMs = 0,
  }) {
    return AIAnalysisProgress(
      isRunning: false,
      isPaused: true,
      isStopping: false,
      total: total,
      completed: completed,
      failed: failed,
      currentStep: currentStep,
      elapsedMs: elapsedMs,
    );
  }

  factory AIAnalysisProgress.stopping({
    required int total,
    required int completed,
    required int failed,
    required String currentStep,
    int elapsedMs = 0,
  }) {
    return AIAnalysisProgress(
      isRunning: false,
      isPaused: false,
      isStopping: true,
      total: total,
      completed: completed,
      failed: failed,
      currentStep: currentStep,
      elapsedMs: elapsedMs,
    );
  }

  final bool isRunning;
  final bool isPaused;
  final bool isStopping;
  final int total;
  final int completed;
  final int failed;
  final String currentStep;
  final int elapsedMs;

  AIAnalysisProgress copyWith({
    bool? isRunning,
    bool? isPaused,
    bool? isStopping,
    int? total,
    int? completed,
    int? failed,
    String? currentStep,
    int? elapsedMs,
  }) {
    return AIAnalysisProgress(
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      isStopping: isStopping ?? this.isStopping,
      total: total ?? this.total,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      currentStep: currentStep ?? this.currentStep,
      elapsedMs: elapsedMs ?? this.elapsedMs,
    );
  }

  double? get averageSecondsPerItem {
    if (completed <= 0 || elapsedMs <= 0) {
      return null;
    }
    return elapsedMs / 1000.0 / completed;
  }

  Duration? get estimatedRemainingDuration {
    final avg = averageSecondsPerItem;
    final remaining = total - completed;
    if (avg == null || remaining <= 0) {
      return null;
    }
    final etaMs = (avg * remaining * 1000).round();
    return Duration(milliseconds: etaMs);
  }

  Duration get elapsed => Duration(milliseconds: elapsedMs);

  double get fraction {
    if (total <= 0) {
      return 0;
    }
    return (completed / total).clamp(0, 1).toDouble();
  }

  bool get isVisible => (isRunning || isPaused || isStopping) && total > 0;
}

class _PreparedAnalysisInput {
  const _PreparedAnalysisInput({
    required this.photo,
    required this.file,
    required this.mobileClipBytes,
    required this.usedThumbnail,
  });

  final PhotoEntity photo;
  final File file;
  final Uint8List mobileClipBytes;
  final bool usedThumbnail;
}

class _PhotoProcessResult {
  const _PhotoProcessResult._({
    required this.didSucceed,
    this.eventId,
    this.junkCandidate,
  });

  const _PhotoProcessResult.success({
    int? eventId,
    JunkPhotoCleanupCandidate? junkCandidate,
  }) : this._(didSucceed: true, eventId: eventId, junkCandidate: junkCandidate);

  const _PhotoProcessResult.failed()
    : this._(didSucceed: false, eventId: null, junkCandidate: null);

  final bool didSucceed;
  final int? eventId;
  final JunkPhotoCleanupCandidate? junkCandidate;
}
