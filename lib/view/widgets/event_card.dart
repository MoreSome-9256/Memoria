import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../pages/event_detail_page.dart';
import 'path_image.dart';

class EventCard extends StatelessWidget {
  final Event event;

  const EventCard({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EventDetailPage(event: event),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover images
            _buildCoverImages(),
            // Event info
            Padding(
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
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${event.startDate.month}月 · ${event.location}',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.photo_library,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${event.photos.length} 张照片',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: event.tags.map((tag) {
                      return Chip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImages() {
    final coverPhotos = event.coverPhotos;

    if (coverPhotos.isEmpty) {
      return Container(
        height: 200,
        color: Colors.grey[300],
        child: const Center(child: Icon(Icons.photo)),
      );
    }

    if (coverPhotos.length == 1) {
      return PathImage(
        path: coverPhotos[0].path,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }

    // Multiple photos - show in grid
    return SizedBox(
      height: 200,
      child: Row(
        children: coverPhotos.asMap().entries.map((entry) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: entry.key < coverPhotos.length - 1 ? 2 : 0,
              ),
              child: PathImage(
                path: entry.value.path,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
