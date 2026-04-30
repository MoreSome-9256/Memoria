import 'package:flutter/material.dart';

import '../../models/entity/story_entity.dart';
import '../../service/story_service.dart';
import 'story_result_page.dart';

class StoriesPage extends StatefulWidget {
  const StoriesPage({super.key});

  @override
  State<StoriesPage> createState() => _StoriesPageState();
}

class _StoriesPageState extends State<StoriesPage> {
  final StoryService _storyService = StoryService();

  late Future<List<StoryEntity>> _storiesFuture;
  final Set<int> _selectedStoryIds = <int>{};

  bool _selectionMode = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _storiesFuture = _loadStories();
  }

  Future<List<StoryEntity>> _loadStories() {
    return _storyService.getAllStories();
  }

  Future<void> _reload() async {
    if (_isDeleting) {
      return;
    }
    setState(() {
      _selectionMode = false;
      _selectedStoryIds.clear();
      _storiesFuture = _loadStories();
    });
  }

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedStoryIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedStoryIds.clear();
    });
  }

  void _toggleStorySelection(int storyId, bool selected) {
    setState(() {
      if (selected) {
        _selectedStoryIds.add(storyId);
      } else {
        _selectedStoryIds.remove(storyId);
      }
    });
  }

  Future<void> _deleteSelectedStories() async {
    if (_selectedStoryIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择要删除的故事。')));
      return;
    }

    final selectedIds = _selectedStoryIds.toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除故事'),
        content: Text(
          '确定要删除选中的 ${selectedIds.length} 个故事吗？\n这会同时删除对应的故事相册缓存，删除后无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    try {
      final deletedCount = await _storyService.deleteStories(selectedIds);
      if (!mounted) {
        return;
      }
      setState(() {
        _isDeleting = false;
        _selectionMode = false;
        _selectedStoryIds.clear();
        _storiesFuture = _loadStories();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 $deletedCount 个故事。')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isDeleting = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  Future<void> _openStory(StoryEntity story) async {
    final photos = await _storyService.loadPhotos(story.photoIds);
    if (!mounted) {
      return;
    }

    if (photos.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这个故事缺少可用照片，暂时无法打开。')));
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

    if (!mounted) {
      return;
    }
    await _reload();
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
    final selectedCount = _selectedStoryIds.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode ? '已选择 $selectedCount 个故事' : '故事相册'),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _isDeleting ? null : _reload,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新故事列表',
          ),
          if (_selectionMode) ...[
            IconButton(
              onPressed: _isDeleting ? null : _deleteSelectedStories,
              icon: const Icon(Icons.delete),
              tooltip: '删除选中的故事',
            ),
            IconButton(
              onPressed: _isDeleting ? null : _exitSelectionMode,
              icon: const Icon(Icons.close),
              tooltip: '取消选择',
            ),
          ] else
            IconButton(
              onPressed: _enterSelectionMode,
              icon: const Icon(Icons.delete_outline),
              tooltip: '选择故事并删除',
            ),
        ],
      ),
      body: FutureBuilder<List<StoryEntity>>(
        future: _storiesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 12),
                  Text('加载故事失败: ${snapshot.error}'),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            );
          }

          final stories = snapshot.data ?? const <StoryEntity>[];
          if (stories.isEmpty) {
            return const Center(child: Text('暂无故事，先去相册生成一篇吧'));
          }

          return Column(
            children: [
              if (_selectionMode)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F1FB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _isDeleting
                        ? '正在删除所选故事…'
                        : '已进入删除模式，请勾选要删除的故事后点击右上角删除图标。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: stories.length,
                  itemBuilder: (context, index) {
                    final story = stories[index];
                    final selected = _selectedStoryIds.contains(story.id);
                    final date = DateTime.fromMillisecondsSinceEpoch(
                      story.updatedAt,
                    );
                    final dateText =
                        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _isDeleting
                            ? null
                            : _selectionMode
                                ? () => _toggleStorySelection(
                                      story.id,
                                      !selected,
                                    )
                                : () => _openStory(story),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_selectionMode)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 4,
                                    right: 10,
                                  ),
                                  child: Checkbox(
                                    value: selected,
                                    onChanged: _isDeleting
                                        ? null
                                        : (value) => _toggleStorySelection(
                                              story.id,
                                              value ?? false,
                                            ),
                                  ),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      story.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      story.subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Colors.grey.shade700,
                                            height: 1.45,
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _StoryMetaChip(
                                          icon: Icons.schedule_outlined,
                                          label: dateText,
                                        ),
                                        _StoryMetaChip(
                                          icon: Icons.photo_library_outlined,
                                          label: '${story.photoCount} 张照片',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (!_selectionMode)
                                const Padding(
                                  padding: EdgeInsets.only(left: 10, top: 6),
                                  child: Icon(Icons.chevron_right),
                                ),
                            ],
                          ),
                        ),
                      ),
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

class _StoryMetaChip extends StatelessWidget {
  const _StoryMetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    const chipBackground = Color(0xFFF7EDEE);
    const chipForeground = Color(0xFF8D6E73);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipForeground),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: chipForeground,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
