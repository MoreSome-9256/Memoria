/// 创作中心页面，聚合故事和推荐相关的创建入口。

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/entity/photo_entity.dart';
import '../../models/entity/story_entity.dart';
import '../../service/create_recommendation_service.dart';
import '../../service/photo_service.dart';
import '../../service/story_service.dart';
import '../widgets/path_image.dart';
import 'album_search_page.dart';
import 'create_page.dart';
import 'stories_page.dart';
import 'story_result_page.dart';

class CreateHubPage extends StatefulWidget {
  const CreateHubPage({super.key});

  @override
  State<CreateHubPage> createState() => _CreateHubPageState();
}

enum _SavedStorySortMode {
  recentSaved,
  recentUpdated,
  mostPhotos,
}

class _CreateHubPageState extends State<CreateHubPage>
    with WidgetsBindingObserver {
  static const Duration _backgroundRefreshPause = Duration(milliseconds: 280);

  final CreateRecommendationService _recommendationService =
      CreateRecommendationService();

  bool _loadingCached = true;
  bool _refreshingRecommendations = false;
  bool _pendingForceRefresh = false;
  String? _refreshError;
  int _refreshSessionId = 0;
  List<CreateRecommendationCardData> _recommendations =
      const <CreateRecommendationCardData>[];
  List<_StoryPreviewItem> _storyPreviews = const <_StoryPreviewItem>[];
  _SavedStorySortMode _storySortMode = _SavedStorySortMode.recentUpdated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCachedContent());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshRecommendationsInBackground());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadCachedContent());
      unawaited(_refreshRecommendationsInBackground());
    }
  }

  Future<void> _loadCachedContent() async {
    try {
      final recommendations =
          await _recommendationService.loadActiveRecommendations();
      final stories = await _loadStoryPreviews(_storySortMode);
      if (!mounted) {
        return;
      }
      setState(() {
        _recommendations = recommendations;
        _storyPreviews = stories;
        _loadingCached = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingCached = false;
        _refreshError = error.toString();
      });
    }
  }

  Future<void> _refreshRecommendationsInBackground({bool force = false}) async {
    if (_refreshingRecommendations) {
      if (force) {
        _pendingForceRefresh = true;
      }
      return;
    }

    final sessionId = ++_refreshSessionId;
    final processedKeys = <String>{};

    setState(() {
      _refreshingRecommendations = true;
      _refreshError = null;
    });

    try {
      var hasRemaining = true;
      while (mounted && sessionId == _refreshSessionId && hasRemaining) {
        final refreshResult =
            await _recommendationService.refreshRecommendationsIfNeeded(
          force: force,
          excludeRecommendationKeys: processedKeys,
        );
        processedKeys.addAll(refreshResult.processedRecommendationKeys);
        hasRemaining = refreshResult.hasRemaining;

        final recommendations =
            await _recommendationService.loadActiveRecommendations();
        if (!mounted || sessionId != _refreshSessionId) {
          return;
        }
        setState(() {
          _recommendations = recommendations;
        });

        if (!hasRemaining) {
          break;
        }

        await Future.delayed(_backgroundRefreshPause);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _refreshError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _refreshingRecommendations = false;
        });
      }
      if (mounted && _pendingForceRefresh) {
        _pendingForceRefresh = false;
        unawaited(_refreshRecommendationsInBackground(force: true));
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _loadCachedContent();
    await _refreshRecommendationsInBackground(force: true);
  }

  Future<List<_StoryPreviewItem>> _loadStoryPreviews(
    _SavedStorySortMode sortMode,
  ) async {
    final stories = await StoryService().getAllStories();
    if (stories.isEmpty) {
      return const <_StoryPreviewItem>[];
    }

    final sorted = List<StoryEntity>.from(stories);
    switch (sortMode) {
      case _SavedStorySortMode.recentSaved:
        sorted.sort((left, right) => right.createdAt.compareTo(left.createdAt));
        break;
      case _SavedStorySortMode.recentUpdated:
        sorted.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
        break;
      case _SavedStorySortMode.mostPhotos:
        sorted.sort((left, right) {
          final countCompare = right.photoCount.compareTo(left.photoCount);
          if (countCompare != 0) {
            return countCompare;
          }
          return right.updatedAt.compareTo(left.updatedAt);
        });
        break;
    }

    final coverIds = sorted
        .map((story) => story.photoIds.isNotEmpty ? story.photoIds.first : null)
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    final covers = (await PhotoService().isar.photoEntitys.getAll(coverIds))
        .whereType<PhotoEntity>()
        .toList(growable: false);
    final reconciled = await PhotoService().reconcileAccessiblePhotos(covers);
    final coverById = <int, PhotoEntity>{
      for (final photo in reconciled) photo.id: photo,
    };

    return sorted
        .take(12)
        .map(
          (story) => _StoryPreviewItem(
            story: story,
            cover: story.photoIds.isNotEmpty
                ? coverById[story.photoIds.first]
                : null,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _changeStorySort(_SavedStorySortMode mode) async {
    if (_storySortMode == mode) {
      return;
    }
    setState(() {
      _storySortMode = mode;
    });
    await _loadCachedContent();
  }

  Future<void> _openStory(StoryEntity story) async {
    final photos = await StoryService().loadPhotos(story.photoIds);
    if (!mounted) {
      return;
    }
    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个故事缺少可用照片，暂时无法打开。')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryResultPage.fromStoryEntity(
          storyEntity: story,
          photos: photos,
          isHorizontal: _safeStoryIsHorizontal(story),
          targetPlatform: story.targetPlatform ?? '小红书',
        ),
      ),
    );

    if (mounted) {
      await _loadCachedContent();
    }
  }

  void _openOriginalCreateSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreatePage()),
    );
  }

  void _openRecommendation(CreateRecommendationCardData card) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AlbumSearchPage(
          initialQuery: card.query,
          initialPhotoIds: card.entity.photoIds,
          hideSearchBar: true,
          lockInitialResults: true,
          recommendationTitle: card.title,
        ),
      ),
    );
  }

  Future<void> _dismissRecommendation(CreateRecommendationCardData card) async {
    await _recommendationService.dismissRecommendation(card.entity.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _recommendations = _recommendations
          .where((item) => item.entity.id != card.entity.id)
          .toList(growable: false);
    });
  }

  bool _safeStoryIsHorizontal(StoryEntity story) {
    try {
      return story.isHorizontal;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          _buildAmbientBackground(),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _buildTopTitle(),
                  const SizedBox(height: 18),
                  _buildSemanticSearchPrompt(),
                  const SizedBox(height: 18),
                  _buildRecommendationGroup(),
                  const SizedBox(height: 18),
                  _buildSavedStoriesGroup(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTitle() {
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Text(
            'Memoria 创作入口',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.black.withValues(alpha: 0.84),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSemanticSearchPrompt() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _openOriginalCreateSearch,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF6FA), Color(0xFFF7F1FF)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.82)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFE5F0),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFCC6B9A),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '想你所想',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.black.withValues(alpha: 0.84),
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '点这里进入语义搜索，试试“春天的气息”“去年今日”“和朋友聚会的那天”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.black.withValues(alpha: 0.58),
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEAF3),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: Color(0xFFB55B86),
                    ),
                    SizedBox(width: 6),
                    Text(
                      '去搜索',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB55B86),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationGroup() {
    return _GroupCard(
      title: '创作推荐',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_refreshingRecommendations)
            Text(
              '后台更新中',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF9D4D72),
                    fontWeight: FontWeight.w700,
                  ),
            )
          else
            IconButton(
              tooltip: '刷新推荐',
              onPressed: () =>
                  unawaited(_refreshRecommendationsInBackground(force: true)),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_refreshError != null) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _refreshError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF8C3A4B),
                    ),
              ),
            ),
          ],
          if (_recommendations.isEmpty)
            _buildEmptyState(
              title: _loadingCached ? '正在读取已有推荐…' : '还没有可展示的创作推荐',
              body:
                  '页面会立即打开，推荐刷新放在后台进行。系统会优先尝试更有意义的主题，例如相聚、成长、旅途、宠物、节庆、校园、兴趣与当季氛围。',
            )
          else
            SizedBox(
              height: 380,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recommendations.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final card = _recommendations[index];
                  return _RecommendationPreviewCard(
                    card: card,
                    onOpen: () => _openRecommendation(card),
                    onDismiss: () => _dismissRecommendation(card),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSavedStoriesGroup() {
    return _GroupCard(
      title: '故事相册',
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PopupMenuButton<_SavedStorySortMode>(
            tooltip: '故事排序',
            onSelected: _changeStorySort,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _SavedStorySortMode.recentUpdated,
                child: Text('最近更新'),
              ),
              PopupMenuItem(
                value: _SavedStorySortMode.recentSaved,
                child: Text('最近保存'),
              ),
              PopupMenuItem(
                value: _SavedStorySortMode.mostPhotos,
                child: Text('照片最多'),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF7EFFC),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _storySortLabel(_storySortMode),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StoriesPage()),
              );
            },
            child: const Text('查看全部'),
          ),
        ],
      ),
      child: _storyPreviews.isEmpty
          ? _buildEmptyState(
              title: _loadingCached ? '正在读取故事相册…' : '还没有故事相册内容',
              body: '当你从推荐或相册里生成故事后，这里会立即展示故事封面和最近更新内容。',
            )
          : SizedBox(
              height: 282,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _storyPreviews.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final item = _storyPreviews[index];
                  return _SavedStoryCard(
                    item: item,
                    onTap: () => _openStory(item.story),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState({
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FB),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }

  String _storySortLabel(_SavedStorySortMode mode) {
    switch (mode) {
      case _SavedStorySortMode.recentSaved:
        return '最近保存';
      case _SavedStorySortMode.recentUpdated:
        return '最近更新';
      case _SavedStorySortMode.mostPhotos:
        return '照片最多';
    }
  }

  Widget _buildAmbientBackground() {
    return Container(
      color: const Color(0xFFFAFAFA),
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              left: -50,
              child: Container(
                width: 300,
                height: 300,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x88FFB6C1),
                ),
              ),
            ),
            Positioned(
              top: -20,
              right: -80,
              child: Container(
                width: 250,
                height: 250,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x77E0B0FF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white.withValues(alpha: 0.86),
        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (trailing != null) ...<Widget>[trailing!],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _RecommendationPreviewCard extends StatelessWidget {
  const _RecommendationPreviewCard({
    required this.card,
    required this.onOpen,
    required this.onDismiss,
  });

  final CreateRecommendationCardData card;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 242,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: const Color(0xFFF9F6FC),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RecommendationCover(photo: card.cover),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE6F1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      card.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9D4D72),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${card.matchedCount} 张',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                card.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                      height: 1.45,
                    ),
              ),
              const Spacer(),
              Row(
                children: [
                  FilledButton(
                    onPressed: onOpen,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD17EAD),
                    ),
                    child: const Text('查看'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onDismiss,
                    child: const Text('隐藏'),
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

class _RecommendationCover extends StatelessWidget {
  const _RecommendationCover({required this.photo});

  final PhotoEntity? photo;

  @override
  Widget build(BuildContext context) {
    if (photo == null) {
      return Container(
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFE6F1), Color(0xFFF3ECFF)],
          ),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.auto_awesome,
          color: Color(0xFFD17EAD),
          size: 34,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 150,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PathImage(path: photo!.path, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.04),
                    Colors.black.withValues(alpha: 0.16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedStoryCard extends StatelessWidget {
  const _SavedStoryCard({
    required this.item,
    required this.onTap,
  });

  final _StoryPreviewItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(item.story.updatedAt);
    final subtitle =
        '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} · ${item.story.photoCount} 张';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: const Color(0xFFF9F6FC),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: item.cover == null
                    ? Container(
                        color: const Color(0xFFF1EBF7),
                        alignment: Alignment.center,
                        child: const Icon(Icons.menu_book_outlined, size: 40),
                      )
                    : PathImage(path: item.cover!.path, fit: BoxFit.cover),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.story.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryPreviewItem {
  const _StoryPreviewItem({
    required this.story,
    required this.cover,
  });

  final StoryEntity story;
  final PhotoEntity? cover;
}
