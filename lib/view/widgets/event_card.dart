import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../pages/event_detail_page.dart';
import 'deferred_path_image.dart';
import 'fullscreen_photo_viewer.dart';

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event});

  final Event event;

  bool _isMeaninglessTitle(String raw) {
    final title = raw.trim();
    if (title.isEmpty) {
      return true;
    }

    if (title.contains('未知地点')) {
      return true;
    }

    const blockedTitles = <String>{
      '未知地点的回忆',
      '未知地点回忆',
      '回忆',
      '时光',
    };
    if (blockedTitles.contains(title)) {
      return true;
    }

    final dateLike = RegExp(
      r'^\d{1,4}年?\d{0,2}月?\d{0,2}日?(\s*[-~至到]\s*\d{1,4}年?\d{0,2}月?\d{0,2}日?)?$',
    );
    return dateLike.hasMatch(title);
  }

  String? _displayTitle() {
    for (final theme in event.aiThemes) {
      final candidate = theme.title.trim();
      if (!_isMeaninglessTitle(candidate)) {
        return candidate;
      }
    }

    final title = event.title.trim();
    if (_isMeaninglessTitle(title)) {
      return null;
    }
    return title;
  }

  String _dateLine() {
    final start =
        '${event.startDate.year}年${event.startDate.month.toString().padLeft(2, '0')}月${event.startDate.day.toString().padLeft(2, '0')}日';
    final sameDay = event.startDate.year == event.endDate.year &&
        event.startDate.month == event.endDate.month &&
        event.startDate.day == event.endDate.day;
    if (sameDay) {
      return start;
    }
    final end =
        '${event.endDate.month.toString().padLeft(2, '0')}月${event.endDate.day.toString().padLeft(2, '0')}日';
    return '$start - $end';
  }

  String? _locationLine() {
    final location = event.location.trim();
    if (location.isEmpty || location == '未知地点') {
      return null;
    }
    return location;
  }

  List<String> _visibleTags(double maxWidth) {
    final visible = <String>[];
    var usedWidth = 0.0;
    for (final tag in event.tags) {
      final estimatedChipWidth = (26 + (tag.runes.length * 14)).toDouble();
      final nextWidth = visible.isEmpty
          ? estimatedChipWidth
          : usedWidth + 8 + estimatedChipWidth;
      if (nextWidth > maxWidth) {
        break;
      }
      visible.add(tag);
      usedWidth = nextWidth;
    }
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final title = _displayTitle();
    final locationLine = _locationLine();
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCoverImages(context),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => EventDetailPage(event: event),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _dateLine(),
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.photo_library,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${event.photoCount} 张照片',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (locationLine != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.place_rounded,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            locationLine,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (event.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final tags = _visibleTags(constraints.maxWidth);
                        if (tags.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: Row(
                            children: tags.map((tag) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Chip(
                                  label: Text(
                                    tag,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              );
                            }).toList(growable: false),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImages(BuildContext context) {
    final coverPhotos = event.coverPhotos;
    if (coverPhotos.isEmpty) {
      return Container(
        height: 200,
        color: Colors.grey[300],
        child: const Center(child: Icon(Icons.photo)),
      );
    }

    if (coverPhotos.length == 1) {
      final photo = coverPhotos.first;
      final heroTag = 'event-cover-${event.id}-${photo.id}';
      return GestureDetector(
        onTap: () => showFullscreenPhotoViewer(
          context,
          path: photo.path,
          heroTag: heroTag,
        ),
        child: Hero(
          tag: heroTag,
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: DeferredPathImage(path: photo.path, fit: BoxFit.cover),
          ),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: Row(
        children: coverPhotos.asMap().entries.map((entry) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: entry.key < coverPhotos.length - 1 ? 2 : 0,
              ),
              child: GestureDetector(
                onTap: () => showFullscreenPhotoViewer(
                  context,
                  path: entry.value.path,
                  heroTag: 'event-cover-${event.id}-${entry.value.id}',
                ),
                child: Hero(
                  tag: 'event-cover-${event.id}-${entry.value.id}',
                  child: SizedBox(
                    height: 200,
                    child: DeferredPathImage(
                      path: entry.value.path,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}
