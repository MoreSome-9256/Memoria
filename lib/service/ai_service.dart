import 'dart:io';
import 'dart:math' as math;
// import 'dart:math'; // ➕ 新增：用于生成随机的假数据
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:isar/isar.dart';
import '../models/entity/photo_entity.dart';
import '../utils/ai_score_helper.dart';
import 'photo_service.dart';
import 'event_service.dart';
import 'mobileclip_tag_service.dart';
import 'mobileclip_vision_service.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final ValueNotifier<AIAnalysisProgress> _progressNotifier =
      ValueNotifier<AIAnalysisProgress>(AIAnalysisProgress.idle());

  bool _isAnalyzing = false;

  ValueListenable<AIAnalysisProgress> get progressListenable =>
      _progressNotifier;

  // 简单的标签翻译字典 (毕设演示够用了，也可以接翻译API)
  final Map<String, String> _tagTranslation = {
    'Food': '美食',
    'Dish': '菜肴',
    'Cuisine': '料理',
    'Meal': '餐食',
    'Beach': '海滩',
    'Sea': '大海',
    'Ocean': '海洋',
    'Sky': '天空',
    'Cloud': '云',
    'Sunset': '日落',
    'Sunrise': '日出',
    'Plant': '植物',
    'Tree': '树木',
    'Flower': '花朵',
    'Grass': '草地',
    'Garden': '花园',
    'Person': '人像',
    'People': '人群',
    'Face': '面孔',
    'Child': '儿童',
    'Baby': '婴儿',
    'Cat': '猫',
    'Dog': '狗',
    'Pet': '宠物',
    'Animal': '动物',
    'Bird': '鸟',
    'Building': '建筑',
    'City': '城市',
    'Architecture': '建筑物',
    'Tower': '塔',
    'Bridge': '桥',
    'Mountain': '山',
    'Hill': '山丘',
    'Forest': '森林',
    'Landscape': '风景',
    'Car': '汽车',
    'Vehicle': '车辆',
    'Road': '道路',
    'Street': '街道',
    'Water': '水',
    'Lake': '湖',
    'River': '河',
    'Snow': '雪',
    'Winter': '冬天',
    'Summer': '夏天',
    'Spring': '春天',
    'Autumn': '秋天',
    'Fall': '秋天',
    'Night': '夜晚',
    'Evening': '傍晚',
    'Morning': '早晨',
    'Daytime': '白天',
    'Indoor': '室内',
    'Outdoor': '户外',
    'Room': '房间',
    'Bedroom': '卧室',
    'Kitchen': '厨房',
    'Restaurant': '餐厅',
    'Table': '桌子',
    'Chair': '椅子',
    'Furniture': '家具',
    'Window': '窗户',
    'Door': '门',
    'Wall': '墙',
    'Ceiling': '天花板',
    'Floor': '地板',
    'Art': '艺术',
    'Painting': '绘画',
    'Sculpture': '雕塑',
    'Museum': '博物馆',
    'Sport': '运动',
    'Game': '游戏',
    'Ball': '球',
    'Playground': '操场',
    'Park': '公园',
    'Festival': '节日',
    'Party': '派对',
    'Concert': '音乐会',
    'Stage': '舞台',
    'Light': '灯光',
    'Darkness': '黑暗',
    'Shadow': '阴影',
    'Reflection': '倒影',
    'Mirror': '镜子',
    'Glass': '玻璃',
    'Book': '书',
    'Paper': '纸',
    'Pen': '笔',
    'Computer': '电脑',
    'Phone': '手机',
    'Screen': '屏幕',
    'Technology': '科技',
    'Drink': '饮料',
    'Coffee': '咖啡',
    'Tea': '茶',
    'Wine': '酒',
    'Bottle': '瓶子',
    'Cup': '杯子',
    'Fruit': '水果',
    'Vegetable': '蔬菜',
    'Dessert': '甜点',
    'Cake': '蛋糕',
    'Bread': '面包',
    'Smile': '微笑',
    'Happy': '快乐',
    'Fun': '有趣',
    'Beautiful': '美丽',
    'Colorful': '色彩斑斓',
  };

  // 🧠 核心方法：批量分析未处理的照片（包含人脸检测和情感分析）
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
    final isar = PhotoService().isar;
    final mobileClipVision = MobileClipVisionService();
    final mobileClipTagService = MobileClipTagService();
    await mobileClipVision.warmUp();
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
      currentStep: '准备开始 AI 打标',
    );

    // 2. 初始化 ML Kit 组件
    final ImageLabelerOptions labelerOptions = ImageLabelerOptions(
      confidenceThreshold: 0.6,
    );
    final imageLabeler = ImageLabeler(options: labelerOptions);

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
              await _markAsAnalyzed(photo.id, [], 0, 0.0, 0.0, isar);
              didFail = true;
              continue;
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

            final embedding = await mobileClipVision.embedImageFile(
              compressedTempFile,
            );

            final inputImage = InputImage.fromFile(compressedTempFile);

            // 📸 任务1：标签识别
            final labels = await imageLabeler.processImage(inputImage);
            final mlKitTags = labels
                .map((label) => _tagTranslation[label.label] ?? label.label)
                .toList(growable: false);
            final mobileClipTags = await mobileClipTagService.retrieveTags(
              embedding,
            );
            final validTags = _mergePreferredTags(mobileClipTags, mlKitTags);

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
              tags: validTags,
            );

            await _markAsAnalyzed(
              photo.id,
              validTags,
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
            await _markAsAnalyzed(photo.id, [], 0, 0.0, 0.0, isar);
            if (remainingPhotos != null) {
              remainingPhotos--;
            }
          } finally {
            if (didFail) {
              failedCount++;
            }
            processedCount++;
            _progressNotifier.value = AIAnalysisProgress.running(
              total: targetTotal,
              completed: processedCount,
              failed: failedCount,
              currentStep: processedCount >= targetTotal
                  ? '正在收尾整理结果'
                  : '已完成 $processedCount / $targetTotal 张',
            );

            // 🧹 清理临时文件
            if (compressedTempFile != null && compressedTempFile.existsSync()) {
              compressedTempFile.deleteSync();
            }
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      imageLabeler.close();
      faceDetector.close();

      if (affectedEventIds.isNotEmpty) {
        await EventService().refreshEventSmartInfo(affectedEventIds.toList());
      }
      debugPrint("✅ AI 分析完成，总计处理: $totalAnalyzed 张");
    } finally {
      _progressNotifier.value = AIAnalysisProgress.idle();
      _isAnalyzing = false;
    }
  }

  List<String> _mergePreferredTags(
    List<String> mobileClipTags,
    List<String> fallbackTags, {
    int maxTags = 5,
  }) {
    final merged = <String>[];

    void addTags(List<String> source) {
      for (final tag in source) {
        final normalized = tag.trim();
        if (normalized.isEmpty || merged.contains(normalized)) {
          continue;
        }
        merged.add(normalized);
        if (merged.length >= maxTags) {
          return;
        }
      }
    }

    addTags(mobileClipTags);
    if (merged.isEmpty) {
      addTags(fallbackTags);
    }

    return merged;
  }

  // 将 AI 分析结果写入数据库（增强版）
  Future<void> _markAsAnalyzed(
    Id id,
    List<String> tags,
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
    required this.total,
    required this.completed,
    required this.failed,
    required this.currentStep,
  });

  factory AIAnalysisProgress.idle() {
    return const AIAnalysisProgress(
      isRunning: false,
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
      total: total,
      completed: completed,
      failed: failed,
      currentStep: currentStep,
    );
  }

  final bool isRunning;
  final int total;
  final int completed;
  final int failed;
  final String currentStep;

  double get fraction {
    if (total <= 0) {
      return 0;
    }
    return (completed / total).clamp(0, 1).toDouble();
  }

  bool get isVisible => isRunning && total > 0;
}
