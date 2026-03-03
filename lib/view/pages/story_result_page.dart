import 'package:flutter/material.dart';

import '../../models/vo/photo.dart';
import '../../models/story.dart';
import '../../models/entity/story_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../service/photo_service.dart';
import '../../service/story_service.dart';
import '../widgets/path_image.dart';

class StoryResultPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final Photo heroImage;
  final List<StorySection> sections;
  final int? storyEntityId; // 新增：用于保存编辑

  const StoryResultPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.heroImage,
    required this.sections,
    this.storyEntityId, // 新增
  });

  // 新增：从 StoryEntity 加载（ConfigPage 生成后）
  factory StoryResultPage.fromStoryEntity({
    required StoryEntity storyEntity,
    required List<PhotoEntity> photos,
  }) {
    // 解析 Markdown 为 StorySection 列表
    final sectionMaps = storyEntity.parseToSections(photos);
    final sections = sectionMaps.map((map) {
      return StorySection(
        text: map['text'] as String,
        photo: map['photo'] as Photo,
      );
    }).toList();

    // 使用第一张照片作为 hero 图
    final heroPhoto = photos.isNotEmpty
        ? Photo(
            id: photos.first.assetId,
            path: photos.first.path,
            dateTaken: DateTime.fromMillisecondsSinceEpoch(
              photos.first.timestamp,
            ),
            tags: photos.first.aiTags ?? [],
            location: photos.first.city ?? photos.first.province,
          )
        : (sectionMaps.isNotEmpty
              ? sectionMaps.first['photo'] as Photo
              : throw Exception('No photos'));

    return StoryResultPage(
      title: storyEntity.title,
      subtitle: storyEntity.subtitle,
      heroImage: heroPhoto,
      sections: sections,
      storyEntityId: storyEntity.id, // 关键：保存 ID
    );
  }

  // 保留：从已保存的 Story 加载（Stories list -> Result）
  factory StoryResultPage.fromStory(Story story) {
    return StoryResultPage(
      title: story.title,
      subtitle: story.subtitle,
      heroImage: story.heroImage,
      sections: story.blocks
          .where((block) => block.photo != null)
          .map((block) => StorySection(text: block.text, photo: block.photo!))
          .toList(),
    );
  }

  @override
  State<StoryResultPage> createState() => _StoryResultPageState();
}

class _StoryResultPageState extends State<StoryResultPage> {
  late List<StorySection> _sections;
  bool _isSaving = false;
  bool _hasSaved = false;

  @override
  void initState() {
    super.initState();
    _sections = List.from(widget.sections);
  }

  void _editText(int index) {
    final controller = TextEditingController(text: _sections[index].text);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('编辑文字'),
          content: TextField(
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _sections[index] = StorySection(
                    text: controller.text,
                    photo: _sections[index].photo,
                  );
                });
                Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveStory() async {
    if (_isSaving) {
      return;
    }

    if (widget.storyEntityId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法保存：缺少故事ID')));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // 1. 加载原始 StoryEntity
      final isar = PhotoService().isar;
      final story = await isar.collection<StoryEntity>().get(
        widget.storyEntityId!,
      );

      if (story == null) {
        throw Exception('Story not found');
      }

      // 2. 将编辑后的 sections 转回 Markdown
      final sectionMaps = _sections.map((section) {
        return {'text': section.text, 'photo': section.photo};
      }).toList();

      final updatedContent = StoryEntity.sectionsToMarkdown(sectionMaps);

      // 3. 更新 content
      story.content = updatedContent;

      // 4. 保存到数据库
      await StoryService().updateStory(story);

      if (!mounted) {
        return;
      }

      setState(() {
        _hasSaved = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('故事已保存，可在故事页回查')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _closePage() {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context, _hasSaved);
      return;
    }

    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void _shareStory() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('分享功能开发中')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero image with title
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 3,
                      color: Colors.black45,
                    ),
                  ],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PathImage(path: widget.heroImage.path, fit: BoxFit.cover),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Subtitle
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.subtitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Story sections
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final section = _sections[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Text block
                    GestureDetector(
                      onTap: () => _editText(index),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                section.text,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.copyWith(height: 1.6),
                              ),
                            ),
                            Icon(Icons.edit, size: 16, color: Colors.grey[400]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Photo
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PathImage(
                        path: section.photo.path,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ),
              );
            }, childCount: _sections.length),
          ),

          // Bottom spacing
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              onPressed: _closePage,
              icon: const Icon(Icons.close),
              label: const Text('关闭'),
            ),
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveStory,
              icon: const Icon(Icons.save),
              label: Text(_isSaving ? '保存中...' : '保存'),
            ),
            TextButton.icon(
              onPressed: _shareStory,
              icon: const Icon(Icons.share),
              label: const Text('分享'),
            ),
          ],
        ),
      ),
    );
  }
}

class StorySection {
  final String text;
  final Photo photo;

  StorySection({required this.text, required this.photo});
}
