import 'package:isar/isar.dart';
import 'package:photo_manager/photo_manager.dart';

import '../data/tag_taxonomy_v2.dart';
import '../models/entity/digital_album_book_entity.dart';
import '../models/entity/story_entity.dart';
import '../models/entity/event_entity.dart';
import '../models/entity/photo_entity.dart';
import '../utils/ocr_policy.dart';
import '../utils/tag_sanitizer.dart';
import 'photo_service.dart';
import 'llm_service.dart';
import 'event_service.dart';

/// 故事服务 - 管理故事的生成和存储
class StoryService {
  static final StoryService _instance = StoryService._internal();
  factory StoryService() => _instance;
  StoryService._internal();

  static const Set<String> _textSceneTags = <String>{
    '文字',
    '文本',
    '文档',
    '屏幕',
    '截图',
    '聊天',
    '表格',
    '课件',
    '试卷',
    '海报',
    '春联',
    '书页',
    '书本',
    '页面',
    '黑板',
    '广告',
    '专题',
  };

  static const Set<String> _nonPromptTags = <String>{
    memoriaOtherLabel,
  };

  /// 📝 核心方法：生成故事
  ///
  /// 参数:
  /// - [event]: 事件实体
  /// - [selectedPhotos]: 用户选中的照片列表
  /// - [title]: 故事主题/标题
  /// - [subtitle]: 副标题/切入点
  /// - [length]: 故事篇幅（短/中）
  ///
  /// 返回: 生成的故事实体（失败返回 null）
  Future<StoryEntity?> generateStory({
    required EventEntity event,
    required List<PhotoEntity> selectedPhotos,
    required String title,
    required String subtitle,
    // required StoryLength length,
    required String aspectRatio,
    required String platform
  }) async {
    try {
      if (event.photoCount < EventService.minPhotosForDisplay) {
        print(
          "⚠️ 事件照片数(${event.photoCount})低于展示阈值(${EventService.minPhotosForDisplay})，跳过故事生成",
        );
        return null;
      }

      if (selectedPhotos.isEmpty) {
        print("⚠️ 没有选中照片，无法生成故事");
        return null;
      }

      // 1. 按时间顺序排序照片（确保故事的连贯性）
      final sortedPhotos = List<PhotoEntity>.from(selectedPhotos)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final promptTagsByPhoto = sortedPhotos
          .map(_buildPromptTagsForPhoto)
          .toList(growable: false);

      // 🌟 2. 提取用于给后端生成故事的核心特征
      final allTags = promptTagsByPhoto.expand((tags) => tags).toSet().toList();
      final rawOcrTags = sortedPhotos
          .expand((p) => p.ocrTags ?? <String>[])
          .toList(growable: false);
      final allOcrTags = OcrPolicy.effectiveTags(rawOcrTags);
      final ocrHighlights = sortedPhotos
          .asMap()
          .entries
          .map((entry) {
            final text = OcrPolicy.effectiveText(
              entry.value.ocrText,
              maxLength: 80,
            );
            if (text.isEmpty) {
              return null;
            }
            return '第${entry.key + 1}张：$text';
          })
          .whereType<String>()
          .take(8)
          .toList(growable: false);
      final promptTags = <String>{...allTags, ...allOcrTags}.toList();

      double totalJoy = 0;
      int validJoyCount = 0;
      for (var p in sortedPhotos) {
        if (p.joyScore != null) {
          totalJoy += p.joyScore!;
          validJoyCount++;
        }
      }
      final avgJoyScore = validJoyCount > 0 ? totalJoy / validJoyCount : 0.0;

      print(
        "📝 开始请求后端生成图文与配乐：${sortedPhotos.length} 张照片, 标签: $promptTags, OCR线索: ${ocrHighlights.length} 条, 欢乐值: $avgJoyScore",
      );

      // 将照片特征转化为大模型可消费的镜头分镜文本，序号与 ![img](i) 一一对应。
      final photoContext = StringBuffer();
      for (int i = 0; i < sortedPhotos.length; i++) {
        final p = sortedPhotos[i];

        final fallbackTags = promptTagsByPhoto[i].isNotEmpty
            ? promptTagsByPhoto[i].join("、")
            : "日常画面";
        final visualSummary = _buildPhotoPromptSummary(
          p,
          fallbackTags: fallbackTags,
        );
        print("🕵️‍♂️ [抓内鬼] 传给 AI 的第 $i 张照片画面摘要是: $visualSummary");
        final loc = [
          p.locationName,
          p.district,
          p.province,
          p.city,
        ].where((e) => e != null && e.isNotEmpty).join("");

        final date = DateTime.fromMillisecondsSinceEpoch(p.timestamp);
        final timeStr = "${date.month}月${date.day}日";
        final textHint = _isTextHeavyPhoto(p)
            ? '；该图以屏幕或文档文字为主，不要推断人物身份、关系或职业'
            : '';

        photoContext.writeln(
          "【镜头 $i】拍摄于 $timeStr ${loc.isNotEmpty ? '($loc)' : ''}，画面内容：$visualSummary$textHint",
        );
      }
      // ==========================================

      print("📝 开始请求后端生成图文：${sortedPhotos.length} 张照片, 欢乐值: $avgJoyScore");

      // 🌟 3. 调用 LLMService 新写的综合接口
      // 🌟 3. 调用 LLMService 新写的综合接口
      final llmService = LLMService();
      final resultData = await llmService.generateStoryAndMusic(
        eventId: event.id,
        tags: promptTags.take(40).toList(), // 最多传40个高频词防撑爆
        ocrTags: allOcrTags.take(20).toList(),
        ocrHighlights: ocrHighlights,
        joyScore: avgJoyScore,
        photoCount: event.photoCount > 0
            ? event.photoCount
            : sortedPhotos.length,
        location:
            event.locationName ??
            event.district ??
            event.city ??
            event.province ??
            '未知地点',
        date: event.dateRangeText,
        stylePreference: subtitle.isNotEmpty ? subtitle : "治愈风",
        // 👇 重点：把刚才在 llm_service 里加的三个参数传进去！
        photoDetails: photoContext.toString(),
        themeTitle: title,
        themeSubtitle: subtitle,
      );

      if (resultData == null || resultData['data'] == null) {
        print("❌ 云端生成失败，可能是网络问题");
        return null;
      }

      // 4. 解析返回的数据
      final finalTitle = resultData['data']['story_title'] ?? title;
      final scriptContent = resultData['data']['script_content'] ?? "生成失败";
      final bgmUrl = resultData['data']['bgm_url']; // 拿到专属音乐链接！

      // 5. 创建并保存故事实体
      final story = StoryEntity.create(
        title: finalTitle,
        subtitle: subtitle, // 保留用户的输入偏好
        content: scriptContent,
        eventId: event.id,
        photoIds: sortedPhotos.map((p) => p.id).toList(),
      );

      // ⚠️ 如果你的 StoryEntity 里有 bgmUrl 字段，记得在这里赋值：
      // story.bgmUrl = bgmUrl;

      // 6. 存入数据库
      final isar = PhotoService().isar;
      await isar.writeTxn(() async {
        await isar.collection<StoryEntity>().put(story);
      });

      print("✅ 综合视听故事生成成功：ID=${story.id}");
      if (bgmUrl != null) print("🎵 附带专属 BGM: $bgmUrl");

      return story;
    } catch (e) {
      print("❌ 故事生成异常: $e");
      return null;
    }
  }

  List<String> _buildPromptTagsForPhoto(PhotoEntity photo) {
    final aiTags = TagSanitizer.sanitizeVisualTags(
      photo.aiTags ?? const <String>[],
    ).where((tag) => !_nonPromptTags.contains(tag)).toList(growable: false);
    final ocrTags = OcrPolicy.effectiveTags(
      photo.ocrTags ?? const <String>[],
    ).where((tag) => !_looksLikeAsciiNoise(tag)).toList(growable: false);

    if (_isTextHeavyPhoto(photo, aiTags: aiTags, ocrTags: ocrTags)) {
      final result = <String>[];

      void addTag(String value) {
        if (value.isEmpty || result.contains(value)) {
          return;
        }
        result.add(value);
      }

      for (final tag in aiTags) {
        if (_textSceneTags.contains(tag)) {
          addTag(tag);
        }
      }

      for (final tag in ocrTags) {
        addTag(tag);
      }

      if (photo.isProbablyScreenshot) {
        addTag('截图');
      }

      if (result.isEmpty) {
        addTag(photo.isProbablyScreenshot ? '屏幕' : '文字');
      }

      return result.take(5).toList(growable: false);
    }

    return aiTags.take(5).toList(growable: false);
  }

  bool _isTextHeavyPhoto(
    PhotoEntity photo, {
    List<String>? aiTags,
    List<String>? ocrTags,
  }) {
    final effectiveAiTags = aiTags ?? photo.aiTags ?? const <String>[];
    final effectiveOcrTags = ocrTags ??
        OcrPolicy.effectiveTags(photo.ocrTags ?? const <String>[]);
    final ocrText = OcrPolicy.effectiveText(photo.ocrText);
    final textLikeAiCount = effectiveAiTags
        .where(_textSceneTags.contains)
        .length;

    return photo.isProbablyScreenshot ||
        effectiveOcrTags.length >= 2 ||
        ocrText.length >= 12 ||
        textLikeAiCount >= 2;
  }

  bool _looksLikeAsciiNoise(String value) {
    return RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(value);
  }

  String _buildPhotoPromptSummary(
    PhotoEntity photo, {
    required String fallbackTags,
  }) {
    final caption = photo.aiCaption?.trim();
    if (caption != null && caption.isNotEmpty) {
      final ocrSummary = _buildPromptOcrSummary(photo);
      if (ocrSummary != null) {
        return '$caption；补充文字线索：$ocrSummary';
      }
      return caption;
    }

    final ocrSummary = _buildPromptOcrSummary(photo);
    if (ocrSummary != null) {
      return '$fallbackTags；补充文字线索：$ocrSummary';
    }

    return fallbackTags;
  }

  String? _buildPromptOcrSummary(PhotoEntity photo) {
    final ocrTags = OcrPolicy.effectiveTags(
      photo.ocrTags ?? const <String>[],
    ).where((tag) => !_looksLikeAsciiNoise(tag)).toList(growable: false);
    if (ocrTags.isNotEmpty) {
      return ocrTags.take(3).join('、');
    }

    final ocrText = OcrPolicy.effectiveText(photo.ocrText);
    if (ocrText.isEmpty) {
      return null;
    }

    return ocrText.length > 36 ? '${ocrText.substring(0, 36)}...' : ocrText;
  }

  /// 🤖 调用 LLM 生成故事内容
  /*Future<String?> _generateStoryContent({
    required String title,
    required String subtitle,
    required EventEntity event,
    required List<String> photoDescriptions,
    required StoryLength length,
    required String locationMode,
  }) async {
    final llmService = LLMService();

    // 检查是否配置了 API Key
    if (!llmService.isApiKeyConfigured) {
      print("⚠️ LLM API Key 未配置，使用模拟模式");
      return _generateMockStoryContent(
        title,
        subtitle,
        photoDescriptions,
        length,
      );
    }

    try {
      // 构造 Prompt
      final prompt = StoryPromptHelper.buildStoryPrompt(
        title: title,
        subtitle: subtitle,
        event: event,
        photoDescriptions: photoDescriptions,
        isShort: length == StoryLength.short,
        locationMode: locationMode,
      );

      // 调用第三方中转站 LLM API
      final content = await llmService.generateBlogText(prompt);

      return content;
    } catch (e) {
      print("❌ LLM 调用失败: $e，回退到模拟模式");
      return _generateMockStoryContent(
        title,
        subtitle,
        photoDescriptions,
        length,
      );
    }
  }*/

  /*String _detectLocationMode(List<PhotoEntity> photos) {
    final hasAddress = photos.any(
      (photo) =>
          (photo.formattedAddress?.trim().isNotEmpty ?? false) ||
          (photo.district?.trim().isNotEmpty ?? false),
    );
    if (hasAddress) {
      return 'address';
    }

    final hasGps = photos.any(
      (photo) => photo.latitude != null && photo.longitude != null,
    );
    if (hasGps) {
      return 'gps';
    }

    return 'time-tag-only';
  }*/

  /// 🧪 模拟模式：生成假的故事内容（用于开发测试）
  /*Future<String> _generateMockStoryContent(
    String title,
    String subtitle,
    List<String> photoDescriptions,
    StoryLength length,
  ) async {
    return StoryPromptHelper.generateMockStoryContent(
      title: title,
      subtitle: subtitle,
      photoDescriptions: photoDescriptions,
      isShort: length == StoryLength.short,
    );
  }*/

  /// 📊 获取所有故事
  Future<List<StoryEntity>> getAllStories() async {
    final isar = PhotoService().isar;
    return await isar
        .collection<StoryEntity>()
        .where()
        .sortByCreatedAtDesc()
        .findAll();
  }

  /// 🔍 根据事件 ID 获取故事
  Future<List<StoryEntity>> getStoriesByEventId(int eventId) async {
    final isar = PhotoService().isar;
    return await isar
        .collection<StoryEntity>()
        .filter()
        .eventIdEqualTo(eventId)
        .sortByCreatedAtDesc()
        .findAll();
  }

  /// 💾 更新故事内容（保存编辑）
  Future<bool> updateStory(StoryEntity story) async {
    final isar = PhotoService().isar;
    story.updatedAt = DateTime.now().millisecondsSinceEpoch;

    await isar.writeTxn(() async {
      await isar.collection<StoryEntity>().put(story);
    });

    print("💾 故事已更新：ID=${story.id}");
    return true;
  }

  /// 🗑️ 删除故事
  Future<bool> deleteStory(int storyId) async {
    final deletedCount = await deleteStories(<int>[storyId]);
    return deletedCount > 0;
  }

  /// 🗑️ 批量删除故事，同时清理关联的故事相册缓存。
  Future<int> deleteStories(Iterable<int> storyIds) async {
    final isar = PhotoService().isar;
    final ids = storyIds.where((id) => id > 0).toSet().toList(growable: false);
    if (ids.isEmpty) {
      return 0;
    }

    final linkedAlbums = await isar
        .collection<DigitalAlbumBookEntity>()
        .filter()
        .anyOf(ids, (query, storyId) => query.storyIdEqualTo(storyId))
        .findAll();

    var deletedCount = 0;
    await isar.writeTxn(() async {
      if (linkedAlbums.isNotEmpty) {
        await isar.collection<DigitalAlbumBookEntity>().deleteAll(
          linkedAlbums.map((album) => album.id).toList(growable: false),
        );
      }
      deletedCount = await isar.collection<StoryEntity>().deleteAll(ids);
    });
    print("🗑️ 故事已删除：$deletedCount/${ids.length}");
    return deletedCount;
  }

  /// 📸 根据 photoIds 加载照片实体
  Future<List<PhotoEntity>> loadPhotos(List<int> photoIds) async {
    final isar = PhotoService().isar;
    final photos = await isar
        .collection<PhotoEntity>()
        .where()
        .anyOf(photoIds, (q, id) => q.idEqualTo(id))
        .sortByTimestamp()
        .findAll();

    // 优先基于 assetId 解析当前可用路径，避免读取临时文件失效
    for (final photo in photos) {
      final asset = await AssetEntity.fromId(photo.assetId);
      final file = await asset?.file;
      final latestPath = file?.path;
      if (latestPath != null &&
          latestPath.isNotEmpty &&
          latestPath != photo.path) {
        photo.path = latestPath;
      }
    }

    await isar.writeTxn(() async {
      await isar.collection<PhotoEntity>().putAll(photos);
    });

    return photos;
  }
}
