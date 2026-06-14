/// 低价值照片回收站，展示被 AI 标记为低价值候选的本地照片记录。

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/entity/photo_entity.dart';
import '../../service/ai_service.dart';
import '../../service/photo_service.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import '../widgets/media_thumbnail.dart';

class JunkPhotoTrashPage extends StatefulWidget {
  const JunkPhotoTrashPage({super.key});

  @override
  State<JunkPhotoTrashPage> createState() => _JunkPhotoTrashPageState();
}

class _JunkPhotoTrashPageState extends State<JunkPhotoTrashPage> {
  late Future<List<PhotoEntity>> _photosFuture;
  final Set<int> _selectedPhotoIds = <int>{};
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _photosFuture = _loadPhotos();
  }

  Future<List<PhotoEntity>> _loadPhotos() {
    return PhotoService().loadJunkCandidatePhotos();
  }

  void _reload() {
    setState(() {
      _selectedPhotoIds.clear();
      _photosFuture = _loadPhotos();
    });
  }

  Future<void> _restorePhotos(Iterable<int> photoIds) async {
    final ids = photoIds.where((id) => id > 0).toSet().toList(growable: false);
    if (ids.isEmpty || _isRestoring) {
      return;
    }

    setState(() {
      _isRestoring = true;
    });
    try {
      final restored = await PhotoService().requeuePhotosForAiByIds(ids);
      AIService().unmarkJunkCandidatesAsKept(ids);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('已恢复 $restored 张照片，下一轮 AI 会重新判断。'),
        ),
      );
      _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('恢复低价值照片失败: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  void _toggleSelection(int photoId) {
    setState(() {
      if (_selectedPhotoIds.contains(photoId)) {
        _selectedPhotoIds.remove(photoId);
      } else {
        _selectedPhotoIds.add(photoId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('低价值照片回收站'),
        actions: [
          if (_selectedPhotoIds.isNotEmpty)
            TextButton(
              onPressed: _isRestoring
                  ? null
                  : () => _restorePhotos(_selectedPhotoIds),
              child: const Text('恢复所选'),
            ),
        ],
      ),
      body: FutureBuilder<List<PhotoEntity>>(
        future: _photosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final photos = snapshot.data ?? const <PhotoEntity>[];
          if (photos.isEmpty) {
            return const _EmptyTrash();
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '共 ${photos.length} 张已标记为低价值。恢复后会清空该标记，并加入下一轮 AI 重新处理。',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ),
                    if (_isRestoring)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  cacheExtent: 700.0,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    final selected = _selectedPhotoIds.contains(photo.id);
                    return _TrashPhotoTile(
                      photo: photo,
                      selected: selected,
                      onTap: () => _toggleSelection(photo.id),
                      onRestore: _isRestoring
                          ? null
                          : () => _restorePhotos(<int>[photo.id]),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrashPhotoTile extends StatelessWidget {
  const _TrashPhotoTile({
    required this.photo,
    required this.selected,
    required this.onTap,
    required this.onRestore,
  });

  final PhotoEntity photo;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => showFullscreenPhotoViewer(
          context,
          path: photo.path,
          assetId: photo.assetId,
          heroTag: 'junk-trash-${photo.id}',
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'junk-trash-${photo.id}',
              child: MediaThumbnail(
                path: photo.path,
                assetId: photo.assetId,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              left: 6,
              top: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.black.withValues(alpha: 0.48),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    selected ? Icons.check : Icons.recycling,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: IconButton.filledTonal(
                tooltip: '恢复为普通照片',
                onPressed: onRestore,
                icon: const Icon(Icons.restore, size: 18),
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTrash extends StatelessWidget {
  const _EmptyTrash();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.recycling,
              size: 54,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('回收站为空', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '被标记为低价值的照片会出现在这里，可随时恢复为普通照片。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}
