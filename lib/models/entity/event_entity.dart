/// 事件聚合的 ObjectBox 实体，保存时间、地点和分析后的事件信息。

import 'dart:io';

import 'package:objectbox/objectbox.dart';
import 'package:photo_manager/photo_manager.dart';

import '../ai_theme.dart';
import 'photo_entity.dart';
import '../event.dart';
import '../../utils/ocr_policy.dart';
import '../../utils/tag_sanitizer.dart';
import '../vo/photo.dart';

@Entity()
class EventEntity {
  @Id()
  int id = 0;

  // 事件基本信息
  late String title; // 事件标题，默认为日期（如 "8月15日-8月18日"）
  late int startTime; // 开始时间戳 (毫秒)
  late int endTime; // 结束时间戳 (毫秒)

  // 聚类中心点坐标 (可能为空，如果所有照片都没有 GPS)
  double? avgLatitude;
  double? avgLongitude;

  // 地理位置信息 (从高德解析)
  String? city; // 城市名称（如 "青岛市"）
  String? province; // 省份（如 "山东省"）
  String? district; // 区县名称（如 "历城区"）
  String? locationName; // 更细粒度地点：学校/商场/园区/楼栋/POI
  String? formattedAddress; // 完整逆地址解析结果

  // 关联的照片
  List<int> photoIds = []; // 关联的 PhotoEntity id 列表

  // 封面图
  int? coverPhotoId; // 封面图的 PhotoEntity id

  // 标签和主题
  List<String> tags = []; // 聚合的标签（从照片 AI 标签统计得出）

  // 统计信息
  int photoCount = 0; // 照片数量（冗余字段，方便查询）

  // AI 智能增强字段
  double? joyScore; // 事件平均欢乐值 (0.0 - 1.0)
  List<String>? aiThemes; // AI 生成的标题列表（本地规则：1个，LLM：3-5个）
  bool isLlmGenerated = false; // 标记当前标题是否由 LLM 生成
  int analyzedPhotoCount = 0; // 已分析照片数量（进度追踪）

  // 季节推导 (根据月份自动计算)
  String get season {
    final date = DateTime.fromMillisecondsSinceEpoch(startTime);
    final month = date.month;
    if (month >= 3 && month <= 5) return '春天';
    if (month >= 6 && month <= 8) return '夏天';
    if (month >= 9 && month <= 11) return '秋天';
    return '冬天';
  }

  // 年份
  int get year {
    final date = DateTime.fromMillisecondsSinceEpoch(startTime);
    return date.year;
  }

  // 位置描述（优先使用 locationName/district/city/province）
  String get location =>
      locationName ?? district ?? city ?? province ?? '未知地点';

  // 格式化日期范围
  String get dateRangeText {
    final start = DateTime.fromMillisecondsSinceEpoch(startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(endTime);
    final startStr = '${start.month}月${start.day}日';
    final endStr = '${end.month}月${end.day}日';

    if (start.month == end.month && start.day == end.day) {
      return startStr;
    }
    return '$startStr - $endStr';
  }

  // 转换为 UI 层的 Event 模型
  Future<Event> toUIModel({
    required Future<List<PhotoEntity>> Function(List<int> ids) loadPhotoEntities,
  }) async {
    final photoEntities = await loadPhotoEntities(photoIds);
    final photos = await _mapEntitiesToPhotos(photoEntities, resolvePath: true);
    return _buildEvent(
      photos: photos,
      coverPhotos: photos.take(3).toList(growable: false),
      photoCountOverride: photoCount > 0 ? photoCount : photos.length,
    );
  }

  Future<Event> toPreviewModel({
    required Future<List<PhotoEntity>> Function(List<int> ids) loadPhotoEntities,
  }) async {
    final coverIds = photoIds.take(3).toList(growable: false);
    final coverEntities = await loadPhotoEntities(coverIds);
    final coverPhotos = await _mapEntitiesToPhotos(
      coverEntities,
      resolvePath: false,
    );
    return _buildEvent(
      photos: const <Photo>[],
      coverPhotos: coverPhotos,
      photoCountOverride: photoCount > 0 ? photoCount : photoIds.length,
    );
  }

  Future<List<Photo>> _mapEntitiesToPhotos(
    List<PhotoEntity> photoEntities, {
    required bool resolvePath,
  }) async {
    final photos = <Photo>[];
    for (final entity in photoEntities) {
      final resolvedPath = resolvePath
          ? await _resolvePhotoPath(entity)
          : entity.path;
      photos.add(
        Photo(
          id: entity.assetId,
          path: resolvedPath,
          dateTaken: DateTime.fromMillisecondsSinceEpoch(entity.timestamp),
          tags: TagSanitizer.sanitizeVisualTags(
            entity.aiTags ?? const <String>[],
          ),
          caption: entity.aiCaption?.trim(),
          ocrSummary: _buildOcrSummary(entity),
          ocrTags: OcrPolicy.effectiveTags(entity.ocrTags ?? const <String>[]),
          location:
              entity.locationName ??
              entity.district ??
              entity.city ??
              entity.province,
        ),
      );
    }
    return photos;
  }

  Event _buildEvent({
    required List<Photo> photos,
    required List<Photo> coverPhotos,
    required int photoCountOverride,
  }) {
    final themes = _buildAiThemes();
    return Event(
      id: id.toString(),
      title: title,
      season: season,
      year: year,
      location: location,
      startDate: DateTime.fromMillisecondsSinceEpoch(startTime),
      endDate: DateTime.fromMillisecondsSinceEpoch(endTime),
      photos: photos,
      coverPhotos: coverPhotos,
      photoCount: photoCountOverride,
      tags: TagSanitizer.sanitizeDisplayTags(tags),
      aiThemes: themes,
    );
  }

  Future<String> _resolvePhotoPath(PhotoEntity entity) async {
    if (entity.path.trim().isNotEmpty && File(entity.path).existsSync()) {
      return entity.path;
    }
    final asset = await AssetEntity.fromId(entity.assetId);
    final file = await asset?.file;
    return file?.path ?? entity.path;
  }

  String? _buildOcrSummary(PhotoEntity entity) {
    return OcrPolicy.effectiveSummary(
      tags: entity.ocrTags ?? const <String>[],
      text: entity.ocrText,
    );
  }

  List<AITheme> _buildAiThemes() {
    final sourceTitles = <String>[];

    if (aiThemes != null && aiThemes!.isNotEmpty) {
      sourceTitles.addAll(aiThemes!);
    }

    if (sourceTitles.isEmpty) {
      sourceTitles.addAll(tags.take(3).map((tag) => '$tag时光'));
    }

    if (sourceTitles.isEmpty) {
      sourceTitles.add('$location的回忆');
    }

    return sourceTitles.asMap().entries.map((entry) {
      final title = entry.value;
      return AITheme(
        id: 'theme_${id}_${entry.key}',
        emoji: _inferEmoji(title),
        title: title,
        subtitle: _buildSubtitle(title),
      );
    }).toList();
  }

  String _inferEmoji(String title) {
    if (title.contains('海') || title.contains('沙滩')) return '🌊';
    if (title.contains('山')) return '⛰️';
    if (title.contains('花')) return '🌸';
    if (title.contains('美食') || title.contains('吃')) return '🍜';
    if (title.contains('猫') || title.contains('狗') || title.contains('宠物')) {
      return '🐾';
    }
    if (title.contains('夜') || title.contains('星')) return '🌃';
    return '📸';
  }

  String _buildSubtitle(String title) {
    if (title.contains('回忆') || title.contains('记忆')) {
      return '把这一刻写成故事';
    }

    if (title.contains('时光')) {
      return '用第一人称记录当时的心情';
    }

    return '$title，值得再次回看';
  }

  // 从照片列表生成事件的工厂方法
  static EventEntity fromPhotos(List<PhotoEntity> photos) {
    if (photos.isEmpty) {
      throw ArgumentError('Cannot create event from empty photo list');
    }

    // 按时间排序
    photos.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final event = EventEntity()
      ..startTime = photos.first.timestamp
      ..endTime = photos.last.timestamp
      ..photoIds = photos.map((p) => p.id).toList()
      ..photoCount = photos.length
      ..coverPhotoId = photos.first.id
      ..province = _pickMostFrequentValue(photos.map((p) => p.province))
      ..city = _pickMostFrequentValue(photos.map((p) => p.city))
      ..district = _pickMostFrequentValue(photos.map((p) => p.district))
      ..locationName = _pickMostFrequentValue(photos.map((p) => p.locationName))
      ..formattedAddress = _pickMostFrequentValue(
        photos.map((p) => p.formattedAddress),
      );

    // 计算中心坐标
    final photosWithGPS = photos
        .where((p) => p.latitude != null && p.longitude != null)
        .toList();
    if (photosWithGPS.isNotEmpty) {
      event.avgLatitude =
          photosWithGPS.map((p) => p.latitude!).reduce((a, b) => a + b) /
          photosWithGPS.length;
      event.avgLongitude =
          photosWithGPS.map((p) => p.longitude!).reduce((a, b) => a + b) /
          photosWithGPS.length;
    }

    // 聚合标签（取出现频率最高的前 5 个）
    final tagCounts = <String, int>{};
    for (var photo in photos) {
      if (photo.aiTags != null) {
        for (final tag in TagSanitizer.sanitizeVisualTags(photo.aiTags!)) {
          tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
        }
      }
    }
    final sortedTags = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    event.tags = sortedTags.take(5).map((e) => e.key).toList();

    // 生成默认标题（日期范围）
    final start = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final end = DateTime.fromMillisecondsSinceEpoch(event.endTime);
    if (start.month == end.month && start.day == end.day) {
      event.title = '${start.month}月${start.day}日';
    } else {
      event.title = '${start.month}月${start.day}日 - ${end.month}月${end.day}日';
    }

    return event;
  }

  static String? _pickMostFrequentValue(Iterable<String?> values) {
    final counts = <String, int>{};
    for (final value in values) {
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) {
        continue;
      }
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }

    if (counts.isEmpty) {
      return null;
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) {
          return countCompare;
        }
        return a.key.length.compareTo(b.key.length);
      });
    return sorted.first.key;
  }
}
