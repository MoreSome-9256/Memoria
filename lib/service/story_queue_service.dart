/// 故事队列服务，管理待生成、进行中和已完成的故事任务。

import 'package:flutter/foundation.dart';

import '../models/ai_theme.dart';
import '../models/entity/photo_entity.dart';
import '../models/event.dart';
import '../models/vo/photo.dart';
import '../utils/ocr_policy.dart';
import '../utils/tag_sanitizer.dart';

class StoryQueueItem {
  const StoryQueueItem({required this.photo, this.semanticSearchQuery});

  final Photo photo;
  final String? semanticSearchQuery;

  StoryQueueItem copyWith({Photo? photo, String? semanticSearchQuery}) {
    return StoryQueueItem(
      photo: photo ?? this.photo,
      semanticSearchQuery: semanticSearchQuery ?? this.semanticSearchQuery,
    );
  }
}

class StoryQueueLaunchBundle {
  const StoryQueueLaunchBundle({
    required this.event,
    required this.theme,
    required this.selectedPhotos,
    this.semanticSearchQuery,
  });

  final Event event;
  final AITheme theme;
  final List<Photo> selectedPhotos;
  final String? semanticSearchQuery;
}

class StoryQueueService {
  StoryQueueService._internal();

  static final StoryQueueService _instance = StoryQueueService._internal();

  factory StoryQueueService() => _instance;

  final ValueNotifier<List<StoryQueueItem>> queueListenable =
      ValueNotifier<List<StoryQueueItem>>(const <StoryQueueItem>[]);
  String? _launchTitle;
  String? _launchSubtitle;

  List<StoryQueueItem> get items => queueListenable.value;

  int get count => queueListenable.value.length;

  bool get isEmpty => queueListenable.value.isEmpty;

  bool containsPhoto(String photoId) {
    return queueListenable.value.any((item) => item.photo.id == photoId);
  }

  int addPhotos(List<Photo> photos, {String? semanticSearchQuery}) {
    if (photos.isEmpty) {
      return 0;
    }

    final normalizedQuery = semanticSearchQuery?.trim();
    final next = List<StoryQueueItem>.from(queueListenable.value);
    var addedCount = 0;

    for (final photo in photos) {
      final photoId = photo.id.trim();
      if (photoId.isEmpty) {
        continue;
      }

      final existingIndex = next.indexWhere((item) => item.photo.id == photoId);
      if (existingIndex >= 0) {
        final existing = next[existingIndex];
        if ((existing.semanticSearchQuery?.trim().isEmpty ?? true) &&
            (normalizedQuery?.isNotEmpty ?? false)) {
          next[existingIndex] = existing.copyWith(
            semanticSearchQuery: normalizedQuery,
          );
        }
        continue;
      }

      next.add(
        StoryQueueItem(
          photo: photo.copyWith(isSelected: true),
          semanticSearchQuery: normalizedQuery,
        ),
      );
      addedCount += 1;
    }

    queueListenable.value = List<StoryQueueItem>.unmodifiable(next);
    return addedCount;
  }

  void replacePhotos(
    List<Photo> photos, {
    String? semanticSearchQuery,
    String? title,
    String? subtitle,
  }) {
    queueListenable.value = const <StoryQueueItem>[];
    _launchTitle = title?.trim();
    _launchSubtitle = subtitle?.trim();
    addPhotos(photos, semanticSearchQuery: semanticSearchQuery);
  }

  void removePhoto(String photoId) {
    final next = queueListenable.value
        .where((item) => item.photo.id != photoId)
        .toList(growable: false);
    queueListenable.value = List<StoryQueueItem>.unmodifiable(next);
  }

  void clear() {
    _launchTitle = null;
    _launchSubtitle = null;
    if (queueListenable.value.isEmpty) {
      return;
    }
    queueListenable.value = const <StoryQueueItem>[];
  }

  void reorder(int oldIndex, int newIndex) {
    final next = List<StoryQueueItem>.from(queueListenable.value);
    if (oldIndex < 0 ||
        oldIndex >= next.length ||
        newIndex < 0 ||
        newIndex > next.length) {
      return;
    }
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    queueListenable.value = List<StoryQueueItem>.unmodifiable(next);
  }

  void updatePhotoCaption(String photoId, String caption) {
    final normalizedId = photoId.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final next = List<StoryQueueItem>.from(queueListenable.value);
    final index = next.indexWhere((item) => item.photo.id == normalizedId);
    if (index < 0) {
      return;
    }

    final existing = next[index];
    final trimmedCaption = caption.trim();
    final currentCaption = existing.photo.caption?.trim() ?? '';
    if (currentCaption == trimmedCaption) {
      return;
    }

    next[index] = existing.copyWith(
      photo: existing.photo.copyWith(caption: trimmedCaption),
    );
    queueListenable.value = List<StoryQueueItem>.unmodifiable(next);
  }

  String? combinedSemanticSearchQuery() {
    final queries = queueListenable.value
        .map((item) => item.semanticSearchQuery?.trim() ?? '')
        .where((query) => query.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (queries.isEmpty) {
      return null;
    }
    return queries.join('；');
  }

  StoryQueueLaunchBundle buildLaunchBundle({
    String title = '我的故事队列',
    String subtitle = 'Queue picks',
  }) {
    final effectiveTitle = _launchTitle?.isNotEmpty == true
        ? _launchTitle!
        : title;
    final effectiveSubtitle = _launchSubtitle?.isNotEmpty == true
        ? _launchSubtitle!
        : subtitle;
    final orderedPhotos = queueListenable.value
        .map((item) => item.photo.copyWith(isSelected: true))
        .toList(growable: false);
    if (orderedPhotos.isEmpty) {
      throw StateError('当前故事队列为空');
    }

    final sortedByTime = List<Photo>.from(orderedPhotos)
      ..sort((a, b) => a.dateTaken.compareTo(b.dateTaken));
    final startDate = sortedByTime.first.dateTaken;
    final endDate = sortedByTime.last.dateTaken;
    final theme = AITheme(
      id: 'story_queue_theme',
      emoji: '\u2728',
      title: effectiveTitle,
      subtitle: effectiveSubtitle,
    );
    final event = Event(
      id: 'story_queue_event',
      title: effectiveTitle,
      season: _seasonOf(startDate),
      year: startDate.year,
      location: _resolveLocation(orderedPhotos),
      startDate: startDate,
      endDate: endDate,
      photos: orderedPhotos,
      aiThemes: <AITheme>[theme],
    );

    return StoryQueueLaunchBundle(
      event: event,
      theme: theme,
      selectedPhotos: orderedPhotos,
      semanticSearchQuery: combinedSemanticSearchQuery(),
    );
  }

  static Photo mapPhotoEntityToQueuePhoto(PhotoEntity photo) {
    return Photo(
      id: photo.assetId,
      location:
          (photo.locationName ??
                  photo.district ??
                  photo.city ??
                  photo.province ??
                  '')
              .trim(),
      path: photo.path,
      dateTaken: DateTime.fromMillisecondsSinceEpoch(photo.timestamp),
      tags: TagSanitizer.sanitizeVisualTags(photo.aiTags ?? const <String>[]),
      caption: photo.aiCaption?.trim(),
      vlmCaption: '',
      ocrSummary: OcrPolicy.effectiveSummary(
        tags: photo.ocrTags ?? const <String>[],
        text: photo.ocrText,
      ),
      ocrTags: OcrPolicy.effectiveTags(photo.ocrTags ?? const <String>[]),
      isSelected: true,
      mediaKind: photo.mediaKind,
      thumbnailBytes: photo.thumbnailBytes,
    );
  }

  String _resolveLocation(List<Photo> photos) {
    final counts = <String, int>{};
    for (final photo in photos) {
      final label = (photo.location ?? '').trim();
      if (label.isEmpty) {
        continue;
      }
      counts[label] = (counts[label] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      return '多地回忆';
    }
    final sorted = counts.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.length == 1 ? sorted.first.key : '多地回忆 · ${sorted.first.key}';
  }

  String _seasonOf(DateTime date) {
    switch (date.month) {
      case 3:
      case 4:
      case 5:
        return '春天';
      case 6:
      case 7:
      case 8:
        return '夏天';
      case 9:
      case 10:
      case 11:
        return '秋天';
      default:
        return '冬天';
    }
  }
}
