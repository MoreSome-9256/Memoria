/// 相册搜索页面，支持语义检索和关键词检索照片。

import 'package:flutter/material.dart';

import '../../models/entity/photo_entity.dart';
import '../../models/vo/semantic_search_models.dart';
import '../../service/album_tag_browser_service.dart';
import '../../service/photo_service.dart';
import '../../service/semantic_photo_search_service.dart';
import '../../service/story_queue_service.dart';
import '../widgets/deferred_path_image.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import 'story_queue_page.dart';
import '../../storage/objectbox/objectbox_service.dart';

enum _SearchSortMode { score, time }

// enum _SelectionMenuAction { selectAll, clear, cancel }

class AlbumSearchPage extends StatefulWidget {
  const AlbumSearchPage({
    super.key,
    required this.initialQuery,
    this.initialPhotoIds = const <int>[],
    this.hideSearchBar = false,
    this.lockInitialResults = false,
    this.recommendationTitle,
  });

  final String initialQuery;
  final List<int> initialPhotoIds;
  final bool hideSearchBar;
  final bool lockInitialResults;
  final String? recommendationTitle;

  @override
  State<AlbumSearchPage> createState() => _AlbumSearchPageState();
}

class _AlbumSearchPageState extends State<AlbumSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final AlbumTagBrowserService _tagBrowserService = AlbumTagBrowserService();

  bool _isSearching = false;
  bool _selectionMode = false;
  String? _errorMessage;
  SemanticSearchResult? _result;
  List<PhotoEntity> _directPhotos = const <PhotoEntity>[];
  _SearchSortMode _sortMode = _SearchSortMode.score;
  String? _selectedTag;
  final Set<int> _selectedPhotoIds = <int>{};

  bool get _isLockedResultMode =>
      widget.lockInitialResults && widget.initialPhotoIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    if (_isLockedResultMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInitialPhotos();
      });
    } else if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    if (_isLockedResultMode) {
      return;
    }
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _result = null;
        _errorMessage = null;
        _selectionMode = false;
        _selectedPhotoIds.clear();
        _selectedTag = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _selectionMode = false;
      _selectedPhotoIds.clear();
    });

    try {
      final result = await SemanticPhotoSearchService().search(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _isSearching = false;
        _sortMode = _SearchSortMode.score;
        _selectedTag = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
        _isSearching = false;
      });
    }
  }

  Future<void> _loadInitialPhotos() async {
    final ids = widget.initialPhotoIds;
    if (ids.isEmpty) {
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _selectionMode = false;
      _selectedPhotoIds.clear();
    });

    try {
      final photos = ObjectBoxService().store.box<PhotoEntity>()
          .getMany(ids).whereType<PhotoEntity>().toList(growable: false);
      final reconciled = await PhotoService().reconcileAccessiblePhotos(photos);
      final photoById = <int, PhotoEntity>{
        for (final photo in reconciled) photo.id: photo,
      };
      final orderedPhotos = ids
          .map((id) => photoById[id])
          .whereType<PhotoEntity>()
          .toList(growable: false);

      if (!mounted) {
        return;
      }
      setState(() {
        _directPhotos = orderedPhotos;
        _isSearching = false;
        _errorMessage = null;
        _sortMode = _SearchSortMode.score;
        _selectedTag = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
        _isSearching = false;
      });
    }
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _performSearch(),
      decoration: InputDecoration(
        hintText: '搜索时间、地点、场景或回忆',
        prefixIcon: const Icon(Icons.manage_search_rounded),
        suffixIcon: IconButton(
          onPressed: _performSearch,
          icon: const Icon(Icons.search_rounded),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildRecommendationTitleBar() {
    final title = (widget.recommendationTitle ?? widget.initialQuery).trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.isEmpty ? '推荐结果' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.auto_awesome_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedOnlyNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFFFFF4E5),
        border: Border.all(color: const Color(0xFFF4B267)),
      ),
      child: const Text(
        '未找到您所需的图片，只找到一些相关图片。',
        style: TextStyle(
          color: Color(0xFF8A4B08),
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildControlPanel(
    List<PhotoEntity> allPhotos,
    Map<int, SemanticSearchHit> hits,
  ) {
    final tagSummaries = _buildFineTagSummaries(allPhotos, hits);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selectedTag == null
                ? '共 ${allPhotos.length} 张，按 ${tagSummaries.length} 个相关标签筛选'
                : '当前标签：$_selectedTag · ${_visiblePhotos(allPhotos, _result).length} 张',
            style: TextStyle(
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '排序方式',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _sortChip('综合得分', _SearchSortMode.score),
              _sortChip('时间', _SearchSortMode.time),
            ],
          ),
          if (tagSummaries.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '相关标签',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('全部'),
                      selected: _selectedTag == null,
                      onSelected: (_) {
                        setState(() {
                          _selectedTag = null;
                        });
                      },
                    ),
                  ),
                  ...tagSummaries.map(
                    (tag) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('${tag.label} ${tag.count}'),
                        selected: _selectedTag == tag.label,
                        onSelected: (_) {
                          setState(() {
                            _selectedTag = tag.label;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  ChoiceChip _sortChip(String label, _SearchSortMode mode) {
    return ChoiceChip(
      label: Text(label),
      selected: _sortMode == mode,
      onSelected: (_) {
        setState(() {
          _sortMode = mode;
        });
      },
    );
  }

  Widget? _buildStoryFab(List<PhotoEntity> photos) {
    if (photos.isEmpty) {
      return null;
    }
    return FloatingActionButton.extended(
      onPressed: () {
        setState(() {
          _selectionMode = true;
          _selectedPhotoIds
            ..clear()
            ..addAll(photos.map((photo) => photo.id));
        });
      },
      icon: const Icon(Icons.auto_stories_rounded),
      label: const Text('生成故事'),
    );
  }

  Widget? _buildFloatingStoryActions(List<PhotoEntity> currentPhotos) {
    final visiblePhotos = _visiblePhotos(currentPhotos, _result);
    final hasVisibleSelection = visiblePhotos
        .any((photo) => _selectedPhotoIds.contains(photo.id));
    final allVisibleSelected = visiblePhotos.isNotEmpty &&
        visiblePhotos.every((photo) => _selectedPhotoIds.contains(photo.id));
    final storyFab = _selectionMode
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: visiblePhotos.isEmpty
                        ? null
                        : () {
                            if (allVisibleSelected || hasVisibleSelection) {
                              setState(() {
                                _selectedPhotoIds.clear();
                              });
                            } else {
                              _selectAllVisible(visiblePhotos);
                            }
                          },
                    icon: Icon(
                      allVisibleSelected || hasVisibleSelection
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                    ),
                    label: Text(
                      allVisibleSelected || hasVisibleSelection ? '取消全选' : '全选',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'semantic-search-add-queue',
                onPressed: _addSelectionToQueue,
                icon: const Icon(Icons.playlist_add_rounded),
                label: Text(
                  _selectedPhotoIds.isEmpty
                      ? '加入故事队列'
                      : '加入故事队列 ${_selectedPhotoIds.length}',
                ),
              ),
            ],
          )
        : _buildStoryFab(currentPhotos);
    if (storyFab == null) {
      return null;
    }
    return ValueListenableBuilder<List<StoryQueueItem>>(
      valueListenable: StoryQueueService().queueListenable,
      builder: (context, items, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (items.isNotEmpty) ...[
              FloatingActionButton.extended(
                heroTag: 'semantic-search-queue',
                onPressed: _openStoryQueuePage,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text('队列 ${items.length}'),
              ),
              const SizedBox(height: 10),
            ],
            storyFab,
          ],
        );
      },
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

    final allPhotos = _currentPhotos(_result);
    if (allPhotos.isEmpty) {
      return;
    }

    final selectedEntities = allPhotos
        .where((photo) => _selectedPhotoIds.contains(photo.id))
        .toList(growable: false);
    final addedCount = StoryQueueService().addPhotos(
      selectedEntities
          .map(StoryQueueService.mapPhotoEntityToQueuePhoto)
          .toList(growable: false),
      semanticSearchQuery: _controller.text.trim(),
    );

    setState(() {
      _selectionMode = false;
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

  SliverPadding _buildGridSliver(List<PhotoEntity> photos) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final photo = photos[index];
            return _SearchPhotoTile(
              photo: photo,
              selectionMode: _selectionMode,
              selected: _selectedPhotoIds.contains(photo.id),
              onTap: () {
                if (_selectionMode) {
                  _toggleSelection(photo.id);
                  return;
                }
                showFullscreenPhotoViewer(
                  context,
                  path: photo.path,
                  heroTag: 'search-photo-${photo.id}',
                );
              },
            );
          },
          childCount: photos.length,
        ),
      ),
    );
  }

  List<Widget> _buildTimeGroupedSlivers(List<PhotoEntity> photos) {
    final groups = _groupPhotosByMonth(photos);
    return <Widget>[
      for (final group in groups) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Text(
              group.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final photo = group.photos[index];
                return _SearchPhotoTile(
                  photo: photo,
                  selectionMode: _selectionMode,
                  selected: _selectedPhotoIds.contains(photo.id),
                  onTap: () {
                    if (_selectionMode) {
                      _toggleSelection(photo.id);
                      return;
                    }
                    showFullscreenPhotoViewer(
                      context,
                      path: photo.path,
                      heroTag: 'search-photo-${photo.id}',
                    );
                  },
                );
              },
              childCount: group.photos.length,
            ),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 96)),
    ];
  }

  List<PhotoEntity> _allPhotos(SemanticSearchResult result) {
    return <int, PhotoEntity>{
      for (final photo in <PhotoEntity>[
        ...result.exactPhotos,
        ...result.relatedPhotos,
      ])
        photo.id: photo,
    }.values.toList(growable: false);
  }

  List<PhotoEntity> _currentPhotos(SemanticSearchResult? result) {
    if (_isLockedResultMode) {
      return _directPhotos;
    }
    if (result == null) {
      return const <PhotoEntity>[];
    }
    return _allPhotos(result);
  }

  List<PhotoEntity> _visiblePhotos(
    List<PhotoEntity> photos,
    SemanticSearchResult? result,
  ) {
    final filtered = photos.where((photo) {
      if (_selectedTag == null) {
        return true;
      }
      final tags = _tagBrowserService.browsableTagsForPhoto(photo);
      return tags.contains(_selectedTag);
    }).toList(growable: false);

    filtered.sort((a, b) {
      switch (_sortMode) {
        case _SearchSortMode.score:
          if (_isLockedResultMode) {
            final lockedRank = <int, int>{
              for (var index = 0; index < widget.initialPhotoIds.length; index++)
                widget.initialPhotoIds[index]: index,
            };
            final aRank = lockedRank[a.id] ?? 1 << 20;
            final bRank = lockedRank[b.id] ?? 1 << 20;
            final rankCompare = aRank.compareTo(bRank);
            if (rankCompare != 0) {
              return rankCompare;
            }
          } else {
            final aScore = result?.hits[a.id]?.score ?? 0.0;
            final bScore = result?.hits[b.id]?.score ?? 0.0;
            final scoreCompare = bScore.compareTo(aScore);
            if (scoreCompare != 0) {
              return scoreCompare;
            }
          }
          return b.timestamp.compareTo(a.timestamp);
        case _SearchSortMode.time:
          return b.timestamp.compareTo(a.timestamp);
      }
    });
    return filtered;
  }

  List<AlbumFineTagSummary> _buildFineTagSummaries(
    List<PhotoEntity> photos,
    Map<int, SemanticSearchHit> hits,
  ) {
    final counts = <String, int>{};
    final scores = <String, double>{};
    for (final photo in photos) {
      final tags = _tagBrowserService.browsableTagsForPhoto(photo);
      final hitScore = hits[photo.id]?.score ?? 0.0;
      for (final tag in tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
        scores[tag] = (scores[tag] ?? 0.0) + 1 + hitScore;
      }
    }

    final sorted = counts.entries.toList(growable: false)
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) {
          return countCompare;
        }
        return (scores[b.key] ?? 0.0).compareTo(scores[a.key] ?? 0.0);
      });

    return sorted
        .take(12)
        .map((entry) => AlbumFineTagSummary(label: entry.key, count: entry.value))
        .toList(growable: false);
  }

  List<_PhotoMonthGroup> _groupPhotosByMonth(List<PhotoEntity> photos) {
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
          (key) => _PhotoMonthGroup(
            title: _formatDayTitle(key),
            photos: grouped[key]!..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
          ),
        )
        .toList(growable: false);
  }

  String _formatDayTitle(String key) {
    final _ = _formatMonthTitle;
    final parts = key.split('-');
    if (parts.length != 3) {
      return key;
    }
    return '${parts[0]}年${parts[1]}月${parts[2]}日';
  }

  String _formatMonthTitle(String key) {
    final parts = key.split('-');
    if (parts.length != 3) {
      return key;
    }
    return '${parts[0]}年${parts[1]}月';
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

  void _selectAllVisible(List<PhotoEntity> visiblePhotos) {
    setState(() {
      _selectedPhotoIds.addAll(visiblePhotos.map((photo) => photo.id));
    });
  }

  Widget _buildIdleState() {
    return const Center(
      child: Text('输入自然语言开始搜索，例如“春节团聚吃饺子的照片”'),
    );
  }

  Widget _buildEmptyState(SemanticSearchResult result) {
    final message = result.relaxationMessage?.trim().isNotEmpty == true
        ? '没有找到符合条件的图片。\n${result.relaxationMessage!}'
        : '没有找到匹配的图片，可以尝试放宽时间、地点或语义描述。';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], height: 1.5),
        ),
      ),
    );
  }

  Widget _buildFilterEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '当前标签筛选下没有图片，可以切换到“全部”查看。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], height: 1.5),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.red, size: 46),
            const SizedBox(height: 12),
            Text(_errorMessage ?? '搜索失败'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isLockedResultMode ? _loadInitialPhotos : _performSearch,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final currentPhotos = _currentPhotos(result);
    final visiblePhotos = _visiblePhotos(currentPhotos, result);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      floatingActionButton: currentPhotos.isEmpty
          ? null
          : _buildFloatingStoryActions(currentPhotos),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.28),
            ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            cacheExtent: 700,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      tooltip: '返回',
                    ),
                  ),
                ),
              ),
              if (_isLockedResultMode)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildRecommendationTitleBar(),
                  ),
                )
              else if (!widget.hideSearchBar)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildSearchBar(),
                  ),
                ),
              if (!widget.hideSearchBar &&
                  result != null &&
                  !result.hasExactMatches &&
                  result.hasRelatedMatches)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildRelatedOnlyNotice(),
                  ),
                ),
              if ((_isLockedResultMode && currentPhotos.isNotEmpty) ||
                  (!widget.hideSearchBar &&
                      result != null &&
                      (result.hasExactMatches || result.hasRelatedMatches)))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildControlPanel(
                      currentPhotos,
                      result?.hits ?? const <int, SemanticSearchHit>{},
                    ),
                  ),
                ),
              if (_isSearching)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildErrorState(),
                )
              else if (!_isLockedResultMode && result == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildIdleState(),
                )
              else if (_isLockedResultMode && currentPhotos.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '这组推荐图片暂时不可用，可以返回后等待后台重新刷新推荐。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[600],
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                )
              else if (!_isLockedResultMode &&
                  !result!.hasExactMatches &&
                  !result.hasRelatedMatches)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(result),
                )
              else if (visiblePhotos.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildFilterEmptyState(),
                )
              else if (_sortMode == _SearchSortMode.time)
                ..._buildTimeGroupedSlivers(visiblePhotos)
              else
                _buildGridSliver(visiblePhotos),
            ],
          ),
        ),
      ),
    );
  }

// Widget _buildSelectionMenuButton({
//   required ValueChanged<_SelectionMenuAction> onSelected,
//   required bool enableSelectAll,
// }) {
//   return Material(
//     color: Theme.of(context).colorScheme.surface,
//     elevation: 4,
//     shadowColor: Colors.black.withValues(alpha: 0.15),
//     shape: const CircleBorder(),
//     child: PopupMenuButton<_SelectionMenuAction>(
//       tooltip: '选图操作',
//       onSelected: onSelected,
//       itemBuilder: (context) => <PopupMenuEntry<_SelectionMenuAction>>[
//         PopupMenuItem<_SelectionMenuAction>(
//           value: _SelectionMenuAction.selectAll,
//           enabled: enableSelectAll,
//           child: const Text('全选'),
//         ),
//         const PopupMenuItem<_SelectionMenuAction>(
//           value: _SelectionMenuAction.clear,
//           child: Text('清空'),
//         ),
//         const PopupMenuItem<_SelectionMenuAction>(
//           value: _SelectionMenuAction.cancel,
//           child: Text('取消'),
//         ),
//       ],
//       child: const SizedBox(
//         width: 48,
//         height: 48,
//         child: Icon(Icons.more_horiz_rounded),
//       ),
//     ),
//   );
// }
}

class _SearchPhotoTile extends StatelessWidget {
  const _SearchPhotoTile({
    required this.photo,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
  });

  final PhotoEntity photo;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectionBadgeColor = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'search-photo-${photo.id}',
              child: DeferredPathImage(path: photo.path, fit: BoxFit.cover),
            ),
            if (selectionMode)
              if (!selected)
                Container(color: Colors.black.withValues(alpha: 0.32)),
            if (selectionMode)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? selectionBadgeColor
                        : Colors.white.withValues(alpha: 0.88),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Icon(
                    selected ? Icons.check_rounded : Icons.add_rounded,
                    size: 16,
                    color: selected ? Colors.white : selectionBadgeColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoMonthGroup {
  const _PhotoMonthGroup({required this.title, required this.photos});

  final String title;
  final List<PhotoEntity> photos;
}
