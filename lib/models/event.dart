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
    required this.photos,
    this.tags = const [],
    this.aiThemes = const [],
  });

  // Get cover photos (first 3)
  List<Photo> get coverPhotos => photos.take(3).toList();

  // Get formatted date range
  String get dateRangeText {
    final start = '${startDate.month}月${startDate.day}日';
    final end = '${endDate.month}月${endDate.day}日';
    return startDate.month == endDate.month && startDate.day == endDate.day
        ? start
        : '$start - $end';
  }
}
