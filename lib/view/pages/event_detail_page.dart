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

  List<Photo> get _selectedPhotos => widget.event.photos
      .where((photo) => _selectedPhotoIds.contains(photo.id))
      .toList(growable: false);

  List<Photo> get _textRichSelectedPhotos => _selectedPhotos
      .where(
        (photo) =>
            (photo.ocrSummary?.trim().isNotEmpty ?? false) ||
            photo.ocrTags.isNotEmpty,
      )
      .toList(growable: false);

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

  void _showPhotoDetail(Photo photo) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.55,
          maxChildSize: 0.94,
          expand: false,
          builder: (context, controller) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: PathImage(path: photo.path, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '照片详情',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildMetaRow(
                    context,
                    Icons.calendar_today_outlined,
                    '${photo.dateTaken.month}月${photo.dateTaken.day}日 ${photo.dateTaken.hour.toString().padLeft(2, '0')}:${photo.dateTaken.minute.toString().padLeft(2, '0')}',
                  ),
                  if ((photo.location?.trim().isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildMetaRow(
                        context,
                        Icons.location_on_outlined,
                        photo.location!,
                      ),
                    ),
                  if ((photo.caption?.trim().isNotEmpty ?? false)) ...[
                    const SizedBox(height: 20),
                    _buildSectionTitle(context, 'AI Caption'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        photo.caption!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                  if ((photo.ocrSummary?.trim().isNotEmpty ?? false)) ...[
                    const SizedBox(height: 20),
                    _buildSectionTitle(context, 'OCR 摘要'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        photo.ocrSummary!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildTagSection(
                    context,
                    title: 'AI 关键词',
                    tags: photo.tags,
                    emptyText: '这张照片暂时没有 AI 关键词。',
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  const SizedBox(height: 20),
                  _buildTagSection(
                    context,
                    title: 'OCR 关键词',
                    tags: photo.ocrTags,
                    emptyText: '这张照片没有识别出明显文字关键词。',
                    color: Theme.of(context).colorScheme.secondaryContainer,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetaRow(
    BuildContext context,
    IconData icon,
    String text,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildTagSection(
    BuildContext context, {
    required String title,
    required List<String> tags,
    required String emptyText,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, '$title (${tags.length})'),
        const SizedBox(height: 8),
        if (tags.isEmpty)
          Text(
            emptyText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).hintColor,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(tag),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
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
                      Expanded(
                        child: Text(
                          widget.event.location,
                          style: Theme.of(context).textTheme.bodyLarge,
                          overflow: TextOverflow.ellipsis, // 超出变省略号
                          maxLines: 1,
                        ),
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
                            // 🌟 修复点 2：用 Flexible 限制 AI 生成的超长标题
                            Flexible(
                              child: Text(
                                theme.title,
                                overflow: TextOverflow.ellipsis, // 超出变省略号
                                maxLines: 1,
                              ),
                            ),
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
                  const SizedBox(height: 4),
                  Text(
                    '点按选择照片，长按查看这张照片的完整关键词。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                  if (_textRichSelectedPhotos.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'OCR 摘要',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._textRichSelectedPhotos.take(3).map((photo) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => _showPhotoDetail(photo),
                          leading: const Icon(Icons.text_snippet_outlined),
                          title: Text(
                            photo.ocrSummary ?? '识别到文本',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: photo.ocrTags.isEmpty
                              ? null
                              : Text(
                                  photo.ocrTags.take(4).join('、'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),
                      );
                    }),
                  ],
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
                  onLongPress: () => _showPhotoDetail(photo),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PathImage(path: photo.path, fit: BoxFit.cover),
                      if (!isSelected)
                        Container(color: Colors.black.withValues(alpha: 0.5)),
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${photo.tags.length + photo.ocrTags.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
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
