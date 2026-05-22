/// 故事结果页面，展示生成后的故事内容和分享入口。

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/entity/photo_entity.dart';
import '../../models/entity/story_entity.dart';
import '../../models/story.dart';
import '../../models/vo/photo.dart';
import '../../models/vo/story_section.dart';
import '../../service/story_service.dart';
import '../../utils/ocr_policy.dart';
import '../widgets/path_image.dart';
import 'digital_album_book_page.dart';
import 'story_video_page.dart';
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

  Future<void> _shareStory() async {
    if (_sections.isEmpty) {
      return;
    }

    final posterFile = await _generateSharePosterFile();
    final storyCaption = [
      widget.title,
      if (widget.subtitle.trim().isNotEmpty) widget.subtitle.trim(),
    ].join(' · ');

    await Share.shareXFiles(
      [XFile(posterFile.path)],
      text: storyCaption,
    );
  }

  Future<File> _generateSharePosterFile() async {
    final tempDir = await getTemporaryDirectory();
    final posterFile = File(
      path.join(tempDir.path, 'story_share_${DateTime.now().millisecondsSinceEpoch}.png'),
    );

    final boundaryKey = GlobalKey();
    final overlay = Overlay.of(context, rootOverlay: true);

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: SizedBox(
                width: 1080,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: _StorySharePoster(
                    title: widget.title,
                    subtitle: widget.subtitle,
                    heroImage: widget.heroImage,
                    sections: _sections,
                    targetPlatform: widget.targetPlatform,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(overlayEntry);

    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final renderObject = boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('Share poster is not ready');
      }

      final image = await renderObject.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Failed to encode share poster');
      }

      await posterFile.writeAsBytes(byteData.buffer.asUint8List());
      return posterFile;
    } finally {
      overlayEntry.remove();
    }
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

  List<StorySection> _buildVideoSections() {
    if (_sections.isEmpty) {
      return const <StorySection>[];
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

    if (playbackSections.isEmpty) {
      return const <StorySection>[];
    }

    final random = math.Random();
    final introPhoto =
        playbackSections[random.nextInt(playbackSections.length)].photo;
    final introSection = StorySection(text: '__INTRO__', photo: introPhoto);
    return <StorySection>[introSection, ...playbackSections];
  }

  void _openVideoPreview() {
    final finalVideoSections = _buildVideoSections();
    if (finalVideoSections.isEmpty) {
      return;
    }

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
          onComplete: (_, __) {},
          currentTextStyle: 'hero',
          textYPosition: 0.8,
          textSize: 24.0,
          textBlurIntensity: 4.0,
          shakeIntensity: 0.0,
          shakeFrequency: 1.0,
          glitchIntensity: 0.0,
          enableFlash: true,
          useVignette: false,
          useGrain: false,
          useCameraFrame: false,
          useGlowRing: false,
          useCloudBorder: false,
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
                label: const Text('分享长图'),
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

class _StorySharePoster extends StatelessWidget {
  const _StorySharePoster({
    required this.title,
    required this.subtitle,
    required this.heroImage,
    required this.sections,
    required this.targetPlatform,
  });

  final String title;
  final String subtitle;
  final Photo heroImage;
  final List<StorySection> sections;
  final String targetPlatform;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6F2), Color(0xFFF7EDF9), Color(0xFFF8FBFF)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -100,
            child: _PosterGlow(color: Color(0x66F1B7D1), size: 360),
          ),
          Positioned(
            top: 220,
            right: -140,
            child: _PosterGlow(color: Color(0x55F8C987), size: 420),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(56, 56, 56, 64),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
                      ),
                      child: Text(
                        'Memoria Story',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: const Color(0xFF7D4F6D),
                            ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${sections.length} 张照片',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF8A6D7D),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontSize: 60,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF24181F),
                      ),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    subtitle.trim(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF6F5A66),
                          height: 1.35,
                        ),
                  ),
                ],
                const SizedBox(height: 28),
                _PosterHeroCard(photo: heroImage),
                const SizedBox(height: 28),
                ...sections
                    .map((section) => _PosterSectionCard(section: section))
                    .expand((widget) => [widget, const SizedBox(height: 22)]),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.84)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Color(0xFFD17EAD)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '适合直接分享到社交平台的故事长图 · $targetPlatform',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF6B5761),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterHeroCard extends StatelessWidget {
  const _PosterHeroCard({required this.photo});

  final Photo photo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB68CA5).withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: PathImage(
                path: photo.path,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 30, 22, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.72),
                    ],
                  ),
                ),
                child: Text(
                  photo.caption?.trim().isNotEmpty ?? false
                      ? photo.caption!.trim()
                      : (photo.location?.trim().isNotEmpty ?? false)
                          ? photo.location!.trim()
                          : '把这一刻留在记忆里',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterSectionCard extends StatelessWidget {
  const _PosterSectionCard({required this.section});

  final StorySection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: PathImage(
                path: section.photo.path,
                fit: BoxFit.cover,
              ),
            ),
          ),
          if (section.text.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              section.text.trim(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF2C2027),
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PosterGlow extends StatelessWidget {
  const _PosterGlow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 80,
            spreadRadius: 24,
          ),
        ],
      ),
    );
  }
}
