import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../models/vo/photo.dart';
import '../../models/story.dart';
import '../../models/entity/story_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../service/photo_service.dart';
import '../../service/story_service.dart';
import '../../utils/ocr_policy.dart';
import '../widgets/path_image.dart';
import 'story_video_page.dart';

class StoryResultPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final Photo heroImage;
  final List<StorySection> sections;
  final int? storyEntityId;
  final String? customMusicPath;
  final Map<String, dynamic>? dynamicBeatData;
  final bool isHorizontal;
  final String targetPlatform;

  const StoryResultPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.heroImage,
    required this.sections,
    this.storyEntityId,
    this.customMusicPath,
    this.dynamicBeatData,
    required this.isHorizontal,
    required this.targetPlatform,
  });

  factory StoryResultPage.fromStoryEntity({
    required StoryEntity storyEntity,
    required List<PhotoEntity> photos,
    String? customMusicPath,
    Map<String, dynamic>? dynamicBeatData,
    List<String>? captions,
    required bool isHorizontal,
    required String targetPlatform,
  }) {
    final Map<String, String> captionMap = {};
    if (captions != null && captions.isNotEmpty) {
      for (int i = 0; i < photos.length; i++) {
        if (i < captions.length) {
          captionMap[photos[i].assetId] = captions[i];
        }
      }
    }

    final sectionMaps = storyEntity.parseToSections(photos);
    List<StorySection> sections = [];

    if (sectionMaps.isNotEmpty) {
      sections = sectionMaps.map((map) {
        final photo = map['photo'] as Photo;
        final String sectionText =
            (captionMap.containsKey(photo.id) &&
                captionMap[photo.id]!.isNotEmpty)
            ? captionMap[photo.id]!
            : map['text'] as String;

        return StorySection(text: sectionText, photo: photo);
      }).toList();
    }

    final usedPhotoIds = sections.map((s) => s.photo.id).toSet();
    for (var p in photos) {
      if (!usedPhotoIds.contains(p.assetId)) {
        sections.add(
          StorySection(
            text: captionMap[p.assetId] ?? '',
            photo: Photo(
              id: p.assetId,
              path: p.path,
              dateTaken: DateTime.fromMillisecondsSinceEpoch(p.timestamp),
              tags: p.aiTags ?? [],
              caption: p.aiCaption?.trim(),
              ocrSummary: OcrPolicy.effectiveSummary(
                tags: p.ocrTags ?? const <String>[],
                text: p.ocrText,
              ),
              location: p.city ?? p.province ?? '未知地点',
            ),
          ),
        );
      }
    }

    if (sections.isEmpty && photos.isNotEmpty) {
      sections.add(
        StorySection(
          text: (captions != null && captions.isNotEmpty)
              ? captions.first
              : (storyEntity.content ?? '我的专属回忆'),
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

    // 🌟 这里已经去掉了那个会导致页面图片消失的假片头数据！页面恢复纯净！

    final heroPhoto = sections.first.photo;

    return StoryResultPage(
      title: storyEntity.title,
      subtitle: storyEntity.subtitle,
      heroImage: heroPhoto,
      sections: sections,
      storyEntityId: storyEntity.id,
      customMusicPath: customMusicPath,
      dynamicBeatData: dynamicBeatData,
      isHorizontal: isHorizontal,
      targetPlatform: targetPlatform,
    );
  }

  factory StoryResultPage.fromStory(Story story) {
    return StoryResultPage(
      title: story.title,
      subtitle: story.subtitle,
      heroImage: story.heroImage,
      sections: story.blocks
          .where((block) => block.photo != null)
          .map((block) => StorySection(text: block.text, photo: block.photo!))
          .toList(),
      isHorizontal: story.isHorizontal,
      targetPlatform: '小红书',
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
    if (_isSaving) return;
    if (widget.storyEntityId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法保存：缺少故事ID')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final isar = PhotoService().isar;
      final story = await isar.collection<StoryEntity>().get(
        widget.storyEntityId!,
      );
      if (story == null) throw Exception('Story not found');

      final sectionMaps = _sections.map((section) {
        return {'text': section.text, 'photo': section.photo};
      }).toList();

      final updatedContent = StoryEntity.sectionsToMarkdown(sectionMaps);
      story.content = updatedContent;
      await StoryService().updateStory(story);

      if (!mounted) return;
      setState(() => _hasSaved = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('故事已保存，可在故事页回查')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      // ==========================================
      // 🚀 核心修复：把片头逻辑转移到了“播放”按钮里，且不污染原数据！
      // ==========================================
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          List<StorySection> finalVideoSections = [];
          if (_sections.isNotEmpty) {
            final random = math.Random();
            final introPhoto =
                _sections[random.nextInt(_sections.length)].photo;

            final introSection = StorySection(
              text: '__INTRO__',
              photo: introPhoto,
            );
            // 在传给视频引擎前，临时拼装片头
            finalVideoSections = [introSection, ..._sections];
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StoryVideoPage(
                title: widget.title,
                subtitle: widget.subtitle,
                sections: finalVideoSections, // 👈 把带有片头的数据安全地传过去
                customMusicPath: widget.customMusicPath,
                isHorizontal: widget.isHorizontal,
                dynamicBeatData: widget.dynamicBeatData,
                targetPlatform: widget.targetPlatform,
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
