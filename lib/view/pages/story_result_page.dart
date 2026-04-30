import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/entity/photo_entity.dart';
import '../../models/entity/story_entity.dart';
import '../../models/story.dart';
import '../../models/vo/photo.dart';
import '../../models/vo/story_section.dart';
import '../../service/photo_service.dart';
import '../../service/story_service.dart';
import '../../utils/ocr_policy.dart';
import '../widgets/path_image.dart';
import 'digital_album_book_page.dart';
import 'story_video_page.dart';
import '../../objectbox.g.dart';
import '../../storage/objectbox/objectbox_service.dart';

class StoryResultPage extends StatefulWidget {
  const StoryResultPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.heroImage,
    required this.sections,
    this.storyTemplateId,
    this.videoCaptionByPhotoId = const <String, String>{},
    this.storyEntityId,
    this.customMusicPath,
    this.dynamicBeatData,
    required this.isHorizontal,
    required this.targetPlatform,
    this.videoCaptions,
  });

  final String title;
  final String subtitle;
  final Photo heroImage;
  final List<StorySection> sections;
  final String? storyTemplateId;
  final Map<String, String> videoCaptionByPhotoId;
  final int? storyEntityId;
  final String? customMusicPath;
  final Map<String, dynamic>? dynamicBeatData;
  final bool isHorizontal;
  final String targetPlatform;
  final List<String>? videoCaptions;

  factory StoryResultPage.fromStoryEntity({
    required StoryEntity storyEntity,
    required List<PhotoEntity> photos,
    String? storyTemplateId,
    String? customMusicPath,
    Map<String, dynamic>? dynamicBeatData,
    List<String>? videoCaptions,
    List<Photo>? photoOverrides,
    required bool isHorizontal,
    required String targetPlatform,
  }) {
    final videoCaptionMap = <String, String>{};
    if (videoCaptions != null && videoCaptions.isNotEmpty) {
      for (var i = 0; i < photos.length && i < videoCaptions.length; i++) {
        final caption = videoCaptions[i].trim();
        if (caption.isNotEmpty) {
          videoCaptionMap[photos[i].assetId] = caption;
        }
      }
    }

    final photoOverrideMap = <String, Photo>{
      for (final photo in photoOverrides ?? const <Photo>[]) photo.id: photo,
    };
    final photoEntityById = <String, PhotoEntity>{
      for (final photo in photos) photo.assetId: photo,
    };

    final sections = <StorySection>[];
    final sectionMaps = storyEntity.parseToSections(photos);
    for (final map in sectionMaps) {
      final basePhoto = map['photo'] as Photo;
      final mergedPhoto = _mergePhotoOverride(
        _mergePhotoEntityData(basePhoto, photoEntityById[basePhoto.id]),
        photoOverrideMap[basePhoto.id],
      );
      final text = map['text'] as String? ?? '';
      sections.add(StorySection(text: text, photo: mergedPhoto));
    }

    final usedPhotoIds = sections.map((item) => item.photo.id).toSet();
    for (final photoEntity in photos) {
      if (usedPhotoIds.contains(photoEntity.assetId)) {
        continue;
      }
      sections.add(
        StorySection(
          text: '',
          photo: _mergePhotoOverride(
            _buildPhotoFromEntity(photoEntity),
            photoOverrideMap[photoEntity.assetId],
          ),
        ),
      );
    }

    if (sections.isEmpty && photos.isNotEmpty) {
      final photoEntity = photos.first;
      sections.add(
        StorySection(
          text: storyEntity.content.trim().isEmpty ? '我的专属回忆' : storyEntity.content,
          photo: _mergePhotoOverride(
            _buildPhotoFromEntity(photoEntity),
            photoOverrideMap[photoEntity.assetId],
          ),
        ),
      );
    }

    final heroPhoto = sections.isNotEmpty
        ? sections.first.photo
        : _mergePhotoOverride(
            _buildPhotoFromEntity(photos.first),
            photoOverrideMap[photos.first.assetId],
          );

    return StoryResultPage(
      title: storyEntity.title,
      subtitle: storyEntity.subtitle,
      heroImage: heroPhoto,
      sections: sections,
      storyTemplateId: storyTemplateId,
      videoCaptionByPhotoId: Map<String, String>.unmodifiable(videoCaptionMap),
      storyEntityId: storyEntity.id,
      customMusicPath: customMusicPath,
      dynamicBeatData: dynamicBeatData,
      isHorizontal: isHorizontal,
      targetPlatform: targetPlatform,
      videoCaptions: videoCaptions,
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
          .toList(growable: false),
      storyTemplateId: null,
      isHorizontal: story.isHorizontal,
      targetPlatform: '小红书',
    );
  }

  static Photo _buildPhotoFromEntity(PhotoEntity photoEntity) {
    return Photo(
      id: photoEntity.assetId,
      location:
          photoEntity.locationName ??
          photoEntity.district ??
          photoEntity.city ??
          photoEntity.province ??
          '未知地点',
      path: photoEntity.path,
      dateTaken: DateTime.fromMillisecondsSinceEpoch(photoEntity.timestamp),
      tags: photoEntity.aiTags ?? const <String>[],
      caption: photoEntity.aiCaption?.trim(),
      ocrSummary: OcrPolicy.effectiveSummary(
        tags: photoEntity.ocrTags ?? const <String>[],
        text: photoEntity.ocrText,
      ),
      ocrTags: OcrPolicy.effectiveTags(photoEntity.ocrTags ?? const <String>[]),
      width: photoEntity.width,
      height: photoEntity.height,
    );
  }

  static Photo _mergePhotoEntityData(Photo basePhoto, PhotoEntity? photoEntity) {
    if (photoEntity == null) {
      return basePhoto;
    }

    final entityPhoto = _buildPhotoFromEntity(photoEntity);
    return entityPhoto.copyWith(
      caption: (basePhoto.caption?.trim().isNotEmpty ?? false)
          ? basePhoto.caption
          : entityPhoto.caption,
      vlmCaption: (basePhoto.vlmCaption?.trim().isNotEmpty ?? false)
          ? basePhoto.vlmCaption
          : entityPhoto.vlmCaption,
      location: (basePhoto.location?.trim().isNotEmpty ?? false)
          ? basePhoto.location
          : entityPhoto.location,
      tags: basePhoto.tags.isNotEmpty ? basePhoto.tags : entityPhoto.tags,
      ocrSummary: (basePhoto.ocrSummary?.trim().isNotEmpty ?? false)
          ? basePhoto.ocrSummary
          : entityPhoto.ocrSummary,
      ocrTags: basePhoto.ocrTags.isNotEmpty ? basePhoto.ocrTags : entityPhoto.ocrTags,
      width: basePhoto.width > 0 ? basePhoto.width : entityPhoto.width,
      height: basePhoto.height > 0 ? basePhoto.height : entityPhoto.height,
      faces: basePhoto.faces ?? entityPhoto.faces,
    );
  }

  static Photo _mergePhotoOverride(Photo basePhoto, Photo? overridePhoto) {
    if (overridePhoto == null) {
      return basePhoto;
    }

    final overrideCaption = overridePhoto.caption?.trim();
    final overrideLocation = overridePhoto.location?.trim();
    final overrideVlmCaption = overridePhoto.vlmCaption?.trim();

    return basePhoto.copyWith(
      path: overridePhoto.path.trim().isNotEmpty ? overridePhoto.path : basePhoto.path,
      location: (overrideLocation?.isNotEmpty ?? false)
          ? overridePhoto.location
          : basePhoto.location,
      caption: (overrideCaption?.isNotEmpty ?? false)
          ? overrideCaption
          : basePhoto.caption,
      vlmCaption: (overrideVlmCaption?.isNotEmpty ?? false)
          ? overrideVlmCaption
          : basePhoto.vlmCaption,
      tags: overridePhoto.tags.isNotEmpty ? overridePhoto.tags : basePhoto.tags,
      ocrSummary: (overridePhoto.ocrSummary?.trim().isNotEmpty ?? false)
          ? overridePhoto.ocrSummary
          : basePhoto.ocrSummary,
      ocrTags: overridePhoto.ocrTags.isNotEmpty ? overridePhoto.ocrTags : basePhoto.ocrTags,
      width: overridePhoto.width > 0 ? overridePhoto.width : basePhoto.width,
      height: overridePhoto.height > 0 ? overridePhoto.height : basePhoto.height,
      faces: overridePhoto.faces ?? basePhoto.faces,
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
    _sections = List<StorySection>.from(widget.sections);
  }

  void _editText(int index) {
    final controller = TextEditingController(text: _sections[index].text);

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('编辑文字'),
          content: TextField(
            controller: controller,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _sections[index] = _sections[index].copyWith(
                    text: controller.text.trim(),
                  );
                });
                Navigator.of(context).pop();
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
      ).showSnackBar(const SnackBar(content: Text('无法保存：缺少故事 ID')));
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final story = ObjectBoxService().store.box<StoryEntity>().get(widget.storyEntityId!);
      if (story == null) {
        throw StateError('Story not found');
      }

      final sectionMaps = _sections
          .map((section) => <String, dynamic>{
                'text': section.text,
                'photo': section.photo,
              })
          .toList(growable: false);

      story.content = StoryEntity.sectionsToMarkdown(sectionMaps);
      story.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await StoryService().updateStory(story);

      if (!mounted) {
        return;
      }

      setState(() {
        _hasSaved = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('故事已保存，可在故事页重新查看')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $error')));
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
      Navigator.of(context).pop(_hasSaved);
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _shareStory() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('分享功能开发中')));
  }

  Future<void> _openDigitalAlbum() async {
    final result = await Navigator.of(context).push<DigitalAlbumBookResult>(
      MaterialPageRoute<DigitalAlbumBookResult>(
        builder: (context) => DigitalAlbumBookPage(
          title: widget.title,
          subtitle: widget.subtitle,
          sections: _sections,
          storyTemplateId: widget.storyTemplateId,
          storyEntityId: widget.storyEntityId,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _hasSaved = _hasSaved || result.saved;
    });
  }

  void _openVideoPreview() {
    if (_sections.isEmpty) {
      return;
    }

    final playbackSections = <StorySection>[];
    for (var index = 0; index < _sections.length; index++) {
      final section = _sections[index];
      final indexedCaption = widget.videoCaptions != null &&
              index < widget.videoCaptions!.length
          ? widget.videoCaptions![index].trim()
          : '';
      final mappedCaption =
          widget.videoCaptionByPhotoId[section.photo.id]?.trim() ?? '';
      final preferredCaption = indexedCaption.isNotEmpty
          ? indexedCaption
          : (mappedCaption.isNotEmpty ? mappedCaption : section.text);
      playbackSections.add(section.copyWith(text: preferredCaption));
    }

    final random = math.Random();
    final introPhoto =
        playbackSections[random.nextInt(playbackSections.length)].photo;
    final introSection = StorySection(text: '__INTRO__', photo: introPhoto);
    final finalVideoSections = <StorySection>[
      introSection,
      ...playbackSections,
    ];

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StoryVideoPage(
          title: widget.title,
          subtitle: widget.subtitle,
          sections: finalVideoSections,
          customMusicPath: widget.customMusicPath,
          isHorizontal: widget.isHorizontal,
          dynamicBeatData: widget.dynamicBeatData,
          targetPlatform: widget.targetPlatform,
        ),
      ),
    );
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
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final section = _sections[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(height: 1.6),
                                ),
                              ),
                              Icon(
                                Icons.edit,
                                size: 16,
                                color: Colors.grey[400],
                              ),
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
                          (section.photo.ocrSummary?.trim().isNotEmpty ?? false)) ...[
                        const SizedBox(height: 10),
                        _PhotoContextCard(photo: section.photo),
                      ],
                    ],
                  ),
                );
              },
              childCount: _sections.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 48),
        child: FloatingActionButton.extended(
          onPressed: _openVideoPreview,
          backgroundColor: const Color(0xFFD17EAD),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.play_circle_fill, size: 28),
          label: const Text(
            '播放回忆',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: BottomAppBar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _closePage,
                icon: const Icon(Icons.close),
                label: const Text('关闭'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveStory,
                icon: const Icon(Icons.save),
                label: Text(_isSaving ? '保存中...' : '保存'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _openDigitalAlbum,
                icon: const Icon(Icons.auto_stories),
                label: const Text('数字相册'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _shareStory,
                icon: const Icon(Icons.share),
                label: const Text('分享'),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            _PhotoContextRow(label: '图片描述', value: caption),
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
  const _PhotoContextRow({
    required this.label,
    required this.value,
  });

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
