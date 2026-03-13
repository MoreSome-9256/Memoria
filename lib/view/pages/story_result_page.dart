import 'package:flutter/material.dart';

import '../../models/vo/photo.dart';
import '../../models/story.dart';
import '../../models/entity/story_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../service/photo_service.dart';
import '../../service/story_service.dart';
import '../widgets/path_image.dart';
import 'story_video_page.dart';

class StoryResultPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final Photo heroImage;
  final List<StorySection> sections;
  final int? storyEntityId; // 新增：用于保存编辑
  final bool isHorizontal;

  const StoryResultPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.heroImage,
    required this.sections,
    this.storyEntityId, // 新增
    this.isHorizontal = false,
  });

  // 新增：从 StoryEntity 加载（ConfigPage 生成后）
  factory StoryResultPage.fromStoryEntity({
    required StoryEntity storyEntity,
    required List<PhotoEntity> photos,
    bool isHorizontal = false,
  }) {
    final sectionMaps = storyEntity.parseToSections(photos);
    List<StorySection> sections = [];

    // 1. 正常提取被 AI 选中的图文段落
    if (sectionMaps.isNotEmpty) {
      sections = sectionMaps.map((map) {
        return StorySection(
          text: map['text'] as String,
          photo: map['photo'] as Photo,
        );
      }).toList();
    }

    // ========================================================
    // 🚀 核心防漏补丁：AI 漏掉的照片，我们全部强行拉回播放列表！
    // ========================================================
    final usedPhotoIds = sections.map((s) => s.photo.id).toSet();
    for (var p in photos) {
      if (!usedPhotoIds.contains(p.assetId)) {
        sections.add(
          StorySection(
            text: '', // AI没写词，我们就空着，在视频里当做“无字纯享版”画面
            photo: Photo(
              id: p.assetId,
              path: p.path,
              dateTaken: DateTime.fromMillisecondsSinceEpoch(p.timestamp),
              tags: p.aiTags ?? [],
              caption: p.aiCaption?.trim(),
              ocrSummary: (p.ocrTags != null && p.ocrTags!.isNotEmpty)
                  ? p.ocrTags!.take(3).join(' · ')
                  : p.ocrText?.trim(),
              location: p.city ?? p.province ?? '未知地点',
            ),
          ),
        );
      }
    }

    // ========================================================
    // 💡 万一上面一顿操作后发现没图，给个终极安全气囊
    // ========================================================
    if (sections.isEmpty && photos.isNotEmpty) {
      sections.add(
        StorySection(
          text: storyEntity.content ?? '我的专属回忆',
          photo: Photo(
            id: photos.first.assetId,
            path: photos.first.path,
            dateTaken: DateTime.fromMillisecondsSinceEpoch(
              photos.first.timestamp,
            ),
            tags: photos.first.aiTags ?? [],
            location: photos.first.city ?? photos.first.province ?? '未知地点',
          ),
        ),
      );
    }

    // 2. 使用第一张照片作为 hero 图
    final heroPhoto = sections.first.photo;

    return StoryResultPage(
      title: storyEntity.title,
      subtitle: storyEntity.subtitle,
      heroImage: heroPhoto,
      sections: sections,
      storyEntityId: storyEntity.id, // 关键：保存 ID
      isHorizontal: isHorizontal,
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
                    if ((section.photo.caption?.trim().isNotEmpty ?? false) ||
                        (section.photo.ocrSummary?.trim().isNotEmpty ??
                            false)) ...[
                      const SizedBox(height: 10),
                      _PhotoContextCard(photo: section.photo),
                    ],
                  ],
                ),
              );
            }, childCount: _sections.length),
          ),

          // Bottom spacing
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      // 🌟 新增：右下角极其显眼的视频生成入口
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StoryVideoPage(
                title: widget.title,
                sections: _sections, // 把排版好的图文数据传过去做视频
                isHorizontal: widget.isHorizontal,
              ),
            ),
          );
        },
        backgroundColor: const Color(0xFFD17EAD),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.play_circle_fill, size: 28),
        label: const Text(
          '播放回忆',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      // 保证悬浮按钮不会挡住底部的 AppBar
      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
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

class _PhotoContextCard extends StatelessWidget {
  const _PhotoContextCard({required this.photo});

  final Photo photo;

  @override
  Widget build(BuildContext context) {
    final caption = photo.caption?.trim();
    final ocrSummary = photo.ocrSummary?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '照片线索',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.grey[700],
            ),
          ),
          if (caption != null && caption.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PhotoContextRow(label: 'AI Caption', value: caption),
          ],
          if (ocrSummary != null && ocrSummary.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PhotoContextRow(label: 'OCR 线索', value: ocrSummary),
          ],
        ],
      ),
    );
  }
}

class _PhotoContextRow extends StatelessWidget {
  const _PhotoContextRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            height: 1.45,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }
}
