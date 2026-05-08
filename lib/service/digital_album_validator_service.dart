/// 数字相册校验服务，验证页面内容、布局和资源完整性。

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../models/vo/album_book_models.dart';

class DigitalAlbumValidatorService {
  const DigitalAlbumValidatorService();

  AlbumBookDocument sanitize(
    AlbumBookDocument document, {
    required Set<String> allowedPhotoIds,
    required Map<String, String> photoPathById,
    required String fallbackTitle,
    required String fallbackSubtitle,
  }) {
    final spreads = document.spreads
        .asMap()
        .entries
        .map(
          (entry) => _sanitizeSpread(
            entry.key,
            entry.value,
            allowedPhotoIds,
            photoPathById: photoPathById,
            pageWidth: document.pageWidth,
            pageHeight: document.pageHeight,
          ),
        )
        .toList(growable: false);

    return document.copyWith(
      title: document.title.trim().isEmpty ? fallbackTitle : document.title.trim(),
      subtitle: document.subtitle.trim().isEmpty
          ? fallbackSubtitle
          : document.subtitle.trim(),
      theme: document.theme.trim().isEmpty ? 'memory_book' : document.theme.trim(),
      spreads: spreads,
    );
  }

  AlbumSpreadModel _sanitizeSpread(
    int spreadIndex,
    AlbumSpreadModel spread,
    Set<String> allowedPhotoIds, {
    required Map<String, String> photoPathById,
    required double pageWidth,
    required double pageHeight,
  }) {
    return spread.copyWith(
      spreadIndex: spreadIndex,
      leftPage: _sanitizePage(
        spread.leftPage.copyWith(pageIndex: spreadIndex * 2),
        allowedPhotoIds,
        photoPathById: photoPathById,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
      ),
      rightPage: _sanitizePage(
        spread.rightPage.copyWith(pageIndex: spreadIndex * 2 + 1),
        allowedPhotoIds,
        photoPathById: photoPathById,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
      ),
    );
  }

  AlbumPageModel _sanitizePage(
    AlbumPageModel page,
    Set<String> allowedPhotoIds, {
    required Map<String, String> photoPathById,
    required double pageWidth,
    required double pageHeight,
  }) {
    final background = AlbumBookDesignTokens.colorTokens.containsKey(page.backgroundColorToken)
        ? page.backgroundColorToken
        : 'paper_warm';
    final elements = page.elements
        .map(
          (element) => _sanitizeElement(
            element,
            allowedPhotoIds,
            photoPathById: photoPathById,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            pageSide: page.side,
          ),
        )
        .whereType<AlbumElementModel>()
        .toList(growable: false)
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    final normalizedElements = _polishPageComposition(
      _resolveImageTextConflicts(_resolveOverlayText(elements, page.side), page.side),
      pageWidth: pageWidth,
      pageHeight: pageHeight,
      pageSide: page.side,
    );
    return page.copyWith(
      backgroundColorToken: background,
      elements: normalizedElements,
    );
  }

  AlbumElementModel? _sanitizeElement(
    AlbumElementModel element,
    Set<String> allowedPhotoIds, {
    required Map<String, String> photoPathById,
    required double pageWidth,
    required double pageHeight,
    required AlbumPageSide pageSide,
  }) {
    if (element.type == AlbumElementType.image) {
      final photoId = element.payload['photo_id']?.toString();
      if (photoId == null || !allowedPhotoIds.contains(photoId)) {
        return null;
      }
    }

    final payload = Map<String, dynamic>.from(element.payload);
    final role = payload['role']?.toString() ?? '';
    final text = payload['text']?.toString().trim() ?? '';
    final style = _sanitizeStyle(
      _normalizeStyleForRole(
        element.style,
        role: role,
        text: text,
      ),
    );
    final safeRect = _safeRectForElement(
      element,
      pageSide: pageSide,
      role: role,
    );
    final width = _clamp(element.w, 0.04, safeRect.width);
    final height = _clamp(element.h, 0.03, safeRect.height);
    final left = _clamp(element.x, safeRect.left, safeRect.right - width);
    final top = _clamp(element.y, safeRect.top, safeRect.bottom - height);
    if (element.type == AlbumElementType.image) {
      final photoId = payload['photo_id']?.toString() ?? '';
      final currentPath = payload['path']?.toString().trim() ?? '';
      final fallbackPath = photoPathById[photoId]?.trim() ?? '';
      if (currentPath.isEmpty && fallbackPath.isNotEmpty) {
        payload['path'] = fallbackPath;
      }
    }

    final normalizedX = element.type == AlbumElementType.image
        ? _snap(_alignedImageX(left, width, safeRect))
        : _snap(_clamp(left, safeRect.left, safeRect.right - width));
    final normalizedY = element.type == AlbumElementType.image
        ? _snap(_alignedImageY(top, height, safeRect))
        : _snap(_clamp(top, safeRect.top, safeRect.bottom - height));
    final normalized = element.copyWith(
      x: normalizedX,
      y: normalizedY,
      w: _snap(width),
      h: _snap(height),
      rotation: element.type == AlbumElementType.image ? 0 : _clamp(element.rotation, -25, 25),
      zIndex: element.zIndex < 0 ? 0 : element.zIndex,
      payload: payload,
      style: style,
    );

    if (normalized.type == AlbumElementType.text ||
        normalized.type == AlbumElementType.subtitle) {
      return _fitTextElement(
        normalized,
        pageWidth: pageWidth,
        pageHeight: pageHeight,
        pageSide: pageSide,
      );
    }
    return normalized;
  }

  AlbumElementStyle _sanitizeStyle(AlbumElementStyle style) {
    final fontId = AlbumBookDesignTokens.fontTokens.containsKey(style.fontId)
        ? style.fontId
        : 'sans_clean';
    final colorToken = AlbumBookDesignTokens.colorTokens.containsKey(style.colorToken)
        ? style.colorToken
        : 'ink_soft';
    return style.copyWith(
      fontId: fontId,
      colorToken: colorToken,
      fontSize: _clamp(style.fontSize, 9, 56),
      borderRadius: _clamp(style.borderRadius, 0, 0.2),
    );
  }

  AlbumElementModel _fitTextElement(
    AlbumElementModel element, {
    required double pageWidth,
    required double pageHeight,
    required AlbumPageSide pageSide,
  }) {
    final text = element.payload['text']?.toString().trim() ?? '';
    if (text.isEmpty || pageWidth <= 0 || pageHeight <= 0) {
      return element;
    }

    final role = element.payload['role']?.toString() ?? '';
    var fontSize = _clamp(
      element.style.fontSize,
      _minFontSizeForRole(role),
      _maxFontSizeForRole(role, text),
    );
    var width = element.w;
    var height = element.h;
    var x = element.x;
    var y = element.y;
    final fitBounds = _safeRectForElement(
      element,
      pageSide: pageSide,
      role: role,
    );
    final maxWidth = _clamp(fitBounds.right - x, width, fitBounds.width);
    final maxHeight = _clamp(fitBounds.bottom - y, height, fitBounds.height);
    final maxLines = _absoluteMaxLinesForRole(role);
    final prefersSingleLine = _prefersSingleLine(role, text);

    for (var i = 0; i < 24; i++) {
      final style = _buildTextStyle(element.style.copyWith(fontSize: fontSize));
      final painter = _measureText(
        text: text,
        style: style,
        maxWidth: (width * pageWidth).clamp(28.0, pageWidth),
        maxLines: maxLines,
        textAlign: _textAlignFromValue(element.style.align),
      );
      final lineCount = painter.computeLineMetrics().length;
      final fitsHeight = painter.height <= height * pageHeight + 0.5;
      final widthFill = painter.width / (width * pageWidth).clamp(1.0, pageWidth);
      final heightFill = painter.height / (height * pageHeight).clamp(1.0, pageHeight);
      final fitsComfortably = painter.width <= width * pageWidth * _preferredWidthFillRatio(role) &&
          painter.height <= height * pageHeight * _preferredTextFillRatio(role);
      if (!painter.didExceedMaxLines &&
          fitsHeight &&
          _shouldGrowText(
            role,
            text,
            fontSize: fontSize,
            maxFontSize: _maxFontSizeForRole(role, text),
            widthFill: widthFill,
            heightFill: heightFill,
            lineCount: lineCount,
          )) {
        if (fontSize < _maxFontSizeForRole(role, text) - 0.1) {
          fontSize = _clamp(
            fontSize + _growthStepForRole(role),
            _minFontSizeForRole(role),
            _maxFontSizeForRole(role, text),
          );
          continue;
        }
      }
      if (!painter.didExceedMaxLines &&
          fitsHeight &&
          fitsComfortably &&
          (!prefersSingleLine || lineCount <= 1)) {
        final payload = Map<String, dynamic>.from(element.payload)
          ..['max_lines'] = maxLines;
        return element.copyWith(
          x: _snap(_clamp(x, fitBounds.left, fitBounds.right - width)),
          y: _snap(_clamp(y, fitBounds.top, fitBounds.bottom - height)),
          w: _snap(width),
          h: _snap(height),
          payload: payload,
          style: element.style.copyWith(fontSize: fontSize),
        );
      }

      if (width < maxWidth - 0.004 &&
          (prefersSingleLine || _shouldPreferWidthGrowth(role, lineCount))) {
        final widestLine = painter.computeLineMetrics().fold<double>(
          painter.width,
          (maxWidthValue, metric) => metric.width > maxWidthValue ? metric.width : maxWidthValue,
        );
        final targetWidth = _clamp((widestLine + 20) / pageWidth, width, maxWidth);
        if (targetWidth > width + 0.004) {
          width = targetWidth;
          x = _clamp(x, fitBounds.left, fitBounds.right - width);
          continue;
        }
      }

      if (fontSize > _minFontSizeForRole(role) + 0.1) {
        fontSize -= fontSize > 20 ? 1.4 : 0.8;
        continue;
      }

      final neededHeight =
          _clamp((painter.height + 14) / pageHeight, height, maxHeight);
      if (neededHeight > height + 0.004) {
        height = neededHeight;
        y = _clamp(y, fitBounds.top, fitBounds.bottom - height);
        continue;
      }

      final neededWidth =
          _clamp((painter.width + 18) / pageWidth, width, maxWidth);
      if (neededWidth > width + 0.004) {
        width = neededWidth;
        x = _clamp(x, fitBounds.left, fitBounds.right - width);
      }
    }

    final payload = Map<String, dynamic>.from(element.payload)
      ..['max_lines'] = maxLines;
    return element.copyWith(
      x: _snap(_clamp(x, fitBounds.left, fitBounds.right - width)),
      y: _snap(_clamp(y, fitBounds.top, fitBounds.bottom - height)),
      w: _snap(width),
      h: _snap(height),
      payload: payload,
      style: element.style.copyWith(fontSize: fontSize),
    );
  }

  TextPainter _measureText({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required int maxLines,
    required TextAlign textAlign,
  }) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
  }

  TextStyle _buildTextStyle(AlbumElementStyle style) {
    return TextStyle(
      fontFamily: _fontFamilyFromId(style.fontId),
      fontSize: style.fontSize,
      fontWeight: _fontWeightFromToken(style.weight),
      fontStyle: style.fontId == 'handwriting_soft' ? FontStyle.italic : FontStyle.normal,
      height: style.fontId == 'display_modern' ? 1.08 : 1.28,
      letterSpacing: _letterSpacingForFont(style.fontId),
    );
  }

  TextAlign _textAlignFromValue(AlbumTextAlignValue align) {
    switch (align) {
      case AlbumTextAlignValue.center:
        return TextAlign.center;
      case AlbumTextAlignValue.right:
        return TextAlign.right;
      case AlbumTextAlignValue.left:
        return TextAlign.left;
    }
  }

  double _letterSpacingForFont(String fontId) {
    switch (fontId) {
      case 'sans_clean':
        return -0.15;
      case 'display_modern':
        return -0.05;
      case 'handwriting_soft':
        return 0.04;
      default:
        return 0;
    }
  }

  FontWeight _fontWeightFromToken(String token) {
    switch (token) {
      case '700':
        return FontWeight.w700;
      case '600':
        return FontWeight.w600;
      case '500':
        return FontWeight.w500;
      case '300':
        return FontWeight.w300;
      default:
        return FontWeight.w400;
    }
  }

  double _minFontSizeForRole(String role) {
    switch (role) {
      case 'meta':
        return 9;
      case 'subtitle':
      case 'overlay_title':
        return 11;
      case 'title':
        return 15;
      case 'art_word':
        return 18;
      case 'caption':
        return 10;
      case 'body':
        return 9;
      default:
        return 9;
    }
  }

  double _maxFontSizeForRole(String role, String text) {
    final length = text.runes.length;
    switch (role) {
      case 'art_word':
        return length <= 6 ? 34 : 30;
      case 'title':
        if (length <= 6) {
          return 38;
        }
        if (length <= 10) {
          return 34;
        }
        return 30;
      case 'subtitle':
      case 'overlay_title':
        return 24;
      case 'body':
        return length <= 50 ? 26 : (length <= 90 ? 24 : 22);
      default:
        return 24;
    }
  }

  int _absoluteMaxLinesForRole(String role) {
    switch (role) {
      case 'meta':
        return 1;
      case 'subtitle':
      case 'overlay_title':
        return 3;
      case 'title':
        return 4;
      case 'art_word':
        return 3;
      case 'caption':
        return 5;
      case 'body':
        return 8;
      default:
        return 6;
    }
  }

  double _preferredTextFillRatio(String role) {
    switch (role) {
      case 'art_word':
        return 0.62;
      case 'title':
        return 0.80;
      case 'subtitle':
      case 'overlay_title':
        return 0.76;
      case 'caption':
        return 0.82;
      case 'body':
        return 0.93;
      default:
        return 0.86;
    }
  }

  double _preferredWidthFillRatio(String role) {
    switch (role) {
      case 'meta':
        return 0.995;
      case 'title':
      case 'caption':
      case 'subtitle':
      case 'overlay_title':
        return 0.99;
      case 'body':
        return 0.985;
      default:
        return 0.985;
    }
  }

  bool _prefersSingleLine(String role, String text) {
    final length = text.runes.length;
    switch (role) {
      case 'meta':
        return true;
      case 'caption':
      case 'subtitle':
      case 'overlay_title':
        return length <= 18;
      case 'title':
        return length <= 14;
      default:
        return false;
    }
  }

  bool _shouldPreferWidthGrowth(String role, int lineCount) {
    if (lineCount <= 1) {
      return false;
    }
    switch (role) {
      case 'title':
      case 'caption':
      case 'subtitle':
      case 'overlay_title':
      case 'meta':
        return true;
      default:
        return false;
    }
  }

  Rect _safeRectForElement(
    AlbumElementModel element, {
    required AlbumPageSide pageSide,
    required String role,
  }) {
    final isImage = element.type == AlbumElementType.image;
    final isShape = element.type == AlbumElementType.shape;

    final outerMargin = isImage ? 0.035 : (isShape ? 0.06 : 0.08);
    final gutterMargin = isImage ? 0.045 : (isShape ? 0.08 : 0.10);
    final topMargin = role == 'meta' ? 0.08 : (isImage ? 0.035 : 0.08);
    final bottomMargin = isImage ? 0.04 : 0.08;

    final left = pageSide == AlbumPageSide.left ? outerMargin : gutterMargin;
    final rightInset = pageSide == AlbumPageSide.left ? gutterMargin : outerMargin;
    return Rect.fromLTRB(left, topMargin, 1 - rightInset, 1 - bottomMargin);
  }

  List<AlbumElementModel> _polishPageComposition(
    List<AlbumElementModel> elements, {
    required double pageWidth,
    required double pageHeight,
    required AlbumPageSide pageSide,
  }) {
    final polished = _polishImageOnlyPage(_polishTextLedPage(elements), pageSide: pageSide);
    final fitted = polished
        .map(
          (element) => element.type == AlbumElementType.text ||
                  element.type == AlbumElementType.subtitle
              ? _fitTextElement(
                  element,
                  pageWidth: pageWidth,
                  pageHeight: pageHeight,
                  pageSide: pageSide,
                )
              : element,
        )
        .toList(growable: false)
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return _finalizePageElements(fitted);
  }

  List<AlbumElementModel> _polishImageOnlyPage(
    List<AlbumElementModel> elements, {
    required AlbumPageSide pageSide,
  }) {
    final images = elements.where((item) => item.type == AlbumElementType.image).toList(growable: false);
    final meaningfulTextCount = elements.where((item) {
      if (item.type != AlbumElementType.text && item.type != AlbumElementType.subtitle) {
        return false;
      }
      final text = item.payload['text']?.toString().trim() ?? '';
      return text.isNotEmpty;
    }).length;
    if (images.length != 1 || meaningfulTextCount != 0) {
      return elements;
    }

    final image = images.first;
    final safeRect = pageSide == AlbumPageSide.left
        ? Rect.fromLTRB(0.025, 0.03, 0.965, 0.955)
        : Rect.fromLTRB(0.035, 0.03, 0.975, 0.955);
    final updated = image.copyWith(
      x: _snap(safeRect.left),
      y: _snap(safeRect.top),
      w: _snap(safeRect.width),
      h: _snap(safeRect.height),
    );
    return elements.map((element) => element.id == image.id ? updated : element).toList(growable: false);
  }

  List<AlbumElementModel> _polishTextLedPage(List<AlbumElementModel> elements) {
    final images = elements.where((item) => item.type == AlbumElementType.image).toList(growable: false);
    if (images.isNotEmpty) {
      return elements;
    }

    AlbumElementModel? title;
    AlbumElementModel? body;
    AlbumElementModel? meta;
    AlbumElementModel? shape;
    AlbumElementModel? artWord;

    for (final element in elements) {
      final role = element.payload['role']?.toString() ?? '';
      if (role == 'title' && title == null) {
        title = element;
      } else if (role == 'body' && body == null) {
        body = element;
      } else if (role == 'meta' && meta == null) {
        meta = element;
      } else if (role == 'art_word' && artWord == null) {
        artWord = element;
      } else if (element.type == AlbumElementType.shape && shape == null) {
        shape = element;
      }
    }

    if (title == null || body == null) {
      return elements;
    }

    final titleText = title.payload['text']?.toString().trim() ?? '';
    final bodyText = body.payload['text']?.toString().trim() ?? '';
    final titleLength = titleText.runes.length;
    final bodyLength = bodyText.runes.length;

    final titleY = meta == null ? 0.14 : 0.20;
    final titleW = titleLength <= 6 ? 0.54 : (titleLength <= 10 ? 0.64 : 0.72);
    final titleH = titleLength <= 8 ? 0.115 : 0.14;
    final titleFontSize = titleLength <= 4 ? 34.0 : (titleLength <= 8 ? 31.0 : 28.0);

    final artWordOccupied = artWord != null;
    final bodyY = artWordOccupied ? 0.66 : titleY + titleH + 0.12;
    final shapeHeight = bodyLength <= 42 ? 0.19 : (bodyLength <= 74 ? 0.23 : 0.27);
    final shapeY = bodyY - 0.035;
    final shapeW = 0.82;
    final bodyW = 0.72;
    final bodyH = shapeHeight - 0.065;

    final updated = <String, AlbumElementModel>{for (final element in elements) element.id: element};

    updated[title.id] = title.copyWith(
      x: 0.10,
      y: titleY,
      w: titleW,
      h: titleH,
      style: title.style.copyWith(
        fontId: titleLength <= 4 ? 'display_modern' : 'serif_elegant',
        fontSize: titleFontSize,
        weight: titleLength <= 8 ? '600' : '500',
        colorToken: 'ink_black',
      ),
    );

    if (meta != null) {
      updated[meta.id] = meta.copyWith(
        x: 0.10,
        y: 0.10,
        w: 0.28,
        h: 0.045,
        style: meta.style.copyWith(
          fontId: 'mono_note',
          fontSize: 15.5,
          colorToken: meta.style.colorToken == 'ink_black' ? 'gold_accent' : meta.style.colorToken,
          weight: '500',
        ),
      );
    }

    if (shape != null && !artWordOccupied) {
      updated[shape.id] = shape.copyWith(
        x: 0.06,
        y: shapeY,
        w: shapeW,
        h: shapeHeight,
        style: shape.style.copyWith(
          colorToken: shape.style.colorToken == 'shadow_soft' ? 'paper_warm' : shape.style.colorToken,
          borderRadius: 0.08,
        ),
        payload: <String, dynamic>{
          ...shape.payload,
          'fill_alpha': ((shape.payload['fill_alpha'] as num?)?.toDouble() ?? 0.20).clamp(0.12, 0.28),
        },
      );
    } else if (shape == null) {
      final generatedShape = AlbumElementModel(
        id: 'generated_body_shape',
        type: AlbumElementType.shape,
        x: 0.06,
        y: shapeY,
        w: shapeW,
        h: shapeHeight,
        rotation: 0,
        zIndex: math.max(0, body.zIndex - 1),
        locked: false,
        payload: const <String, dynamic>{
          'fill_alpha': 0.18,
          'generated_kind': 'body_backing',
          'generated_for_role': 'body',
        },
        style: const AlbumElementStyle(
          colorToken: 'paper_warm',
          borderRadius: 0.08,
        ),
      );
      updated[generatedShape.id] = generatedShape;
    }

    updated[body.id] = body.copyWith(
      x: 0.10,
      y: bodyY,
      w: bodyW,
      h: bodyH,
      style: body.style.copyWith(
        fontId: 'serif_elegant',
        fontSize: bodyLength <= 40 ? 24 : (bodyLength <= 74 ? 22.5 : 21),
        colorToken: 'ink_soft',
        weight: '400',
      ),
    );

    if (artWord != null) {
      updated[artWord.id] = artWord.copyWith(
        x: 0.10,
        y: 0.48,
        w: 0.32,
        h: 0.10,
        style: artWord.style.copyWith(
          fontSize: artWord.style.fontSize > 30 ? 30 : artWord.style.fontSize,
        ),
      );
    }

    final mapped = elements.map((element) => updated[element.id] ?? element).toList(growable: false);
    if (shape == null) {
      return <AlbumElementModel>[
        ...mapped,
        updated['generated_body_shape']!,
      ];
    }
    return mapped;
  }

  double _growthStepForRole(String role) {
    switch (role) {
      case 'art_word':
        return 1.0;
      case 'title':
        return 0.8;
      case 'body':
        return 0.6;
      case 'meta':
      case 'caption':
      case 'subtitle':
      case 'overlay_title':
        return 0.6;
      default:
        return 0.5;
    }
  }

  bool _shouldGrowText(
    String role,
    String text, {
    required double fontSize,
    required double maxFontSize,
    required double widthFill,
    required double heightFill,
    required int lineCount,
  }) {
    if (fontSize >= maxFontSize - 0.1) {
      return false;
    }
    switch (role) {
      case 'title':
        return widthFill < 0.76 || (lineCount <= 1 && heightFill < 0.42);
      case 'body':
        return text.runes.length >= 18 && widthFill < 0.86 && heightFill < 0.84;
      case 'meta':
        return widthFill < 0.62;
      case 'caption':
      case 'subtitle':
      case 'overlay_title':
        return widthFill < 0.74 && heightFill < 0.70;
      case 'art_word':
        return widthFill < 0.58;
      default:
        return false;
    }
  }

  AlbumElementStyle _normalizeStyleForRole(
    AlbumElementStyle style, {
    required String role,
    required String text,
  }) {
    final length = text.runes.length;
    switch (role) {
      case 'title':
        return style.copyWith(
          fontId: style.fontId == 'sans_clean'
              ? (length <= 4 ? 'display_modern' : 'serif_elegant')
              : style.fontId,
          colorToken: style.colorToken == 'ink_soft' ? 'ink_black' : style.colorToken,
          weight: style.weight == '400' ? (length <= 8 ? '600' : '500') : style.weight,
          align: AlbumTextAlignValue.left,
        );
      case 'body':
        return style.copyWith(
          fontId: style.fontId == 'serif_elegant' ? style.fontId : 'serif_elegant',
          colorToken: style.colorToken == 'ink_black' ? 'ink_soft' : style.colorToken,
          weight: style.weight == '700' || style.weight == '600' ? '400' : style.weight,
          align: AlbumTextAlignValue.left,
        );
      case 'meta':
        return style.copyWith(
          fontId: style.fontId == 'sans_clean' ? 'mono_note' : style.fontId,
          colorToken: style.colorToken == 'ink_black' || style.colorToken == 'ink_soft'
              ? 'gold_accent'
              : style.colorToken,
          weight: style.weight == '400' ? '500' : style.weight,
          align: AlbumTextAlignValue.left,
        );
      case 'caption':
      case 'subtitle':
      case 'overlay_title':
        return style.copyWith(
          fontId: style.fontId == 'sans_clean'
              ? (length <= 16 ? 'handwriting_soft' : 'serif_elegant')
              : style.fontId,
          colorToken: style.colorToken == 'ink_black' ? 'sage_accent' : style.colorToken,
          weight: style.weight == '400' && length <= 16 ? '500' : style.weight,
          align: style.align == AlbumTextAlignValue.right
              ? AlbumTextAlignValue.right
              : AlbumTextAlignValue.left,
        );
      case 'art_word':
        return style.copyWith(
          fontId: style.fontId == 'sans_clean' ? 'display_modern' : style.fontId,
          colorToken: style.colorToken == 'ink_black' ? 'rose_accent' : style.colorToken,
          weight: style.weight == '400' ? '700' : style.weight,
        );
      default:
        return style;
    }
  }

  List<AlbumElementModel> _resolveOverlayText(
    List<AlbumElementModel> elements,
    AlbumPageSide pageSide,
  ) {
    final images = elements.where((item) => item.type == AlbumElementType.image).toList(growable: false);
    if (images.isEmpty) {
      return elements;
    }

    final resolved = <AlbumElementModel>[];
    for (final element in elements) {
      if (!_isOverlayTextRole(element)) {
        resolved.add(element);
        continue;
      }
      final textRect = Rect.fromLTWH(element.x, element.y, element.w, element.h);
      var overlap = 0.0;
      for (final image in images) {
        overlap = math.max(
          overlap,
          _overlapRatio(textRect, Rect.fromLTWH(image.x, image.y, image.w, image.h)),
        );
      }
      if (overlap <= 0.02) {
        resolved.add(element);
        continue;
      }
      final relocated = _relocateTextOutsideImages(
        element,
        images,
        safeRect: _safeRectForElement(
          element,
          pageSide: pageSide,
          role: element.payload['role']?.toString() ?? '',
        ),
      );
      final moved = relocated != null &&
          ((relocated.x - element.x).abs() > 0.002 || (relocated.y - element.y).abs() > 0.002);
      if (moved) {
        resolved.add(relocated);
      }
    }
    return resolved..sort((a, b) => a.zIndex.compareTo(b.zIndex));
  }

  List<AlbumElementModel> _resolveImageTextConflicts(
    List<AlbumElementModel> elements,
    AlbumPageSide pageSide,
  ) {
    // Text elements are intentionally allowed to remain above images.
    // We no longer remove or relocate general text just because an image
    // overlaps it; final layering guarantees text stays readable.
    return elements..sort((a, b) => a.zIndex.compareTo(b.zIndex));
  }

  bool _isOverlayTextRole(AlbumElementModel element) {
    if (element.type != AlbumElementType.text && element.type != AlbumElementType.subtitle) {
      return false;
    }
    final role = element.payload['role']?.toString() ?? '';
    return role == 'caption' ||
        role == 'subtitle' ||
        role == 'overlay_title' ||
        role == 'art_word';
  }

  AlbumElementModel? _relocateTextOutsideImages(
    AlbumElementModel text,
    List<AlbumElementModel> images,
    {Rect? safeRect}
  ) {
    final textRect = Rect.fromLTWH(text.x, text.y, text.w, text.h);
    AlbumElementModel? overlappingImage;
    double maxOverlap = 0;
    for (final image in images) {
      final overlap = _overlapRatio(textRect, Rect.fromLTWH(image.x, image.y, image.w, image.h));
      if (overlap > maxOverlap) {
        maxOverlap = overlap;
        overlappingImage = image;
      }
    }

    if (maxOverlap < 0.22 || overlappingImage == null) {
      return text;
    }

    final imageRect = Rect.fromLTWH(
      overlappingImage.x,
      overlappingImage.y,
      overlappingImage.w,
      overlappingImage.h,
    );
    const gap = 0.03;
    final candidates = <Rect>[
      Rect.fromLTWH(text.x, imageRect.top - text.h - gap, text.w, text.h),
      Rect.fromLTWH(text.x, imageRect.bottom + gap, text.w, text.h),
      Rect.fromLTWH(imageRect.left - text.w - gap, text.y, text.w, text.h),
      Rect.fromLTWH(imageRect.right + gap, text.y, text.w, text.h),
    ];

    Rect? bestCandidate;
    var bestScore = double.infinity;
    for (final candidate in candidates) {
      final bounds = safeRect ?? Rect.fromLTRB(0, 0, 0.985, 0.985);
      if (candidate.left < bounds.left ||
          candidate.top < bounds.top ||
          candidate.right > bounds.right ||
          candidate.bottom > bounds.bottom) {
        continue;
      }
      var overlapScore = 0.0;
      for (final image in images) {
        overlapScore += _overlapRatio(candidate, Rect.fromLTWH(image.x, image.y, image.w, image.h));
      }
      if (overlapScore > 0.04) {
        continue;
      }
      final distance = (candidate.center - textRect.center).distance;
      final score = overlapScore * 100 + distance;
      if (score < bestScore) {
        bestScore = score;
        bestCandidate = candidate;
      }
    }

    if (bestCandidate == null) {
      return null;
    }

    return text.copyWith(
      x: _snap(bestCandidate.left),
      y: _snap(bestCandidate.top),
      w: _snap(bestCandidate.width),
      h: _snap(bestCandidate.height),
    );
  }

  double _overlapRatio(Rect a, Rect b) {
    final overlap = a.intersect(b);
    if (overlap.isEmpty) {
      return 0;
    }
    final area = a.width * a.height;
    if (area <= 0) {
      return 0;
    }
    return (overlap.width * overlap.height) / area;
  }

  AlbumElementModel _backingShapeForText(AlbumElementModel text) {
    const padX = 0.028;
    const padY = 0.022;
    final x = _clamp(text.x - padX, 0.04, 0.90);
    final y = _clamp(text.y - padY, 0.04, 0.92);
    final w = _clamp(text.w + padX * 2, 0.18, 0.90 - x);
    final h = _clamp(text.h + padY * 2, 0.08, 0.94 - y);
    return AlbumElementModel(
      id: 'contrast_${text.id}',
      type: AlbumElementType.shape,
      x: _snap(x),
      y: _snap(y),
      w: _snap(w),
      h: _snap(h),
      rotation: text.rotation,
      zIndex: math.max(0, text.zIndex - 1),
      locked: false,
      payload: <String, dynamic>{
        'fill_alpha': 0.72,
        'generated_kind': 'contrast_backing',
        'generated_for_text_id': text.id,
      },
      style: const AlbumElementStyle(
        colorToken: 'paper_warm',
        borderRadius: 0.06,
      ),
    );
  }

  List<AlbumElementModel> _finalizePageElements(List<AlbumElementModel> elements) {
    final withoutWeakArtWords = _removeLowValueArtWords(elements);
    final withoutLowValueNotes = _removeLowValueNotes(withoutWeakArtWords);
    final syncedShapes = _syncGeneratedTextBackings(withoutLowValueNotes);
    return _normalizeLayerOrder(_dedupeElementsById(syncedShapes))
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
  }

  List<AlbumElementModel> _normalizeLayerOrder(List<AlbumElementModel> elements) {
    final images = <AlbumElementModel>[];
    final shapes = <AlbumElementModel>[];
    final texts = <AlbumElementModel>[];
    final others = <AlbumElementModel>[];

    for (final element in elements) {
      if (element.type == AlbumElementType.image) {
        images.add(element);
      } else if (element.type == AlbumElementType.text ||
          element.type == AlbumElementType.subtitle) {
        texts.add(element);
      } else if (element.type == AlbumElementType.shape) {
        shapes.add(element);
      } else {
        others.add(element);
      }
    }

    images.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    shapes.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    texts.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    others.sort((a, b) => a.zIndex.compareTo(b.zIndex));

    var nextZ = 0;
    final normalized = <AlbumElementModel>[];
    for (final element in <AlbumElementModel>[
      ...images,
      ...others,
      ...shapes,
      ...texts,
    ]) {
      normalized.add(element.copyWith(zIndex: nextZ));
      nextZ += 1;
    }
    return normalized;
  }

  List<AlbumElementModel> _removeLowValueArtWords(List<AlbumElementModel> elements) {
    final titleText = elements
        .where((element) => element.payload['role']?.toString() == 'title')
        .map((element) => element.payload['text']?.toString().trim() ?? '')
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    final bodyText = elements
        .where((element) => element.payload['role']?.toString() == 'body')
        .map((element) => element.payload['text']?.toString().trim() ?? '')
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    final metaText = elements
        .where((element) => element.payload['role']?.toString() == 'meta')
        .map((element) => element.payload['text']?.toString().trim() ?? '')
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');

    const genericWords = <String>{
      '春',
      '夏',
      '秋',
      '冬',
      '花',
      '樱',
      '夜樱',
      '春夜',
      '春日',
      '夏日',
      '秋日',
      '冬日',
      '人物',
      '风景',
      '回忆',
      '时光',
      '记忆',
    };

    return elements.where((element) {
      final role = element.payload['role']?.toString() ?? '';
      if (role != 'art_word') {
        return true;
      }
      final text = element.payload['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        return false;
      }
      final normalized = text.replaceAll(RegExp(r'\s+'), '');
      if (normalized.runes.length <= 1) {
        return false;
      }
      if (genericWords.contains(normalized)) {
        return false;
      }
      if (normalized.runes.length <= 3 &&
          ((titleText.isNotEmpty && titleText.contains(normalized)) ||
              (bodyText.isNotEmpty && bodyText.contains(normalized)) ||
              (metaText.isNotEmpty && metaText.contains(normalized)))) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<AlbumElementModel> _removeLowValueNotes(List<AlbumElementModel> elements) {
    final hasBody = elements.any((element) => element.payload['role']?.toString() == 'body');
    final hasTitle = elements.any((element) => element.payload['role']?.toString() == 'title');
    final hasImage = elements.any((element) => element.type == AlbumElementType.image);
    if (!hasTitle || !hasBody) {
      return elements;
    }

    const weakNotes = <String>{
      '\u968f\u6027\u9009\u62e9',
      '\u665a\u98ce',
      '\u6625\u591c',
      '\u591c\u6a31',
      '\u6625\u65e5',
      '\u767d\u65e5\u7684\u5e8f',
    };

    return elements.where((element) {
      final role = element.payload['role']?.toString() ?? '';
      if (role != 'caption' && role != 'subtitle') {
        return true;
      }
      final text = element.payload['text']?.toString().trim() ?? '';
      final normalized = text.replaceAll(RegExp(r'\s+'), '');
      if (normalized.isEmpty) {
        return false;
      }
      if (!hasImage && normalized.runes.length <= 6) {
        return false;
      }
      if (weakNotes.contains(normalized)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<AlbumElementModel> _syncGeneratedTextBackings(List<AlbumElementModel> elements) {
    final textById = <String, AlbumElementModel>{
      for (final element in elements)
        if (element.type == AlbumElementType.text || element.type == AlbumElementType.subtitle)
          element.id: element,
    };
    final body = elements.firstWhere(
      (element) => element.payload['role']?.toString() == 'body',
      orElse: () => const AlbumElementModel(
        id: '',
        type: AlbumElementType.text,
        x: 0,
        y: 0,
        w: 0,
        h: 0,
        rotation: 0,
        zIndex: 0,
        locked: false,
        payload: <String, dynamic>{},
        style: AlbumElementStyle(),
      ),
    );

    final synced = <AlbumElementModel>[];
    for (final element in elements) {
      if (element.type != AlbumElementType.shape) {
        synced.add(element);
        continue;
      }

      final generatedForTextId = element.payload['generated_for_text_id']?.toString() ?? '';
      if (generatedForTextId.isNotEmpty) {
        final target = textById[generatedForTextId];
        if (target == null) {
          continue;
        }
        synced.add(
          _backingShapeForText(target).copyWith(
            id: element.id,
            style: element.style,
            payload: <String, dynamic>{
              ..._backingShapeForText(target).payload,
              ...element.payload,
            },
          ),
        );
        continue;
      }

      final generatedKind = element.payload['generated_kind']?.toString() ?? '';
      final generatedRole = element.payload['generated_for_role']?.toString() ?? '';
      if ((generatedKind == 'body_backing' || generatedRole == 'body') && body.id.isNotEmpty) {
        synced.add(
          element.copyWith(
            x: _snap(_clamp(body.x - 0.05, 0.05, 0.80)),
            y: _snap(_clamp(body.y - 0.055, 0.08, 0.84)),
            w: _snap(_clamp(body.w + 0.14, 0.28, 0.86)),
            h: _snap(_clamp(body.h + 0.12, 0.12, 0.76)),
            zIndex: math.max(0, body.zIndex - 1),
            payload: <String, dynamic>{
              ...element.payload,
              'fill_alpha': ((element.payload['fill_alpha'] as num?)?.toDouble() ?? 0.18)
                  .clamp(0.14, 0.28),
            },
          ),
        );
        continue;
      }

      synced.add(element);
    }
    return synced;
  }

  List<AlbumElementModel> _dedupeElementsById(List<AlbumElementModel> elements) {
    final deduped = <String, AlbumElementModel>{};
    for (var index = 0; index < elements.length; index++) {
      final element = elements[index];
      final rawId = element.id.trim();
      final id = rawId.isEmpty ? 'element_${element.type.name}_$index' : rawId;
      deduped[id] = rawId == id ? element : element.copyWith(id: id);
    }
    return deduped.values.toList(growable: false);
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

  double _clamp(double value, double min, double max) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  double _snap(double value) {
    return (value * 1000).roundToDouble() / 1000;
  }

  double _alignedImageX(double x, double width, Rect safeRect) {
    final clamped = _clamp(x, safeRect.left, safeRect.right - width);
    final centered = safeRect.left + (safeRect.width - width) / 2;
    if ((clamped - centered).abs() <= 0.025) {
      return centered;
    }
    if (clamped <= safeRect.left + 0.02) {
      return safeRect.left;
    }
    final rightGap = safeRect.right - (clamped + width);
    if (rightGap <= 0.04) {
      return safeRect.right - width;
    }
    return clamped;
  }

  double _alignedImageY(double y, double height, Rect safeRect) {
    final clamped = _clamp(y, safeRect.top, safeRect.bottom - height);
    if (clamped <= safeRect.top + 0.02) {
      return safeRect.top;
    }
    final bottomGap = safeRect.bottom - (clamped + height);
    if (bottomGap <= 0.04) {
      return safeRect.bottom - height;
    }
    return clamped;
  }
}
