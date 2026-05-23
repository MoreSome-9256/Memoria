/// 数字相册书页面，展示和编辑书册式相册内容。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vo/album_book_models.dart';
import '../../models/vo/photo.dart';
import '../../models/vo/story_section.dart';
import '../../service/digital_album_ai_service.dart';
import '../../service/digital_album_book_service.dart';
import '../../service/digital_album_layout_service.dart';
import '../../service/digital_album_validator_service.dart';
import '../widgets/path_image.dart';
// import 'vlm_photo_picker_page.dart';

class DigitalAlbumBookResult {
  const DigitalAlbumBookResult({
    required this.saved,
    required this.document,
  });

  final bool saved;
  final AlbumBookDocument? document;
}

class DigitalAlbumBookPage extends StatefulWidget {
  const DigitalAlbumBookPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.sections,
    this.storyTemplateId,
    required this.storyEntityId,
  });

  final String title;
  final String subtitle;
  final List<StorySection> sections;
  final String? storyTemplateId;
  final int? storyEntityId;

  @override
  State<DigitalAlbumBookPage> createState() => _DigitalAlbumBookPageState();
}

class _DigitalAlbumBookPageState extends State<DigitalAlbumBookPage>
    with SingleTickerProviderStateMixin {
  final DigitalAlbumLayoutService _layoutService = const DigitalAlbumLayoutService();
  final DigitalAlbumValidatorService _validator = const DigitalAlbumValidatorService();
  final DigitalAlbumAiService _aiService = const DigitalAlbumAiService();
  final DigitalAlbumBookService _bookService = const DigitalAlbumBookService();
  final PageController _pageController = PageController();
  final TransformationController _spreadZoomController = TransformationController();
  final FocusNode _inlineTextFocusNode = FocusNode();
  final List<_EditorSnapshot> _history = <_EditorSnapshot>[];
  late final AnimationController _turnController;
  AlbumBookDocument? _document;
  _SelectedElementRef? _selectedElement;
  TextEditingController? _inlineTextController;
  String? _inlineEditingElementId;
  String? _textUndoSeedElementId;
  String? _gestureUndoSeedElementId;
  Timer? _crossPageSwitchTimer;
  String? _crossPagePendingElementId;
  int? _crossPagePendingSpreadIndex;
  AlbumPageSide? _crossPagePendingTargetSide;
  double? _crossPagePendingLocalX;
  double? _crossPagePendingLocalY;
  bool _isInlineTextEditing = false;
  int _currentSpread = 0;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAiBusy = false;
  bool _editMode = false;
  bool _hasSaved = false;
  bool _isDirty = false;
  bool _isSpreadZoomed = false;
  bool _isQuickMenuVisible = false;
  bool _isTemplatePanelVisible = false;
  int? _turnFromSpread;
  int? _turnToSpread;
  bool _turnForward = true;
  bool _turnCommitOnComplete = false;
  double _turnDragExtent = 1;
  double _turnDragDelta = 0;
  late List<StorySection> _workingSections;
  final AlbumBookStylePreset _currentStylePreset = AlbumBookStylePreset.editorial;
  Set<String> _selectedTemplateIds =
      Set<String>.from(DigitalAlbumLayoutService.defaultTemplateIds);
  Set<String> _templateDraftIds =
      Set<String>.from(DigitalAlbumLayoutService.defaultTemplateIds);

  @override
  void initState() {
    super.initState();
    _turnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..addStatusListener(_handleTurnStatusChanged);
    _workingSections = _cloneSections(widget.sections);
    _lockLandscape();
    _loadBook();
  }

  @override
  void dispose() {
    _cancelPendingCrossPageSwitch();
    _turnController.dispose();
    _restoreOrientation();
    _pageController.dispose();
    _spreadZoomController.dispose();
    _disposeInlineTextController();
    _inlineTextFocusNode.dispose();
    super.dispose();
  }

  Future<void> _lockLandscape() async {
    await SystemChrome.setPreferredOrientations(
      const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
  }

  Future<void> _restoreOrientation() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _loadBook() async {
    final fallback = _layoutService.buildDefaultBook(
      title: widget.title,
      subtitle: widget.subtitle,
      sections: _workingSections,
      preset: _currentStylePreset,
      allowedTemplateIds: _selectedTemplateIds,
    );

    AlbumBookDocument? loaded;
    if (widget.storyEntityId != null) {
      loaded = await _bookService.loadByStoryId(widget.storyEntityId!);
      if (loaded != null && !_matchesCurrentStorySections(loaded)) {
        debugPrint(
          'Ignoring stale digital album cache for storyId=${widget.storyEntityId}; photo set does not match current story sections.',
        );
        await _bookService.deleteByStoryId(widget.storyEntityId!);
        loaded = null;
      }
    }

    final baseDocument = loaded ?? fallback;
    final document = _sanitize(baseDocument);
    if (!mounted) {
      return;
    }

    _disposeInlineTextController();
    setState(() {
      _document = document;
      _isLoading = false;
      _hasSaved = loaded != null;
      _isDirty = false;
      _selectedElement = null;
      _editMode = false;
      _selectedTemplateIds =
          Set<String>.from(DigitalAlbumLayoutService.defaultTemplateIds);
      _templateDraftIds =
          Set<String>.from(DigitalAlbumLayoutService.defaultTemplateIds);
    });
    _syncWorkingSectionsWithDocument(document);
  }

  bool _matchesCurrentStorySections(AlbumBookDocument document) {
    final currentPhotoIds = _workingSections
        .map((section) => section.photo.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (currentPhotoIds.isEmpty) {
      return true;
    }

    final documentPhotoIds = <String>{};
    for (final spread in document.spreads) {
      for (final page in <AlbumPageModel>[spread.leftPage, spread.rightPage]) {
        for (final element in page.elements) {
          final photoId = element.payload['photo_id']?.toString().trim();
          if (photoId != null && photoId.isNotEmpty) {
            documentPhotoIds.add(photoId);
          }
        }
      }
    }

    return documentPhotoIds.isNotEmpty &&
        setEquals(currentPhotoIds, documentPhotoIds);
  }

  void _syncSpreadZoomState() {
    final zoomed = _spreadZoomController.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _isSpreadZoomed || !mounted) {
      return;
    }
    setState(() {
      _isSpreadZoomed = zoomed;
    });
  }

  void _resetSpreadZoom() {
    _spreadZoomController.value = Matrix4.identity();
    if (_isSpreadZoomed && mounted) {
      setState(() {
        _isSpreadZoomed = false;
      });
    }
  }

  AlbumBookDocument _sanitize(AlbumBookDocument document) {
    final allowedPhotoIds = _collectAllowedPhotoIds(document);
    final photoPathById = <String, String>{
      for (final section in _workingSections)
        if (section.photo.id.trim().isNotEmpty && section.photo.path.trim().isNotEmpty)
          section.photo.id: section.photo.path,
    };
    return _validator.sanitize(
      document,
      allowedPhotoIds: allowedPhotoIds,
      photoPathById: photoPathById,
      fallbackTitle: widget.title,
      fallbackSubtitle: widget.subtitle,
    );
  }

  Set<String> _collectAllowedPhotoIds(AlbumBookDocument document) {
    final ids = _workingSections.map((section) => section.photo.id).toSet();
    for (final spread in document.spreads) {
      for (final page in <AlbumPageModel>[spread.leftPage, spread.rightPage]) {
        for (final element in page.elements) {
          final photoId = element.payload['photo_id']?.toString();
          if (photoId != null && photoId.isNotEmpty) {
            ids.add(photoId);
          }
        }
      }
    }
    return ids;
  }

  bool _isTextElement(AlbumElementModel? element) {
    return element != null &&
        (element.type == AlbumElementType.text || element.type == AlbumElementType.subtitle);
  }

  void _disposeInlineTextController() {
    _inlineTextFocusNode.unfocus();
    final controller = _inlineTextController;
    controller?.removeListener(_handleInlineTextChanged);
    _inlineTextController = null;
    _inlineEditingElementId = null;
    _textUndoSeedElementId = null;
    _gestureUndoSeedElementId = null;
    _isInlineTextEditing = false;
    if (controller != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
    }
  }

  List<StorySection> _cloneSections(Iterable<StorySection> sections) {
    return sections
        .map(
          (section) => section.copyWith(
            photo: section.photo.copyWith(
              tags: List<String>.from(section.photo.tags),
              ocrTags: List<String>.from(section.photo.ocrTags),
            ),
          ),
        )
        .toList(growable: true);
  }

  void _pushUndoSnapshot() {
    final document = _document;
    if (document == null) {
      return;
    }
    _history.add(
      _EditorSnapshot(
        document: document,
        sections: _cloneSections(_workingSections),
        currentSpread: _currentSpread,
      ),
    );
    if (_history.length > 40) {
      _history.removeAt(0);
    }
  }

  void _undoLastChange() {
    if (_history.isEmpty) {
      return;
    }
    final snapshot = _history.removeLast();
    final restoredDocument = _sanitize(snapshot.document);
    _finishManipulationGesture();
    _disposeInlineTextController();
    setState(() {
      _document = restoredDocument;
      _workingSections = _cloneSections(snapshot.sections);
      _currentSpread = snapshot.currentSpread.clamp(
        0,
        math.max(0, restoredDocument.spreads.length - 1),
      );
      _selectedElement = null;
      _editMode = false;
      _isDirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) {
        return;
      }
      _pageController.jumpToPage(_currentSpread);
    });
  }

  StorySection _sectionFromImageElement(AlbumElementModel element) {
    final dateRaw = element.payload['date_taken']?.toString();
    final parsedDate = dateRaw == null ? null : DateTime.tryParse(dateRaw);
    return StorySection(
      text: '',
      photo: Photo(
        id: element.payload['photo_id']?.toString() ?? element.id,
        path: element.payload['path']?.toString() ?? '',
        dateTaken: parsedDate ?? DateTime.now(),
        tags: const <String>[],
        ocrTags: const <String>[],
      ),
    );
  }

  List<StorySection> _sectionsForDocument(AlbumBookDocument document) {
    final sectionByPhotoId = <String, StorySection>{
      for (final section in _workingSections) section.photo.id: section,
    };
    final orderedIds = <String>[];
    final fallbackById = <String, StorySection>{};
    for (final spread in document.spreads) {
      for (final page in <AlbumPageModel>[spread.leftPage, spread.rightPage]) {
        for (final element in page.elements) {
          if (element.type != AlbumElementType.image) {
            continue;
          }
          final photoId = element.payload['photo_id']?.toString();
          if (photoId == null || photoId.isEmpty || orderedIds.contains(photoId)) {
            continue;
          }
          orderedIds.add(photoId);
          fallbackById[photoId] = _sectionFromImageElement(element);
        }
      }
    }

    if (orderedIds.isEmpty) {
      return _cloneSections(_workingSections);
    }

    return orderedIds
        .map((id) => sectionByPhotoId[id] ?? fallbackById[id]!)
        .toList(growable: false);
  }

  void _syncWorkingSectionsWithDocument(AlbumBookDocument document) {
    _workingSections = _cloneSections(_sectionsForDocument(document));
  }

  void _handleInlineTextChanged() {
    // Inline text is intentionally buffered in the controller while editing.
    // We only commit it back into the document when editing ends, which keeps
    // the page tree stable and avoids rebuilding the selected text box on
    // every keystroke.
  }

  void _commitInlineTextIfNeeded() {
    final controller = _inlineTextController;
    final selected = _selectedElementModel;
    if (!_isInlineTextEditing ||
        controller == null ||
        selected == null ||
        selected.id != _inlineEditingElementId) {
      return;
    }
    final currentText = selected.payload['text']?.toString() ?? '';
    if (currentText == controller.text) {
      return;
    }
    if (_textUndoSeedElementId != selected.id) {
      _pushUndoSnapshot();
      _textUndoSeedElementId = selected.id;
    }
    _updateSelectedElement((current) {
      final payload = Map<String, dynamic>.from(current.payload);
      payload['text'] = controller.text;
      return current.copyWith(payload: payload);
    });
  }

  void _syncInlineTextEditor({bool requestFocus = false}) {
    final selected = _selectedElementModel;
    if (!_isTextElement(selected)) {
      _disposeInlineTextController();
      _inlineTextFocusNode.unfocus();
      return;
    }

    final textElement = selected!;
    if (!requestFocus && !_isInlineTextEditing) {
      _disposeInlineTextController();
      _inlineTextFocusNode.unfocus();
      return;
    }

    if (requestFocus) {
      _isInlineTextEditing = true;
    }

    final text = textElement.payload['text']?.toString() ?? '';
    if (_inlineEditingElementId != textElement.id || _inlineTextController == null) {
      _disposeInlineTextController();
      final controller = TextEditingController(text: text);
      controller.addListener(_handleInlineTextChanged);
      _inlineTextController = controller;
      _inlineEditingElementId = textElement.id;
    } else if (_inlineTextController!.text != text && !_inlineTextFocusNode.hasFocus) {
      _inlineTextController!.text = text;
      _inlineTextController!.selection = TextSelection.collapsed(
        offset: _inlineTextController!.text.length,
      );
    }

    if (requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _inlineTextController == null) {
          return;
        }
        _inlineTextFocusNode.requestFocus();
        _inlineTextController!.selection = TextSelection.collapsed(
          offset: _inlineTextController!.text.length,
        );
      });
    }
  }

  Future<void> _runAiCopywriting() async {
    final document = _document;
    final currentSections = document == null ? const <StorySection>[] : _sectionsForDocument(document);
    if (document == null || _isAiBusy || currentSections.isEmpty) {
      return;
    }

    setState(() {
      _isAiBusy = true;
    });

    try {
      _pushUndoSnapshot();
      final rewritten = await _aiService.writeCopyForBook(
        title: widget.title,
        subtitle: widget.subtitle,
        sections: currentSections,
        document: document,
        storyTemplateId: widget.storyTemplateId,
      );

      if (!mounted) {
        return;
      }

      if (rewritten == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 写文案暂不可用，已保留当前相册')),
        );
        return;
      }

      final sanitized = _sanitize(rewritten);
      setState(() {
        _document = sanitized;
        _selectedElement = null;
        _editMode = false;
        _isDirty = true;
      });
      _disposeInlineTextController();
      _resetSpreadZoom();
      _syncWorkingSectionsWithDocument(sanitized);

      if (widget.storyEntityId != null) {
        await _bookService.save(
          storyId: widget.storyEntityId!,
          document: sanitized,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _hasSaved = true;
          _isDirty = false;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 已为整本相册补全文案')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 写文案失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAiBusy = false;
        });
      }
    }
  }

  void _handleAiCopyTap() {
    if (!_aiService.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前未配置 DeepSeek / LLM 接口，无法执行 AI 写文案')),
      );
      return;
    }
    unawaited(_runAiCopywriting());
  }

  void _applyTemplateSelection(Set<String> selectedTemplateIds) {
    final currentDocument = _document;
    final currentSections =
        currentDocument == null ? const <StorySection>[] : _sectionsForDocument(currentDocument);
    if (_isAiBusy || _isLoading || currentSections.isEmpty || currentDocument == null) {
      return;
    }
    final nextSelection = Set<String>.from(selectedTemplateIds);
    if (nextSelection.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一种排版')),
      );
      return;
    }
    if (!nextSelection.any(DigitalAlbumLayoutService.supportsSinglePhoto)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少保留一种可承接单图的排版')),
      );
      return;
    }
    _pushUndoSnapshot();
    var rebuilt = _sanitize(
      _layoutService.buildDefaultBook(
        title: widget.title,
        subtitle: widget.subtitle,
        sections: currentSections,
        preset: _currentStylePreset,
        allowedTemplateIds: nextSelection,
      ),
    );
    rebuilt = _sanitize(_reuseExistingCopy(currentDocument, rebuilt));
    setState(() {
      _selectedTemplateIds = nextSelection;
      _templateDraftIds = Set<String>.from(nextSelection);
      _document = rebuilt;
      _selectedElement = null;
      _editMode = false;
      _isDirty = true;
      _currentSpread = 0;
      _isQuickMenuVisible = false;
      _isTemplatePanelVisible = false;
    });
    _pageController.jumpToPage(0);
    _disposeInlineTextController();
    _resetSpreadZoom();
    _syncWorkingSectionsWithDocument(rebuilt);
  }

  AlbumBookDocument _reuseExistingCopy(
    AlbumBookDocument source,
    AlbumBookDocument target,
  ) {
    final sourceSpreads = source.spreads;
    final targetSpreads = List<AlbumSpreadModel>.from(target.spreads);
    final count = math.min(sourceSpreads.length, targetSpreads.length);
    for (var i = 0; i < count; i++) {
      final sourceSpread = sourceSpreads[i];
      final targetSpread = targetSpreads[i];
      targetSpreads[i] = targetSpread.copyWith(
        leftPage: _reusePageCopy(sourceSpread.leftPage, targetSpread.leftPage),
        rightPage: _reusePageCopy(sourceSpread.rightPage, targetSpread.rightPage),
      );
    }
    return target.copyWith(spreads: targetSpreads);
  }

  AlbumPageModel _reusePageCopy(
    AlbumPageModel source,
    AlbumPageModel target,
  ) {
    final sourceTexts = _pageTextsByRole(source);
    final nextElements = target.elements.map((element) {
      if (element.type != AlbumElementType.text &&
          element.type != AlbumElementType.subtitle) {
        return element;
      }
      final role = element.payload['role']?.toString().trim() ?? '';
      final replacement = sourceTexts[role];
      if (replacement == null || replacement.trim().isEmpty) {
        return element;
      }
      final payload = Map<String, dynamic>.from(element.payload);
      payload['text'] = replacement.trim();
      return element.copyWith(payload: payload);
    }).toList(growable: false);
    return target.copyWith(elements: nextElements);
  }

  Map<String, String> _pageTextsByRole(AlbumPageModel page) {
    final texts = <String, String>{};
    for (final element in page.elements) {
      if (element.type != AlbumElementType.text &&
          element.type != AlbumElementType.subtitle) {
        continue;
      }
      final role = element.payload['role']?.toString().trim() ?? '';
      final text = element.payload['text']?.toString().trim() ?? '';
      if (role.isEmpty || text.isEmpty || texts.containsKey(role)) {
        continue;
      }
      texts[role] = text;
    }
    return texts;
  }

  void _dismissFloatingMenus() {
    if (!_isQuickMenuVisible && !_isTemplatePanelVisible) {
      return;
    }
    setState(() {
      _isQuickMenuVisible = false;
      _isTemplatePanelVisible = false;
      _templateDraftIds = Set<String>.from(_selectedTemplateIds);
    });
  }

  void _toggleQuickMenu() {
    setState(() {
      final next = !_isQuickMenuVisible;
      _isQuickMenuVisible = next;
      _isTemplatePanelVisible = false;
      _templateDraftIds = Set<String>.from(_selectedTemplateIds);
    });
  }

  void _toggleTemplatePanel() {
    setState(() {
      _isQuickMenuVisible = true;
      final next = !_isTemplatePanelVisible;
      _isTemplatePanelVisible = next;
      if (next) {
        _templateDraftIds = Set<String>.from(_selectedTemplateIds);
      }
    });
  }

  void _toggleTemplateDraft(String templateId) {
    setState(() {
      if (_templateDraftIds.contains(templateId)) {
        _templateDraftIds.remove(templateId);
      } else {
        _templateDraftIds.add(templateId);
      }
    });
  }

  void _applyTemplateDraft() {
    _applyTemplateSelection(Set<String>.from(_templateDraftIds));
  }

  Future<bool> _saveBook() async {
    final document = _document;
    if (_isSaving || document == null) {
      return false;
    }
    if (widget.storyEntityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前故事缺少存储 ID，暂时无法保存数字相册')),
      );
      return false;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _bookService.save(
        storyId: widget.storyEntityId!,
        document: document,
      );
      if (!mounted) {
        return false;
      }
      setState(() {
        _hasSaved = true;
        _isDirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('数字相册书已保存')),
      );
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $error')),
      );
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _closePage() async {
    _commitInlineTextIfNeeded();
    _clearEditingSelection();
    if (_isDirty && mounted) {
      final shouldSave = await showDialog<bool?>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('保存数字相册？'),
            content: const Text('当前相册还有未保存的修改，离开前要先保存吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('直接离开'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('保存并离开'),
              ),
            ],
          );
        },
      );
      if (shouldSave == null) {
        return;
      }
      if (shouldSave) {
        final saved = await _saveBook();
        if (!saved) {
          return;
        }
      }
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(
      DigitalAlbumBookResult(
        saved: _hasSaved,
        document: _document,
      ),
    );
  }

  bool get _canPerformPageTurn =>
      _selectedElement == null &&
      !_editMode &&
      !_isSpreadZoomed &&
      !_isInlineTextEditing;

  bool get _isTurnActive => _turnFromSpread != null && _turnToSpread != null;

  void _handleTurnStatusChanged(AnimationStatus status) {
    if (!_isTurnActive) {
      return;
    }
    if (status == AnimationStatus.completed && _turnCommitOnComplete) {
      final target = _turnToSpread;
      if (target != null) {
        _pageController.jumpToPage(target);
        if (mounted) {
          setState(() {
            _currentSpread = target;
            _selectedElement = null;
          });
        }
        _disposeInlineTextController();
        _inlineTextFocusNode.unfocus();
        _resetSpreadZoom();
      }
      _resetTurnState(resetController: false);
      _turnController.value = 0;
      return;
    }

    if (status == AnimationStatus.dismissed ||
        (status == AnimationStatus.completed && !_turnCommitOnComplete)) {
      _resetTurnState(resetController: false);
      if (_turnController.value != 0) {
        _turnController.value = 0;
      }
    }
  }

  void _resetTurnState({bool resetController = true}) {
    _turnCommitOnComplete = false;
    _turnFromSpread = null;
    _turnToSpread = null;
    _turnDragDelta = 0;
    _turnDragExtent = 1;
    if (resetController) {
      _turnController.stop();
      _turnController.value = 0;
    }
    if (mounted) {
      setState(() {});
    }
  }

  bool _beginTurn({
    required int targetSpread,
    required bool forward,
    double initialProgress = 0,
  }) {
    final document = _document;
    if (document == null ||
        targetSpread < 0 ||
        targetSpread >= document.spreads.length ||
        targetSpread == _currentSpread) {
      return false;
    }
    _turnController.stop();
    _turnCommitOnComplete = false;
    _turnFromSpread = _currentSpread;
    _turnToSpread = targetSpread;
    _turnForward = forward;
    _turnController.value = initialProgress.clamp(0.0, 1.0);
    if (mounted) {
      setState(() {});
    }
    return true;
  }

  void _animateTurnTo({
    required bool commit,
    Duration duration = const Duration(milliseconds: 520),
    Curve curve = Curves.easeOutCubic,
  }) {
    if (!_isTurnActive) {
      return;
    }
    _turnCommitOnComplete = commit;
    final target = commit ? 1.0 : 0.0;
    _turnController.animateTo(
      target,
      duration: duration,
      curve: curve,
    );
  }

  void _handleTurnDragStart(double spreadWidth) {
    if (!_canPerformPageTurn || _isTurnActive) {
      return;
    }
    _turnDragExtent = math.max(spreadWidth, 1);
    _turnDragDelta = 0;
  }

  void _handleTurnDragUpdate(double deltaDx, double spreadWidth) {
    if (!_canPerformPageTurn) {
      return;
    }

    _turnDragExtent = math.max(spreadWidth, 1);
    _turnDragDelta += deltaDx;

    if (!_isTurnActive) {
      if (_turnDragDelta < -8 && _currentSpread < (_document?.spreads.length ?? 0) - 1) {
        if (!_beginTurn(
          targetSpread: _currentSpread + 1,
          forward: true,
        )) {
          return;
        }
      } else if (_turnDragDelta > 8 && _currentSpread > 0) {
        if (!_beginTurn(
          targetSpread: _currentSpread - 1,
          forward: false,
        )) {
          return;
        }
      } else {
        return;
      }
    }

    final signedProgress = _turnForward ? -_turnDragDelta : _turnDragDelta;
    final progress = (signedProgress / (_turnDragExtent * 0.84)).clamp(0.0, 1.0);
    _turnController.value = progress;
  }

  void _handleTurnDragEnd(double primaryVelocity) {
    if (!_isTurnActive) {
      _turnDragDelta = 0;
      return;
    }
    final progress = _turnController.value;
    final shouldCommit = progress > 0.34 ||
        (_turnForward ? primaryVelocity < -420 : primaryVelocity > 420);
    _animateTurnTo(
      commit: shouldCommit,
      duration: Duration(
        milliseconds: shouldCommit
            ? math.max(220, ((1 - progress) * 420).round())
            : math.max(180, (progress * 320).round()),
      ),
      curve: shouldCommit ? Curves.easeOutQuart : Curves.easeOutCubic,
    );
  }

  void _handleTurnDragCancel() {
    if (!_isTurnActive) {
      _turnDragDelta = 0;
      return;
    }
    _animateTurnTo(
      commit: false,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToSpread(int index) {
    final document = _document;
    if (document == null || index < 0 || index >= document.spreads.length) {
      return;
    }
    if (_isTurnActive || !_canPerformPageTurn) {
      return;
    }
    if (index == _currentSpread) {
      return;
    }
    _resetSpreadZoom();
    final delta = index - _currentSpread;
    if (delta.abs() != 1) {
      _pageController.jumpToPage(index);
      setState(() {
        _currentSpread = index;
        _selectedElement = null;
      });
      return;
    }
    _beginTurn(
      targetSpread: index,
      forward: delta > 0,
    );
    _animateTurnTo(
      commit: true,
      duration: const Duration(milliseconds: 860),
      curve: Curves.easeInOutCubic,
    );
  }

  void _selectElement(
    int spreadIndex,
    AlbumPageSide side,
    String elementId,
  ) {
    _commitInlineTextIfNeeded();
    final document = _document;
    AlbumElementModel? tappedElement;
    if (document != null && spreadIndex >= 0 && spreadIndex < document.spreads.length) {
      final spread = document.spreads[spreadIndex];
      final page = side == AlbumPageSide.left ? spread.leftPage : spread.rightPage;
      for (final element in page.elements) {
        if (element.id == elementId) {
          tappedElement = element;
          break;
        }
      }
    }
    final previous = _selectedElement;
    final isSameSelection =
        previous != null &&
        previous.spreadIndex == spreadIndex &&
        previous.side == side &&
        previous.elementId == elementId;
    _cancelPendingCrossPageSwitch();
    _textUndoSeedElementId = null;
    _gestureUndoSeedElementId = null;
    final isTextTarget = _isTextElement(tappedElement);
    final shouldFocusText = isTextTarget && isSameSelection;
    setState(() {
      _editMode = !isTextTarget;
      _isInlineTextEditing = shouldFocusText;
      _selectedElement = _SelectedElementRef(
        spreadIndex: spreadIndex,
        side: side,
        elementId: elementId,
      );
    });
    if (isTextTarget) {
      _syncInlineTextEditor(requestFocus: shouldFocusText);
      return;
    }
    _syncInlineTextEditor(requestFocus: false);
  }

  void _clearEditingSelection() {
    _commitInlineTextIfNeeded();
    _finishManipulationGesture();
    setState(() {
      _editMode = false;
      _isInlineTextEditing = false;
      _gestureUndoSeedElementId = null;
      _selectedElement = null;
    });
    _disposeInlineTextController();
    _inlineTextFocusNode.unfocus();
  }

  void _handleBlankLongPress(
    int spreadIndex,
    AlbumPageSide side,
    Offset normalizedOffset,
  ) {
    // Intentionally no-op: adding content is now surfaced from the quick menu.
  }

  AlbumElementModel? get _selectedElementModel {
    final document = _document;
    final ref = _selectedElement;
    if (document == null || ref == null) {
      return null;
    }
    final spread = document.spreads[ref.spreadIndex];
    final page = ref.side == AlbumPageSide.left ? spread.leftPage : spread.rightPage;
    for (final element in page.elements) {
      if (element.id == ref.elementId) {
        return element;
      }
    }
    return null;
  }

  void _updateSelectedElement(AlbumElementModel Function(AlbumElementModel current) transform) {
    final document = _document;
    final ref = _selectedElement;
    if (document == null || ref == null) {
      return;
    }

    final spreads = List<AlbumSpreadModel>.from(document.spreads);
    final spread = spreads[ref.spreadIndex];
    final sourcePage = ref.side == AlbumPageSide.left ? spread.leftPage : spread.rightPage;
    final updatedElements = sourcePage.elements
        .map((element) => element.id == ref.elementId ? transform(element) : element)
        .toList(growable: false);
    final updatedPage = sourcePage.copyWith(elements: updatedElements);

    spreads[ref.spreadIndex] = ref.side == AlbumPageSide.left
        ? spread.copyWith(leftPage: updatedPage)
        : spread.copyWith(rightPage: updatedPage);

    final sanitized = _sanitize(document.copyWith(spreads: spreads));
    setState(() {
      _document = sanitized;
      _isDirty = true;
    });
    _syncWorkingSectionsWithDocument(sanitized);
  }

  _PageInsertionTarget _resolveInsertionTarget(AlbumBookDocument document) {
    final selected = _selectedElement;
    if (selected != null) {
      return _PageInsertionTarget(
        spreadIndex: selected.spreadIndex,
        side: selected.side,
      );
    }

    final spread = document.spreads[_currentSpread];
    final leftCount = spread.leftPage.elements.length;
    final rightCount = spread.rightPage.elements.length;
    return _PageInsertionTarget(
      spreadIndex: _currentSpread,
      side: leftCount <= rightCount ? AlbumPageSide.left : AlbumPageSide.right,
    );
  }

  void _insertElementOnPage({
    required int spreadIndex,
    required AlbumPageSide side,
    required AlbumElementModel element,
    bool startEditMode = true,
  }) {
    final document = _document;
    if (document == null) {
      return;
    }
    _pushUndoSnapshot();

    final spreads = List<AlbumSpreadModel>.from(document.spreads);
    final spread = spreads[spreadIndex];
    final page = side == AlbumPageSide.left ? spread.leftPage : spread.rightPage;
    final nextElements = List<AlbumElementModel>.from(page.elements)..add(element);
    final updatedPage = page.copyWith(elements: nextElements);

    spreads[spreadIndex] = side == AlbumPageSide.left
        ? spread.copyWith(leftPage: updatedPage)
        : spread.copyWith(rightPage: updatedPage);

    setState(() {
      _document = document.copyWith(spreads: spreads);
      _editMode = startEditMode;
      _isInlineTextEditing = false;
      _isDirty = true;
      _selectedElement = _SelectedElementRef(
        spreadIndex: spreadIndex,
        side: side,
        elementId: element.id,
      );
    });
    _syncInlineTextEditor();
    _syncWorkingSectionsWithDocument(_document!);
  }

  void _cancelPendingCrossPageSwitch() {
    _crossPageSwitchTimer?.cancel();
    _crossPageSwitchTimer = null;
    _crossPagePendingElementId = null;
    _crossPagePendingSpreadIndex = null;
    _crossPagePendingTargetSide = null;
    _crossPagePendingLocalX = null;
    _crossPagePendingLocalY = null;
  }

  void _finishManipulationGesture() {
    _cancelPendingCrossPageSwitch();
    _gestureUndoSeedElementId = null;
  }

  void _commitSelectedElementMove({
    required _SelectedElementRef ref,
    required AlbumElementModel selected,
    required AlbumPageSide nextSide,
    required double localX,
    required double localY,
  }) {
    final document = _document;
    if (document == null) {
      return;
    }

    final spreads = List<AlbumSpreadModel>.from(document.spreads);
    final spread = spreads[ref.spreadIndex];
    final sourcePage = ref.side == AlbumPageSide.left ? spread.leftPage : spread.rightPage;
    final movedElement = selected.copyWith(x: localX, y: localY);

    if (nextSide == ref.side) {
      final updatedElements = sourcePage.elements
          .map((element) => element.id == ref.elementId ? movedElement : element)
          .toList(growable: false);
      final updatedPage = sourcePage.copyWith(elements: updatedElements);
      spreads[ref.spreadIndex] = ref.side == AlbumPageSide.left
          ? spread.copyWith(leftPage: updatedPage)
          : spread.copyWith(rightPage: updatedPage);
    } else {
      final sourceElements = sourcePage.elements
          .where((element) => element.id != ref.elementId)
          .toList(growable: false);
      final targetPage = nextSide == AlbumPageSide.left ? spread.leftPage : spread.rightPage;
      final targetElements = List<AlbumElementModel>.from(targetPage.elements)..add(movedElement);
      spreads[ref.spreadIndex] = nextSide == AlbumPageSide.left
          ? spread.copyWith(
              leftPage: targetPage.copyWith(elements: targetElements),
              rightPage: sourcePage.copyWith(elements: sourceElements),
            )
          : spread.copyWith(
              leftPage: sourcePage.copyWith(elements: sourceElements),
              rightPage: targetPage.copyWith(elements: targetElements),
            );
    }

    setState(() {
      _document = document.copyWith(spreads: spreads);
      _selectedElement = _SelectedElementRef(
        spreadIndex: ref.spreadIndex,
        side: nextSide,
        elementId: ref.elementId,
      );
      _isDirty = true;
    });
    _syncWorkingSectionsWithDocument(_document!);
  }

  void _scheduleCrossPageSwitch({
    required _SelectedElementRef ref,
    required AlbumElementModel selected,
    required AlbumPageSide targetSide,
    required double localX,
    required double localY,
  }) {
    final isSamePending = _crossPagePendingElementId == ref.elementId &&
        _crossPagePendingSpreadIndex == ref.spreadIndex &&
        _crossPagePendingTargetSide == targetSide;
    _crossPagePendingElementId = ref.elementId;
    _crossPagePendingSpreadIndex = ref.spreadIndex;
    _crossPagePendingTargetSide = targetSide;
    _crossPagePendingLocalX = localX;
    _crossPagePendingLocalY = localY;
    if (isSamePending && _crossPageSwitchTimer != null) {
      return;
    }
    _crossPageSwitchTimer?.cancel();
    _crossPageSwitchTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted) {
        return;
      }
      final currentRef = _selectedElement;
      final currentSelected = _selectedElementModel;
      if (currentRef == null ||
          currentSelected == null ||
          currentRef.elementId != ref.elementId ||
          currentRef.spreadIndex != ref.spreadIndex ||
          _crossPagePendingElementId != ref.elementId ||
          _crossPagePendingSpreadIndex != ref.spreadIndex ||
          _crossPagePendingTargetSide != targetSide ||
          _crossPagePendingLocalX == null ||
          _crossPagePendingLocalY == null) {
        return;
      }
      _commitSelectedElementMove(
        ref: currentRef,
        selected: currentSelected,
        nextSide: targetSide,
        localX: _crossPagePendingLocalX!,
        localY: _crossPagePendingLocalY!,
      );
      _cancelPendingCrossPageSwitch();
    });
  }

  void _moveSelectedElement(Offset delta, Size pageSize) {
    final document = _document;
    final ref = _selectedElement;
    if (document == null || ref == null || pageSize.width <= 0 || pageSize.height <= 0) {
      return;
    }
    final selected = _selectedElementModel;
    if (selected == null) {
      return;
    }
    if (_gestureUndoSeedElementId != ref.elementId) {
      _pushUndoSnapshot();
      _gestureUndoSeedElementId = ref.elementId;
    }

    const gutterWidth = 9.0;
    final pageWidth = pageSize.width;
    final spreadWidth = (pageWidth * 2) + gutterWidth;
    final currentLeftInSpread = ref.side == AlbumPageSide.left
        ? selected.x * pageWidth
        : pageWidth + gutterWidth + (selected.x * pageWidth);
    final currentTop = selected.y * pageSize.height;
    final elementWidth = selected.w * pageWidth;
    final elementHeight = selected.h * pageSize.height;

    final nextLeftInSpread =
        (currentLeftInSpread + delta.dx).clamp(0.0, spreadWidth - elementWidth).toDouble();
    final nextTop =
        (currentTop + delta.dy).clamp(0.0, pageSize.height - elementHeight).toDouble();
    final rightEdge = nextLeftInSpread + elementWidth;
    final rightPageOrigin = pageWidth + gutterWidth;
    const seamHoldThreshold = 4.0;
    final wantsSwitchToRight =
        ref.side == AlbumPageSide.left && delta.dx > 0 && rightEdge >= (pageWidth - seamHoldThreshold);
    final wantsSwitchToLeft = ref.side == AlbumPageSide.right &&
        delta.dx < 0 &&
        nextLeftInSpread <= (rightPageOrigin + seamHoldThreshold);

    if (wantsSwitchToRight || wantsSwitchToLeft) {
      final targetSide = wantsSwitchToRight ? AlbumPageSide.right : AlbumPageSide.left;
      final heldLeftInSpread = wantsSwitchToRight
          ? pageWidth - elementWidth
          : rightPageOrigin;
      final heldPageOriginX = ref.side == AlbumPageSide.left ? 0.0 : rightPageOrigin;
      final heldLocalX =
          ((heldLeftInSpread - heldPageOriginX) / pageWidth).clamp(0.0, 0.98 - selected.w)
              as num;
      final heldLocalY = (nextTop / pageSize.height).clamp(0.0, 0.98 - selected.h) as num;
      _commitSelectedElementMove(
        ref: ref,
        selected: selected,
        nextSide: ref.side,
        localX: heldLocalX.toDouble(),
        localY: heldLocalY.toDouble(),
      );

      final targetLocalY = (nextTop / pageSize.height).clamp(0.0, 0.98 - selected.h) as num;
      _scheduleCrossPageSwitch(
        ref: ref,
        selected: selected,
        targetSide: targetSide,
        localX: wantsSwitchToRight ? 0.0 : (0.98 - selected.w).clamp(0.0, 0.98).toDouble(),
        localY: targetLocalY.toDouble(),
      );
      return;
    }

    _cancelPendingCrossPageSwitch();
    final pageOriginX = ref.side == AlbumPageSide.left ? 0.0 : rightPageOrigin;
    final localX = ((nextLeftInSpread - pageOriginX) / pageWidth).clamp(0.0, 0.98 - selected.w)
        as num;
    final localY = (nextTop / pageSize.height).clamp(0.0, 0.98 - selected.h) as num;
    _commitSelectedElementMove(
      ref: ref,
      selected: selected,
      nextSide: ref.side,
      localX: localX.toDouble(),
      localY: localY.toDouble(),
    );
  }

  void _resizeSelectedElement(Offset delta, Size pageSize) {
    if (pageSize.width <= 0 || pageSize.height <= 0) {
      return;
    }
    final ref = _selectedElement;
    if (ref != null && _gestureUndoSeedElementId != ref.elementId) {
      _pushUndoSnapshot();
      _gestureUndoSeedElementId = ref.elementId;
    }
    _updateSelectedElement((current) {
      final nextW = ((current.w + (delta.dx / pageSize.width)).clamp(0.06, 0.98 - current.x)
              as num)
          .toDouble();
      final nextH = ((current.h + (delta.dy / pageSize.height)).clamp(0.04, 0.98 - current.y)
              as num)
          .toDouble();
      return current.copyWith(w: nextW, h: nextH);
    });
  }

  Future<void> _addTextElement({required AlbumElementType type}) async {
    final document = _document;
    if (document == null) {
      return;
    }

    final target = _resolveInsertionTarget(document);
    final page = target.side == AlbumPageSide.left
        ? document.spreads[target.spreadIndex].leftPage
        : document.spreads[target.spreadIndex].rightPage;
    final nextZ = page.elements
            .where((item) => item.type == AlbumElementType.text || item.type == AlbumElementType.subtitle)
            .fold<int>(0, (maxZ, item) => math.max(maxZ, item.zIndex)) +
        1;
    final element = AlbumElementModel(
      id: '${type.name}_${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      x: 0.12,
      y: type == AlbumElementType.subtitle ? 0.14 : 0.28,
      w: type == AlbumElementType.subtitle ? 0.62 : 0.52,
      h: type == AlbumElementType.subtitle ? 0.12 : 0.16,
      rotation: 0,
      zIndex: nextZ,
      locked: false,
      payload: <String, dynamic>{
        'role': type == AlbumElementType.subtitle ? 'subtitle' : 'body',
        'text': type == AlbumElementType.subtitle ? '新的题签' : '新的文字内容',
      },
      style: AlbumElementStyle(
        fontId: type == AlbumElementType.subtitle ? 'display_modern' : 'sans_clean',
        fontSize: type == AlbumElementType.subtitle ? 26 : 18,
        colorToken: type == AlbumElementType.subtitle ? 'ink_black' : 'ink_soft',
        weight: type == AlbumElementType.subtitle ? '700' : '400',
        shadow: type == AlbumElementType.subtitle,
      ),
    );

    _insertElementOnPage(
      spreadIndex: target.spreadIndex,
      side: target.side,
      element: element,
      startEditMode: false,
    );
  }

  Future<void> _addImageElement() async {
    final document = _document;
    if (document == null) {
      return;
    }

    final result = await Navigator.of(context).push<List<VlmPhotoPickerResult>>(
      MaterialPageRoute<List<VlmPhotoPickerResult>>(
        builder: (BuildContext context) => const VlmPhotoPickerPage(),
      ),
    );
    final picked = result == null || result.isEmpty ? null : result.first;
    if (picked == null) {
      return;
    }

    final target = _resolveInsertionTarget(document);
    final page = target.side == AlbumPageSide.left
        ? document.spreads[target.spreadIndex].leftPage
        : document.spreads[target.spreadIndex].rightPage;
    final nextZ = page.elements
            .where((item) => item.type == AlbumElementType.image)
            .fold<int>(0, (maxZ, item) => math.max(maxZ, item.zIndex)) +
        1;
    final element = AlbumElementModel(
      id: 'image_${DateTime.now().microsecondsSinceEpoch}',
      type: AlbumElementType.image,
      x: 0.12,
      y: 0.16,
      w: 0.62,
      h: 0.44,
      rotation: 0,
      zIndex: nextZ,
      locked: false,
      payload: <String, dynamic>{
        'role': 'photo',
        'photo_id': picked.assetId,
        'path': picked.path,
        'date_taken': picked.createdAt.toIso8601String(),
        'crop': <String, dynamic>{
          'mode': 'cover',
          'focus_x': 0.5,
          'focus_y': 0.5,
        },
      },
      style: const AlbumElementStyle(borderRadius: 0.06),
    );

    _insertElementOnPage(
      spreadIndex: target.spreadIndex,
      side: target.side,
      element: element,
    );
  }

  Future<void> _replaceSelectedImage() async {
    final element = _selectedElementModel;
    if (element == null || element.type != AlbumElementType.image) {
      return;
    }

    final result = await Navigator.of(context).push<List<VlmPhotoPickerResult>>(
      MaterialPageRoute<List<VlmPhotoPickerResult>>(
        builder: (BuildContext context) => const VlmPhotoPickerPage(),
      ),
    );
    final replacement = result == null || result.isEmpty ? null : result.first;
    if (replacement == null) {
      return;
    }

    _pushUndoSnapshot();
    _updateSelectedElement((current) {
      final payload = Map<String, dynamic>.from(current.payload);
      payload['photo_id'] = replacement.assetId;
      payload['path'] = replacement.path;
      payload['date_taken'] = replacement.createdAt.toIso8601String();
      return current.copyWith(payload: payload);
    });
  }

  void _deleteSelectedElement() {
    final document = _document;
    final ref = _selectedElement;
    if (document == null || ref == null) {
      return;
    }
    _pushUndoSnapshot();
    _disposeInlineTextController();

    final spreads = List<AlbumSpreadModel>.from(document.spreads);
    final spread = spreads[ref.spreadIndex];
    final page = ref.side == AlbumPageSide.left ? spread.leftPage : spread.rightPage;
    final nextElements = page.elements
        .where((element) => element.id != ref.elementId)
        .toList(growable: false);
    final updatedPage = page.copyWith(elements: nextElements);

    spreads[ref.spreadIndex] = ref.side == AlbumPageSide.left
        ? spread.copyWith(leftPage: updatedPage)
        : spread.copyWith(rightPage: updatedPage);

    setState(() {
      _document = document.copyWith(spreads: spreads);
      _selectedElement = null;
      _editMode = false;
      _isDirty = true;
    });
    _syncWorkingSectionsWithDocument(_document!);
  }

  void _bringSelectedToFront() {
    final document = _document;
    final ref = _selectedElement;
    final selected = _selectedElementModel;
    if (document == null || ref == null || selected == null) {
      return;
    }

    final spread = document.spreads[ref.spreadIndex];
    final page = ref.side == AlbumPageSide.left ? spread.leftPage : spread.rightPage;
    if (selected.type == AlbumElementType.image) {
      final topImageZ = page.elements
          .where((item) => item.type == AlbumElementType.image)
          .fold<int>(0, (maxZ, item) => math.max(maxZ, item.zIndex));
      _updateSelectedElement((current) => current.copyWith(zIndex: topImageZ + 1));
      return;
    }
    final topZ = page.elements.fold<int>(0, (maxZ, item) => math.max(maxZ, item.zIndex));
    _updateSelectedElement((current) => current.copyWith(zIndex: topZ + 1));
  }

  bool get _isSelectedTextElement {
    final selected = _selectedElementModel;
    return selected != null &&
        (selected.type == AlbumElementType.text || selected.type == AlbumElementType.subtitle);
  }

  void _startEditingSelectedText() {
    if (!_isSelectedTextElement) {
      return;
    }
    setState(() {
      _isInlineTextEditing = true;
    });
    _syncInlineTextEditor(requestFocus: true);
  }

  void _toggleSelectedTextBold() {
    if (!_isSelectedTextElement) {
      return;
    }
    _commitInlineTextIfNeeded();
    _pushUndoSnapshot();
    _updateSelectedElement((current) {
      final nextWeight = current.style.weight == '700' ? '400' : '700';
      return current.copyWith(style: current.style.copyWith(weight: nextWeight));
    });
  }

  void _setSelectedTextFontSize(double fontSize) {
    if (!_isSelectedTextElement) {
      return;
    }
    _commitInlineTextIfNeeded();
    _pushUndoSnapshot();
    _updateSelectedElement((current) {
      return current.copyWith(
        style: current.style.copyWith(fontSize: fontSize.clamp(10.0, 44.0)),
      );
    });
  }

  void _setSelectedTextColorToken(String colorToken) {
    if (!_isSelectedTextElement) {
      return;
    }
    _commitInlineTextIfNeeded();
    _pushUndoSnapshot();
    _updateSelectedElement((current) {
      return current.copyWith(style: current.style.copyWith(colorToken: colorToken));
    });
  }

  void _setSelectedTextAlign(AlbumTextAlignValue align) {
    if (!_isSelectedTextElement) {
      return;
    }
    _commitInlineTextIfNeeded();
    _pushUndoSnapshot();
    _updateSelectedElement((current) {
      return current.copyWith(style: current.style.copyWith(align: align));
    });
  }

  Widget _buildToolbarMenu<T>({
    required String label,
    required List<PopupMenuEntry<T>> items,
    required void Function(T value) onSelected,
    Color backgroundColor = Colors.white,
    Color foregroundColor = const Color(0xFF5B3D36),
  }) {
    return Material(
      color: backgroundColor,
      elevation: 1,
      borderRadius: BorderRadius.circular(999),
      child: PopupMenuButton<T>(
        tooltip: '',
        onSelected: onSelected,
        itemBuilder: (context) => items,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: foregroundColor,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 18, color: foregroundColor),
            ],
          ),
        ),
      ),
    );
  }

  Rect? _selectionRectInSpread(Size spreadSize) {
    final selected = _selectedElementModel;
    final ref = _selectedElement;
    if (selected == null || ref == null) {
      return null;
    }
    const gutterWidth = 9.0;
    final pageWidth = (spreadSize.width - gutterWidth).clamp(0.0, double.infinity) / 2;
    final pageOriginX = ref.side == AlbumPageSide.left ? 0.0 : pageWidth + gutterWidth;
    return Rect.fromLTWH(
      pageOriginX + selected.x * pageWidth,
      selected.y * spreadSize.height,
      selected.w * pageWidth,
      selected.h * spreadSize.height,
    );
  }

  Offset? _selectionAnchorInSpread(Size spreadSize) {
    final elementRect = _selectionRectInSpread(spreadSize);
    if (elementRect != null) {
      return Offset(elementRect.center.dx, elementRect.top);
    }
    return null;
  }

  Size _computeSpreadSize(
    AlbumBookDocument document,
    Size viewportSize,
    EdgeInsets safePadding,
  ) {
    final rawSpreadAspect = (document.pageWidth * 2) / document.pageHeight;
    final screenAspect = viewportSize.width / viewportSize.height;
    final targetAspect = screenAspect * 0.998;
    final spreadAspect =
        rawSpreadAspect > targetAspect ? targetAspect : rawSpreadAspect;
    final horizontalPadding = safePadding.left + safePadding.right;
    final verticalPadding = safePadding.top + safePadding.bottom;
    final maxWidth = viewportSize.width - horizontalPadding;
    final maxHeight = viewportSize.height - verticalPadding;

    var spreadWidth = maxWidth;
    var spreadHeight = spreadWidth / spreadAspect;
    if (spreadHeight > maxHeight) {
      spreadHeight = maxHeight;
      spreadWidth = spreadHeight * spreadAspect;
    }
    return Size(spreadWidth, spreadHeight);
  }

  Widget _buildToolbarChip({
    required String label,
    required VoidCallback onTap,
    Color backgroundColor = Colors.white,
    Color foregroundColor = const Color(0xFF5B3D36),
  }) {
    return Material(
      color: backgroundColor,
      elevation: 1,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: foregroundColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionToolbarOverlay(Size canvasSize, Size spreadSize) {
    final anchor = _selectionAnchorInSpread(spreadSize);
    if (anchor == null) {
      return const SizedBox.shrink();
    }

    final selected = _selectedElementModel;
    final isImage = selected?.type == AlbumElementType.image;
    final isText = selected != null &&
        (selected.type == AlbumElementType.text || selected.type == AlbumElementType.subtitle);
    if (!isImage && !isText) {
      return const SizedBox.shrink();
    }
    final toolbarWidth = isText ? 372.0 : 240.0;
    final toolbarHeight = isText ? 64.0 : 112.0;
    final spreadLeft = ((canvasSize.width - spreadSize.width) / 2).clamp(0.0, canvasSize.width);
    final spreadTop = ((canvasSize.height - spreadSize.height) / 2).clamp(0.0, canvasSize.height);
    final desiredLeft = spreadLeft + anchor.dx - (toolbarWidth / 2);
    final maxLeft = math.max(12.0, canvasSize.width - toolbarWidth - 12);
    final left = desiredLeft.clamp(12.0, maxLeft);
    final preferAbove = anchor.dy > 120;
    final desiredTop = spreadTop + (preferAbove ? anchor.dy - toolbarHeight - 14 : anchor.dy + 14);
    final maxTop = math.max(12.0, canvasSize.height - toolbarHeight - 12);
    final top = desiredTop.clamp(12.0, maxTop);

    return Positioned(
      left: left,
      top: top,
      width: toolbarWidth,
      child: Material(
        color: Colors.white.withValues(alpha: 0.97),
        elevation: 10,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, isText ? 10 : 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (isImage) ...[
                      _buildToolbarChip(label: '更换图片', onTap: _replaceSelectedImage),
                      const SizedBox(width: 8),
                      _buildToolbarChip(label: '置于顶层', onTap: _bringSelectedToFront),
                      const SizedBox(width: 8),
                      _buildToolbarChip(label: '删除', onTap: _deleteSelectedElement),
                      const SizedBox(width: 8),
                      _buildToolbarChip(label: '完成', onTap: _clearEditingSelection),
                    ],
                    if (isText) ...[
                      _buildToolbarChip(
                        label: _isInlineTextEditing ? '完成编辑' : '编辑',
                        onTap: _isInlineTextEditing ? _clearEditingSelection : _startEditingSelectedText,
                      ),
                      const SizedBox(width: 8),
                      _buildToolbarMenu<double>(
                        label: '字号',
                        onSelected: _setSelectedTextFontSize,
                        items: const [
                          PopupMenuItem(value: 14, child: Text('14')),
                          PopupMenuItem(value: 18, child: Text('18')),
                          PopupMenuItem(value: 22, child: Text('22')),
                          PopupMenuItem(value: 26, child: Text('26')),
                          PopupMenuItem(value: 30, child: Text('30')),
                          PopupMenuItem(value: 36, child: Text('36')),
                        ],
                      ),
                      const SizedBox(width: 8),
                      _buildToolbarMenu<String>(
                        label: '颜色',
                        onSelected: _setSelectedTextColorToken,
                        items: const [
                          PopupMenuItem(value: 'ink_black', child: Text('墨黑')),
                          PopupMenuItem(value: 'ink_soft', child: Text('柔墨')),
                          PopupMenuItem(value: 'rose_accent', child: Text('玫粉')),
                          PopupMenuItem(value: 'gold_accent', child: Text('金棕')),
                          PopupMenuItem(value: 'sage_accent', child: Text('鼠尾草')),
                        ],
                      ),
                      const SizedBox(width: 8),
                      _buildToolbarChip(label: '加粗', onTap: _toggleSelectedTextBold),
                      const SizedBox(width: 8),
                      _buildToolbarMenu<AlbumTextAlignValue>(
                        label: '对齐',
                        onSelected: _setSelectedTextAlign,
                        items: const [
                          PopupMenuItem(
                            value: AlbumTextAlignValue.left,
                            child: Text('左对齐'),
                          ),
                          PopupMenuItem(
                            value: AlbumTextAlignValue.center,
                            child: Text('居中'),
                          ),
                          PopupMenuItem(
                            value: AlbumTextAlignValue.right,
                            child: Text('右对齐'),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      _buildToolbarChip(label: '删除', onTap: _deleteSelectedElement),
                      const SizedBox(width: 8),
                      _buildToolbarChip(label: '完成', onTap: _clearEditingSelection),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpreadCard(AlbumBookDocument document, int index) {
    return _BookSpreadCard(
      spread: document.spreads[index],
      spreadIndex: index,
      designPageWidth: document.pageWidth,
      designPageHeight: document.pageHeight,
      selected: _selectedElement,
      editMode: _editMode,
      isSpreadZoomed: _isSpreadZoomed,
      isInlineTextEditing: _isInlineTextEditing,
      editingTextElementId: _inlineEditingElementId,
      inlineTextController: _inlineTextController,
      inlineTextFocusNode: _inlineTextFocusNode,
      onElementSelected: _selectElement,
      onBlankLongPress: _handleBlankLongPress,
      onCanvasTap: _clearEditingSelection,
      onElementMoved: _moveSelectedElement,
      onElementResized: _resizeSelectedElement,
      onManipulationEnd: _finishManipulationGesture,
    );
  }

  Widget _buildReadOnlyPage({
    required int spreadIndex,
    required AlbumPageModel page,
    required double designPageWidth,
    required double designPageHeight,
  }) {
    return IgnorePointer(
      child: _AlbumCanvasPage(
        page: page,
        spreadIndex: spreadIndex,
        designPageWidth: designPageWidth,
        designPageHeight: designPageHeight,
        selected: null,
        editMode: false,
        isSpreadZoomed: false,
        isInlineTextEditing: false,
        editingTextElementId: null,
        inlineTextController: null,
        inlineTextFocusNode: _inlineTextFocusNode,
        onElementSelected: (_, _, _) {},
        onBlankLongPress: (_, _, _) {},
        onCanvasTap: () {},
        onElementMoved: (_, _) {},
        onElementResized: (_, _) {},
        onManipulationEnd: () {},
      ),
    );
  }

  Widget _buildTurnOverlay(AlbumBookDocument document) {
    if (!_isTurnActive || _turnFromSpread == null || _turnToSpread == null) {
      return const SizedBox.shrink();
    }
    final fromSpread = document.spreads[_turnFromSpread!];
    final toSpread = document.spreads[_turnToSpread!];
    final leftStatic = _turnForward
        ? _buildReadOnlyPage(
            spreadIndex: _turnFromSpread!,
            page: fromSpread.leftPage,
            designPageWidth: document.pageWidth,
            designPageHeight: document.pageHeight,
          )
        : _buildReadOnlyPage(
            spreadIndex: _turnToSpread!,
            page: toSpread.leftPage,
            designPageWidth: document.pageWidth,
            designPageHeight: document.pageHeight,
          );
    final rightStatic = _turnForward
        ? _buildReadOnlyPage(
            spreadIndex: _turnToSpread!,
            page: toSpread.rightPage,
            designPageWidth: document.pageWidth,
            designPageHeight: document.pageHeight,
          )
        : _buildReadOnlyPage(
            spreadIndex: _turnFromSpread!,
            page: fromSpread.rightPage,
            designPageWidth: document.pageWidth,
            designPageHeight: document.pageHeight,
          );
    final turningFront = _turnForward
        ? _buildReadOnlyPage(
            spreadIndex: _turnFromSpread!,
            page: fromSpread.rightPage,
            designPageWidth: document.pageWidth,
            designPageHeight: document.pageHeight,
          )
        : _buildReadOnlyPage(
            spreadIndex: _turnFromSpread!,
            page: fromSpread.leftPage,
            designPageWidth: document.pageWidth,
            designPageHeight: document.pageHeight,
          );
    final turningBack = _turnForward
        ? _buildReadOnlyPage(
            spreadIndex: _turnToSpread!,
            page: toSpread.leftPage,
            designPageWidth: document.pageWidth,
            designPageHeight: document.pageHeight,
          )
        : _buildReadOnlyPage(
            spreadIndex: _turnToSpread!,
            page: toSpread.rightPage,
            designPageWidth: document.pageWidth,
            designPageHeight: document.pageHeight,
          );
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _turnController,
        builder: (BuildContext context, Widget? child) {
          final progress = _turnController.value.clamp(0.0, 1.0);
          return _BookPageTurnScene(
            progress: progress,
            forward: _turnForward,
            leftStaticPage: leftStatic,
            rightStaticPage: rightStatic,
            turningFrontPage: turningFront,
            turningBackPage: turningBack,
          );
        },
      ),
    );
  }

  Widget _buildTurnGestureLayer(double spreadWidth) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _handleTurnDragStart(spreadWidth),
        onHorizontalDragUpdate: (details) =>
            _handleTurnDragUpdate(details.delta.dx, spreadWidth),
        onHorizontalDragEnd: (details) =>
            _handleTurnDragEnd(details.primaryVelocity ?? 0),
        onHorizontalDragCancel: _handleTurnDragCancel,
        child: const SizedBox.expand(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final viewportSize = MediaQuery.sizeOf(context);
    final viewportPadding = MediaQuery.paddingOf(context);
    final overlaySpreadSize = document == null
        ? Size.zero
        : _computeSpreadSize(document, viewportSize, viewportPadding);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_closePage());
        }
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowLeft): _PrevSpreadIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight): _NextSpreadIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _PrevSpreadIntent: CallbackAction<_PrevSpreadIntent>(
              onInvoke: (intent) {
                _goToSpread(_currentSpread - 1);
                return null;
              },
            ),
            _NextSpreadIntent: CallbackAction<_NextSpreadIntent>(
              onInvoke: (intent) {
                _goToSpread(_currentSpread + 1);
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: const Color(0xFFE8DDD2),
              body: _isLoading || document == null
                  ? const Center(child: CircularProgressIndicator())
                  : Builder(
                      builder: (BuildContext context) {
                        final safePadding = MediaQuery.paddingOf(context);
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: LayoutBuilder(
                                builder: (BuildContext context, BoxConstraints constraints) {
                                  final rawSpreadAspect =
                                      (document.pageWidth * 2) / document.pageHeight;
                                  final screenAspect =
                                      constraints.maxWidth / constraints.maxHeight;
                                  final targetAspect = screenAspect * 0.998;
                                  final spreadAspect = rawSpreadAspect > targetAspect
                                      ? targetAspect
                                      : rawSpreadAspect;
                                  final horizontalPadding = 0.0 + safePadding.left + safePadding.right;
                                  final verticalPadding = 0.0 + safePadding.top + safePadding.bottom;
                                  final maxWidth = constraints.maxWidth - horizontalPadding;
                                  final maxHeight = constraints.maxHeight - verticalPadding;

                                  double spreadWidth = maxWidth;
                                  double spreadHeight = spreadWidth / spreadAspect;
                                  if (spreadHeight > maxHeight) {
                                    spreadHeight = maxHeight;
                                    spreadWidth = spreadHeight * spreadAspect;
                                  }

                                  return Center(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onDoubleTap: _isSpreadZoomed ? _resetSpreadZoom : null,
                                      child: InteractiveViewer(
                                        transformationController: _spreadZoomController,
                                        minScale: 1,
                                        maxScale: 3.4,
                                        panEnabled: _isSpreadZoomed,
                                        scaleEnabled: true,
                                        boundaryMargin: const EdgeInsets.all(240),
                                        clipBehavior: Clip.none,
                                        onInteractionUpdate: (_) => _syncSpreadZoomState(),
                                        onInteractionEnd: (_) => _syncSpreadZoomState(),
                                        child: SizedBox(
                                          width: spreadWidth,
                                          height: spreadHeight,
                                          child: Stack(
                                            children: [
                                              PageView.builder(
                                                controller: _pageController,
                                                physics: const NeverScrollableScrollPhysics(),
                                                itemCount: document.spreads.length,
                                                onPageChanged: (value) {
                                                  setState(() {
                                                    _currentSpread = value;
                                                    _selectedElement = null;
                                                  });
                                                  _disposeInlineTextController();
                                                  _inlineTextFocusNode.unfocus();
                                                  _resetSpreadZoom();
                                                },
                                                itemBuilder: (BuildContext context, int index) {
                                                  return _buildSpreadCard(document, index);
                                                },
                                              ),
                                              if (_isTurnActive) _buildTurnOverlay(document),
                                              if (_canPerformPageTurn)
                                                _buildTurnGestureLayer(spreadWidth),
                                              if (_selectedElement == null &&
                                                  !_editMode &&
                                                  !_isSpreadZoomed &&
                                                  !_isInlineTextEditing)
                                                Positioned.fill(
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Align(
                                                          alignment: Alignment.centerLeft,
                                                          child: GestureDetector(
                                                            behavior: HitTestBehavior.translucent,
                                                            onTap: () => _goToSpread(_currentSpread - 1),
                                                            child: const SizedBox(width: 64),
                                                          ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Align(
                                                          alignment: Alignment.centerRight,
                                                          child: GestureDetector(
                                                            behavior: HitTestBehavior.translucent,
                                                            onTap: () => _goToSpread(_currentSpread + 1),
                                                            child: const SizedBox(width: 64),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (_isAiBusy)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: safePadding.top + 2,
                                child: const LinearProgressIndicator(minHeight: 2),
                              ),
                            Positioned(
                              left: 8 + safePadding.left,
                              right: 8 + safePadding.right,
                              top: 6 + safePadding.top,
                              child: _buildTopOverlay(context),
                            ),
                            if (_selectedElement == null &&
                                !_editMode &&
                                !_isInlineTextEditing &&
                                (_isQuickMenuVisible || _isTemplatePanelVisible))
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _dismissFloatingMenus,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            if (_selectedElement == null && !_editMode && !_isInlineTextEditing)
                              Positioned(
                                left: 10 + safePadding.left,
                                bottom: 12 + safePadding.bottom,
                                child: _buildFloatingControls(context),
                              ),
                            if (_selectedElement == null &&
                                !_editMode &&
                                !_isSpreadZoomed &&
                                !_isInlineTextEditing)
                              Positioned(
                                left: 4 + safePadding.left,
                                right: 4 + safePadding.right,
                                top: 0,
                                bottom: 0,
                                child: _buildSideNavigation(document),
                              ),
                            if (_editMode)
                              _buildSelectionToolbarOverlay(
                                viewportSize,
                                overlaySpreadSize,
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopOverlay(BuildContext context) {
    return Row(
      children: [
        _buildOverlayAction(
          context: context,
          icon: Icons.arrow_back,
          tooltip: '返回',
          onTap: () => unawaited(_closePage()),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildMoreMenuButton(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      elevation: 8,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: _toggleQuickMenu,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Text(
            '···',
            style: TextStyle(
              fontSize: 20,
              height: 1,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6D4755),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isTemplatePanelVisible) ...[
          _buildTemplatePanel(),
          const SizedBox(height: 8),
        ],
        if (_isQuickMenuVisible) ...[
          _buildQuickActionTags(),
          const SizedBox(height: 8),
        ],
        _buildMoreMenuButton(context),
      ],
    );
  }

  Widget _buildQuickActionTags() {
    Widget tag(String label, VoidCallback onTap, {bool busy = false, bool active = false}) {
      return Material(
        color: active
            ? const Color(0xFFF7E7EA)
            : Colors.white.withValues(alpha: 0.96),
        elevation: 5,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5B3D36),
                    ),
                  ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tag('AI写文案', () {
              _dismissFloatingMenus();
              _handleAiCopyTap();
            }, busy: _isAiBusy),
            const SizedBox(width: 8),
            tag(
              '选择模板',
              _toggleTemplatePanel,
              active: _isTemplatePanelVisible,
            ),
            const SizedBox(width: 8),
            tag('保存', () {
              _dismissFloatingMenus();
              unawaited(_saveBook());
            }, busy: _isSaving),
            const SizedBox(width: 8),
            tag('撤回', () {
              _dismissFloatingMenus();
              _undoLastChange();
            }),
            const SizedBox(width: 8),
            tag('新增图片', () {
              _dismissFloatingMenus();
              unawaited(_addImageElement());
            }),
            const SizedBox(width: 8),
            tag('新增文案', () {
              _dismissFloatingMenus();
              unawaited(_addTextElement(type: AlbumElementType.text));
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplatePanel() {
    return Material(
      color: Colors.white.withValues(alpha: 0.98),
      elevation: 10,
      borderRadius: BorderRadius.circular(22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 340,
          maxHeight: 250,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '选择模板',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF46312C),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final templateId in DigitalAlbumLayoutService.selectableTemplateIds)
                      FilterChip(
                        label: Text(
                          DigitalAlbumLayoutService.templateLabels[templateId] ?? templateId,
                        ),
                        selected: _templateDraftIds.contains(templateId),
                        onSelected: (_) => _toggleTemplateDraft(templateId),
                        selectedColor: const Color(0xFFF6DDE3),
                        backgroundColor: const Color(0xFFF9F3F0),
                        labelStyle: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF4E342E),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        side: const BorderSide(color: Color(0xFFE6D8D0)),
                        showCheckmark: false,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _applyTemplateDraft,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6D4755),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      '确认',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayAction({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.92),
        elevation: 6,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, color: const Color(0xFF6D4755)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSideNavigation(AlbumBookDocument document) {
    return IgnorePointer(
      ignoring: document.spreads.length <= 1,
      child: Row(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _buildSideArrow(
              enabled: _currentSpread > 0,
              icon: Icons.chevron_left,
              onTap: () => _goToSpread(_currentSpread - 1),
            ),
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: _buildSideArrow(
              enabled: _currentSpread < document.spreads.length - 1,
              icon: Icons.chevron_right,
              onTap: () => _goToSpread(_currentSpread + 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideArrow({
    required bool enabled,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.22,
      child: Material(
        color: Colors.white.withValues(alpha: 0.78),
        elevation: 5,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 28, color: const Color(0xFF8C5367)),
          ),
        ),
      ),
    );
  }

}

class _BookSpreadCard extends StatelessWidget {
  const _BookSpreadCard({
    required this.spread,
    required this.spreadIndex,
    required this.designPageWidth,
    required this.designPageHeight,
    required this.selected,
    required this.editMode,
    required this.isSpreadZoomed,
    required this.isInlineTextEditing,
    required this.editingTextElementId,
    required this.inlineTextController,
    required this.inlineTextFocusNode,
    required this.onElementSelected,
    required this.onBlankLongPress,
    required this.onCanvasTap,
    required this.onElementMoved,
    required this.onElementResized,
    required this.onManipulationEnd,
  });

  final AlbumSpreadModel spread;
  final int spreadIndex;
  final double designPageWidth;
  final double designPageHeight;
  final _SelectedElementRef? selected;
  final bool editMode;
  final bool isSpreadZoomed;
  final bool isInlineTextEditing;
  final String? editingTextElementId;
  final TextEditingController? inlineTextController;
  final FocusNode inlineTextFocusNode;
  final void Function(int spreadIndex, AlbumPageSide side, String elementId) onElementSelected;
  final void Function(int spreadIndex, AlbumPageSide side, Offset normalizedOffset)
      onBlankLongPress;
  final VoidCallback onCanvasTap;
  final void Function(Offset delta, Size pageSize) onElementMoved;
  final void Function(Offset delta, Size pageSize) onElementResized;
  final VoidCallback onManipulationEnd;

  @override
  Widget build(BuildContext context) {
    return _BookSpreadShell(
      child: Row(
        children: [
          Expanded(
            child: _AlbumCanvasPage(
              page: spread.leftPage,
              spreadIndex: spreadIndex,
              designPageWidth: designPageWidth,
              designPageHeight: designPageHeight,
              selected: selected,
              editMode: editMode,
              isSpreadZoomed: isSpreadZoomed,
              isInlineTextEditing: isInlineTextEditing,
              editingTextElementId: editingTextElementId,
              inlineTextController: inlineTextController,
              inlineTextFocusNode: inlineTextFocusNode,
              onElementSelected: onElementSelected,
              onBlankLongPress: onBlankLongPress,
              onCanvasTap: onCanvasTap,
              onElementMoved: onElementMoved,
              onElementResized: onElementResized,
              onManipulationEnd: onManipulationEnd,
            ),
          ),
          const _BookSpine(),
          Expanded(
            child: _AlbumCanvasPage(
              page: spread.rightPage,
              spreadIndex: spreadIndex,
              designPageWidth: designPageWidth,
              designPageHeight: designPageHeight,
              selected: selected,
              editMode: editMode,
              isSpreadZoomed: isSpreadZoomed,
              isInlineTextEditing: isInlineTextEditing,
              editingTextElementId: editingTextElementId,
              inlineTextController: inlineTextController,
              inlineTextFocusNode: inlineTextFocusNode,
              onElementSelected: onElementSelected,
              onBlankLongPress: onBlankLongPress,
              onCanvasTap: onCanvasTap,
              onElementMoved: onElementMoved,
              onElementResized: onElementResized,
              onManipulationEnd: onManipulationEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookSpreadShell extends StatelessWidget {
  const _BookSpreadShell({
    required this.child,
    this.enableOuterShadow = true,
  });

  final Widget child;
  final bool enableOuterShadow;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 1, 0, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFE3D3C2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 1, 0, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF2E6D9),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0xFFF7EEE5),
                Color(0xFFE9DCCB),
              ],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: enableOuterShadow
                  ? const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 10,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: child,
          ),
        ),
      ],
    );
  }
}

class _BookSpine extends StatelessWidget {
  const _BookSpine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      margin: const EdgeInsets.symmetric(horizontal: 0.5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Colors.brown.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.86),
            Colors.brown.withValues(alpha: 0.14),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class _BookPageTurnScene extends StatelessWidget {
  const _BookPageTurnScene({
    required this.progress,
    required this.forward,
    required this.leftStaticPage,
    required this.rightStaticPage,
    required this.turningFrontPage,
    required this.turningBackPage,
  });

  final double progress;
  final bool forward;
  final Widget leftStaticPage;
  final Widget rightStaticPage;
  final Widget turningFrontPage;
  final Widget turningBackPage;

  @override
  Widget build(BuildContext context) {
    const spineTotalWidth = 9.0;
    final p = progress.clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(p);
    final signedAngle = (forward ? -1.0 : 1.0) * math.pi * eased;
    final halfTurn = math.pi / 2;
    final foldedness = math.sin(eased * math.pi);
    final frontVisible = signedAngle.abs() <= halfTurn;
    final spineShadow = (0.06 + foldedness * 0.12).clamp(0.0, 0.18);
    final pageShadow = (0.12 + foldedness * 0.22).clamp(0.0, 0.34);

    return _BookSpreadShell(
      enableOuterShadow: false,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final pageWidth = (constraints.maxWidth - spineTotalWidth) / 2;
          final spineCenter = pageWidth + (spineTotalWidth / 2);
          final turningFace = frontVisible
              ? turningFrontPage
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: turningBackPage,
                );

          return Stack(
            children: [
              Row(
                children: [
                  Expanded(child: leftStaticPage),
                  const _BookSpine(),
                  Expanded(child: rightStaticPage),
                ],
              ),
              Positioned(
                left: spineCenter,
                top: 0,
                bottom: 0,
                width: 0,
                child: IgnorePointer(
                  child: OverflowBox(
                    minWidth: pageWidth,
                    maxWidth: pageWidth,
                    minHeight: constraints.maxHeight,
                    maxHeight: constraints.maxHeight,
                    alignment:
                        forward ? Alignment.centerLeft : Alignment.centerRight,
                    child: _CurvedTurnPageSurface(
                      pageFace: turningFace,
                      forward: forward,
                      foldedness: foldedness,
                      signedAngle: signedAngle,
                      pageWidth: pageWidth,
                      pageHeight: constraints.maxHeight,
                      pageShadow: pageShadow,
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: <Color>[
                        Colors.transparent,
                        Colors.black.withValues(alpha: foldedness * 0.05),
                        Colors.black.withValues(alpha: spineShadow),
                        Colors.black.withValues(alpha: foldedness * 0.05),
                        Colors.transparent,
                      ],
                      stops: const <double>[0, 0.44, 0.5, 0.56, 1],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CurvedTurnPageSurface extends StatelessWidget {
  const _CurvedTurnPageSurface({
    required this.pageFace,
    required this.forward,
    required this.foldedness,
    required this.signedAngle,
    required this.pageWidth,
    required this.pageHeight,
    required this.pageShadow,
  });

  final Widget pageFace;
  final bool forward;
  final double foldedness;
  final double signedAngle;
  final double pageWidth;
  final double pageHeight;
  final double pageShadow;

  @override
  Widget build(BuildContext context) {
    final hingeAlignment = forward ? Alignment.centerLeft : Alignment.centerRight;
    final globalLiftY = -pageHeight * 0.15 * foldedness;
    final globalLiftZ = -pageWidth * 0.12 * foldedness;
    final innerShade = (0.025 + foldedness * 0.07).clamp(0.0, 0.11);
    final outerGlow = (0.015 + foldedness * 0.03).clamp(0.0, 0.05);
    final simplePhase = foldedness < 0.12;

    if (simplePhase) {
      return Transform(
        alignment: hingeAlignment,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0017)
          ..translateByDouble(0.0, globalLiftY * 0.35, globalLiftZ * 0.25, 1.0)
          ..rotateY(signedAngle),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: pageShadow * 0.55),
                blurRadius: 16,
                offset: Offset(forward ? -8 : 8, 10),
                spreadRadius: -10,
              ),
            ],
          ),
          child: SizedBox(
            width: pageWidth,
            height: pageHeight,
            child: pageFace,
          ),
        ),
      );
    }

    return Transform(
      alignment: hingeAlignment,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.00185)
        ..translateByDouble(0.0, globalLiftY, globalLiftZ, 1.0)
        ..rotateY(signedAngle),
      child: ClipPath(
        clipper: _RaisedPageClipper(
          forward: forward,
          foldedness: foldedness,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: pageShadow),
                blurRadius: 18 + foldedness * 16,
                offset: Offset(
                  forward ? -12 : 12,
                  14 + foldedness * 7,
                ),
                spreadRadius: -12,
              ),
            ],
          ),
          child: SizedBox(
            width: pageWidth,
            height: pageHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                pageFace,
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: forward ? Alignment.centerLeft : Alignment.centerRight,
                      end: forward ? Alignment.centerRight : Alignment.centerLeft,
                      colors: <Color>[
                        Colors.black.withValues(alpha: innerShade),
                        Colors.transparent,
                        Colors.white.withValues(alpha: outerGlow),
                      ],
                      stops: const <double>[0.0, 0.56, 1.0],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RaisedPageClipper extends CustomClipper<Path> {
  const _RaisedPageClipper({
    required this.forward,
    required this.foldedness,
  });

  final bool forward;
  final double foldedness;

  @override
  Path getClip(Size size) {
    final topLift = size.height * 0.16 * foldedness;
    final bottomLift = size.height * 0.08 * foldedness;
    final bellyDepth = size.height * 0.11 * foldedness;
    final path = Path();

    if (forward) {
      path.moveTo(0, 0);
      path.quadraticBezierTo(
        size.width * 0.42,
        -bellyDepth,
        size.width,
        topLift,
      );
      path.lineTo(size.width, size.height - bottomLift);
      path.quadraticBezierTo(
        size.width * 0.58,
        size.height - (bellyDepth * 0.18),
        0,
        size.height,
      );
    } else {
      path.moveTo(size.width, 0);
      path.quadraticBezierTo(
        size.width * 0.58,
        -bellyDepth,
        0,
        topLift,
      );
      path.lineTo(0, size.height - bottomLift);
      path.quadraticBezierTo(
        size.width * 0.42,
        size.height - (bellyDepth * 0.18),
        size.width,
        size.height,
      );
    }

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _RaisedPageClipper oldClipper) {
    return oldClipper.forward != forward || oldClipper.foldedness != foldedness;
  }
}

class _AlbumCanvasPage extends StatelessWidget {
  const _AlbumCanvasPage({
    required this.page,
    required this.spreadIndex,
    required this.designPageWidth,
    required this.designPageHeight,
    required this.selected,
    required this.editMode,
    required this.isSpreadZoomed,
    required this.isInlineTextEditing,
    required this.editingTextElementId,
    required this.inlineTextController,
    required this.inlineTextFocusNode,
    required this.onElementSelected,
    required this.onBlankLongPress,
    required this.onCanvasTap,
    required this.onElementMoved,
    required this.onElementResized,
    required this.onManipulationEnd,
  });

  final AlbumPageModel page;
  final int spreadIndex;
  final double designPageWidth;
  final double designPageHeight;
  final _SelectedElementRef? selected;
  final bool editMode;
  final bool isSpreadZoomed;
  final bool isInlineTextEditing;
  final String? editingTextElementId;
  final TextEditingController? inlineTextController;
  final FocusNode inlineTextFocusNode;
  final void Function(int spreadIndex, AlbumPageSide side, String elementId) onElementSelected;
  final void Function(int spreadIndex, AlbumPageSide side, Offset normalizedOffset)
      onBlankLongPress;
  final VoidCallback onCanvasTap;
  final void Function(Offset delta, Size pageSize) onElementMoved;
  final void Function(Offset delta, Size pageSize) onElementResized;
  final VoidCallback onManipulationEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final pageSize = Size(constraints.maxWidth, constraints.maxHeight);
        final pageScale = math.min(
          constraints.maxWidth / math.max(designPageWidth, 1),
          constraints.maxHeight / math.max(designPageHeight, 1),
        );
        final elements = List<AlbumElementModel>.from(page.elements)
          ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
        return Container(
          decoration: BoxDecoration(
            color: _colorFromToken(page.backgroundColorToken),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.brown.withValues(alpha: 0.08),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: (editMode || isInlineTextEditing || selected != null)
                        ? onCanvasTap
                        : null,
                    onLongPressStart: (details) => onBlankLongPress(
                      spreadIndex,
                      page.side,
                      Offset(
                        (details.localPosition.dx / pageSize.width).clamp(0.0, 1.0),
                        (details.localPosition.dy / pageSize.height).clamp(0.0, 1.0),
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.04,
                      child: Image.asset(
                        'assets/images/noise.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                for (final element in elements)
                  _ElementBox(
                    key: ValueKey<String>(element.id),
                    element: element,
                    pageScale: pageScale,
                    canManipulate: !isSpreadZoomed && !isInlineTextEditing,
                    selected: selected != null &&
                        selected!.spreadIndex == spreadIndex &&
                        selected!.side == page.side &&
                        selected!.elementId == element.id,
                    editMode: editMode,
                    isInlineTextEditing: isInlineTextEditing,
                    editingTextElementId: editingTextElementId,
                    inlineTextController: inlineTextController,
                    inlineTextFocusNode: inlineTextFocusNode,
                    pageSize: pageSize,
                    onSelect: () => onElementSelected(spreadIndex, page.side, element.id),
                    onMove: (delta) => onElementMoved(delta, pageSize),
                    onResize: (delta) => onElementResized(delta, pageSize),
                    onGestureEnd: onManipulationEnd,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ElementBox extends StatelessWidget {
  const _ElementBox({
    super.key,
    required this.element,
    required this.pageScale,
    required this.canManipulate,
    required this.selected,
    required this.editMode,
    required this.isInlineTextEditing,
    required this.editingTextElementId,
    required this.inlineTextController,
    required this.inlineTextFocusNode,
    required this.pageSize,
    required this.onSelect,
    required this.onMove,
    required this.onResize,
    required this.onGestureEnd,
  });

  final AlbumElementModel element;
  final double pageScale;
  final bool canManipulate;
  final bool selected;
  final bool editMode;
  final bool isInlineTextEditing;
  final String? editingTextElementId;
  final TextEditingController? inlineTextController;
  final FocusNode inlineTextFocusNode;
  final Size pageSize;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;
  final VoidCallback onGestureEnd;

  @override
  Widget build(BuildContext context) {
    final left = element.x * pageSize.width;
    final top = element.y * pageSize.height;
    final width = element.w * pageSize.width;
    final height = element.h * pageSize.height;
    final isSelectableElement = element.type != AlbumElementType.shape;
    final isTextEditingElement =
        selected &&
        isInlineTextEditing &&
        editingTextElementId == element.id &&
        (element.type == AlbumElementType.text || element.type == AlbumElementType.subtitle);
    final showSelectionFrame = selected && isSelectableElement;
    final showResizeHandle = canManipulate &&
        selected &&
        (element.type == AlbumElementType.image ||
            element.type == AlbumElementType.text ||
            element.type == AlbumElementType.subtitle);

    if (!isSelectableElement) {
      return Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          onLongPress: () {},
          child: Transform.rotate(
            angle: element.rotation * math.pi / 180,
            child: _buildContent(context),
          ),
        ),
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: isTextEditingElement ? null : onSelect,
        onTap: isTextEditingElement ? null : ((selected || editMode) ? onSelect : null),
        onPanUpdate: isTextEditingElement
            ? null
            : (canManipulate && selected ? (details) => onMove(details.delta) : null),
        onPanEnd: isTextEditingElement
            ? null
            : (canManipulate && selected ? (_) => onGestureEnd() : null),
        onPanCancel: isTextEditingElement ? null : (canManipulate && selected ? onGestureEnd : null),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.rotate(
              angle: element.rotation * math.pi / 180,
              child: _buildContent(context),
            ),
            if (showSelectionFrame)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFC46A8A),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            if (showResizeHandle)
              Positioned(
                right: -14,
                bottom: -14,
                child: GestureDetector(
                  onPanUpdate: (details) => onResize(details.delta),
                  onPanEnd: (_) => onGestureEnd(),
                  onPanCancel: onGestureEnd,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC46A8A),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.open_in_full,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (element.type) {
      case AlbumElementType.image:
        return _ImageElementView(element: element);
      case AlbumElementType.text:
      case AlbumElementType.subtitle:
        return _TextElementView(
          element: element,
          pageScale: pageScale,
          isEditing: selected &&
              isInlineTextEditing &&
              editingTextElementId == element.id &&
              inlineTextController != null,
          controller: selected && editingTextElementId == element.id
              ? inlineTextController
              : null,
          focusNode: selected && editingTextElementId == element.id
              ? inlineTextFocusNode
              : null,
        );
      case AlbumElementType.shape:
      case AlbumElementType.sticker:
        final alpha = (element.payload['fill_alpha'] as num?)?.toDouble() ?? 0.18;
        return Container(
          decoration: BoxDecoration(
            color: _colorFromToken(element.style.colorToken).withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(element.style.borderRadius * 100),
          ),
        );
    }
  }
}

class _ImageElementView extends StatelessWidget {
  const _ImageElementView({required this.element});

  final AlbumElementModel element;

  @override
  Widget build(BuildContext context) {
    final path = element.payload['path']?.toString() ?? '';
    final radius = (element.style.borderRadius * 100).clamp(8, 24).toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: path.isEmpty
            ? Container(color: const Color(0xFFEFE3D5))
            : PathImage(
                path: path,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
      ),
    );
  }
}

class _TextElementView extends StatelessWidget {
  const _TextElementView({
    required this.element,
    required this.pageScale,
    required this.isEditing,
    this.controller,
    this.focusNode,
  });

  final AlbumElementModel element;
  final double pageScale;
  final bool isEditing;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final text = element.payload['text']?.toString() ?? '';
    final role = element.payload['role']?.toString() ?? '';
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final size = constraints.biggest;
        final baseStyle = _buildElementTextStyle(
          element.style,
          scale: pageScale,
        );
        final payloadMaxLines = (element.payload['max_lines'] as num?)?.toInt();
        final maxLines = payloadMaxLines ??
            _resolveMaxLines(
              role: role,
              boxHeight: size.height,
              baseFontSize: baseStyle.fontSize ?? element.style.fontSize,
              lineHeight: baseStyle.height ?? 1.35,
            );
        final fittedStyle = _fitTextStyle(
          text: text,
          baseStyle: baseStyle,
          maxWidth: size.width,
          maxHeight: size.height,
          maxLines: maxLines,
          textAlign: _textAlignFromValue(element.style.align),
        );

        final strutStyle = StrutStyle.fromTextStyle(fittedStyle, forceStrutHeight: true);
        return SizedBox.expand(
          child: Align(
            alignment: _alignmentFromTextAlign(element.style.align),
            child: isEditing && controller != null && focusNode != null
                ? TextField(
                    controller: controller,
                    focusNode: focusNode,
                    maxLines: maxLines,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    textAlign: _textAlignFromValue(element.style.align),
                    style: fittedStyle,
                    strutStyle: strutStyle,
                    cursorColor: _colorFromToken(element.style.colorToken),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                : Text(
                    text,
                    maxLines: maxLines,
                    overflow: TextOverflow.clip,
                    softWrap: true,
                    textAlign: _textAlignFromValue(element.style.align),
                    textWidthBasis: TextWidthBasis.longestLine,
                    strutStyle: strutStyle,
                    style: fittedStyle,
                  ),
          ),
        );
      },
    );
  }
}

class _SelectedElementRef {
  const _SelectedElementRef({
    required this.spreadIndex,
    required this.side,
    required this.elementId,
  });

  final int spreadIndex;
  final AlbumPageSide side;
  final String elementId;
}

class _PageInsertionTarget {
  const _PageInsertionTarget({
    required this.spreadIndex,
    required this.side,
  });

  final int spreadIndex;
  final AlbumPageSide side;
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.document,
    required this.sections,
    required this.currentSpread,
  });

  final AlbumBookDocument document;
  final List<StorySection> sections;
  final int currentSpread;
}

class _PrevSpreadIntent extends Intent {
  const _PrevSpreadIntent();
}

class _NextSpreadIntent extends Intent {
  const _NextSpreadIntent();
}

Color _colorFromToken(String token) {
  final hex = AlbumBookDesignTokens.colorTokens[token] ?? '#5D4538';
  final normalized = hex.replaceFirst('#', '');
  final value = int.tryParse('FF$normalized', radix: 16) ?? 0xFF5D4538;
  return Color(value);
}

String? _fontFamilyFromId(String fontId) {
  switch (AlbumBookDesignTokens.fontTokens[fontId] ?? AlbumFontPreset.sansClean) {
    case AlbumFontPreset.serifElegant:
      return 'serif';
    case AlbumFontPreset.sansClean:
      return 'sans-serif';
    case AlbumFontPreset.handwritingSoft:
      return 'cursive';
    case AlbumFontPreset.displayModern:
      return 'sans-serif-condensed';
    case AlbumFontPreset.monoNote:
      return 'monospace';
  }
}

TextStyle _buildElementTextStyle(AlbumElementStyle style, {double scale = 1.0}) {
  final preset = AlbumBookDesignTokens.fontTokens[style.fontId] ?? AlbumFontPreset.sansClean;
  final typographyScale = scale <= 1
      ? math.sqrt(scale).clamp(0.82, 1.0).toDouble()
      : (1 + (scale - 1) * 0.35).clamp(1.0, 1.18).toDouble();
  final scaledFontSize = (style.fontSize * typographyScale).clamp(10.0, 58.0);
  final base = TextStyle(
    fontFamily: _fontFamilyFromId(style.fontId),
    fontSize: scaledFontSize,
    fontWeight: _fontWeightFromToken(style.weight),
    height: 1.28,
    color: _colorFromToken(style.colorToken),
    shadows: style.shadow
        ? <Shadow>[
            Shadow(
              color: const Color(0x33000000),
              blurRadius: 8 * typographyScale.clamp(0.82, 1.18),
              offset: Offset(0, 2 * typographyScale.clamp(0.82, 1.18)),
            ),
          ]
        : null,
  );

  switch (preset) {
    case AlbumFontPreset.serifElegant:
      return base.copyWith(letterSpacing: 0.0);
    case AlbumFontPreset.sansClean:
      return base.copyWith(letterSpacing: -0.15);
    case AlbumFontPreset.handwritingSoft:
      return base.copyWith(letterSpacing: 0.06, fontStyle: FontStyle.italic);
    case AlbumFontPreset.displayModern:
      return base.copyWith(letterSpacing: 0.02, height: 1.08);
    case AlbumFontPreset.monoNote:
      return base.copyWith(letterSpacing: 0.02);
  }
}

int _resolveMaxLines({
  required String role,
  required double boxHeight,
  required double baseFontSize,
  required double lineHeight,
}) {
  final estimated = (boxHeight / (baseFontSize * lineHeight)).floor().clamp(1, 8);
  switch (role) {
    case 'meta':
      return 1;
    case 'subtitle':
      return estimated.clamp(1, 3);
    case 'overlay_title':
      return estimated.clamp(1, 3);
    case 'title':
      return estimated.clamp(1, 4);
    case 'art_word':
      return estimated.clamp(1, 3);
    case 'caption':
      return estimated.clamp(1, 5);
    case 'body':
      return estimated.clamp(2, 8);
    default:
      return estimated.clamp(1, 6);
  }
}

TextStyle _fitTextStyle({
  required String text,
  required TextStyle baseStyle,
  required double maxWidth,
  required double maxHeight,
  required int maxLines,
  required TextAlign textAlign,
}) {
  if (text.trim().isEmpty || maxWidth <= 0 || maxHeight <= 0) {
    return baseStyle;
  }

  var currentSize = ((baseStyle.fontSize ?? 16).clamp(8.5, 44.0) as num).toDouble();
  final minSize = maxLines >= 4 ? 8.5 : 9.5;
  final lineHeight = baseStyle.height ?? 1.28;
  final prefersSingleLine = _prefersSingleLine(text, maxLines);

  while (currentSize > minSize) {
    final style = baseStyle.copyWith(fontSize: currentSize);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);

    final fitsHeight = painter.height <= maxHeight + 0.5;
    final lineCount = painter.computeLineMetrics().length;
    if (!painter.didExceedMaxLines && fitsHeight && (!prefersSingleLine || lineCount <= 1)) {
      return style;
    }

    currentSize -= currentSize > 18 ? 1.4 : 0.9;
  }

  return baseStyle.copyWith(
    fontSize: minSize,
    height: lineHeight > 1.2 ? 1.2 : lineHeight,
  );
}

bool _prefersSingleLine(String text, int maxLines) {
  if (maxLines <= 1) {
    return true;
  }
  return text.runes.length <= 16;
}

FontWeight _fontWeightFromToken(String token) {
  switch (token) {
    case '300':
      return FontWeight.w300;
    case '500':
      return FontWeight.w500;
    case '600':
      return FontWeight.w600;
    case '700':
      return FontWeight.w700;
    default:
      return FontWeight.w400;
  }
}

TextAlign _textAlignFromValue(AlbumTextAlignValue value) {
  switch (value) {
    case AlbumTextAlignValue.left:
      return TextAlign.left;
    case AlbumTextAlignValue.center:
      return TextAlign.center;
    case AlbumTextAlignValue.right:
      return TextAlign.right;
  }
}

Alignment _alignmentFromTextAlign(AlbumTextAlignValue value) {
  switch (value) {
    case AlbumTextAlignValue.left:
      return Alignment.centerLeft;
    case AlbumTextAlignValue.center:
      return Alignment.center;
    case AlbumTextAlignValue.right:
      return Alignment.centerRight;
  }
}


