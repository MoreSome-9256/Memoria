/// 事件详情页面，展示单个事件的照片、信息和操作。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../models/event.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/vo/photo.dart';
import '../../service/junk_photo_cleanup_service.dart';
import '../../service/story_queue_service.dart';
import '../../utils/ocr_policy.dart';
import '../widgets/deferred_path_image.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import '../widgets/media_thumbnail.dart';
import 'story_queue_page.dart';
import '../../objectbox.g.dart';
import '../../storage/objectbox/objectbox_service.dart';
enum _EventActionMode { none, story, delete }

class EventDetailPage extends StatefulWidget {
  final Event event;

  const EventDetailPage({super.key, required this.event});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final Set<String> _selectedPhotoIds = {};
  String? _selectedThemeId;
  _EventActionMode _actionMode = _EventActionMode.none;
  late List<Photo> _photos;
  bool _isLoadingPhotos = false;

  List<Photo> get _selectedPhotos => _photos
      .where((photo) => _selectedPhotoIds.contains(photo.id))
      .toList(growable: false);

  List<Photo> get _textRichSelectedPhotos => _selectedPhotos
      .where(
        (photo) =>
            OcrPolicy.mlKitEnabled &&
            ((photo.ocrSummary?.trim().isNotEmpty ?? false) ||
                photo.ocrTags.isNotEmpty),
      )
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _photos = List<Photo>.from(widget.event.photos);
    _isLoadingPhotos = _photos.isEmpty;
    // Select first theme by default
    if (widget.event.aiThemes.isNotEmpty) {
      _selectedThemeId = widget.event.aiThemes.first.id;
    }
    if (_isLoadingPhotos) {
      unawaited(_hydratePhotosFromLocalIndex());
    }
  }

  bool get _isSelectionMode => _actionMode != _EventActionMode.none;
  bool get _isDeleteMode => _actionMode == _EventActionMode.delete;

  Future<void> _hydratePhotosFromLocalIndex() async {
    final eventId = int.tryParse(widget.event.id);
    if (eventId == null || eventId < 0) {
      if (mounted) {
        setState(() => _isLoadingPhotos = false);
      }
      return;
    }

    final _pb = ObjectBoxService().store.box<PhotoEntity>();
    final _q = _pb.query(PhotoEntity_.eventId.equals(eventId))
        .order(PhotoEntity_.timestamp).build();
    final entities = _q.find();
    _q.close();

    final hydrated = <Photo>[];
    for (final entity in entities) {
      hydrated.add(
        Photo(
          id: entity.assetId,
          path: await _resolvePhotoPath(entity),
          dateTaken: DateTime.fromMillisecondsSinceEpoch(entity.timestamp),
          tags: entity.aiTags ?? const <String>[],
          caption: entity.aiCaption?.trim(),
          ocrSummary: OcrPolicy.effectiveSummary(
            tags: entity.ocrTags ?? const <String>[],
            text: entity.ocrText,
          ),
          ocrTags: OcrPolicy.effectiveTags(entity.ocrTags ?? const <String>[]),
          location:
              entity.locationName ??
              entity.district ??
              entity.city ??
              entity.province,
        ),
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _photos = hydrated;
      _isLoadingPhotos = false;
    });
  }

  Future<String> _resolvePhotoPath(PhotoEntity entity) async {
    if (entity.path.trim().isNotEmpty) {
      return entity.path;
    }
    final asset = await AssetEntity.fromId(entity.assetId);
    final file = await asset?.file;
    return file?.path ?? entity.path;
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
                       child: MediaThumbnail(
                         path: photo.path,
                         assetId: photo.id,
                         fit: BoxFit.cover,
                       ),
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
                  if (OcrPolicy.mlKitEnabled) ...[
                    const SizedBox(height: 20),
                    _buildTagSection(
                      context,
                      title: 'OCR 关键词',
                      tags: photo.ocrTags,
                      emptyText: '这张照片没有识别出明显文字关键词。',
                      color: Theme.of(context).colorScheme.secondaryContainer,
                    ),
                  ],
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

  void _openStoryQueuePage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const StoryQueuePage(),
      ),
    );
  }

  void _addSelectionToQueue() {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一张照片加入故事队列')),
      );
      return;
    }

    final selectedPhotos = _photos
        .where((photo) => _selectedPhotoIds.contains(photo.id))
        .toList(growable: false);
    final addedCount = StoryQueueService().addPhotos(selectedPhotos);

    setState(() {
      _actionMode = _EventActionMode.none;
      _selectedPhotoIds.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          addedCount > 0 ? '已加入故事队列 $addedCount 张' : '这些照片已经在故事队列里了',
        ),
      ),
    );
    _openStoryQueuePage();
  }

  Future<void> _deleteSelectionFromLocalIndex() async {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一张照片再删除')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除本地记录'),
          content: Text(
            '将从 App 本地数据库中删除 ${_selectedPhotoIds.length} 张照片记录，不会删除手机系统相册中的原图。是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final selectedAssetIds = _selectedPhotoIds.toList(growable: false);
    final _pb2 = ObjectBoxService().store.box<PhotoEntity>();
    final _q2 = _pb2.query(PhotoEntity_.assetId.oneOf(selectedAssetIds)).build();
    final entities = _q2.find();
    _q2.close();

    var removedCount = 0;
    for (final entity in entities) {
      await JunkPhotoCleanupService().removeFromLocalIndex(entity);
      StoryQueueService().removePhoto(entity.assetId);
      removedCount += 1;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      if (removedCount > 0) {
        _photos = _photos
            .where((photo) => !_selectedPhotoIds.contains(photo.id))
            .toList(growable: false);
      }
      _actionMode = _EventActionMode.none;
      _selectedPhotoIds.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(removedCount > 0 ? '已删除 $removedCount 条本地记录' : '没有删除任何本地记录'),
      ),
    );
  }

  Widget _buildFloatingActions() {
    return ValueListenableBuilder<List<StoryQueueItem>>(
      valueListenable: StoryQueueService().queueListenable,
      builder: (context, items, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (items.isNotEmpty) ...[
              FloatingActionButton.extended(
                heroTag: 'event-detail-queue',
                onPressed: _openStoryQueuePage,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text('队列 ${items.length}'),
              ),
              const SizedBox(height: 10),
            ],
            if (_isSelectionMode && _photos.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'event-detail-back',
                    onPressed: () {
                      setState(() {
                        _actionMode = _EventActionMode.none;
                        _selectedPhotoIds.clear();
                      });
                    },
                    child: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      final allSelected = _photos
                          .every((p) => _selectedPhotoIds.contains(p.id));
                      if (allSelected) {
                        setState(() {
                          _selectedPhotoIds.clear();
                        });
                      } else {
                        setState(() {
                          _selectedPhotoIds.addAll(
                            _photos.map((photo) => photo.id),
                          );
                        });
                      }
                    },
                    icon: Icon(
                      _photos.isNotEmpty &&
                              _photos
                                  .every((p) => _selectedPhotoIds.contains(p.id))
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                    ),
                    label: Text(
                      _photos.isNotEmpty &&
                              _photos
                                  .every((p) => _selectedPhotoIds.contains(p.id))
                          ? '取消全选'
                          : '全选',
                    ),
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton.extended(
                    heroTag: 'event-detail-story',
                    onPressed: _isDeleteMode
                        ? _deleteSelectionFromLocalIndex
                        : _addSelectionToQueue,
                    icon: Icon(
                      _isDeleteMode
                          ? Icons.delete_outline_rounded
                          : Icons.playlist_add_rounded,
                    ),
                    label: Text(
                      _selectedPhotoIds.isEmpty
                          ? (_isDeleteMode ? '删除本地记录' : '加入故事队列')
                          : (_isDeleteMode
                              ? '删除本地记录 ${_selectedPhotoIds.length}'
                              : '加入故事队列 ${_selectedPhotoIds.length}'),
                    ),
                  ),
                ],
              )
            else if (!_isLoadingPhotos)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'event-detail-delete',
                    onPressed: () {
                      setState(() {
                        _actionMode = _EventActionMode.delete;
                        _selectedPhotoIds.clear();
                      });
                    },
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton.extended(
                    heroTag: 'event-detail-story',
                    onPressed: () {
                      setState(() {
                        _actionMode = _EventActionMode.story;
                        _selectedPhotoIds.clear();
                      });
                    },
                    icon: const Icon(Icons.auto_stories_rounded),
                    label: const Text('生成故事'),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        cacheExtent: 700,
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
                          overflow: TextOverflow.ellipsis, // 瓒呭嚭鍙樼渷鐣ュ彿
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
                            // Limit long AI-generated titles with Flexible.
                            Flexible(
                              child: Text(
                                theme.title,
                                overflow: TextOverflow.ellipsis,
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
                    _isSelectionMode
                        ? '照片 (${_selectedPhotoIds.length}/${_photos.length})'
                        : '照片 (${_isLoadingPhotos ? widget.event.photoCount : _photos.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isLoadingPhotos
                        ? '先展示这一组时刻的概要，图片会在滑到这里时继续懒加载。'
                        : _isSelectionMode
                        ? (_isDeleteMode
                            ? '点击图片选择要从 App 本地数据库中删除的记录。'
                            : '点击图片加入故事队列，再点右下角按钮继续。')
                        : '先预览照片内容，点击右下角按钮后再进入选图。',
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
          // Photo grid
          if (_isLoadingPhotos)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final photo = _photos[index];
                  final isSelected = _selectedPhotoIds.contains(photo.id);

                  return GestureDetector(
                    onTap: () {
                      if (_isSelectionMode) {
                        _togglePhotoSelection(photo);
                        return;
                      }
                       showFullscreenPhotoViewer(
                         context,
                         path: photo.path,
                         assetId: photo.id,
                         heroTag: 'event-photo-${photo.id}',
                       );
                    },
                    onLongPress: () => _showPhotoDetail(photo),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                         Hero(
                           tag: 'event-photo-${photo.id}',
                           child: DeferredPathImage(
                             path: photo.path,
                             assetId: photo.id,
                             fit: BoxFit.cover,
                           ),
                         ),
                        if (_isSelectionMode && !isSelected)
                          Container(color: Colors.black.withValues(alpha: 0.32)),
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
                              '${photo.tags.length + (OcrPolicy.mlKitEnabled ? photo.ocrTags.length : 0)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (_isSelectionMode)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (_isDeleteMode
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.primary)
                                    : Colors.white.withValues(alpha: 0.88),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Icon(
                                isSelected
                                    ? (_isDeleteMode
                                        ? Icons.delete_rounded
                                        : Icons.check_rounded)
                                    : Icons.add_rounded,
                                size: 16,
                                color: isSelected
                                    ? Colors.white
                                    : (_isDeleteMode
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.primary),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }, childCount: _photos.length),
              ),
            ),
          // Bottom spacing for FAB
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: _buildFloatingActions(),
    );
  }
}
