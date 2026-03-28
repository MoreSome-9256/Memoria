import 'package:flutter/material.dart';

import '../../service/story_queue_service.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import '../widgets/path_image.dart';
import 'config_page.dart';

class StoryQueuePage extends StatelessWidget {
  const StoryQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = StoryQueueService();
    return Scaffold(
      appBar: AppBar(
        title: const Text('故事队列'),
        actions: [
          ValueListenableBuilder<List<StoryQueueItem>>(
            valueListenable: queue.queueListenable,
            builder: (context, items, _) {
              return TextButton(
                onPressed: items.isEmpty ? null : queue.clear,
                child: const Text('清空'),
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<StoryQueueItem>>(
        valueListenable: queue.queueListenable,
        builder: (context, items, _) {
          if (items.isEmpty) {
            return _EmptyQueueView(
              onBack: () => Navigator.of(context).maybePop(),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '共 ${items.length} 张，按加入队列的顺序生成故事',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '可跨标签、语义搜索和时刻分组持续加图；拖动可调整顺序，点图片查看大图，点右侧可移除。',
                      style: TextStyle(color: Colors.grey[700], height: 1.4),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: items.length,
                  onReorder: queue.reorder,
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _QueuePhotoTile(
                      key: ValueKey<String>('story-queue-${item.photo.id}'),
                      index: index,
                      item: item,
                      onPreview: () {
                        showFullscreenPhotoViewer(
                          context,
                          path: item.photo.path,
                          heroTag: 'story-queue-photo-${item.photo.id}',
                        );
                      },
                      onRemove: () => queue.removePhoto(item.photo.id),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: ValueListenableBuilder<List<StoryQueueItem>>(
          valueListenable: queue.queueListenable,
          builder: (context, items, _) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: FilledButton.icon(
                onPressed: items.isEmpty
                    ? null
                    : () => _openConfigPage(context, queue),
                icon: const Icon(Icons.auto_stories_rounded),
                label: Text(items.isEmpty ? '先加入照片' : '生成故事 ${items.length}'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openConfigPage(BuildContext context, StoryQueueService queue) {
    final bundle = queue.buildLaunchBundle();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConfigPage(
          event: bundle.event,
          selectedPhotos: bundle.selectedPhotos,
          selectedTheme: bundle.theme,
          semanticSearchQuery: bundle.semanticSearchQuery,
          preservePhotoOrder: true,
        ),
      ),
    );
  }
}

class _QueuePhotoTile extends StatelessWidget {
  const _QueuePhotoTile({
    super.key,
    required this.index,
    required this.item,
    required this.onPreview,
    required this.onRemove,
  });

  final int index;
  final StoryQueueItem item;
  final VoidCallback onPreview;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final photo = item.photo;
    final caption = photo.caption?.trim() ?? '';
    final tags = photo.tags.take(3).join('、');
    final date = photo.dateTaken;
    final meta = <String>[
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      if ((photo.location ?? '').trim().isNotEmpty) photo.location!.trim(),
    ].join(' · ');

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onPreview,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: Hero(
                    tag: 'story-queue-photo-${photo.id}',
                    child: PathImage(path: photo.path, fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '第 ${index + 1} 张',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (caption.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else if (tags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        tags,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if ((item.semanticSearchQuery?.trim().isNotEmpty ?? false)) ...[
                      const SizedBox(height: 4),
                      Text(
                        '搜索线索：${item.semanticSearchQuery!.trim()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.drag_handle_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '移出队列',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyQueueView extends StatelessWidget {
  const _EmptyQueueView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.65),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_stories_outlined,
                size: 38,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '故事队列还是空的',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '先在标签预览、时刻分组或语义搜索里把喜欢的照片加入队列，再回来生成故事。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], height: 1.5),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('继续选图'),
            ),
          ],
        ),
      ),
    );
  }
}
