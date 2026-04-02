import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
// import 'dart:math'; // ➕ 新增：用于生成随机的假数据
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
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
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../storage/vector_index/vector_index_constants.dart';

part 'ai_service_progress.dart';
part 'ai_service_input.dart';
part 'ai_service_auxiliary.dart';
part 'ai_service_models.dart';
part 'ai_service_profiler.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal() {
    _progressNotifier.addListener(_syncProgressNotification);
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
  static const String _analysisInputStrategyOverride = String.fromEnvironment(
    'AI_ANALYSIS_INPUT_STRATEGY',
    defaultValue: 'thumbnail_first',
  );
  static const String _analysisThumbnailTimeoutMsOverride =
      String.fromEnvironment(
        'AI_ANALYSIS_THUMBNAIL_TIMEOUT_MS',
        defaultValue: '120',
      );
  static const String _analysisAuxiliaryStrategyOverride =
      String.fromEnvironment(
        'AI_ANALYSIS_AUXILIARY_STRATEGY',
        defaultValue: 'always_compress',
      );
  static const int _minFaceDetectorInputSize = 32;
  static const int _maxParallelWorkers = 8;
  static const int _maxConcurrentCaptionWorkers = 2;
  static const String _autoResumeKey = 'ai_auto_resume';
  static const String _runtimeActiveKey = 'ai_runtime_active';
  static const String _runtimeHeartbeatAtKey = 'ai_runtime_heartbeat_at';
  static const String _runtimeTotalKey = 'ai_runtime_total';
  static const String _runtimeCompletedKey = 'ai_runtime_completed';
  static const String _runtimeFailedKey = 'ai_runtime_failed';
  static const String _manualStopPendingKey = 'ai_manual_stop_pending';

  final ValueNotifier<AIAnalysisProgress> _progressNotifier =
      ValueNotifier<AIAnalysisProgress>(AIAnalysisProgress.idle());
  final ValueNotifier<JunkPhotoCleanupReport?> _junkCleanupReportNotifier =
      ValueNotifier<JunkPhotoCleanupReport?>(null);
  final JunkPhotoFilterService _junkPhotoFilterService =
      JunkPhotoFilterService();
  final PhotoEmbeddingIndexRepository _photoEmbeddingIndexRepository =
      PhotoEmbeddingIndexRepository();
  final Set<Id> _junkFilterBypassPhotoIds = <Id>{};
  final ListQueue<_AsyncCaptionTask> _pendingCaptionTasks =
      ListQueue<_AsyncCaptionTask>();
  static final _AnalysisInputConfig _analysisInputConfig =
      _AnalysisInputConfig.resolve(
        strategyLabel: _analysisInputStrategyOverride,
        thumbnailTimeoutMsLabel: _analysisThumbnailTimeoutMsOverride,
      );
  static final _AnalysisAuxiliaryConfig _analysisAuxiliaryConfig =
      _AnalysisAuxiliaryConfig.resolve(
        strategyLabel: _analysisAuxiliaryStrategyOverride,
      );

  bool _autoResumeEnabled = false;

  bool _isAnalyzing = false;
  bool _pauseRequested = false;
  bool _stopRequested = false;
  int _inflightCount = 0;
  int _activeCaptionTasks = 0;
  Completer<void>? _analysisCompleter;
  int _lastRuntimeHeartbeatPersistAtMs = 0;

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

  // 🧠 核心方法：批量分析未处理的照片（包含人脸检测和情感分析）
  Future<void> analyzePhotosInBackground({
    int batchSize = 10,
    int? maxPhotos,
  }) async {
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
    final attemptedPhotoIds = <Id>{};
    final queuedPhotoIds = <Id>{};
    final queue = ListQueue<PhotoEntity>();
    final recentDurationsMs = ListQueue<int>();
    final pipelineProfiler = _AiPipelineRunProfiler(
      summaryEvery: math.max(4, math.min(batchSize, 8)),
    );
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
          elapsedMs: elapsedMs(),
        );
        await mobileClipEmbeddingService.warmUpBackend(selectedBackend);

        _progressNotifier.value = AIAnalysisProgress.running(
          total: targetTotal,
          completed: processedCount,
          failed: failedCount,
          currentStep: '正在预热引擎 (2/3)：加载标签语义模型',
          elapsedMs: elapsedMs(),
        );
        await mobileClipTagService.warmUp();

        _progressNotifier.value = AIAnalysisProgress.running(
          total: targetTotal,
          completed: processedCount,
          failed: failedCount,
          currentStep: '正在预热引擎 (3/3)：加载低价值过滤模板',
          elapsedMs: elapsedMs(),
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
            elapsedMs: elapsedMs(),
          );
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }

        activeWorkerCount = math.min(
          math.max(1, maxWorkerCount ~/ 2),
          maxWorkerCount,
        );

        _progressNotifier.value = AIAnalysisProgress.running(
          total: targetTotal,
          completed: processedCount,
          failed: failedCount,
          currentStep:
              '引擎预热完成：${_formatWorkerWarmupStatus(readyWorkers, maxWorkerCount)}，初始并发 $activeWorkerCount / $maxWorkerCount',
          elapsedMs: elapsedMs(),
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
            if (queue.length >= maxBuffered) {
              await Future<void>.delayed(const Duration(milliseconds: 35));
              continue;
            }

            final pendingFetchWatch = Stopwatch()..start();
            final fetchedCandidates = await isar
                .collection<PhotoEntity>()
                .filter()
                .isAiAnalyzedEqualTo(false)
                .sortByTimestampDesc()
                .limit(currentBatchSize * 4)
                .findAll();
            final photosToAnalyze = fetchedCandidates
                .where(
                  (photo) =>
                      !attemptedPhotoIds.contains(photo.id) &&
                      !queuedPhotoIds.contains(photo.id),
                )
                .take(currentBatchSize)
                .toList(growable: false);
            pendingFetchWatch.stop();
            pipelineProfiler.recordPendingFetch(
              fetchMs: pendingFetchWatch.elapsedMicroseconds / 1000.0,
              fetchedCandidates: fetchedCandidates.length,
              scheduledPhotos: photosToAnalyze.length,
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
              currentStep: '任务已入队 $scheduledCount / $targetTotal，等待 workers 处理',
              elapsedMs: elapsedMs(),
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

      final workers = List<Future<void>>.generate(maxWorkerCount, (
        workerIndex,
      ) async {
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
            _inflightCount = inflightCount;

            _progressNotifier.value = AIAnalysisProgress.running(
              total: targetTotal,
              completed: processedCount,
              failed: failedCount,
              currentStep:
                  '并行处理中 (worker ${workerIndex + 1}) 第 ${processedCount + 1} / $targetTotal 张',
              elapsedMs: elapsedMs(),
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
              );
            } else if (_pauseRequested) {
              _progressNotifier.value = AIAnalysisProgress.paused(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: '已暂停，随时可以继续',
                elapsedMs: elapsedMs(),
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

      await Future.wait(<Future<void>>[
        produceWork(),
        tuneActiveWorkerCount(),
        ...workers,
      ]);

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
      pipelineProfiler.logFinalSummary();
      await mobileClipTagService.endWorkflowSession();
      await mobileClipEmbeddingService.endWorkflowSession();

      final remainingPending = await isar
          .collection<PhotoEntity>()
          .filter()
          .isAiAnalyzedEqualTo(false)
          .count();
      if (remainingPending > 0 && !_stopRequested) {
        _progressNotifier.value = AIAnalysisProgress.paused(
          total: remainingPending,
          completed: 0,
          failed: 0,
          currentStep: _stopRequested
              ? '已暂停，剩余 $remainingPending 张待打标'
              : '本轮结束，剩余 $remainingPending 张待打标，点击继续',
          elapsedMs: elapsedMs(),
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

  Future<void> _setManualStopPending(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_manualStopPendingKey, value);
  }

  Future<bool> _readManualStopPending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_manualStopPendingKey) ?? false;
  }

  Future<void> _persistRuntimeState({
    required bool isActive,
    int? total,
    int? completed,
    int? failed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_runtimeActiveKey, isActive);
    if (!isActive) {
      await prefs.remove(_runtimeHeartbeatAtKey);
      await prefs.remove(_runtimeTotalKey);
      await prefs.remove(_runtimeCompletedKey);
      await prefs.remove(_runtimeFailedKey);
      return;
    }

    await prefs.setInt(
      _runtimeHeartbeatAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (total != null) {
      await prefs.setInt(_runtimeTotalKey, total);
    }
    if (completed != null) {
      await prefs.setInt(_runtimeCompletedKey, completed);
    }
    if (failed != null) {
      await prefs.setInt(_runtimeFailedKey, failed);
    }
  }

  Future<_RuntimeSnapshot> _readRuntimeSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getBool(_runtimeActiveKey) ?? false;
    final heartbeatAtMs = prefs.getInt(_runtimeHeartbeatAtKey) ?? 0;
    final ageMs = DateTime.now().millisecondsSinceEpoch - heartbeatAtMs;
    final recent =
        heartbeatAtMs > 0 && ageMs <= const Duration(hours: 1).inMilliseconds;
    return _RuntimeSnapshot(
      isActive: active && recent,
      total: prefs.getInt(_runtimeTotalKey) ?? 0,
      completed: prefs.getInt(_runtimeCompletedKey) ?? 0,
      failed: prefs.getInt(_runtimeFailedKey) ?? 0,
    );
  }

  Future<bool> _waitIfPaused() async {
    while (_pauseRequested && !_stopRequested) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return !_stopRequested;
  }

  void _enqueueAsyncCaption(_AsyncCaptionTask task) {
    _pendingCaptionTasks.addLast(task);
    _pumpAsyncCaptionQueue();
  }

  void _pumpAsyncCaptionQueue() {
    while (_activeCaptionTasks < _maxConcurrentCaptionWorkers &&
        _pendingCaptionTasks.isNotEmpty) {
      final task = _pendingCaptionTasks.removeFirst();
      _activeCaptionTasks++;
      unawaited(_runAsyncCaptionTask(task));
    }
  }

  Future<void> _runAsyncCaptionTask(_AsyncCaptionTask task) async {
    final watch = Stopwatch()..start();
    try {
      final caption = await task.captionService.generateCaption(
        imageFile: task.imageFile,
        visualTags: task.visualTags,
        ocrTags: task.ocrTags,
        ocrText: task.ocrText,
        location: task.location,
        takenAt: task.takenAt,
        isProbablyScreenshot: task.isProbablyScreenshot,
        faceCount: task.faceCount,
      );
      if (caption.trim().isNotEmpty) {
        await _updatePhotoCaption(task.photoId, caption);
      }
      watch.stop();
      debugPrint(
        'AI async caption photoId=${task.photoId} '
        'updated=${caption.trim().isNotEmpty} '
        'elapsedMs=${(watch.elapsedMicroseconds / 1000.0).toStringAsFixed(1)}',
      );
    } catch (error) {
      watch.stop();
      debugPrint(
        '⚠️ AI async caption failed photoId=${task.photoId} '
        'elapsedMs=${(watch.elapsedMicroseconds / 1000.0).toStringAsFixed(1)} '
        'error=$error',
      );
    } finally {
      if (task.imageFile.existsSync()) {
        try {
          await task.imageFile.delete();
        } catch (_) {}
      }
      _activeCaptionTasks = math.max(0, _activeCaptionTasks - 1);
      _pumpAsyncCaptionQueue();
    }
  }

  Future<void> _updatePhotoCaption(Id photoId, String caption) async {
    final trimmed = caption.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final isar = PhotoService().isar;
    await isar.writeTxn(() async {
      final photo = await isar.collection<PhotoEntity>().get(photoId);
      if (photo == null) {
        return;
      }
      photo.aiCaption = trimmed;
      await isar.collection<PhotoEntity>().put(photo);
    });
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
    final profile = _AiPhotoProfile(
      photoId: photo.id,
      backendLabel: selectedBackend.label,
    );
    File? analysisFile;
    try {
      profile.inputStrategy = _analysisInputConfig.strategy.label;
      profile.auxiliaryStrategy = _analysisAuxiliaryConfig.strategy.label;
      final prepared = await _prepareAnalysisInputConfigured(photo);
      if (prepared == null) {
        profile.outcome = 'prepare_failed';
        return _PhotoProcessResult.failed(profile: profile);
      }

      profile.inputLoadMs = prepared.loadMs;
      profile.thumbnailReadMs = prepared.thumbnailReadMs;
      profile.fileReadMs = prepared.fileReadMs;
      profile.inputBytes = prepared.mobileClipBytes.lengthInBytes;
      profile.inputSource = prepared.inputSource;
      profile.inputStrategy = prepared.inputStrategy;
      profile.usedThumbnail = prepared.usedThumbnail;
      profile.thumbnailAttempted = prepared.thumbnailAttempted;
      profile.thumbnailTimedOut = prepared.thumbnailTimedOut;
      profile.fallbackToOriginal = prepared.fallbackToOriginal;
      profile.fallbackReason = prepared.fallbackReason;

      final resolution = await mobileClipEmbeddingService.resolvePhotoEmbedding(
        photo: photo,
        preferredImageBytes: prepared.mobileClipBytes,
        backend: selectedBackend,
      );
      final embeddingProfile = resolution.profile;
      profile.embeddingCacheHit = resolution.reusedCache;
      if (embeddingProfile != null) {
        profile.providerLabel = embeddingProfile.providerLabel;
        profile.decodeMs = embeddingProfile.decodeMs;
        profile.resizeNormalizeMs = embeddingProfile.resizeNormalizeMs;
        profile.tensorBuildMs = embeddingProfile.tensorBuildMs;
        profile.inferenceMs = embeddingProfile.inferenceMs;
        profile.objectBoxWriteMs = embeddingProfile.vectorIndexWriteMs;
      }
      final embedding = photo.imageEmbedding ?? const <double>[];
      if (embedding.isEmpty) {
        profile.outcome = 'embedding_empty';
        return _PhotoProcessResult.failed(profile: profile);
      }

      if (!skipJunkFilter) {
        final junkWatch = Stopwatch()..start();
        final junkDecision = await _junkPhotoFilterService.evaluatePhoto(
          photo: photo,
          imageEmbedding: embedding,
        );
        junkWatch.stop();
        profile.junkFilterMs = junkWatch.elapsedMicroseconds / 1000.0;
        if (junkDecision.shouldFilter) {
          final persistenceProfile = await _markAsAnalyzed(
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
            selectedBackend,
            skipVectorIndexWrite: true,
          );
          profile.isarWriteMs = persistenceProfile.isarWriteMs;
          profile.outcome = 'junk_filtered';
          return _PhotoProcessResult.success(
            eventId: photo.eventId,
            junkCandidate: JunkPhotoCleanupCandidate(
              photoId: photo.id,
              assetId: photo.assetId,
              path: photo.path,
              timestamp: photo.timestamp,
              reasons: junkDecision.hits,
            ),
            profile: profile,
          );
        }
      }

      final tagWatch = Stopwatch()..start();
      final mobileClipTags = await mobileClipTagService.retrieveTags(embedding);
      tagWatch.stop();
      profile.tagRetrievalMs = tagWatch.elapsedMicroseconds / 1000.0;
      final visualTags = _sanitizeVisualTags(mobileClipTags);

      final auxiliaryFileWatch = Stopwatch()..start();
      final resolvedAnalysisFile = await _AnalysisFileResolver(
        config: _analysisAuxiliaryConfig,
        createCompressedFile: _createAuxiliaryAnalysisFile,
      ).resolve(sourceFile: prepared.file, photoId: photo.id);
      analysisFile = resolvedAnalysisFile.file;
      auxiliaryFileWatch.stop();
      profile.auxiliaryFileMs = auxiliaryFileWatch.elapsedMicroseconds / 1000.0;
      profile.auxiliarySource = resolvedAnalysisFile.source;
      profile.auxiliaryCreated = resolvedAnalysisFile.createdTemporaryFile;
      final inputImage = InputImage.fromFile(analysisFile);

      var ocrResult = OcrResult.empty();
      if (OcrService.shouldRunOcr(visualTags, aspectRatio: photo.aspectRatio)) {
        final ocrWatch = Stopwatch()..start();
        ocrResult = await ocrService.analyzeImageFile(analysisFile);
        ocrWatch.stop();
        profile.ocrMs = ocrWatch.elapsedMicroseconds / 1000.0;
      }

      final dimensionWatch = Stopwatch()..start();
      final analysisDimensions = await _readImageDimensions(
        analysisFile,
        knownWidth: photo.width,
        knownHeight: photo.height,
      );
      dimensionWatch.stop();
      profile.analysisDecodeMs = dimensionWatch.elapsedMicroseconds / 1000.0;
      final canRunFaceDetection =
          analysisDimensions != null &&
          analysisDimensions.$1 >= _minFaceDetectorInputSize &&
          analysisDimensions.$2 >= _minFaceDetectorInputSize;
      if (!canRunFaceDetection) {
        final sizeLabel = analysisDimensions == null
            ? 'unknown'
            : '${analysisDimensions.$1}x${analysisDimensions.$2}';
        debugPrint(
          '⏭️ 跳过人脸检测 photoId=${photo.id} '
          'dbSize=${photo.width}x${photo.height} analysisSize=$sizeLabel '
          'path=${analysisFile.path}',
        );
      }

      final faceDetectionWatch = Stopwatch()..start();
      final faces = canRunFaceDetection
          ? await faceDetector.processImage(inputImage)
          : const <Face>[];
      faceDetectionWatch.stop();
      profile.faceDetectionMs = faceDetectionWatch.elapsedMicroseconds / 1000.0;
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

      final facePipelineProfile = await facePipelineService
          .rebuildFacesForPhoto(
            isar: isar,
            photo: photo,
            imageFile: analysisFile,
            faces: faces,
          );
      profile.facePersistMs = facePipelineProfile.totalMs;
      profile.faceExistingReadMs = facePipelineProfile.existingReadMs;
      profile.faceSourceDecodeMs = facePipelineProfile.sourceDecodeMs;
      profile.faceWarmUpMs = facePipelineProfile.embeddingWarmUpMs;
      profile.faceCropMs = facePipelineProfile.cropMs;
      profile.faceDebugCropMs = facePipelineProfile.debugCropMs;
      profile.faceTempFileMs = facePipelineProfile.tempFileMs;
      profile.faceEmbeddingMs = facePipelineProfile.embeddingMs;
      profile.faceIsarWriteMs = facePipelineProfile.isarWriteMs;
      profile.faceObjectBoxWriteMs = facePipelineProfile.objectBoxWriteMs;
      profile.faceCleanupMs = facePipelineProfile.cleanupMs;
      profile.faceRequestedCount = facePipelineProfile.requestedFaces;
      profile.facePersistedCount = facePipelineProfile.persistedFaces;

      final captionLocation =
          photo.locationName ?? photo.district ?? photo.city ?? photo.province;
      final takenAt = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
      var caption = '';
      if (photoCaptionService.prefersAsyncGeneration && !_stopRequested) {
        profile.captionDeferred = true;
      } else {
        final captionWatch = Stopwatch()..start();
        caption = await photoCaptionService.generateCaption(
          imageFile: prepared.file,
          visualTags: visualTags,
          ocrTags: ocrResult.tags,
          ocrText: ocrResult.text,
          location: captionLocation,
          takenAt: takenAt,
          isProbablyScreenshot: photo.isProbablyScreenshot,
          faceCount: faceCount,
        );
        captionWatch.stop();
        profile.captionMs = captionWatch.elapsedMicroseconds / 1000.0;
      }

      final persistenceProfile = await _markAsAnalyzed(
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
        selectedBackend,
        skipVectorIndexWrite: true,
      );
      profile.isarWriteMs = persistenceProfile.isarWriteMs;
      profile.outcome = 'completed';

      if (profile.captionDeferred) {
        _enqueueAsyncCaption(
          _AsyncCaptionTask(
            photoId: photo.id,
            imageFile: prepared.file,
            captionService: photoCaptionService,
            visualTags: visualTags,
            ocrTags: ocrResult.tags,
            ocrText: ocrResult.text,
            location: captionLocation,
            takenAt: takenAt,
            isProbablyScreenshot: photo.isProbablyScreenshot,
            faceCount: faceCount,
          ),
        );
      }

      return _PhotoProcessResult.success(
        eventId: photo.eventId,
        profile: profile,
      );
    } catch (error) {
      debugPrint('❌ AI 分析失败 photoId=${photo.id}: $error');
      profile.outcome = 'error';
      profile.error = error.toString();
      return _PhotoProcessResult.failed(profile: profile);
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

  Future<_PreparedAnalysisInput?> _prepareAnalysisInputConfigured(
    PhotoEntity photo,
  ) {
    if (_analysisInputConfig.strategy ==
        _AnalysisInputStrategy.thumbnailFirst) {
      return _prepareAnalysisInput(photo);
    }
    return _AnalysisInputLoader(
      config: _analysisInputConfig,
      thumbnailSize: _mobileClipThumbnailSize,
    ).load(photo);
  }

  Future<_PreparedAnalysisInput?> _prepareAnalysisInput(
    PhotoEntity photo,
  ) async {
    final file = File(photo.path);
    if (!file.existsSync()) {
      return null;
    }

    final loadWatch = Stopwatch()..start();
    Uint8List? mobileClipBytes;
    var thumbnailReadMs = 0.0;
    var fileReadMs = 0.0;
    var inputSource = 'original_file';
    var fallbackReason = 'none';
    try {
      final asset = await AssetEntity.fromId(photo.assetId);
      final thumbnailWatch = Stopwatch()..start();
      mobileClipBytes = await asset?.thumbnailDataWithSize(
        _mobileClipThumbnailSize,
      );
      thumbnailWatch.stop();
      thumbnailReadMs = thumbnailWatch.elapsedMicroseconds / 1000.0;
      if (mobileClipBytes != null && mobileClipBytes.isNotEmpty) {
        inputSource = 'thumbnail';
      } else if (asset == null) {
        fallbackReason = 'asset_unavailable';
      } else {
        fallbackReason = 'thumbnail_empty';
      }
    } catch (error) {
      fallbackReason = 'thumbnail_error';
      debugPrint('⚠️ 读取系统缩略图失败 photoId=${photo.id}: $error');
    }

    if (mobileClipBytes == null || mobileClipBytes.isEmpty) {
      final fileReadWatch = Stopwatch()..start();
      mobileClipBytes = await file.readAsBytes();
      fileReadWatch.stop();
      fileReadMs = fileReadWatch.elapsedMicroseconds / 1000.0;
    }
    if (mobileClipBytes.isEmpty) {
      return null;
    }
    loadWatch.stop();

    return _PreparedAnalysisInput(
      photo: photo,
      file: file,
      mobileClipBytes: mobileClipBytes,
      usedThumbnail: inputSource == 'thumbnail',
      inputSource: inputSource,
      inputStrategy: _AnalysisInputStrategy.thumbnailFirst.label,
      thumbnailAttempted: true,
      thumbnailTimedOut: false,
      fallbackToOriginal: inputSource != 'thumbnail',
      fallbackReason: inputSource == 'thumbnail' ? 'none' : fallbackReason,
      loadMs: loadWatch.elapsedMicroseconds / 1000.0,
      thumbnailReadMs: thumbnailReadMs,
      fileReadMs: fileReadMs,
    );
  }

  Future<File> _createAuxiliaryAnalysisFile(
    File sourceFile,
    int photoId,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
    final targetPath =
        '${tempDir.path}/temp_mlkit_${photoId}_$uniqueSuffix.jpg';
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
  Future<_AiPersistenceProfile> _markAsAnalyzed(
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
    MobileClipBackend selectedBackend, {
    bool skipVectorIndexWrite = false,
  }) async {
    final isarWriteWatch = Stopwatch()..start();
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
    isarWriteWatch.stop();

    var objectBoxWriteMs = 0.0;
    if (!skipVectorIndexWrite) {
      final objectBoxWriteWatch = Stopwatch()..start();
      if (imageEmbedding.isEmpty) {
        _photoEmbeddingIndexRepository.deleteByPhotoIds(<int>[id]);
      } else {
        _photoEmbeddingIndexRepository.upsertEmbedding(
          photoId: id,
          vector: imageEmbedding,
          modelVersion: buildPhotoEmbeddingModelVersion(selectedBackend),
        );
      }
      objectBoxWriteWatch.stop();
      objectBoxWriteMs = objectBoxWriteWatch.elapsedMicroseconds / 1000.0;
    }

    return _AiPersistenceProfile(
      isarWriteMs: isarWriteWatch.elapsedMicroseconds / 1000.0,
      objectBoxWriteMs: objectBoxWriteMs,
    );
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

Future<(int, int)?> _readImageDimensions(
  File imageFile, {
  int? knownWidth,
  int? knownHeight,
}) async {
  try {
    // Catalog dimensions are sufficient for the face min-size gate.
    if (knownWidth != null &&
        knownHeight != null &&
        knownWidth > 0 &&
        knownHeight > 0) {
      return (knownWidth, knownHeight);
    }

    final bytes = await imageFile.readAsBytes();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info != null && info.width > 0 && info.height > 0) {
      return (info.width, info.height);
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }
    final baked = img.bakeOrientation(decoded);
    return (baked.width, baked.height);
  } catch (error) {
    debugPrint('⚠️ 读取分析图尺寸失败 path=${imageFile.path}: $error');
    return null;
  }
}
