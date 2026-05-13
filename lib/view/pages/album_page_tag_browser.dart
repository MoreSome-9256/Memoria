/// 相册标签浏览页面，按标签层次快速浏览照片。

part of 'album_page.dart';

class _AlbumTagBrowserData {
  const _AlbumTagBrowserData({
    required this.totalPhotoCount,
    required this.analyzedPhotoCount,
    required this.taggedPhotoCount,
    required this.photos,
    required this.clusters,
  });

  final int totalPhotoCount;
  final int analyzedPhotoCount;
  final int taggedPhotoCount;
  final List<PhotoEntity> photos;
  final List<AlbumCoarseTagCluster> clusters;
}

class _AlbumTagClusterTile extends StatelessWidget {
  const _AlbumTagClusterTile({required this.cluster, required this.onTap});

  final AlbumCoarseTagCluster cluster;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: _AlbumTagClusterCoverMosaic(photos: cluster.coverPhotos),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            cluster.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            cluster.photoCount.toString(),
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _AlbumTagClusterCoverMosaic extends StatelessWidget {
  const _AlbumTagClusterCoverMosaic({required this.photos});

  final List<PhotoEntity> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return ColoredBox(
        color: Colors.grey.shade300,
        child: const Center(child: Icon(Icons.photo_library_outlined)),
      );
    }

    if (photos.length <= 2) {
      return _DeferredPathImage(path: photos.first.path, fit: BoxFit.cover);
    }

    final visible = photos.take(4).toList(growable: false);
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: visible.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        return _DeferredPathImage(path: visible[index].path, fit: BoxFit.cover);
      },
    );
  }
}

class _AlbumTagClusterSheet extends StatefulWidget {
  const _AlbumTagClusterSheet({required this.cluster, required this.allPhotos});

  final AlbumCoarseTagCluster cluster;
  final List<PhotoEntity> allPhotos;

  @override
  State<_AlbumTagClusterSheet> createState() => _AlbumTagClusterSheetState();
}

enum _ClusterSelectionMenuAction { selectAll, clear, cancel }

enum _ClusterActionMode { none, story, delete }

class _AlbumTagClusterSheetState extends State<_AlbumTagClusterSheet> {
  final AlbumTagBrowserService _browserService = AlbumTagBrowserService();
  String? _selectedFineTag;
  static const int _secondaryFilterTopK = 12;
  static const double _sheetBottomInset = 168;
  late final Stream<List<PhotoEntity>> _photosStream;
  _ClusterActionMode _actionMode = _ClusterActionMode.none;
  final Set<int> _selectedPhotoIds = <int>{};

  bool get _isSelectionMode => _actionMode != _ClusterActionMode.none;
  bool get _isDeleteMode => _actionMode == _ClusterActionMode.delete;

  @override
  void initState() {
    super.initState();
    _photosStream = _debounceStream<void>(
      PhotoService().isar.collection<PhotoEntity>().watchLazy(
        fireImmediately: true,
      ),
      const Duration(milliseconds: 650),
    ).asyncMap((_) => _loadCurrentPhotos());
  }

  Stream<T> _debounceStream<T>(Stream<T> source, Duration delay) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    Timer? timer;
    T? pending;
    var hasPending = false;

    void emitPending() {
      if (!hasPending) {
        return;
      }
      controller.add(pending as T);
      hasPending = false;
      pending = null;
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = source.listen(
          (event) {
            pending = event;
            hasPending = true;
            timer?.cancel();
            timer = Timer(delay, emitPending);
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            emitPending();
            controller.close();
          },
          cancelOnError: false,
        );
      },
      onCancel: () {
        timer?.cancel();
        subscription?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PhotoEntity>>(
      stream: _photosStream,
      initialData: widget.allPhotos,
      builder: (context, snapshot) {
        final allPhotos = snapshot.data ?? widget.allPhotos;
        final baseClusterPhotos = _browserService.photosForCoarseCluster(
          allPhotos,
          widget.cluster.coarseId,
        );
        final secondaryFilters = _browserService.topFineTagsForCoarseCluster(
          baseClusterPhotos,
          widget.cluster.coarseId,
          topK: _secondaryFilterTopK,
          includeCrossCoarseTags: true,
        );
        final clusterPhotos = _browserService.filterPhotosByFineTag(
          baseClusterPhotos,
          coarseId: widget.cluster.coarseId,
          fineTag: _selectedFineTag,
        );
        final monthGroups = _groupPhotosByMonth(clusterPhotos);

        return Stack(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.86,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.cluster.label,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedFineTag == null
                              ? '共 ${clusterPhotos.length} 张，按 ${secondaryFilters.length} 个相关标签筛选'
                              : '当前筛选：$_selectedFineTag · ${clusterPhotos.length} 张',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 14),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: const Text('全部'),
                                  selected: _selectedFineTag == null,
                                  onSelected: (_) {
                                    setState(() {
                                      _selectedFineTag = null;
                                    });
                                  },
                                ),
                              ),
                              ...secondaryFilters.map(
                                (tag) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text('${tag.label} ${tag.count}'),
                                    selected: _selectedFineTag == tag.label,
                                    onSelected: (_) {
                                      setState(() {
                                        _selectedFineTag = tag.label;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: clusterPhotos.isEmpty
                        ? Center(
                            child: Text(
                              '当前筛选下暂无图片',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : CustomScrollView(
                            slivers: [
                              for (final group in monthGroups) ...[
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      12,
                                    ),
                                    child: Text(
                                      group.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    18,
                                  ),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 3,
                                          mainAxisSpacing: 8,
                                          crossAxisSpacing: 8,
                                          childAspectRatio: 0.82,
                                        ),
                                    delegate: SliverChildBuilderDelegate((
                                      context,
                                      index,
                                    ) {
                                      final photo = group.photos[index];
                                      return _AlbumTagPhotoTile(
                                        photo: photo,
                                        selectionMode: _isSelectionMode,
                                        deleteMode: _isDeleteMode,
                                        selected: _selectedPhotoIds.contains(
                                          photo.id,
                                        ),
                                        onTap: () {
                                          if (_isSelectionMode) {
                                            _toggleSelection(photo.id);
                                            return;
                                          }
                                          showFullscreenPhotoViewer(
                                            context,
                                            path: photo.path,
                                            heroTag:
                                                'album-tag-photo-${photo.id}',
                                          );
                                        },
                                      );
                                    }, childCount: group.photos.length),
                                  ),
                                ),
                              ],
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height:
                                      _sheetBottomInset +
                                      MediaQuery.of(context).padding.bottom,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: _buildFloatingActions(clusterPhotos),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFloatingActions(List<PhotoEntity> clusterPhotos) {
    return ValueListenableBuilder<List<StoryQueueItem>>(
      valueListenable: StoryQueueService().queueListenable,
      builder: (context, items, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (items.isNotEmpty) ...[
              FloatingActionButton.extended(
                heroTag: 'tag-cluster-queue',
                onPressed: _openStoryQueuePage,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text('队列 ${items.length}'),
              ),
              const SizedBox(height: 10),
            ],
            if (_isSelectionMode)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSelectionMenuButton(
                    enableSelectAll: clusterPhotos.isNotEmpty,
                    onSelected: (action) {
                      switch (action) {
                        case _ClusterSelectionMenuAction.selectAll:
                          setState(() {
                            _selectedPhotoIds.addAll(
                              clusterPhotos.map((photo) => photo.id),
                            );
                          });
                          break;
                        case _ClusterSelectionMenuAction.clear:
                          setState(() {
                            _selectedPhotoIds.clear();
                          });
                          break;
                        case _ClusterSelectionMenuAction.cancel:
                          setState(() {
                            _actionMode = _ClusterActionMode.none;
                            _selectedPhotoIds.clear();
                          });
                          break;
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton.extended(
                    heroTag: 'tag-cluster-story',
                    onPressed: _isDeleteMode
                        ? () => _deleteSelectionFromLocalIndex(clusterPhotos)
                        : () => _addSelectionToQueue(clusterPhotos),
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
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'tag-cluster-delete',
                    onPressed: () {
                      setState(() {
                        _actionMode = _ClusterActionMode.delete;
                        _selectedPhotoIds.clear();
                      });
                    },
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton.extended(
                    heroTag: 'tag-cluster-story',
                    onPressed: () {
                      setState(() {
                        _actionMode = _ClusterActionMode.story;
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

  Widget _buildSelectionMenuButton({
    required ValueChanged<_ClusterSelectionMenuAction> onSelected,
    required bool enableSelectAll,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: const CircleBorder(),
      child: PopupMenuButton<_ClusterSelectionMenuAction>(
        tooltip: '选图操作',
        onSelected: onSelected,
        itemBuilder: (context) => <PopupMenuEntry<_ClusterSelectionMenuAction>>[
          PopupMenuItem<_ClusterSelectionMenuAction>(
            value: _ClusterSelectionMenuAction.selectAll,
            enabled: enableSelectAll,
            child: const Text('全选'),
          ),
          const PopupMenuItem<_ClusterSelectionMenuAction>(
            value: _ClusterSelectionMenuAction.clear,
            child: Text('清空'),
          ),
          const PopupMenuItem<_ClusterSelectionMenuAction>(
            value: _ClusterSelectionMenuAction.cancel,
            child: Text('取消'),
          ),
        ],
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.more_horiz_rounded),
        ),
      ),
    );
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

  void _addSelectionToQueue(List<PhotoEntity> clusterPhotos) {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一张照片加入故事队列')));
      return;
    }

    final selected = clusterPhotos
        .where((photo) => _selectedPhotoIds.contains(photo.id))
        .map(StoryQueueService.mapPhotoEntityToQueuePhoto)
        .toList(growable: false);
    final addedCount = StoryQueueService().addPhotos(selected);

    setState(() {
      _actionMode = _ClusterActionMode.none;
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

  Future<void> _deleteSelectionFromLocalIndex(
    List<PhotoEntity> clusterPhotos,
  ) async {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一张照片再删除')));
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

    final selected = clusterPhotos
        .where((photo) => _selectedPhotoIds.contains(photo.id))
        .toList(growable: false);

    var removedCount = 0;
    for (final entity in selected) {
      await JunkPhotoCleanupService().removeFromLocalIndex(entity);
      StoryQueueService().removePhoto(entity.assetId);
      removedCount += 1;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _actionMode = _ClusterActionMode.none;
      _selectedPhotoIds.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          removedCount > 0 ? '已删除 $removedCount 条本地记录' : '没有删除任何本地记录',
        ),
      ),
    );
  }

  void _openStoryQueuePage() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const StoryQueuePage()));
  }

  Future<List<PhotoEntity>> _loadCurrentPhotos() async {
    if (AIService().isAnalyzing) {
      // 打标高峰期避免每次写库都触发重查，减少 UI 抢占。
      return widget.allPhotos;
    }

    return _loadAlbumTagBrowserSourcePhotos();
  }

  List<_AlbumPhotoMonthGroup> _groupPhotosByMonth(List<PhotoEntity> photos) {
    final grouped = <String, List<PhotoEntity>>{};
    for (final photo in photos) {
      final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => <PhotoEntity>[]).add(photo);
    }
    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys
        .map(
          (key) => _AlbumPhotoMonthGroup(
            title: _formatMonthTitle(key),
            photos: grouped[key]!
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
          ),
        )
        .toList(growable: false);
  }

  String _formatMonthTitle(String key) {
    final parts = key.split('-');
    if (parts.length != 3) {
      return key;
    }
    return '${parts[0]}年${parts[1]}月${parts[2]}日';
  }
}

class _AlbumPhotoMonthGroup {
  const _AlbumPhotoMonthGroup({required this.title, required this.photos});

  final String title;
  final List<PhotoEntity> photos;
}
