/// 主题聚类页面，展示按语义主题组织的照片分组。

import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../models/entity/photo_entity.dart';
import '../../models/theme_cluster_models.dart';
import '../../service/theme_cluster_service.dart';
import '../../utils/media_type_helper.dart';
import '../widgets/deferred_path_image.dart';
import 'stories_page.dart';

class ThemeClustersPage extends StatefulWidget {
  const ThemeClustersPage({super.key});

  @override
  State<ThemeClustersPage> createState() => _ThemeClustersPageState();
}

class _ThemeClustersPageState extends State<ThemeClustersPage> {
  late Future<List<ThemeCluster>> _clustersFuture;
  bool _pureEmbeddingOnly = false;
  bool _deferredUiReady = false;
  static const int _themePageMaxNewEmbeddingsPerRun = 0;

  static const Map<String, IconData> _themeIcons = <String, IconData>{
    'people': Icons.people_alt_outlined,
    'food': Icons.restaurant_outlined,
    'books': Icons.menu_book_outlined,
    'cars': Icons.directions_car_outlined,
    'scenery': Icons.landscape_outlined,
    'pets': Icons.pets_outlined,
  };

  static const Map<String, Color> _themeColors = <String, Color>{
    'people': Color(0xFFE67E22),
    'food': Color(0xFFD35454),
    'books': Color(0xFF4F7CAC),
    'cars': Color(0xFF5B8C5A),
    'scenery': Color(0xFF3C8DAD),
    'pets': Color(0xFF9B59B6),
  };

  @override
  void initState() {
    super.initState();
    _clustersFuture = _loadClustersForCurrentMode();
    _scheduleDeferredUiReveal();
  }

  Future<List<ThemeCluster>> _loadClustersForCurrentMode() {
    return ThemeClusterService().loadClusters(
      pureEmbeddingOnly: _pureEmbeddingOnly,
      maxNewEmbeddingsPerRun: _themePageMaxNewEmbeddingsPerRun,
    );
  }

  void _scheduleDeferredUiReveal() {
    _deferredUiReady = false;
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _deferredUiReady = true;
      });
    });
  }

  Future<void> _reload() async {
    setState(() {
      _clustersFuture = _loadClustersForCurrentMode();
    });
    _scheduleDeferredUiReveal();
  }

  void _toggleClusteringMode() {
    setState(() {
      _pureEmbeddingOnly = !_pureEmbeddingOnly;
      _clustersFuture = _loadClustersForCurrentMode();
    });
    _scheduleDeferredUiReveal();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          _pureEmbeddingOnly
              ? '已切换为纯 embedding 模式（仅 512 维向量）'
              : '已切换为混合模式（向量 + 规则）',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('主题聚类'),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _toggleClusteringMode,
            icon: Icon(
              _pureEmbeddingOnly
                  ? Icons.scatter_plot_outlined
                  : Icons.tune_outlined,
            ),
            tooltip: _pureEmbeddingOnly
                ? '当前：纯 embedding（点击切回混合）'
                : '当前：混合模式（点击切到纯 embedding）',
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新主题聚类',
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => StoriesPage()),
              );
            },
            icon: const Icon(Icons.auto_stories_outlined),
            tooltip: '查看故事列表',
          ),
        ],
      ),
      body: FutureBuilder<List<ThemeCluster>>(
              future: _clustersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ValueListenableBuilder<ThemeClusteringProgress>(
                    valueListenable: ThemeClusterService().progressListenable,
                    builder: (context, progress, _) {
                      final isDeterminate = progress.total > 0;
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                value: isDeterminate ? progress.ratio : null,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                progress.message ?? '正在计算主题聚类...',
                                textAlign: TextAlign.center,
                              ),
                              if (progress.stage ==
                                  ThemeClusteringStage.preparingEmbeddings)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '复用向量 ${progress.cachedEmbeddings} · 新算 ${progress.newEmbeddings}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 56,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(height: 12),
                          Text('主题聚类加载失败: ${snapshot.error}'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _reload,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final clusters = snapshot.data ?? const <ThemeCluster>[];
                if (!_deferredUiReady) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (clusters.isEmpty) {
                  return const _EmptyThemeView();
                }

                return RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: clusters.length + 1,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return const _IntroCard();
                      }

                      final cluster = clusters[index - 1];
                      final color =
                          _themeColors[cluster.definition.id] ??
                          Theme.of(context).colorScheme.primary;
                      final icon =
                          _themeIcons[cluster.definition.id] ??
                          Icons.category_outlined;

                      return _ThemeClusterCard(
                        cluster: cluster,
                        color: color,
                        icon: icon,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ThemeClusterDetailPage(
                                cluster: cluster,
                                color: color,
                                icon: icon,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class ThemeClusterDetailPage extends StatelessWidget {
  const ThemeClusterDetailPage({
    super.key,
    required this.cluster,
    required this.color,
    required this.icon,
  });

  final ThemeCluster cluster;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _ThemeClusterDetailBody(cluster: cluster, color: color, icon: icon);
  }
}

class _ThemeClusterDetailBody extends StatefulWidget {
  const _ThemeClusterDetailBody({
    required this.cluster,
    required this.color,
    required this.icon,
  });

  final ThemeCluster cluster;
  final Color color;
  final IconData icon;

  @override
  State<_ThemeClusterDetailBody> createState() =>
      _ThemeClusterDetailBodyState();
}

class _ThemeClusterDetailBodyState extends State<_ThemeClusterDetailBody> {
  late String _selectedSubclusterId;
  bool _deferredBodyReady = false;
  Timer? _deferTimer;

  @override
  void initState() {
    super.initState();
    _selectedSubclusterId = widget.cluster.primarySubcluster.id;
    _deferTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _deferredBodyReady = true;
      });
    });
  }

  @override
  void dispose() {
    _deferTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_deferredBodyReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedSubcluster = widget.cluster.subclusters.firstWhere(
      (item) => item.id == _selectedSubclusterId,
      orElse: () => widget.cluster.primarySubcluster,
    );
    final compactDisplayPreferred =
        selectedSubcluster.cohesion?.levelLabel == '精选';

    return Scaffold(
      appBar: AppBar(title: Text(widget.cluster.definition.title)),
      body: CustomScrollView(
        cacheExtent: 700,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(widget.icon, color: widget.color),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.cluster.definition.title,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(widget.cluster.definition.subtitle),
                            const SizedBox(height: 6),
                            Text(
                              '共 ${widget.cluster.totalPhotos} 张 · ${widget.cluster.subclusters.length} 个子簇 · 按月份串联',
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.cluster.subclusters.length > 1) ...[
                  const SizedBox(height: 16),
                  Text(
                    '子簇切换',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: widget.cluster.subclusters
                          .map((subcluster) {
                            final isSelected =
                                subcluster.id == selectedSubcluster.id;
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _SubclusterSelectorCard(
                                subcluster: subcluster,
                                color: widget.color,
                                isSelected: isSelected,
                                onTap: () {
                                  setState(() {
                                    _selectedSubclusterId = subcluster.id;
                                  });
                                },
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _SubclusterSummaryCard(
                  subcluster: selectedSubcluster,
                  color: widget.color,
                ),
                const SizedBox(height: 10),
                _ClusterPresentationHint(
                  compactDisplayPreferred: compactDisplayPreferred,
                  cohesion: selectedSubcluster.cohesion,
                  color: widget.color,
                ),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            sliver: SliverList.builder(
              itemCount: selectedSubcluster.groups.length,
              itemBuilder: (context, index) {
                final group = selectedSubcluster.groups[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _TimelineGroupSection(
                    group: group,
                    compactDisplayPreferred: compactDisplayPreferred,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SubclusterSummaryCard extends StatelessWidget {
  const _SubclusterSummaryCard({required this.subcluster, required this.color});

  final ThemeSubcluster subcluster;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cohesion = subcluster.cohesion;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subcluster.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subcluster.subtitle,
            style: TextStyle(color: Colors.grey[700], height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            '${subcluster.totalPhotos} 张 · ${subcluster.groups.length} 个时间段',
            style: TextStyle(color: Colors.grey[600]),
          ),
          if (cohesion != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CohesionBadge(cohesion: cohesion, color: color),
                Text(
                  cohesion.detailLabel,
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            subcluster.algorithm.currentLabel,
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
          Text(
            subcluster.algorithm.nextLabel,
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          if (subcluster.coverPhotos.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: Row(
                children: subcluster.coverPhotos
                    .take(4)
                    .map((photo) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: DeferredPathImage(
                                path: photo.path,
                                assetId: photo.assetId,
                                kind: MediaTypeHelper.fromStorageValue(
                                  photo.mediaKind,
                                  path: photo.path,
                                ),
                                thumbnailBytes: photo.thumbnailBytes,
                                fit: BoxFit.cover,
                              ),
                            ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubclusterSelectorCard extends StatelessWidget {
  const _SubclusterSelectorCard({
    required this.subcluster,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final ThemeSubcluster subcluster;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cohesion = subcluster.cohesion;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 168,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.10) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.45)
                : Colors.grey.withValues(alpha: 0.18),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subcluster.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${subcluster.totalPhotos} 张',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
            if (cohesion != null) ...[
              const SizedBox(height: 6),
              _CohesionBadge(cohesion: cohesion, color: color, compact: true),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: 54,
              child: Row(
                children: subcluster.coverPhotos
                    .take(3)
                    .map((photo) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: DeferredPathImage(
                                path: photo.path,
                                assetId: photo.assetId,
                                kind: MediaTypeHelper.fromStorageValue(
                                  photo.mediaKind,
                                  path: photo.path,
                                ),
                                thumbnailBytes: photo.thumbnailBytes,
                                fit: BoxFit.cover,
                              ),
                            ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CohesionBadge extends StatelessWidget {
  const _CohesionBadge({
    required this.cohesion,
    required this.color,
    this.compact = false,
  });

  final ThemeSubclusterCohesion cohesion;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        compact ? cohesion.levelLabel : cohesion.summaryLabel,
        style: TextStyle(
          color: color,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}

class _ThemeClusterCard extends StatelessWidget {
  const _ThemeClusterCard({
    required this.cluster,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final ThemeCluster cluster;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cluster.definition.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cluster.subclusters.length > 1
                              ? '${cluster.totalPhotos} 张 · ${cluster.subclusters.length} 个子簇 · ${cluster.totalTimelineGroups} 个时间段'
                              : '${cluster.totalPhotos} 张 · ${cluster.totalTimelineGroups} 个时间段',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                cluster.definition.subtitle,
                style: TextStyle(color: Colors.grey[800]),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 88,
                child: Row(
                  children: cluster.coverPhotos
                      .take(4)
                      .map((photo) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: DeferredPathImage(
                                  path: photo.path,
                                  assetId: photo.assetId,
                                  kind: MediaTypeHelper.fromStorageValue(
                                    photo.mediaKind,
                                    path: photo.path,
                                  ),
                                  thumbnailBytes: photo.thumbnailBytes,
                                  fit: BoxFit.cover,
                                ),
                              ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClusterPresentationHint extends StatelessWidget {
  const _ClusterPresentationHint({
    required this.compactDisplayPreferred,
    required this.cohesion,
    required this.color,
  });

  final bool compactDisplayPreferred;
  final ThemeSubclusterCohesion? cohesion;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final title = compactDisplayPreferred ? '当前按精选模式折叠展示' : '当前按平铺模式展示';
    final subtitle = compactDisplayPreferred
        ? '这类照片大概率是连拍或同机位微变化，优先收紧成胶片条，避免满屏重复。'
        : '这类照片虽然属于同一主题，但内部跨度更大，保留平铺更能体现内容丰富度。';
    final resolvedCohesion = cohesion;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            compactDisplayPreferred
                ? Icons.view_carousel_outlined
                : Icons.grid_view_outlined,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey[700], height: 1.4),
                ),
                if (resolvedCohesion != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '基于簇内均值距离 ${resolvedCohesion.meanDistance.toStringAsFixed(3)} 自动判断。',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineGroupSection extends StatelessWidget {
  const _TimelineGroupSection({
    required this.group,
    required this.compactDisplayPreferred,
  });

  static const int _maxGridPhotosPerGroup = 36;

  final ThemeTimelineGroup group;
  final bool compactDisplayPreferred;

  @override
  Widget build(BuildContext context) {
    final visibleGridPhotos = compactDisplayPreferred
        ? group.photos
        : group.photos.take(_maxGridPhotosPerGroup).toList(growable: false);
    final hiddenCount = compactDisplayPreferred
        ? 0
        : group.totalPhotos - visibleGridPhotos.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              group.title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text(
              '${group.totalPhotos} 张',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (compactDisplayPreferred)
          _CompactTimelineStrip(group: group)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                cacheExtent: 500,
                itemCount: visibleGridPhotos.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final photo = visibleGridPhotos[index];
                  return _ThemePhotoTile(photo: photo);
                },
              ),
              if (hiddenCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '该时间段还有 $hiddenCount 张图片，已折叠以保证流畅度',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _CompactTimelineStrip extends StatelessWidget {
  const _CompactTimelineStrip({required this.group});

  final ThemeTimelineGroup group;

  @override
  Widget build(BuildContext context) {
    final visiblePhotos = group.photos.take(8).toList(growable: false);
    final hiddenCount = group.totalPhotos - visiblePhotos.length;

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visiblePhotos.length + (hiddenCount > 0 ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index >= visiblePhotos.length) {
            return _HiddenCountTile(hiddenCount: hiddenCount);
          }

          return SizedBox(
            width: 88,
            child: _ThemePhotoTile(photo: visiblePhotos[index]),
          );
        },
      ),
    );
  }
}

class _HiddenCountTile extends StatelessWidget {
  const _HiddenCountTile({required this.hiddenCount});

  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          '+$hiddenCount',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.grey[700],
          ),
        ),
      ),
    );
  }
}

class _ThemePhotoTile extends StatelessWidget {
  const _ThemePhotoTile({required this.photo});

  final PhotoEntity photo;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
    final tagText = (photo.aiTags ?? const <String>[]).take(2).join(' · ');

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DeferredPathImage(
              path: photo.path,
              assetId: photo.assetId,
              kind: MediaTypeHelper.fromStorageValue(
                photo.mediaKind,
                path: photo.path,
              ),
              thumbnailBytes: photo.thumbnailBytes,
              fit: BoxFit.cover,
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${date.month}.${date.day}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (tagText.isNotEmpty)
                      Text(
                        tagText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
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

class _EmptyThemeView extends StatelessWidget {
  const _EmptyThemeView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text('暂时还没有足够的主题聚类结果'),
            const SizedBox(height: 8),
            Text(
              '先去相册页刷新并完成一轮 AI 打标，人物、食物、书、车这些主题就会慢慢长出来。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
