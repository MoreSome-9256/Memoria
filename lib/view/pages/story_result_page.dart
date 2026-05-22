/// 故事结果页面，展示生成后的故事内容和分享入口。

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../objectbox.g.dart';
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
          text: storyEntity.content.trim().isEmpty
              ? '我的专属回忆'
              : storyEntity.content,
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

  static Photo _mergePhotoEntityData(
    Photo basePhoto,
    PhotoEntity? photoEntity,
  ) {
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
      ocrTags: basePhoto.ocrTags.isNotEmpty
          ? basePhoto.ocrTags
          : entityPhoto.ocrTags,
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
      path: overridePhoto.path.trim().isNotEmpty
          ? overridePhoto.path
          : basePhoto.path,
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
      ocrTags: overridePhoto.ocrTags.isNotEmpty
          ? overridePhoto.ocrTags
          : basePhoto.ocrTags,
      width: overridePhoto.width > 0 ? overridePhoto.width : basePhoto.width,
      height: overridePhoto.height > 0
          ? overridePhoto.height
          : basePhoto.height,
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
            decoration: const InputDecoration(border: OutlineInputBorder()),
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
      final store = ObjectBoxService().store;
      final storyBox = store.box<StoryEntity>();
      final story = storyBox.get(widget.storyEntityId!);
      if (story == null) {
        throw StateError('Story not found');
      }

      final sectionMaps = _sections
          .map(
            (section) => <String, dynamic>{
              'text': section.text,
              'photo': section.photo,
            },
          )
          .toList(growable: false);

      story.content = StoryEntity.sectionsToMarkdown(sectionMaps);
      story.updatedAt = DateTime.now().millisecondsSinceEpoch;
      story.isManuallySaved = true; // 标记为手动保存
      
      store.runInTransaction(TxMode.write, () {
        // 删除所有自动保存的记录（因为用户已经手动保存了）
        final autoSavedQuery = storyBox.query(
          StoryEntity_.isManuallySaved.equals(false),
        ).build();
        final autoSavedStories = autoSavedQuery.find();
        autoSavedQuery.close();
        
        if (autoSavedStories.isNotEmpty) {
          storyBox.removeMany(autoSavedStories.map((s) => s.id).toList());
        }
        
        // 保存当前故事
        storyBox.put(story);
      });

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

    if (!mounted) {
      return;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '分享预览',
      barrierColor: Colors.black.withValues(alpha: 0.78),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _SharePosterPreviewSheet(
          posterFile: posterFile,
          caption: storyCaption,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Future<File> _generateSharePosterFile() async {
    await _precachePosterImages();
    if (!mounted || !context.mounted) {
      throw StateError('Share poster generation was cancelled');
    }
    final overlay = Overlay.of(context, rootOverlay: true);

    final tempDir = await getTemporaryDirectory();
    final posterFile = File(
      path.join(
        tempDir.path,
        'story_share_${DateTime.now().millisecondsSinceEpoch}.png',
      ),
    );

    final boundaryKey = GlobalKey();

    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.topCenter,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minWidth: 1080,
                maxWidth: 1080,
                minHeight: 0,
                maxHeight: double.infinity,
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

  Future<void> _precachePosterImages() async {
    final paths = <String>{
      widget.heroImage.path,
      for (final section in _sections) section.photo.path,
    }.where((item) => item.trim().isNotEmpty).take(16).toList(growable: false);

    for (final imagePath in paths) {
      final uri = Uri.tryParse(imagePath);
      final scheme = uri?.scheme.toLowerCase();
      final provider = scheme == 'http' || scheme == 'https'
          ? NetworkImage(imagePath) as ImageProvider
          : FileImage(_localImageFile(imagePath, uri));
      try {
        await precacheImage(
          provider,
          context,
        ).timeout(const Duration(milliseconds: 900));
      } catch (_) {
        // Missing or slow images should not block sharing; poster widgets show
        // their own placeholder if an image cannot be decoded in time.
      }
    }
  }

  File _localImageFile(String imagePath, Uri? uri) {
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      return File(uri.toFilePath());
    }
    return File(imagePath);
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
      final indexedCaption =
          widget.videoCaptions != null && index < widget.videoCaptions!.length
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
          onComplete: (_, _) {},
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
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: PathImage(
                          path: section.photo.path,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
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
    final visibleSections = sections;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFBF7F0), Color(0xFFF5F1E8), Color(0xFF3D3630)],
          stops: [0.0, 0.45, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(height: 18, color: const Color(0xFF172326)),
          ),
          Positioned(
            top: 18,
            left: 0,
            bottom: 0,
            child: Container(width: 18, color: const Color(0xFF172326)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(58, 62, 58, 64),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF172326),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Memoria Story',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: const Color(0xFFF8F3E7),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${sections.length} 张照片',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF5D5148),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontSize: _fitTitleSize(title),
                    height: 1.02,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF191D1D),
                  ),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 760),
                    padding: const EdgeInsets.only(left: 18),
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Color(0xFFCC775A), width: 6),
                      ),
                    ),
                    child: Text(
                      subtitle.trim(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF5D5148),
                        height: 1.34,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 34),
                _PosterHeroCard(photo: heroImage),
                const SizedBox(height: 32),
                for (var index = 0; index < visibleSections.length; index++)
                  _PosterSectionCard(
                    section: visibleSections[index],
                    index: index,
                  ),
                const SizedBox(height: 26),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF172326),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '由 Memoria 生成',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFFF1C45B),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _fitTitleSize(String value) {
    final length = value.characters.length;
    if (length >= 22) {
      return 42;
    }
    if (length >= 14) {
      return 50;
    }
    return 64;
  }
}

class _PosterHeroCard extends StatelessWidget {
  const _PosterHeroCard({required this.photo});

  final Photo photo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F292A), width: 4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(10, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipPath(
            clipper: _PosterShapeClipper(style: 2),
            child: AspectRatio(
              aspectRatio: 1.28,
              child: _PosterPathImage(
                path: photo.path,
                alignment: Alignment.center,
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              decoration: BoxDecoration(
                color: const Color(0xE8172326),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                photo.caption?.trim().isNotEmpty ?? false
                    ? photo.caption!.trim()
                    : (photo.location?.trim().isNotEmpty ?? false)
                    ? photo.location!.trim()
                    : '把这一刻留在记忆里',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFF8F3E7),
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterSectionCard extends StatelessWidget {
  const _PosterSectionCard({required this.section, required this.index});

  final StorySection section;
  final int index;

  @override
  Widget build(BuildContext context) {
    final flip = index.isOdd;
    final text = section.text.trim();
    final rotation = <double>[-0.025, 0.018, -0.012, 0.024][index % 4];
    final image = Transform.rotate(
      angle: rotation,
      child: _PosterFramedImage(
        photo: section.photo,
        index: index,
        compact: index % 3 == 1,
      ),
    );
    final textBlock = _PosterTextBlock(text: text, index: index);

    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: flip ? 11 : 9, child: flip ? textBlock : image),
          const SizedBox(width: 24),
          Expanded(flex: flip ? 9 : 11, child: flip ? image : textBlock),
        ],
      ),
    );
  }
}

class _PosterFramedImage extends StatelessWidget {
  const _PosterFramedImage({
    required this.photo,
    required this.index,
    required this.compact,
  });

  final Photo photo;
  final int index;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 12, 12, compact ? 30 : 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDED4C4), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(6, 9),
          ),
        ],
      ),
      child: ClipPath(
        clipper: _PosterShapeClipper(style: index % 4),
        child: AspectRatio(
          aspectRatio: compact ? 0.9 : 1.16,
          child: _PosterPathImage(
            path: photo.path,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }
}

class _PosterTextBlock extends StatelessWidget {
  const _PosterTextBlock({required this.text, required this.index});

  final String text;
  final int index;

  @override
  Widget build(BuildContext context) {
    final accentColors = const <Color>[
      Color(0xFFCC775A),
      Color(0xFF3D6C64),
      Color(0xFFB18A33),
      Color(0xFF6D5E8C),
    ];
    final accent = accentColors[index % accentColors.length];
    final displayText = text.isEmpty ? '这一帧，也在故事里发光。' : text;
    final fontSize = displayText.characters.length > 70 ? 28.0 : 33.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        color: index.isEven ? const Color(0xFFFFFCF4) : Colors.transparent,
        border: Border(
          left: BorderSide(color: accent, width: 8),
          top: BorderSide(color: accent.withValues(alpha: 0.32), width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (index + 1).toString().padLeft(2, '0'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: accent,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            displayText,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: const Color(0xFF202321),
              fontSize: fontSize,
              height: 1.34,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterPathImage extends StatelessWidget {
  const _PosterPathImage({
    required this.path,
    this.alignment = Alignment.center,
  });

  final String path;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFE4DDD0)),
      child: PathImage(
        path: path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        alignment: alignment,
        enableSmartCache: false,
      ),
    );
  }
}

class _PosterShapeClipper extends CustomClipper<Path> {
  const _PosterShapeClipper({required this.style});

  final int style;

  @override
  Path getClip(Size size) {
    final path = Path();
    switch (style) {
      case 1:
        path
          ..moveTo(size.width * 0.06, 0)
          ..lineTo(size.width, size.height * 0.04)
          ..lineTo(size.width * 0.94, size.height)
          ..lineTo(0, size.height * 0.96)
          ..close();
        return path;
      case 2:
        path
          ..moveTo(0, size.height * 0.08)
          ..quadraticBezierTo(0, 0, size.width * 0.08, 0)
          ..lineTo(size.width * 0.92, 0)
          ..quadraticBezierTo(size.width, 0, size.width, size.height * 0.08)
          ..lineTo(size.width, size.height * 0.86)
          ..quadraticBezierTo(
            size.width * 0.72,
            size.height,
            size.width * 0.48,
            size.height,
          )
          ..lineTo(size.width * 0.08, size.height)
          ..quadraticBezierTo(0, size.height, 0, size.height * 0.92)
          ..close();
        return path;
      case 3:
        path
          ..moveTo(size.width * 0.12, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height * 0.88)
          ..lineTo(size.width * 0.88, size.height)
          ..lineTo(0, size.height)
          ..lineTo(0, size.height * 0.12)
          ..close();
        return path;
      default:
        return Path()..addRRect(
          RRect.fromRectAndRadius(
            Offset.zero & size,
            const Radius.circular(18),
          ),
        );
    }
  }

  @override
  bool shouldReclip(covariant _PosterShapeClipper oldClipper) {
    return oldClipper.style != style;
  }
}

class _SharePosterPreviewSheet extends StatefulWidget {
  const _SharePosterPreviewSheet({
    required this.posterFile,
    required this.caption,
  });

  final File posterFile;
  final String caption;

  @override
  State<_SharePosterPreviewSheet> createState() =>
      _SharePosterPreviewSheetState();
}

class _SharePosterPreviewSheetState extends State<_SharePosterPreviewSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  bool _autoShareTriggered = false;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await _controller.forward();
      if (mounted && !_autoShareTriggered) {
        _autoShareTriggered = true;
        await _share();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_isSharing) {
      return;
    }
    setState(() => _isSharing = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(widget.posterFile.path, mimeType: 'image/png')],
        text: widget.caption,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final previewWidth = math.min(media.size.width - 36, 390.0);
    final previewHeight = media.size.height * 0.56;

    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(color: Colors.transparent),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _scale,
                        builder: (context, child) {
                          final topOffset = Tween<double>(
                            begin: media.size.height * 0.12,
                            end: 0,
                          ).evaluate(_scale);
                          final scale = Tween<double>(
                            begin: 1.16,
                            end: 1,
                          ).evaluate(_scale);
                          return Transform.translate(
                            offset: Offset(0, topOffset),
                            child: Transform.scale(scale: scale, child: child),
                          );
                        },
                        child: Container(
                          width: previewWidth,
                          height: previewHeight,
                          decoration: BoxDecoration(
                            color: const Color(0xFF111718),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.32),
                                blurRadius: 34,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: InteractiveViewer(
                              minScale: 0.65,
                              maxScale: 4,
                              child: SingleChildScrollView(
                                child: Image.file(
                                  widget.posterFile,
                                  width: previewWidth - 20,
                                  fit: BoxFit.fitWidth,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isSharing ? null : _share,
                              icon: const Icon(Icons.ios_share),
                              label: Text(_isSharing ? '分享中...' : '分享'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                              label: const Text('退出'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isSharing ? null : () {},
                          icon: const Icon(Icons.style),
                          label: const Text('换个样式'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
