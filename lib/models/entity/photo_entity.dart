/// 照片元数据的核心 ObjectBox 实体，保存尺寸、位置、标签和向量信息。

import 'dart:typed_data';

import 'package:objectbox/objectbox.dart';

@Entity()
class PhotoEntity {
  @Id()
  int id = 0;

  @Unique(onConflict: ConflictStrategy.replace)
  late String assetId;

  late String path;
  @Index()
  late int timestamp;

  // 📐 图片尺寸信息 (用于过滤截图和UI占位)
  late int width;
  late int height;

  // 媒体索引信息：扫描阶段写入，UI 阶段只读本地字段，避免逐张反查系统相册。
  @Index()
  String mediaKind = 'image'; // image / dynamicImage / video
  String? mimeType;
  bool isLivePhoto = false;
  @Property(type: PropertyType.byteVector)
  Uint8List? thumbnailBytes;

  // 📍 地理坐标 (WGS84 标准坐标)
  double? latitude;
  double? longitude;

  // 🏙️ 地址信息 (高德解析结果)
  @Index()
  String? province; // 省：北京市 / 山东省

  @Index()
  String? city; // 市：北京市 / 青岛市 (直辖市这里可能为空或与省相同)

  String? district; // 区：朝阳区 / 市南区
  String? locationName; // 更细粒度地点：学校/商场/园区/楼栋/POI
  String? formattedAddress; // 完整地址：北京市朝阳区xx街道...

  String? adcode; // 城市编码 (如 110101)，用于精确数据分析

  // 状态标记
  bool isLocationProcessed = false;

  // 🤖 AI 分析相关
  List<String>? aiTags; // AI 识别的标签（美食、海滩等）
  @Index()
  bool isAiAnalyzed = false; // AI 分析状态标记
  @Index()
  bool isAiAnalysisCandidate = false; // 已明确加入某轮 AI 任务但尚未完成
  String? aiCaption; // 单张照片的一句话描述
  List<double>? imageEmbedding; // MobileCLIP 图像向量，用于后续聚类
  String? ocrText; // OCR 提取出的原始文本
  List<String>? ocrTags; // 从 OCR 文本中提炼出的短标签

  // 👤 人脸识别信息 (用于后续 AI 选图)
  int faceCount = 0; // 检测到的人脸数量
  double smileProb = 0.0; // 微笑概率 (0.0 - 1.0)

  // 😊 情感分析 (AI 增强)
  double? joyScore; // 欢乐值评分 (0.0 - 1.0)，综合人脸微笑度和场景标签

  // 🔗 事件关联 (快速查找所属事件)
  @Index()
  int? eventId; // 所属事件的 ID，用于增量更新

  // 计算图片宽高比
  double get aspectRatio => width > 0 ? width / height : 1.0;

  // 判断是否可能是截图 (极端比例)
  bool get isProbablyScreenshot {
    final normalizedPath = path.toLowerCase();
    const screenshotKeywords = <String>[
      'screenshot',
      'screen_shot',
      'screen-shot',
      'screen shot',
      'capture',
      'screen capture',
      '截屏',
      '截图',
    ];
    if (screenshotKeywords.any(normalizedPath.contains)) {
      return true;
    }
    final ratio = aspectRatio;
    return ratio > 0 && ratio < 0.52;
  }
}
