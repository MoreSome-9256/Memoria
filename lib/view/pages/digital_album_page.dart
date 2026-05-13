/// 数字相册页面，用于编辑和预览相册版式。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/entity/photo_entity.dart';
import '../../models/entity/story_entity.dart';
import '../../models/vo/photo.dart';
import '../../models/vo/story_section.dart';
import '../widgets/path_image.dart';
import '../../objectbox.g.dart';
import '../../storage/objectbox/objectbox_service.dart';

class DigitalAlbumResult {
  const DigitalAlbumResult({
    required this.sections,
    required this.saved,
  });

  final List<StorySection> sections;
  final bool saved;
}

class DigitalAlbumPage extends StatefulWidget {
  const DigitalAlbumPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.sections,
    required this.storyEntityId,
  });

  final String title;
  final String subtitle;
  final List<StorySection> sections;
  final int? storyEntityId;

  @override
  State<DigitalAlbumPage> createState() => _DigitalAlbumPageState();
}

class _DigitalAlbumPageState extends State<DigitalAlbumPage> {
  late final PageController _pageController;
  late List<StorySection> _sections;
  late List<_AlbumPageDraft> _pages;
  int _currentPage = 0;
  bool _isSaving = false;
  bool _hasSaved = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _sections = List<StorySection>.from(widget.sections);
    _pages = _buildAlbumPages(_sections);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _refreshPages() {
    _pages = _buildAlbumPages(_sections);
    if (_currentPage >= _pages.length) {
      _currentPage = _pages.isEmpty ? 0 : _pages.length - 1;
    }
  }

  Future<void> _jumpToPage(int index) async {
    if (index < 0 || index >= _pages.length) {
      return;
    }
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goPrevious() => _jumpToPage(_currentPage - 1);

  Future<void> _goNext() => _jumpToPage(_currentPage + 1);

  Future<void> _editCurrentPage() async {
    if (_pages.isEmpty) {
      return;
    }

    final page = _pages[_currentPage];
    if (!page.isEditable || page.sectionIndex == null) {
      return;
    }

    final controller = TextEditingController(text: page.body);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            page.kind == _AlbumPageKind.story ? '编辑故事文案' : '编辑图片说明',
          ),
          content: TextField(
            controller: controller,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '在这里修改本页文案',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (saved != true) {
      return;
    }

    final sectionIndex = page.sectionIndex!;
    final newText = controller.text.trim();
    if (page.kind == _AlbumPageKind.story) {
      _sections[sectionIndex] = _sections[sectionIndex].copyWith(text: newText);
    } else {
      _sections[sectionIndex] = _sections[sectionIndex].copyWith(
        photo: _sections[sectionIndex].photo.copyWith(caption: newText),
      );
    }

    setState(_refreshPages);
  }

  Future<void> _saveAlbum() async {
    if (_isSaving) {
      return;
    }

    if (widget.storyEntityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前故事缺少存储 ID，无法保存数字相册修改')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final store = ObjectBoxService().store;
      final story = store.box<StoryEntity>().get(widget.storyEntityId!);
      if (story == null) {
        throw StateError('Story not found');
      }

      final photos = store.box<PhotoEntity>().getMany(story.photoIds);
      final existingPhotos = photos.whereType<PhotoEntity>().toList(growable: false);

      final photoByAssetId = <String, PhotoEntity>{
        for (final photo in existingPhotos) photo.assetId: photo,
      };

      final sectionMaps = _sections
          .map((section) => <String, dynamic>{
                'text': section.text,
                'photo': section.photo,
              })
          .toList(growable: false);

      story.content = StoryEntity.sectionsToMarkdown(sectionMaps);
      story.updatedAt = DateTime.now().millisecondsSinceEpoch;

      final changedPhotos = <PhotoEntity>[];
      for (final section in _sections) {
        final photoEntity = photoByAssetId[section.photo.id];
        if (photoEntity == null) {
          continue;
        }

        final newCaption = section.photo.caption?.trim();
        final oldCaption = photoEntity.aiCaption?.trim();
        if ((newCaption ?? '') == (oldCaption ?? '')) {
          continue;
        }

        photoEntity.aiCaption = newCaption;
        changedPhotos.add(photoEntity);
      }

      store.runInTransaction(TxMode.write, () {
        store.box<StoryEntity>().put(story);
        if (changedPhotos.isNotEmpty) {
          store.box<PhotoEntity>().putMany(changedPhotos);
        }
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _hasSaved = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('数字相册内容已保存')));
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

  void _closeAlbum() {
    Navigator.of(context).pop(
      DigitalAlbumResult(
        sections: List<StorySection>.from(_sections),
        saved: _hasSaved,
      ),
    );
  }

  List<_AlbumPageDraft> _buildAlbumPages(List<StorySection> sections) {
    final pages = <_AlbumPageDraft>[
      _AlbumPageDraft.cover(
        title: widget.title,
        subtitle: widget.subtitle,
        photo: sections.isNotEmpty ? sections.first.photo : null,
      ),
    ];

    StorySection? previous;
    for (var index = 0; index < sections.length; index++) {
      final section = sections[index];
      final chapterPage = _buildChapterPage(previous, section, index);
      if (chapterPage != null) {
        pages.add(chapterPage);
      }

      if (_shouldUseStoryLayout(index, sections, section)) {
        pages.add(
          _AlbumPageDraft.story(
            sectionIndex: index,
            title: _buildPageTitle(section.photo, index),
            body: section.text.trim(),
            footer: _buildMetaText(section.photo),
            photo: section.photo,
          ),
        );
      } else {
        pages.add(
          _AlbumPageDraft.caption(
            sectionIndex: index,
            title: _buildPageTitle(section.photo, index),
            body: _deriveCaption(section),
            footer: _buildMetaText(section.photo),
            photo: section.photo,
          ),
        );
      }

      previous = section;
    }

    if (sections.isNotEmpty) {
      pages.add(
        const _AlbumPageDraft(
          kind: _AlbumPageKind.ending,
          title: '回忆整理完成',
          body: '你可以继续翻页浏览，也可以回到故事页继续微调内容。',
          footer: '支持再次编辑并保存',
        ),
      );
    }

    return pages;
  }

  _AlbumPageDraft? _buildChapterPage(
    StorySection? previous,
    StorySection current,
    int index,
  ) {
    if (previous == null) {
      return _AlbumPageDraft.chapter(
        title: _buildPageTitle(current.photo, index),
        body: _buildMetaText(current.photo),
      );
    }

    final previousDay = DateTime(
      previous.photo.dateTaken.year,
      previous.photo.dateTaken.month,
      previous.photo.dateTaken.day,
    );
    final currentDay = DateTime(
      current.photo.dateTaken.year,
      current.photo.dateTaken.month,
      current.photo.dateTaken.day,
    );

    final dayChanged = currentDay.isAfter(previousDay);
    final previousLocation = previous.photo.location?.trim() ?? '';
    final currentLocation = current.photo.location?.trim() ?? '';
    final locationChanged = previousLocation != currentLocation;

    if (!dayChanged && !locationChanged && index % 3 != 0) {
      return null;
    }

    final title = locationChanged && currentLocation.isNotEmpty
        ? currentLocation
        : _formatDayLabel(current.photo.dateTaken);

    return _AlbumPageDraft.chapter(
      title: title,
      body: _buildMetaText(current.photo),
    );
  }

  bool _shouldUseStoryLayout(
    int index,
    List<StorySection> sections,
    StorySection section,
  ) {
    final textLength = section.text.trim().length;
    if (index == 0 || index == sections.length - 1) {
      return true;
    }
    if (textLength >= 56) {
      return true;
    }
    return index.isOdd;
  }

  String _deriveCaption(StorySection section) {
    final existingCaption = section.photo.caption?.trim();
    if (existingCaption != null && existingCaption.isNotEmpty) {
      return existingCaption;
    }

    final text = section.text.trim();
    if (text.isEmpty) {
      return '点击编辑，为这张照片补上一句说明。';
    }

    final punctuation = <String>['。', '！', '？', '.', '!', '?'];
    var splitIndex = -1;
    for (final symbol in punctuation) {
      final index = text.indexOf(symbol);
      if (index >= 0 && (splitIndex == -1 || index < splitIndex)) {
        splitIndex = index;
      }
    }

    final firstSentence = splitIndex >= 0 ? text.substring(0, splitIndex + 1) : text;
    if (firstSentence.length <= 36) {
      return firstSentence;
    }
    return '${firstSentence.substring(0, 34).trim()}...';
  }

  String _buildPageTitle(Photo photo, int index) {
    final location = photo.location?.trim();
    if (location != null && location.isNotEmpty) {
      return location;
    }
    return '第 ${index + 1} 张照片';
  }

  String _buildMetaText(Photo photo) {
    final timeText = _formatDateTime(photo.dateTaken);
    final location = photo.location?.trim();
    if (location != null && location.isNotEmpty) {
      return '$timeText · $location';
    }
    return timeText;
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }

  String _formatDayLabel(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}.$month.$day';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeAlbum();
        }
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowLeft): _PreviousAlbumPageIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight): _NextAlbumPageIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _PreviousAlbumPageIntent: CallbackAction<_PreviousAlbumPageIntent>(
              onInvoke: (intent) {
                _goPrevious();
                return null;
              },
            ),
            _NextAlbumPageIntent: CallbackAction<_NextAlbumPageIntent>(
              onInvoke: (intent) {
                _goNext();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: const Color(0xFFF6EFE9),
              appBar: AppBar(
                leading: IconButton(
                  onPressed: _closeAlbum,
                  icon: const Icon(Icons.arrow_back),
                ),
                title: const Text('数字相册'),
                actions: [
                  IconButton(
                    onPressed: _pages.isNotEmpty && _pages[_currentPage].isEditable
                        ? _editCurrentPage
                        : null,
                    icon: const Icon(Icons.edit_note),
                    tooltip: '编辑本页文案',
                  ),
                  IconButton(
                    onPressed: _isSaving ? null : _saveAlbum,
                    icon: const Icon(Icons.save),
                    tooltip: '保存数字相册',
                  ),
                ],
              ),
              body: Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _pages.length,
                      onPageChanged: (value) {
                        setState(() {
                          _currentPage = value;
                        });
                      },
                      itemBuilder: (context, index) {
                        final page = _pages[index];
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                          child: _DigitalAlbumSheet(
                            page: page,
                            pageNumber: index + 1,
                            totalPages: _pages.length,
                            onEdit: page.isEditable ? _editCurrentPage : null,
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                      child: Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: _currentPage > 0 ? _goPrevious : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '第 ${_currentPage + 1} / ${_pages.length} 页',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: _pages.isEmpty
                                      ? 0
                                      : (_currentPage + 1) / _pages.length,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filled(
                            onPressed:
                                _currentPage < _pages.length - 1 ? _goNext : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DigitalAlbumSheet extends StatelessWidget {
  const _DigitalAlbumSheet({
    required this.page,
    required this.pageNumber,
    required this.totalPages,
    required this.onEdit,
  });

  final _AlbumPageDraft page;
  final int pageNumber;
  final int totalPages;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF7),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: switch (page.kind) {
          _AlbumPageKind.cover => _buildCover(context),
          _AlbumPageKind.chapter => _buildChapter(context),
          _AlbumPageKind.caption => _buildCaption(context),
          _AlbumPageKind.story => _buildStory(context),
          _AlbumPageKind.ending => _buildEnding(context),
        },
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Digital Album',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                letterSpacing: 1.8,
                color: Colors.brown.shade300,
              ),
        ),
        const SizedBox(height: 14),
        Text(
          page.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF4B3328),
              ),
        ),
        const SizedBox(height: 10),
        Text(
          page.body,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                height: 1.5,
                color: const Color(0xFF7B6255),
              ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: page.photo == null
                ? Container(color: const Color(0xFFF3E7DD))
                : PathImage(
                    path: page.photo!.path,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
          ),
        ),
        const SizedBox(height: 18),
        _AlbumPageFooter(
          pageNumber: pageNumber,
          totalPages: totalPages,
          foreground: Colors.brown.shade300,
        ),
      ],
    );
  }

  Widget _buildChapter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Text(
          page.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF4B3328),
              ),
        ),
        const SizedBox(height: 14),
        Text(
          page.body,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                height: 1.7,
                color: const Color(0xFF7B6255),
              ),
        ),
        const Spacer(),
        Text(
          '新的章节从这里展开',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.brown.shade300,
              ),
        ),
        const SizedBox(height: 14),
        _AlbumPageFooter(
          pageNumber: pageNumber,
          totalPages: totalPages,
          foreground: Colors.brown.shade300,
        ),
      ],
    );
  }

  Widget _buildCaption(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AlbumHeader(title: page.title, footer: page.footer),
        const SizedBox(height: 18),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: PathImage(
              path: page.photo!.path,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 160,
          child: _EditableTextCard(
            title: '图片说明',
            text: page.body,
            onEdit: onEdit,
          ),
        ),
        const SizedBox(height: 16),
        _AlbumPageFooter(
          pageNumber: pageNumber,
          totalPages: totalPages,
          foreground: Colors.brown.shade300,
        ),
      ],
    );
  }

  Widget _buildStory(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AlbumHeader(title: page.title, footer: page.footer),
        const SizedBox(height: 18),
        SizedBox(
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: PathImage(
              path: page.photo!.path,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: _EditableTextCard(
            title: '故事片段',
            text: page.body,
            onEdit: onEdit,
            dense: false,
          ),
        ),
        const SizedBox(height: 16),
        _AlbumPageFooter(
          pageNumber: pageNumber,
          totalPages: totalPages,
          foreground: Colors.brown.shade300,
        ),
      ],
    );
  }

  Widget _buildEnding(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Text(
          page.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF4B3328),
              ),
        ),
        const SizedBox(height: 14),
        Text(
          page.body,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                height: 1.7,
                color: const Color(0xFF7B6255),
              ),
        ),
        const Spacer(),
        Text(
          page.footer,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.brown.shade300,
              ),
        ),
        const SizedBox(height: 14),
        _AlbumPageFooter(
          pageNumber: pageNumber,
          totalPages: totalPages,
          foreground: Colors.brown.shade300,
        ),
      ],
    );
  }
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.title,
    required this.footer,
  });

  final String title;
  final String footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF4B3328),
              ),
        ),
        const SizedBox(height: 6),
        Text(
          footer,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.brown.shade300,
              ),
        ),
      ],
    );
  }
}

class _EditableTextCard extends StatelessWidget {
  const _EditableTextCard({
    required this.title,
    required this.text,
    required this.onEdit,
    this.dense = true,
  });

  final String title;
  final String text;
  final VoidCallback? onEdit;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFEF8F2),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(dense ? 16 : 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.brown.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.brown.shade400,
                        ),
                  ),
                  const Spacer(),
                  if (onEdit != null)
                    Icon(Icons.edit, size: 18, color: Colors.brown.shade300),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    text.trim().isEmpty ? '点击这里填写本页内容' : text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          height: dense ? 1.65 : 1.8,
                          color: const Color(0xFF5D4538),
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumPageFooter extends StatelessWidget {
  const _AlbumPageFooter({
    required this.pageNumber,
    required this.totalPages,
    required this.foreground,
  });

  final int pageNumber;
  final int totalPages;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: foreground.withValues(alpha: 0.4))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '$pageNumber / $totalPages',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                ),
          ),
        ),
        Expanded(child: Divider(color: foreground.withValues(alpha: 0.4))),
      ],
    );
  }
}

enum _AlbumPageKind {
  cover,
  chapter,
  caption,
  story,
  ending,
}

class _AlbumPageDraft {
  const _AlbumPageDraft({
    required this.kind,
    required this.title,
    required this.body,
    required this.footer,
    this.sectionIndex,
    this.photo,
    this.isEditable = false,
  });

  factory _AlbumPageDraft.cover({
    required String title,
    required String subtitle,
    required Photo? photo,
  }) {
    return _AlbumPageDraft(
      kind: _AlbumPageKind.cover,
      title: title,
      body: subtitle,
      footer: '向右翻页，开始浏览数字相册',
      photo: photo,
    );
  }

  factory _AlbumPageDraft.chapter({
    required String title,
    required String body,
  }) {
    return _AlbumPageDraft(
      kind: _AlbumPageKind.chapter,
      title: title,
      body: body,
      footer: '时间线与故事线从这里自然展开',
    );
  }

  factory _AlbumPageDraft.caption({
    required int sectionIndex,
    required String title,
    required String body,
    required String footer,
    required Photo photo,
  }) {
    return _AlbumPageDraft(
      kind: _AlbumPageKind.caption,
      title: title,
      body: body,
      footer: footer,
      sectionIndex: sectionIndex,
      photo: photo,
      isEditable: true,
    );
  }

  factory _AlbumPageDraft.story({
    required int sectionIndex,
    required String title,
    required String body,
    required String footer,
    required Photo photo,
  }) {
    return _AlbumPageDraft(
      kind: _AlbumPageKind.story,
      title: title,
      body: body,
      footer: footer,
      sectionIndex: sectionIndex,
      photo: photo,
      isEditable: true,
    );
  }

  final _AlbumPageKind kind;
  final String title;
  final String body;
  final String footer;
  final int? sectionIndex;
  final Photo? photo;
  final bool isEditable;
}

class _PreviousAlbumPageIntent extends Intent {
  const _PreviousAlbumPageIntent();
}

class _NextAlbumPageIntent extends Intent {
  const _NextAlbumPageIntent();
}
