import 'package:flutter/material.dart';

import '../../models/ai_theme.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../../models/vo/semantic_search_models.dart';
import '../../service/album_tag_browser_service.dart';
import '../../service/semantic_photo_search_service.dart';
import '../../utils/ocr_policy.dart';
import '../../utils/tag_sanitizer.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import '../widgets/path_image.dart';
import 'config_page.dart';

enum _SearchSortMode { score, time }

class AlbumSearchPage extends StatefulWidget {
  const AlbumSearchPage({super.key, required this.initialQuery});

  final String initialQuery;

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
  _SearchSortMode _sortMode = _SearchSortMode.score;
  String? _selectedTag;
  final Set<int> _selectedPhotoIds = <int>{};

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    if (widget.initialQuery.trim().isNotEmpty) {
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

  Widget _buildControlPanel(SemanticSearchResult result) {
    final allPhotos = _allPhotos(result);
    final tagSummaries = _buildFineTagSummaries(allPhotos, result.hits);

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
                : '当前标签：$_selectedTag · ${_visiblePhotos(result).length} 张',
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

  Widget? _buildStoryFab(
    SemanticSearchResult result,
    List<PhotoEntity> visiblePhotos,
  ) {
    if (_allPhotos(result).isEmpty) {
      return null;
    }
    if (_selectionMode) {
      return FloatingActionButton.extended(
        onPressed: _generateStoryFromSelection,
        icon: const Icon(Icons.auto_stories_rounded),
        label: Text(
          _selectedPhotoIds.isEmpty
              ? '继续生成'
              : '继续生成 ${_selectedPhotoIds.length}',
        ),
      );
    }
    return FloatingActionButton.extended(
      onPressed: () {
        setState(() {
          _selectionMode = true;
          _selectedPhotoIds.clear();
        });
      },
      icon: const Icon(Icons.auto_stories_rounded),
      label: const Text('生成故事'),
    );
  }

  Widget _buildSelectionBar(List<PhotoEntity> visiblePhotos) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedPhotoIds.isEmpty
                    ? '已进入选图模式，点击图片即可加入故事生成。'
                    : '已选择 ${_selectedPhotoIds.length} 张照片',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: visiblePhotos.isEmpty ? null : () => _selectAllVisible(visiblePhotos),
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedPhotoIds.clear();
                });
              },
              child: const Text('清空'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedPhotoIds.clear();
                });
              },
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
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

  List<PhotoEntity> _visiblePhotos(SemanticSearchResult result) {
    final photos = _allPhotos(result).where((photo) {
      if (_selectedTag == null) {
        return true;
      }
      final tags = _tagBrowserService.clusterableTagsForPhoto(photo);
      return tags.contains(_selectedTag);
    }).toList(growable: false);

    photos.sort((a, b) {
      switch (_sortMode) {
        case _SearchSortMode.score:
          final aScore = result.hits[a.id]?.score ?? 0.0;
          final bScore = result.hits[b.id]?.score ?? 0.0;
          final scoreCompare = bScore.compareTo(aScore);
          if (scoreCompare != 0) {
            return scoreCompare;
          }
          return b.timestamp.compareTo(a.timestamp);
        case _SearchSortMode.time:
          return b.timestamp.compareTo(a.timestamp);
      }
    });
    return photos;
  }

  List<AlbumFineTagSummary> _buildFineTagSummaries(
    List<PhotoEntity> photos,
    Map<int, SemanticSearchHit> hits,
  ) {
    final counts = <String, int>{};
    final scores = <String, double>{};
    for (final photo in photos) {
      final tags = _tagBrowserService.clusterableTagsForPhoto(photo);
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
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => <PhotoEntity>[]).add(photo);
    }
    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys
        .map(
          (key) => _PhotoMonthGroup(
            title: _formatMonthTitle(key),
            photos: grouped[key]!..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
          ),
        )
        .toList(growable: false);
  }

  String _formatMonthTitle(String key) {
    final parts = key.split('-');
    if (parts.length != 2) {
      return key;
    }
    return '${parts[0]}年${parts[1]}月';
  }

  String _primaryLocationLabel(PhotoEntity photo) {
    return (photo.locationName ??
            photo.district ??
            photo.city ??
            photo.province ??
            '')
        .trim()
        .ifEmpty('未知地点');
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

  void _generateStoryFromSelection() {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一张照片再生成故事')),
      );
      return;
    }

    final result = _result;
    if (result == null) {
      return;
    }

    final selectedEntities = _allPhotos(result)
        .where((photo) => _selectedPhotoIds.contains(photo.id))
        .toList(growable: false)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (selectedEntities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可用于生成故事的照片')),
      );
      return;
    }

    final mappedPhotos = selectedEntities.map(_mapPhotoEntityToPhoto).toList();
    final startDate =
        DateTime.fromMillisecondsSinceEpoch(selectedEntities.first.timestamp);
    final endDate =
        DateTime.fromMillisecondsSinceEpoch(selectedEntities.last.timestamp);
    final queryTitle = _controller.text.trim().isEmpty ? '我的回忆' : _controller.text.trim();
    final virtualTheme = AITheme(
      id: 'semantic_search_theme',
      emoji: '\u2728',
      title: queryTitle,
      subtitle: 'Semantic search picks',
    );
    final virtualEvent = Event(
      id: '-1',
      title: queryTitle,
      season: _seasonOf(startDate),
      year: startDate.year,
      location: _resolveEventLocation(selectedEntities),
      startDate: startDate,
      endDate: endDate,
      photos: mappedPhotos,
      aiThemes: <AITheme>[virtualTheme],
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConfigPage(
          event: virtualEvent,
          selectedPhotos: virtualEvent.photos,
          selectedTheme: virtualTheme,
          semanticSearchQuery: _controller.text.trim(),
        ),
      ),
    );
  }

  Photo _mapPhotoEntityToPhoto(PhotoEntity photo) {
    return Photo(
      id: photo.assetId,
      location: _primaryLocationLabel(photo),
      path: photo.path,
      dateTaken: DateTime.fromMillisecondsSinceEpoch(photo.timestamp),
      tags: TagSanitizer.sanitizeVisualTags(photo.aiTags ?? const <String>[]),
      caption: photo.aiCaption?.trim(),
      ocrSummary: OcrPolicy.effectiveSummary(
        tags: photo.ocrTags ?? const <String>[],
        text: photo.ocrText,
      ),
      ocrTags: OcrPolicy.effectiveTags(photo.ocrTags ?? const <String>[]),
      isSelected: true,
    );
  }

  String _resolveEventLocation(List<PhotoEntity> photos) {
    final counts = <String, int>{};
    for (final photo in photos) {
      final label = _primaryLocationLabel(photo);
      counts[label] = (counts[label] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      return '多地回忆';
    }
    final sorted = counts.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.length == 1 ? sorted.first.key : '多地回忆 · ${sorted.first.key}';
  }

  String _seasonOf(DateTime date) {
    final month = date.month;
    if (month >= 3 && month <= 5) {
      return 'Spring';
    }
    if (month >= 6 && month <= 8) {
      return 'Summer';
    }
    if (month >= 9 && month <= 11) {
      return 'Autumn';
    }
    return 'Winter';
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
              onPressed: _performSearch,
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
    final visiblePhotos = result == null ? const <PhotoEntity>[] : _visiblePhotos(result);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      floatingActionButton:
          result == null ? null : _buildStoryFab(result, visiblePhotos),
      bottomNavigationBar:
          _selectionMode ? _buildSelectionBar(visiblePhotos) : null,
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
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _buildSearchBar(),
                ),
              ),
              if (result != null && !result.hasExactMatches && result.hasRelatedMatches)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildRelatedOnlyNotice(),
                  ),
                ),
              if (result != null &&
                  (result.hasExactMatches || result.hasRelatedMatches))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildControlPanel(result),
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
              else if (result == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildIdleState(),
                )
              else if (!result.hasExactMatches && !result.hasRelatedMatches)
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
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: 'search-photo-${photo.id}',
              child: PathImage(path: photo.path, fit: BoxFit.cover),
            ),
            if (selectionMode)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black.withValues(alpha: 0.32),
                    border: Border.all(color: Colors.white, width: 1.8),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : null,
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

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
