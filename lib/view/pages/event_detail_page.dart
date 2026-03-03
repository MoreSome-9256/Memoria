import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../widgets/path_image.dart';
import 'config_page.dart';

class EventDetailPage extends StatefulWidget {
  final Event event;

  const EventDetailPage({super.key, required this.event});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final Set<String> _selectedPhotoIds = {};
  String? _selectedThemeId;

  @override
  void initState() {
    super.initState();
    // Select all photos by default
    _selectedPhotoIds.addAll(widget.event.photos.map((p) => p.id));
    // Select first theme by default
    if (widget.event.aiThemes.isNotEmpty) {
      _selectedThemeId = widget.event.aiThemes.first.id;
    }
  }

  void _togglePhotoSelection(Photo photo) {
    setState(() {
      if (_selectedPhotoIds.contains(photo.id)) {
        _selectedPhotoIds.remove(photo.id);
      } else {
        _selectedPhotoIds.add(photo.id);
      }
    });
  }

  void _navigateToConfigPage() {
    final selectedTheme = widget.event.aiThemes
        .where((theme) => theme.id == _selectedThemeId)
        .firstOrNull;

    if (selectedTheme == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择一个主题')));
      return;
    }

    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一张照片')));
      return;
    }

    final selectedPhotos = widget.event.photos
        .where((photo) => _selectedPhotoIds.contains(photo.id))
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConfigPage(
          event: widget.event,
          selectedPhotos: selectedPhotos,
          selectedTheme: selectedTheme,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(title: Text(widget.event.title), pinned: true),
          // Event info section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date range
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        widget.event.dateRangeText,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.location_on, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        widget.event.location,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // AI theme chips
                  Text(
                    'AI 推荐主题',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.event.aiThemes.map((theme) {
                      final isSelected = theme.id == _selectedThemeId;
                      return ChoiceChip(
                        showCheckmark: false,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(theme.emoji),
                            const SizedBox(width: 4),
                            Text(theme.title),
                          ],
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedThemeId = selected ? theme.id : null;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Photo count info
                  Text(
                    '照片 (${_selectedPhotoIds.length}/${widget.event.photos.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          // Photo grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final photo = widget.event.photos[index];
                final isSelected = _selectedPhotoIds.contains(photo.id);

                return GestureDetector(
                  onTap: () => _togglePhotoSelection(photo),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PathImage(path: photo.path, fit: BoxFit.cover),
                      if (!isSelected)
                        Container(color: Colors.black.withValues(alpha: 0.5)),
                      if (isSelected)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }, childCount: widget.event.photos.length),
            ),
          ),
          // Bottom spacing for FAB
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToConfigPage,
        icon: const Icon(Icons.edit),
        label: const Text('生成故事'),
      ),
    );
  }
}
