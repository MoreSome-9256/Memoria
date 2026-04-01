import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vo/album_book_models.dart';
import '../../models/vo/story_section.dart';
import '../../service/digital_album_ai_service.dart';
import '../../service/digital_album_book_service.dart';
import '../../service/digital_album_layout_service.dart';
import '../../service/digital_album_validator_service.dart';
import '../widgets/path_image.dart';
import 'vlm_photo_picker_page.dart';

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
    required this.storyEntityId,
  });

  final String title;
  final String subtitle;
  final List<StorySection> sections;
  final int? storyEntityId;

  @override
  State<DigitalAlbumBookPage> createState() => _DigitalAlbumBookPageState();
}

class _DigitalAlbumBookPageState extends State<DigitalAlbumBookPage> {
  final DigitalAlbumLayoutService _layoutService = const DigitalAlbumLayoutService();
  final DigitalAlbumValidatorService _validator = const DigitalAlbumValidatorService();
  final DigitalAlbumAiService _aiService = const DigitalAlbumAiService();
  final DigitalAlbumBookService _bookService = const DigitalAlbumBookService();
  final PageController _pageController = PageController();
  final TransformationController _spreadZoomController = TransformationController();
  final FocusNode _inlineTextFocusNode = FocusNode();
  AlbumBookDocument? _document;
  _SelectedElementRef? _selectedElement;
  TextEditingController? _inlineTextController;
  String? _inlineEditingElementId;
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
  final AlbumBookStylePreset _currentStylePreset = AlbumBookStylePreset.editorial;
  Set<String> _selectedTemplateIds =
      Set<String>.from(DigitalAlbumLayoutService.defaultTemplateIds);
  Set<String> _templateDraftIds =
      Set<String>.from(DigitalAlbumLayoutService.defaultTemplateIds);

  @override
  void initState() {
    super.initState();
    _lockLandscape();
    _loadBook();
  }

  @override
  void dispose() {
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
      sections: widget.sections,
      preset: _currentStylePreset,
      allowedTemplateIds: _selectedTemplateIds,
    );

    AlbumBookDocument? loaded;
    if (widget.storyEntityId != null) {
      loaded = await _bookService.loadByStoryId(widget.storyEntityId!);
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
      for (final section in widget.sections)
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
    final ids = widget.sections.map((section) => section.photo.id).toSet();
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
    _inlineTextController?.removeListener(_handleInlineTextChanged);
    _inlineTextController?.dispose();
    _inlineTextController = null;
    _inlineEditingElementId = null;
  }

  void _handleInlineTextChanged() {
    final controller = _inlineTextController;
    final selected = _selectedElementModel;
    if (controller == null || selected == null || selected.id != _inlineEditingElementId) {
      return;
    }
    final currentText = selected.payload['text']?.toString() ?? '';
    if (currentText == controller.text) {
      return;
    }
    _updateSelectedElement((current) {
      final payload = Map<String, dynamic>.from(current.payload);
      payload['text'] = controller.text;
      return current.copyWith(payload: payload);
    });
  }

  void _syncInlineTextEditor({bool requestFocus = false}) {
    final selected = _selectedElementModel;
    if (!_editMode || !_isTextElement(selected)) {
      _disposeInlineTextController();
      _inlineTextFocusNode.unfocus();
      return;
    }

    final text = selected!.payload['text']?.toString() ?? '';
    if (_inlineEditingElementId != selected.id || _inlineTextController == null) {
      _disposeInlineTextController();
      final controller = TextEditingController(text: text);
      controller.addListener(_handleInlineTextChanged);
      _inlineTextController = controller;
      _inlineEditingElementId = selected.id;
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

  void _updateSelectedTextStyle({
    String? fontId,
    double? fontSize,
    String? colorToken,
    AlbumTextAlignValue? align,
    String? weight,
    bool? shadow,
    double? rotationDelta,
  }) {
    if (!_isTextElement(_selectedElementModel)) {
      return;
    }
    _updateSelectedElement((current) {
      return current.copyWith(
        rotation: current.rotation + (rotationDelta ?? 0),
        style: current.style.copyWith(
          fontId: fontId,
          fontSize: fontSize,
          colorToken: colorToken,
          align: align,
          weight: weight,
          shadow: shadow,
        ),
      );
    });
  }

  Future<void> _runAiCopywriting() async {
    final document = _document;
    if (document == null || _isAiBusy || widget.sections.isEmpty) {
      return;
    }

    setState(() {
      _isAiBusy = true;
    });

    try {
      final rewritten = await _aiService.writeCopyForBook(
        title: widget.title,
        subtitle: widget.subtitle,
        sections: widget.sections,
        document: document,
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
        _isDirty = widget.storyEntityId == null;
      });
      _disposeInlineTextController();
      _resetSpreadZoom();

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
    if (_isAiBusy || _isLoading || widget.sections.isEmpty) {
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
    final currentDocument = _document;
    var rebuilt = _sanitize(
      _layoutService.buildDefaultBook(
        title: widget.title,
        subtitle: widget.subtitle,
        sections: widget.sections,
        preset: _currentStylePreset,
        allowedTemplateIds: nextSelection,
      ),
    );
    if (currentDocument != null) {
      rebuilt = _sanitize(_reuseExistingCopy(currentDocument, rebuilt));
    }
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

  void _toggleEditMode() {
    final nextEditMode = !_editMode;
    setState(() {
      _editMode = nextEditMode;
      if (!nextEditMode) {
        _selectedElement = null;
      }
    });
    if (!nextEditMode) {
      _disposeInlineTextController();
      _inlineTextFocusNode.unfocus();
    } else {
      _syncInlineTextEditor();
    }
  }

  void _goToSpread(int index) {
    final document = _document;
    if (document == null || index < 0 || index >= document.spreads.length) {
      return;
    }
    _resetSpreadZoom();
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _selectElement(
    int spreadIndex,
    AlbumPageSide side,
    String elementId,
  ) {
    setState(() {
      _editMode = true;
      _selectedElement = _SelectedElementRef(
        spreadIndex: spreadIndex,
        side: side,
        elementId: elementId,
      );
    });
    _syncInlineTextEditor(requestFocus: true);
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
  }) {
    final document = _document;
    if (document == null) {
      return;
    }

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
      _editMode = true;
      _isDirty = true;
      _selectedElement = _SelectedElementRef(
        spreadIndex: spreadIndex,
        side: side,
        elementId: element.id,
      );
    });
    _syncInlineTextEditor(requestFocus: _isTextElement(element));
  }

  void _moveSelectedElement(Offset delta, Size pageSize) {
    if (pageSize.width <= 0 || pageSize.height <= 0) {
      return;
    }
    _updateSelectedElement((current) {
      final nextX = ((current.x + (delta.dx / pageSize.width)).clamp(0.0, 0.98 - current.w) as num)
          .toDouble();
      final nextY =
          ((current.y + (delta.dy / pageSize.height)).clamp(0.0, 0.98 - current.h) as num)
              .toDouble();
      return current.copyWith(x: nextX, y: nextY);
    });
  }

  void _resizeSelectedElement(Offset delta, Size pageSize) {
    if (pageSize.width <= 0 || pageSize.height <= 0) {
      return;
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
    final nextZ = page.elements.fold<int>(0, (maxZ, item) => math.max(maxZ, item.zIndex)) + 1;
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
    );

    if (mounted) {
      _syncInlineTextEditor(requestFocus: true);
    }
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
    final nextZ = page.elements.fold<int>(0, (maxZ, item) => math.max(maxZ, item.zIndex)) + 1;
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

    _updateSelectedElement((current) {
      final payload = Map<String, dynamic>.from(current.payload);
      payload['photo_id'] = replacement.assetId;
      payload['path'] = replacement.path;
      return current.copyWith(payload: payload);
    });
  }

  void _deleteSelectedElement() {
    final document = _document;
    final ref = _selectedElement;
    if (document == null || ref == null) {
      return;
    }

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
      _isDirty = true;
    });
    _disposeInlineTextController();
  }

  Future<void> _editSelectedText() async {
    _syncInlineTextEditor(requestFocus: true);
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
    final topZ = page.elements.fold<int>(0, (maxZ, item) => math.max(maxZ, item.zIndex));
    _updateSelectedElement((current) => current.copyWith(zIndex: topZ + 1));
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
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
                                                physics: (_editMode || _isSpreadZoomed)
                                                    ? const NeverScrollableScrollPhysics()
                                                    : const BouncingScrollPhysics(),
                                                itemCount: document.spreads.length,
                                                onPageChanged: (value) {
                                                  setState(() {
                                                    _currentSpread = value;
                                                    _selectedElement = null;
                                                  });
                                                  _disposeInlineTextController();
                                                  _resetSpreadZoom();
                                                },
                                                itemBuilder: (BuildContext context, int index) {
                                                  return AnimatedBuilder(
                                                    animation: _pageController,
                                                    child: _BookSpreadCard(
                                                      spread: document.spreads[index],
                                                      spreadIndex: index,
                                                      designPageWidth: document.pageWidth,
                                                      designPageHeight: document.pageHeight,
                                                      selected: _selectedElement,
                                                      editMode: _editMode,
                                                      isSpreadZoomed: _isSpreadZoomed,
                                                      editingTextElementId: _inlineEditingElementId,
                                                      inlineTextController: _inlineTextController,
                                                      inlineTextFocusNode: _inlineTextFocusNode,
                                                      onElementSelected: _selectElement,
                                                      onElementMoved: _moveSelectedElement,
                                                      onElementResized: _resizeSelectedElement,
                                                    ),
                                                    builder: (BuildContext context, Widget? child) {
                                                      final position = _pageController.hasClients &&
                                                              _pageController.position
                                                                  .hasContentDimensions
                                                          ? (_pageController.page ??
                                                              _currentSpread.toDouble())
                                                          : _currentSpread.toDouble();
                                                      final offset = index - position;
                                                      final clamped = offset.clamp(-1.0, 1.0);
                                                      final rotation = clamped * -0.14;
                                                      final scale = 1 - (clamped.abs() * 0.02);
                                                      final alignment = clamped >= 0
                                                          ? Alignment.centerLeft
                                                          : Alignment.centerRight;
                                                      return Transform.scale(
                                                        scale: scale,
                                                        child: Transform(
                                                          alignment: alignment,
                                                          transform: Matrix4.identity()
                                                            ..setEntry(3, 2, 0.0012)
                                                            ..rotateY(rotation),
                                                          child: child,
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                              if (!_editMode && !_isSpreadZoomed)
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
                            if (!_editMode && (_isQuickMenuVisible || _isTemplatePanelVisible))
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _dismissFloatingMenus,
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            if (!_editMode)
                              Positioned(
                                left: 10 + safePadding.left,
                                bottom: 12 + safePadding.bottom,
                                child: _buildFloatingControls(context),
                              ),
                            if (!_editMode && !_isSpreadZoomed)
                              Positioned(
                                left: 4 + safePadding.left,
                                right: 4 + safePadding.right,
                                top: 0,
                                bottom: 0,
                                child: _buildSideNavigation(document),
                              ),
                            if (_editMode)
                              Positioned(
                                left: 8 + safePadding.left,
                                right: 8 + safePadding.right,
                                bottom: 6 + safePadding.bottom,
                                child: _buildEditBar(context),
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
          tooltip: '杩斿洖',
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
      constraints: const BoxConstraints(maxWidth: 320),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          tag('AI写文案', () {
            _dismissFloatingMenus();
            _handleAiCopyTap();
          }, busy: _isAiBusy),
          tag(
            '选择模板',
            _toggleTemplatePanel,
            active: _isTemplatePanelVisible,
          ),
          tag('保存', () {
            _dismissFloatingMenus();
            unawaited(_saveBook());
          }, busy: _isSaving),
        ],
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

  Widget _buildEditBar(BuildContext context) {
    final selected = _selectedElementModel;
    final selectedText = _isTextElement(selected) ? selected! : null;
    return Container(
      key: const ValueKey<String>('edit_bar'),
      margin: const EdgeInsets.symmetric(horizontal: 36),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _toggleEditMode,
                icon: const Icon(Icons.check),
                label: const Text('完成编辑'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  selected == null
                      ? '长按图片或文字进入编辑'
                      : '已选中 ${selected.type == AlbumElementType.image ? '图片' : '文字'} 元素',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: _addImageElement,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('新增图片'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _addTextElement(type: AlbumElementType.text),
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('新增文字'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _addTextElement(type: AlbumElementType.subtitle),
                  icon: const Icon(Icons.subtitles_outlined),
                  label: const Text('新增题签'),
                ),
                const SizedBox(width: 8),
                if (selected?.type == AlbumElementType.image) ...[
                  FilledButton.icon(
                    onPressed: _replaceSelectedImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('更换图片'),
                  ),
                  const SizedBox(width: 8),
                ],
                if (selected != null &&
                    (selected.type == AlbumElementType.text ||
                        selected.type == AlbumElementType.subtitle)) ...[
                  FilledButton.icon(
                    onPressed: _editSelectedText,
                    icon: const Icon(Icons.text_fields),
                    label: const Text('编辑文字'),
                  ),
                  const SizedBox(width: 8),
                ],
                if (selected != null)
                  TextButton.icon(
                    onPressed: _bringSelectedToFront,
                    icon: const Icon(Icons.layers),
                    label: const Text('置于顶层'),
                  ),
                if (selected != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _deleteSelectedElement,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除元素'),
                  ),
                ],
              ],
            ),
          ),
          if (selectedText != null) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _syncInlineTextEditor(requestFocus: true),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('直接改字'),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: 'Font',
                    onSelected: (value) => _updateSelectedTextStyle(fontId: value),
                    itemBuilder: (context) => AlbumBookDesignTokens.fontTokens.keys
                        .map(
                          (fontId) => PopupMenuItem<String>(
                            value: fontId,
                            child: Text(_fontLabel(fontId)),
                          ),
                        )
                        .toList(growable: false),
                    child: Chip(
                      label: Text(_fontLabel(selectedText.style.fontId)),
                      avatar: const Icon(Icons.font_download, size: 18),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () => _updateSelectedTextStyle(
                      fontSize: (selectedText.style.fontSize - 2).clamp(10, 72).toDouble(),
                    ),
                    icon: const Icon(Icons.text_decrease),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    onPressed: () => _updateSelectedTextStyle(
                      fontSize: (selectedText.style.fontSize + 2).clamp(10, 72).toDouble(),
                    ),
                    icon: const Icon(Icons.text_increase),
                  ),
                  const SizedBox(width: 8),
                  ...AlbumBookDesignTokens.colorTokens.keys.map(
                    (token) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => _updateSelectedTextStyle(colorToken: token),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: _colorFromToken(token),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: selectedText.style.colorToken == token
                                  ? Colors.black
                                  : Colors.black12,
                              width: selectedText.style.colorToken == token ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () => _updateSelectedTextStyle(align: AlbumTextAlignValue.left),
                    icon: const Icon(Icons.format_align_left),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    onPressed: () => _updateSelectedTextStyle(align: AlbumTextAlignValue.center),
                    icon: const Icon(Icons.format_align_center),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    onPressed: () => _updateSelectedTextStyle(align: AlbumTextAlignValue.right),
                    icon: const Icon(Icons.format_align_right),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () => _updateSelectedTextStyle(
                      weight: selectedText.style.weight == '700' ? '400' : '700',
                    ),
                    icon: const Icon(Icons.format_bold),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    onPressed: () => _updateSelectedTextStyle(
                      shadow: !selectedText.style.shadow,
                    ),
                    icon: const Icon(Icons.blur_on),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    onPressed: () => _updateSelectedTextStyle(rotationDelta: 90),
                    icon: const Icon(Icons.rotate_90_degrees_ccw),
                  ),
                ],
              ),
            ),
          ],
        ],
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
    required this.editingTextElementId,
    required this.inlineTextController,
    required this.inlineTextFocusNode,
    required this.onElementSelected,
    required this.onElementMoved,
    required this.onElementResized,
  });

  final AlbumSpreadModel spread;
  final int spreadIndex;
  final double designPageWidth;
  final double designPageHeight;
  final _SelectedElementRef? selected;
  final bool editMode;
  final bool isSpreadZoomed;
  final String? editingTextElementId;
  final TextEditingController? inlineTextController;
  final FocusNode inlineTextFocusNode;
  final void Function(int spreadIndex, AlbumPageSide side, String elementId) onElementSelected;
  final void Function(Offset delta, Size pageSize) onElementMoved;
  final void Function(Offset delta, Size pageSize) onElementResized;

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
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: Stack(
              children: [
                Row(
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
                        editingTextElementId: editingTextElementId,
                        inlineTextController: inlineTextController,
                        inlineTextFocusNode: inlineTextFocusNode,
                        onElementSelected: onElementSelected,
                        onElementMoved: onElementMoved,
                        onElementResized: onElementResized,
                      ),
                    ),
                    Container(
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
                    ),
                    Expanded(
                      child: _AlbumCanvasPage(
                        page: spread.rightPage,
                        spreadIndex: spreadIndex,
                        designPageWidth: designPageWidth,
                        designPageHeight: designPageHeight,
                        selected: selected,
                        editMode: editMode,
                        isSpreadZoomed: isSpreadZoomed,
                        editingTextElementId: editingTextElementId,
                        inlineTextController: inlineTextController,
                        inlineTextFocusNode: inlineTextFocusNode,
                        onElementSelected: onElementSelected,
                        onElementMoved: onElementMoved,
                        onElementResized: onElementResized,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
    required this.editingTextElementId,
    required this.inlineTextController,
    required this.inlineTextFocusNode,
    required this.onElementSelected,
    required this.onElementMoved,
    required this.onElementResized,
  });

  final AlbumPageModel page;
  final int spreadIndex;
  final double designPageWidth;
  final double designPageHeight;
  final _SelectedElementRef? selected;
  final bool editMode;
  final bool isSpreadZoomed;
  final String? editingTextElementId;
  final TextEditingController? inlineTextController;
  final FocusNode inlineTextFocusNode;
  final void Function(int spreadIndex, AlbumPageSide side, String elementId) onElementSelected;
  final void Function(Offset delta, Size pageSize) onElementMoved;
  final void Function(Offset delta, Size pageSize) onElementResized;

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
                    canManipulate: editMode && !isSpreadZoomed,
                    selected: selected != null &&
                        selected!.spreadIndex == spreadIndex &&
                        selected!.side == page.side &&
                        selected!.elementId == element.id,
                    editMode: editMode,
                    editingTextElementId: editingTextElementId,
                    inlineTextController: inlineTextController,
                    inlineTextFocusNode: inlineTextFocusNode,
                    pageSize: pageSize,
                    onSelect: () => onElementSelected(spreadIndex, page.side, element.id),
                    onMove: (delta) => onElementMoved(delta, pageSize),
                    onResize: (delta) => onElementResized(delta, pageSize),
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
    required this.editingTextElementId,
    required this.inlineTextController,
    required this.inlineTextFocusNode,
    required this.pageSize,
    required this.onSelect,
    required this.onMove,
    required this.onResize,
  });

  final AlbumElementModel element;
  final double pageScale;
  final bool canManipulate;
  final bool selected;
  final bool editMode;
  final String? editingTextElementId;
  final TextEditingController? inlineTextController;
  final FocusNode inlineTextFocusNode;
  final Size pageSize;
  final VoidCallback onSelect;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;

  @override
  Widget build(BuildContext context) {
    final left = element.x * pageSize.width;
    final top = element.y * pageSize.height;
    final width = element.w * pageSize.width;
    final height = element.h * pageSize.height;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onSelect,
        onTap: editMode ? onSelect : null,
        onPanUpdate: canManipulate && selected ? (details) => onMove(details.delta) : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.rotate(
              angle: element.rotation * math.pi / 180,
              child: _buildContent(context),
            ),
            if (canManipulate && selected)
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
            if (canManipulate && selected)
              Positioned(
                right: -14,
                bottom: -14,
                child: GestureDetector(
                  onPanUpdate: (details) => onResize(details.delta),
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
          isEditing: editMode &&
              selected &&
              editingTextElementId == element.id &&
              inlineTextController != null,
          controller: editMode && selected && editingTextElementId == element.id
              ? inlineTextController
              : null,
          focusNode: editMode && selected && editingTextElementId == element.id
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

String _fontLabel(String fontId) {
  switch (fontId) {
    case 'serif_elegant':
      return '优雅衬线';
    case 'sans_clean':
      return '简洁无衬线';
    case 'handwriting_soft':
      return '柔和手写';
    case 'display_modern':
      return '现代标题';
    case 'mono_note':
      return '打字机';
    default:
      return fontId;
  }
}


