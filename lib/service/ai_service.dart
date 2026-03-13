import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
// import 'dart:math'; // ➕ 新增：用于生成随机的假数据
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:isar/isar.dart';
import '../models/entity/photo_entity.dart';
import '../utils/ai_score_helper.dart';
import '../utils/tag_sanitizer.dart';
import 'photo_service.dart';
import 'event_service.dart';
import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_embedding_service.dart';
import 'mobileclip_tag_service.dart';
import 'ocr_service.dart';
import 'photo_caption_service.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  static const Set<String> _blockedVisualTags = <String>{
    'Screenshot',
    'Cool',
    'Glasses',
    'Goggles',
    'Selfie',
    '截图',
    '自拍',
  };

  final ValueNotifier<AIAnalysisProgress> _progressNotifier =
      ValueNotifier<AIAnalysisProgress>(AIAnalysisProgress.idle());

  bool _isAnalyzing = false;
  bool _pauseRequested = false;
  bool _stopRequested = false;
  Completer<void>? _analysisCompleter;

  ValueListenable<AIAnalysisProgress> get progressListenable =>
      _progressNotifier;

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
    if (!_isAnalyzing || !_pauseRequested) {
      return;
    }
    _pauseRequested = false;
    final current = _progressNotifier.value;
    if (current.isVisible) {
      _progressNotifier.value = current.copyWith(
        isRunning: true,
        isPaused: false,
        currentStep: '继续后台打标中',
      );
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
    final isar = PhotoService().isar;
    final mobileClipEmbeddingService = MobileClipEmbeddingService();
    final mobileClipTagService = MobileClipTagService();
    final photoCaptionService = PhotoCaptionService();
    final ocrService = OcrService();
    final selectedBackend = await mobileClipEmbeddingService.getSelectedBackend();
    await mobileClipEmbeddingService.warmUpBackend(selectedBackend);
    await mobileClipTagService.warmUp();

    final pendingCount = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(false)
        .count();
    final targetTotal = maxPhotos == null
        ? pendingCount
        : math.min(pendingCount, maxPhotos);

    if (targetTotal <= 0) {
      _progressNotifier.value = AIAnalysisProgress.idle();
      _isAnalyzing = false;
      return;
    }

    _progressNotifier.value = AIAnalysisProgress.running(
      total: targetTotal,
      completed: 0,
      failed: 0,
      currentStep: '准备开始 AI 打标 (${selectedBackend.label})',
    );

    // 2. 初始化 ML Kit 人脸检测（视觉标签改由 MobileCLIP 统一生成）
    final FaceDetectorOptions faceOptions = FaceDetectorOptions(
      enableClassification: true,
      enableTracking: false,
    );
    final faceDetector = FaceDetector(options: faceOptions);

    var totalAnalyzed = 0;
    final affectedEventIds = <int>{};
    var remainingPhotos = maxPhotos;
    var failedCount = 0;
    var processedCount = 0;

    try {
      while (true) {
        final shouldContinue = await _waitIfPaused();
        if (!shouldContinue || _stopRequested) {
          break;
        }

        if (remainingPhotos != null && remainingPhotos <= 0) {
          break;
        }

        final currentBatchSize = remainingPhotos == null
            ? batchSize
            : math.min(batchSize, remainingPhotos);

        // 🌟 修复点：直接拉取未分析的照片，不搞复杂的预取和过滤
        final photosToAnalyze = await isar
            .collection<PhotoEntity>()
            .filter()
            .isAiAnalyzedEqualTo(false)
            .sortByTimestampDesc()
            .limit(currentBatchSize)
            .findAll();

        if (photosToAnalyze.isEmpty) {
          break;
        }

        debugPrint("🤖 开始 AI 视觉分析，本批次: ${photosToAnalyze.length} 张");

        for (final photo in photosToAnalyze) {
          final shouldContinue = await _waitIfPaused();
          if (!shouldContinue || _stopRequested) {
            break;
          }

          final file = File(photo.path);
          var didFail = false;
          File? compressedTempFile;
          _progressNotifier.value = AIAnalysisProgress.running(
            total: targetTotal,
            completed: processedCount,
            failed: failedCount,
            currentStep: '正在分析第 ${processedCount + 1} / $targetTotal 张',
          );

          try {
            if (!file.existsSync()) {
              await _markAsAnalyzed(
                photo.id,
                [],
                const <double>[],
                '',
                '',
                const <String>[],
                0,
                0.0,
                0.0,
                isar,
              );
              didFail = true;
              continue;
            }
            // ==========================================
            // 🌟 核心拦截网：在这里识别并放过截图！
            // ==========================================
            if (photo.isProbablyScreenshot) {
              debugPrint("⏭️ 检测到截图，跳过 AI 视觉打标: ${photo.id}");
              // 直接假装分析完了，随便塞个“截图”标签，其他全部塞空值
              await _markAsAnalyzed(
                photo.id,
                ['截图'], // visualTags
                const <double>[], // embedding (🌟 新增：空向量)
                '', // caption (🌟 新增：空描述)
                '', // ocrText
                const <String>[], // ocrTags
                0, // faceCount
                0.0, // maxSmileProb
                0.0, // joyScore
                isar, // isar 实例
              );
              if (photo.eventId != null) {
                affectedEventIds.add(photo.eventId!);
              }
              totalAnalyzed++;
              if (remainingPhotos != null) {
                remainingPhotos--;
              }
              continue; // 🚀 直接触发 finally 块去更新进度条，并进入下一张照片！
            }

            final tempDir = await getTemporaryDirectory();
            final targetPath = '${tempDir.path}/temp_mlkit_${photo.id}.jpg';

            // 🔧 压缩图片，防止 OOM
            final result = await FlutterImageCompress.compressAndGetFile(
              file.absolute.path,
              targetPath,
              minWidth: 1024,
              minHeight: 1024,
              quality: 80,
            );

            if (result == null) throw Exception("压缩失败");
            compressedTempFile = File(result.path);

            final embedding =
                await mobileClipEmbeddingService.embedImageFileWithBackend(
                  compressedTempFile,
                  selectedBackend,
                );

            final inputImage = InputImage.fromFile(compressedTempFile);

            // 📸 任务1：视觉标签识别（仅使用 MobileCLIP）
            final mobileClipTags = await mobileClipTagService.retrieveTags(
              embedding,
            );
            final visualTags = _sanitizeVisualTags(
              mobileClipTags,
            );

            OcrResult ocrResult = OcrResult.empty();
            if (OcrService.shouldRunOcr(
              visualTags,
              aspectRatio: photo.aspectRatio,
            )) {
              ocrResult = await ocrService.analyzeImageFile(compressedTempFile);
            }

            // 😊 任务2：情感分析
            final faces = await faceDetector.processImage(inputImage);
            int faceCount = faces.length;
            double maxSmileProb = faces.isNotEmpty
                ? faces
                      .map((f) => f.smilingProbability ?? 0.0)
                      .reduce((a, b) => a > b ? a : b)
                : 0.0;

            double joyScore = AIScoreHelper.calculateJoyScore(
              faceCount: faceCount,
              maxSmileProb: maxSmileProb,
              tags: visualTags,
            );

            final caption = await photoCaptionService.generateCaption(
              imageFile: compressedTempFile,
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

            if (photo.eventId != null) {
              affectedEventIds.add(photo.eventId!);
            }
            totalAnalyzed++;
            if (remainingPhotos != null) {
              remainingPhotos--;
            }
          } catch (e) {
            didFail = true;
            debugPrint("❌ AI 分析失败: $e");
            await _markAsAnalyzed(
              photo.id,
              [],
              const <double>[],
              '',
              '',
              const <String>[],
              0,
              0.0,
              0.0,
              isar,
            );
            if (remainingPhotos != null) {
              remainingPhotos--;
            }
          } finally {
            if (didFail) {
              failedCount++;
            }
            processedCount++;
            if (_stopRequested) {
              _progressNotifier.value = AIAnalysisProgress.stopping(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: '正在结束本轮打标…',
              );
            } else if (_pauseRequested) {
              _progressNotifier.value = AIAnalysisProgress.paused(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: '已暂停，随时可以继续',
              );
            } else {
              _progressNotifier.value = AIAnalysisProgress.running(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: processedCount >= targetTotal
                    ? '正在收尾整理结果'
                    : '已完成 $processedCount / $targetTotal 张',
              );
            }

            // 🧹 清理临时文件
            if (compressedTempFile != null && compressedTempFile.existsSync()) {
              compressedTempFile.deleteSync();
            }
          }

          if (_stopRequested) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }

        if (_stopRequested) {
          break;
        }
      }

      faceDetector.close();

      if (affectedEventIds.isNotEmpty) {
        await EventService().refreshEventSmartInfo(affectedEventIds.toList());
      }
      debugPrint("✅ AI 分析完成，总计处理: $totalAnalyzed 张");
    } finally {
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

  Future<void> backfillMissingCaptionsInBackground({
    int batchSize = 12,
    int? maxPhotos,
  }) async {
    if (_isAnalyzing) {
      debugPrint('⏭️ AI 打标任务已在运行，跳过 caption 回填');
      return;
    }

    _isAnalyzing = true;
    _pauseRequested = false;
    _stopRequested = false;
    _analysisCompleter = Completer<void>();

    final isar = PhotoService().isar;
    final photoCaptionService = PhotoCaptionService();
    final targetTotal = await _countCaptionBackfillCandidates(
      isar,
      maxPhotos: maxPhotos,
    );

    if (targetTotal <= 0) {
      _progressNotifier.value = AIAnalysisProgress.idle();
      _isAnalyzing = false;
      return;
    }

    _progressNotifier.value = AIAnalysisProgress.running(
      total: targetTotal,
      completed: 0,
      failed: 0,
      currentStep: '准备回填旧照片 caption',
    );

    var processedCount = 0;
    var failedCount = 0;
    var remainingPhotos = maxPhotos;
    final attemptedPhotoIds = <Id>{};

    try {
      while (true) {
        final shouldContinue = await _waitIfPaused();
        if (!shouldContinue || _stopRequested) {
          break;
        }

        if (remainingPhotos != null && remainingPhotos <= 0) {
          break;
        }

        final currentBatchSize = remainingPhotos == null
            ? batchSize
            : math.min(batchSize, remainingPhotos);
        final photosToBackfill =
            await _loadCaptionBackfillCandidates(
              isar,
              limit: currentBatchSize,
            ).then(
              (photos) => photos
                  .where((photo) => !attemptedPhotoIds.contains(photo.id))
                  .toList(growable: false),
            );

        if (photosToBackfill.isEmpty) {
          break;
        }

        for (final photo in photosToBackfill) {
          attemptedPhotoIds.add(photo.id);
          final shouldContinue = await _waitIfPaused();
          if (!shouldContinue || _stopRequested) {
            break;
          }

          var didFail = false;
          _progressNotifier.value = AIAnalysisProgress.running(
            total: targetTotal,
            completed: processedCount,
            failed: failedCount,
            currentStep:
                '正在回填第 ${processedCount + 1} / $targetTotal 张照片的 caption',
          );

          try {
            final file = File(photo.path);
            if (!file.existsSync()) {
              didFail = true;
            } else {
              final caption = await photoCaptionService.generateCaption(
                imageFile: file,
                visualTags: photo.aiTags ?? const <String>[],
                ocrTags: photo.ocrTags ?? const <String>[],
                ocrText: photo.ocrText ?? '',
                location:
                    photo.locationName ??
                    photo.district ??
                    photo.city ??
                    photo.province,
                takenAt: DateTime.fromMillisecondsSinceEpoch(photo.timestamp),
                isProbablyScreenshot: photo.isProbablyScreenshot,
                faceCount: photo.faceCount,
              );
              await _markCaptionBackfilled(photo.id, caption, isar);
            }
          } catch (e) {
            didFail = true;
            debugPrint('❌ caption 回填失败: $e');
          } finally {
            if (didFail) {
              failedCount++;
            }
            processedCount++;
            if (remainingPhotos != null) {
              remainingPhotos--;
            }

            if (_stopRequested) {
              _progressNotifier.value = AIAnalysisProgress.stopping(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: '正在结束本轮 caption 回填…',
              );
            } else if (_pauseRequested) {
              _progressNotifier.value = AIAnalysisProgress.paused(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: 'caption 回填已暂停，随时可以继续',
              );
            } else {
              _progressNotifier.value = AIAnalysisProgress.running(
                total: targetTotal,
                completed: processedCount,
                failed: failedCount,
                currentStep: processedCount >= targetTotal
                    ? '正在收尾整理 caption 结果'
                    : '已回填 $processedCount / $targetTotal 张 caption',
              );
            }
          }

          if (_stopRequested) {
            break;
          }

          await Future.delayed(const Duration(milliseconds: 80));
        }

        if (_stopRequested) {
          break;
        }
      }

      debugPrint('✅ caption 回填完成，总计处理: $processedCount 张');
    } finally {
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

  Future<int> _countCaptionBackfillCandidates(
    Isar isar, {
    int? maxPhotos,
  }) async {
    final nullCaptionCount = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .aiCaptionIsNull()
        .count();
    final emptyCaptionCount = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .aiCaptionIsEmpty()
        .count();
    final total = nullCaptionCount + emptyCaptionCount;
    return maxPhotos == null ? total : math.min(total, maxPhotos);
  }

  Future<List<PhotoEntity>> _loadCaptionBackfillCandidates(
    Isar isar, {
    required int limit,
  }) async {
    final nullCaptionPhotos = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .aiCaptionIsNull()
        .sortByTimestampDesc()
        .limit(limit)
        .findAll();
    if (nullCaptionPhotos.length >= limit) {
      return nullCaptionPhotos;
    }

    final emptyCaptionPhotos = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .aiCaptionIsEmpty()
        .sortByTimestampDesc()
        .limit(limit - nullCaptionPhotos.length)
        .findAll();

    return <PhotoEntity>[...nullCaptionPhotos, ...emptyCaptionPhotos];
  }

  Future<void> _markCaptionBackfilled(
    Id id,
    String aiCaption,
    Isar isar,
  ) async {
    final trimmedCaption = aiCaption.trim();
    if (trimmedCaption.isEmpty) {
      return;
    }

    await isar.writeTxn(() async {
      final photo = await isar.collection<PhotoEntity>().get(id);
      if (photo == null) {
        return;
      }

      photo.aiCaption = trimmedCaption;
      await isar.collection<PhotoEntity>().put(photo);
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
    );
  }

  factory AIAnalysisProgress.running({
    required int total,
    required int completed,
    required int failed,
    required String currentStep,
  }) {
    return AIAnalysisProgress(
      isRunning: true,
      isPaused: false,
      isStopping: false,
      total: total,
      completed: completed,
      failed: failed,
      currentStep: currentStep,
    );
  }

  factory AIAnalysisProgress.paused({
    required int total,
    required int completed,
    required int failed,
    required String currentStep,
  }) {
    return AIAnalysisProgress(
      isRunning: false,
      isPaused: true,
      isStopping: false,
      total: total,
      completed: completed,
      failed: failed,
      currentStep: currentStep,
    );
  }

  factory AIAnalysisProgress.stopping({
    required int total,
    required int completed,
    required int failed,
    required String currentStep,
  }) {
    return AIAnalysisProgress(
      isRunning: false,
      isPaused: false,
      isStopping: true,
      total: total,
      completed: completed,
      failed: failed,
      currentStep: currentStep,
    );
  }

  final bool isRunning;
  final bool isPaused;
  final bool isStopping;
  final int total;
  final int completed;
  final int failed;
  final String currentStep;

  AIAnalysisProgress copyWith({
    bool? isRunning,
    bool? isPaused,
    bool? isStopping,
    int? total,
    int? completed,
    int? failed,
    String? currentStep,
  }) {
    return AIAnalysisProgress(
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      isStopping: isStopping ?? this.isStopping,
      total: total ?? this.total,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      currentStep: currentStep ?? this.currentStep,
    );
  }

  double get fraction {
    if (total <= 0) {
      return 0;
    }
    return (completed / total).clamp(0, 1).toDouble();
  }

  bool get isVisible => (isRunning || isPaused || isStopping) && total > 0;
}
