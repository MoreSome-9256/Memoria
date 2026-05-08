/// 事件领域模型，表示一组按时间和上下文聚合的照片及其主题信息。

import 'vo/photo.dart';
import 'ai_theme.dart';

class Event {
  final String id;
  final String title;
  final String season;
  final int year;
  final String location;
  final DateTime startDate;
  final DateTime endDate;
  final List<Photo> photos;
  final List<Photo> coverPhotos;
  final int photoCount;
  final List<String> tags;
  final List<AITheme> aiThemes;

  Event({
    required this.id,
    required this.title,
    required this.season,
    required this.year,
    required this.location,
    required this.startDate,
    required this.endDate,
    this.photos = const <Photo>[],
    List<Photo>? coverPhotos,
    int? photoCount,
    this.tags = const [],
    this.aiThemes = const [],
  }) : coverPhotos =
           List<Photo>.unmodifiable(
             coverPhotos ?? photos.take(3).toList(growable: false),
           ),
       photoCount = photoCount ?? photos.length;

  // Get formatted date range
  String get dateRangeText {
    final start = '${startDate.month}月${startDate.day}日';
    final end = '${endDate.month}月${endDate.day}日';
    return startDate.month == endDate.month && startDate.day == endDate.day
        ? start
        : '$start - $end';
  }
}
