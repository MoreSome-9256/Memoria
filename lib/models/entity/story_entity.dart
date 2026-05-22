import 'package:objectbox/objectbox.dart';
import 'photo_entity.dart';
import '../vo/photo.dart';
import '../../utils/ocr_policy.dart';

/// 故事实体 - 存储用户生成的故事文章
@Entity()
class StoryEntity {
  @Id()
  int id = 0;

  // 📝 故事基本信息
  late String title; // 故事主题/标题
  late String subtitle; // 副标题/切入点
  late String content; // Markdown 格式内容（含图片占位符）
  late int createdAt; // 创建时间戳
  late int updatedAt; // 更新时间戳
  late bool isHorizontal;
  String? targetPlatform;

  // 🔗 关联信息
  @Index()
  late int eventId; // 来源事件 ID
  List<int> photoIds = []; // 选中的照片 ID 列表（按时间顺序）

  // 🎨 元数据
  int photoCount = 0; // 照片数量（冗余字段）
  bool isLlmGenerated = true; // 是否由 LLM 生成
  bool isManuallySaved = false; // 是否用户手动保存（false表示自动保存/草稿）
  String? cachedVideoPath; // 已生成视频的文件路径，避免重复渲染
  String? cachedVideoKey; // 视频缓存指纹，用于 VideoCacheService 查找
  String? customMusicPath; // 自定义音乐文件路径
  String? dynamicBeatDataJson; // 音乐节拍数据（JSON）
  String? videoParamsJson; // 视频渲染参数（JSON，含文字样式、特效等）

  // 📅 格式化创建时间
  String get createdAtText {
    final date = DateTime.fromMillisecondsSinceEpoch(createdAt);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // 🔄 工厂方法：从事件和选中照片创建故事
  static StoryEntity create({
    required String title,
    required String subtitle,
    required String content,
    required int eventId,
    required List<int> photoIds,
    bool isManuallySaved = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return StoryEntity()
      ..title = title
      ..subtitle = subtitle
      ..content = content
      ..createdAt = now
      ..updatedAt = now
      ..eventId = eventId
      ..photoIds = photoIds
      ..photoCount = photoIds.length
      ..isLlmGenerated = true
      ..isManuallySaved = isManuallySaved;
  }

  // 🔄 解析 Markdown 为 StorySection 列表（用于 UI 展示）
  /// StorySection 定义在 story_result_page.dart 中
  /// 这里返回一个 List<Map<String, dynamic>> 供 UI 层转换
  List<Map<String, dynamic>> parseToSections(List<PhotoEntity> photos) {
    final sections = <Map<String, dynamic>>[];
    final lines = content.split('\n');
    final buffer = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();

      // 检查图片占位符：![img](index)
      final imgMatch = RegExp(r'!\[img\]\((\d+)\)').firstMatch(trimmed);

      if (imgMatch != null) {
        // 遇到图片占位符
        if (buffer.isNotEmpty) {
          final indexStr = imgMatch.group(1);
          final index = int.tryParse(indexStr ?? '0') ?? 0;

          if (index < photos.length) {
            final photoEntity = photos[index];
            sections.add({
              'text': buffer.toString().trim(),
              'photo': _convertToPhoto(photoEntity),
            });
          }
          buffer.clear();
        }
      } else if (trimmed.isNotEmpty) {
        // 累积文本内容
        buffer.writeln(line);
      }
    }

    // 处理剩余文本（追加到最后一个 section）
    if (buffer.isNotEmpty && sections.isNotEmpty) {
      final lastSection = sections.last;
      sections[sections.length - 1] = {
        'text': '${lastSection['text']}\n\n${buffer.toString().trim()}',
        'photo': lastSection['photo'],
      };
    }

    return sections;
  }

  // 🔄 将编辑后的 sections 转回 Markdown
  /// sections 是 List<{text: String, photo: Photo}> 格式
  static String sectionsToMarkdown(List<Map<String, dynamic>> sections) {
    final buffer = StringBuffer();

    for (int i = 0; i < sections.length; i++) {
      final text = sections[i]['text'] as String;

      // 写入文本内容
      buffer.writeln(text);
      buffer.writeln();

      // 写入图片占位符
      buffer.writeln('![img]($i)');
      buffer.writeln();
    }

    return buffer.toString().trim();
  }

  // 🔄 PhotoEntity 转换为 Photo (UI 模型)
  static Photo _convertToPhoto(PhotoEntity entity) {
    return Photo(
      id: entity.assetId,
      path: entity.path,
      dateTaken: DateTime.fromMillisecondsSinceEpoch(entity.timestamp),
      tags: entity.aiTags ?? [],
      caption: entity.aiCaption?.trim(),
      ocrSummary: OcrPolicy.effectiveSummary(
        tags: entity.ocrTags ?? const <String>[],
        text: entity.ocrText,
      ),
      ocrTags: OcrPolicy.effectiveTags(entity.ocrTags ?? const <String>[]),
      location:
          entity.locationName ??
          entity.district ??
          entity.city ??
          entity.province,
    );
  }
}
