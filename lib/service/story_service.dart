import 'package:isar/isar.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/entity/story_entity.dart';
import '../models/entity/event_entity.dart';
import '../models/entity/photo_entity.dart';
import '../utils/story_prompt_helper.dart';
import 'photo_service.dart';
import 'llm_service.dart';
import '../view/pages/config_page.dart'; // for StoryLength enum
import 'event_service.dart';

/// 故事服务 - 管理故事的生成和存储
class StoryService {
  static final StoryService _instance = StoryService._internal();
  factory StoryService() => _instance;
  StoryService._internal();

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
    required StoryLength length,
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

      final locationMode = _detectLocationMode(sortedPhotos);
      print("📍 故事位置线索模式: $locationMode");

      print("📝 开始生成故事：${sortedPhotos.length} 张照片");

      // 2. 构造照片描述文本（供 LLM 理解）
      final photoDescriptions = StoryPromptHelper.buildPhotoDescriptions(
        sortedPhotos,
      );

      // 3. 调用 LLM 生成故事内容
      final content = await _generateStoryContent(
        title: title,
        subtitle: subtitle,
        event: event,
        photoDescriptions: photoDescriptions,
        length: length,
        locationMode: locationMode,
      );

      if (content == null) {
        print("❌ LLM 生成失败");
        return null;
      }

      // 4. 创建并保存故事实体
      final story = StoryEntity.create(
        title: title,
        subtitle: subtitle,
        content: content,
        eventId: event.id,
        photoIds: sortedPhotos.map((p) => p.id).toList(),
      );

      // 保存到数据库
      final isar = PhotoService().isar;
      await isar.writeTxn(() async {
        await isar.collection<StoryEntity>().put(story);
      });

      print("✅ 故事生成成功：ID=${story.id}");
      return story;
    } catch (e) {
      print("❌ 故事生成异常: $e");
      return null;
    }
  }

  /// 🤖 调用 LLM 生成故事内容
  Future<String?> _generateStoryContent({
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
  }

  String _detectLocationMode(List<PhotoEntity> photos) {
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
  }

  /// 🧪 模拟模式：生成假的故事内容（用于开发测试）
  Future<String> _generateMockStoryContent(
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
  }

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
    final isar = PhotoService().isar;
    await isar.writeTxn(() async {
      await isar.collection<StoryEntity>().delete(storyId);
    });
    print("🗑️ 故事已删除：ID=$storyId");
    return true;
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
