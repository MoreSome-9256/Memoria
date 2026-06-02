/// 故事队列页面，用于查看当前排队和进行中的任务。

import 'package:flutter/material.dart';

import '../../service/story_queue_service.dart';
import '../../utils/media_type_helper.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import '../widgets/media_thumbnail.dart';
import 'story_config_page.dart';

class StoryQueuePage extends StatelessWidget {
  const StoryQueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = StoryQueueService();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: '返回',
        ),
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
                      '建议先把每张图片描述改成更贴合画面的内容，再生成故事；拖动可调整顺序，点图片查看大图，点右侧可移除。',
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
                          assetId: item.photo.id,
                          heroTag: 'story-queue-photo-${item.photo.id}',
                        );
                      },
                      onRemove: () => queue.removePhoto(item.photo.id),
                      onCaptionChanged: (value) =>
                          queue.updatePhotoCaption(item.photo.id, value),
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

class _QueuePhotoTile extends StatefulWidget {
  const _QueuePhotoTile({
    super.key,
    required this.index,
    required this.item,
    required this.onPreview,
    required this.onRemove,
    required this.onCaptionChanged,
  });

  final int index;
  final StoryQueueItem item;
  final VoidCallback onPreview;
  final VoidCallback onRemove;
  final ValueChanged<String> onCaptionChanged;

  @override
  State<_QueuePhotoTile> createState() => _QueuePhotoTileState();
}

class _QueuePhotoTileState extends State<_QueuePhotoTile> {
  late final TextEditingController _captionController;
  late final FocusNode _captionFocusNode;

  String get _captionText => widget.item.photo.caption?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: _captionText);
    _captionFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _QueuePhotoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final latestCaption = _captionText;
    if (_captionFocusNode.hasFocus ||
        _captionController.text == latestCaption) {
      return;
    }
    _captionController.value = TextEditingValue(
      text: latestCaption,
      selection: TextSelection.collapsed(offset: latestCaption.length),
    );
  }

  @override
  void dispose() {
    _captionController.dispose();
    _captionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.item.photo;
    final tags = photo.tags.take(3).join(' / ');
    final date = photo.dateTaken;
    final meta = <String>[
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      if ((photo.location ?? '').trim().isNotEmpty) photo.location!.trim(),
    ].join(' · ');

    return Container(
      key: widget.key,
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: widget.onPreview,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: Hero(
                        tag: 'story-queue-photo-${photo.id}',
                        child: MediaThumbnail(
                          path: photo.path,
                          assetId: photo.id,
                          kind: MediaTypeHelper.fromStorageValue(
                            photo.mediaKind,
                            path: photo.path,
                          ),
                          thumbnailBytes: photo.thumbnailBytes,
                          fit: BoxFit.cover,
                        ),
                      ),
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
                        '第 ${widget.index + 1} 张',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if ((widget.item.semanticSearchQuery?.trim().isNotEmpty ??
                          false)) ...[
                        const SizedBox(height: 6),
                        Text(
                          '搜索线索：${widget.item.semanticSearchQuery!.trim()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
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
                      index: widget.index,
                      child: const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.drag_handle_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    IconButton(
                      onPressed: widget.onRemove,
                      icon: const Icon(Icons.close_rounded),
                      tooltip: '移出队列',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _captionController,
              focusNode: _captionFocusNode,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              onChanged: widget.onCaptionChanged,
              decoration: InputDecoration(
                hintText: '手动写一句更贴合这张图片的描述',
                isDense: true,
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.18),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.18),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.2,
                  ),
                ),
              ),
            ),
            if (_captionText.isEmpty && tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '参考标签：$tags',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey[700], fontSize: 12),
              ),
            ],
          ],
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
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.65),
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
