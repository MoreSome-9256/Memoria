import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../pages/event_detail_page.dart';
import 'deferred_path_image.dart';
import 'fullscreen_photo_viewer.dart';

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
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
                  Text(
                    event.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${event.startDate.month}月 · ${event.location}',
                          style: TextStyle(color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
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
                  if (event.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: event.tags.map((tag) {
                        return Chip(
                          label: Text(tag, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(growable: false),
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
