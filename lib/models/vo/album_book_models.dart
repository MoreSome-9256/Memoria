import 'dart:convert';

/// 数字相册书页面设计的值对象集合，描述布局、字体和颜色等样式。

enum AlbumPageSide { left, right }

enum AlbumElementType { image, text, subtitle, shape, sticker }

enum AlbumTextAlignValue { left, center, right }

enum AlbumFontPreset {
  serifElegant,
  sansClean,
  handwritingSoft,
  displayModern,
  monoNote,
}

class AlbumBookDesignTokens {
  static const String schemaVersion = 'memoria.album.layout.v1';

  static const Map<String, String> colorTokens = <String, String>{
    'paper_warm': '#FFF8F0',
    'paper_rose': '#FFF2F2',
    'paper_sage': '#F4F7EF',
    'ink_black': '#2E221D',
    'ink_soft': '#5D4538',
    'rose_accent': '#C46A8A',
    'gold_accent': '#B08C4E',
    'sage_accent': '#7D9B76',
    'shadow_soft': '#CBB8A8',
  };

  static const Map<String, AlbumFontPreset> fontTokens = <String, AlbumFontPreset>{
    'serif_elegant': AlbumFontPreset.serifElegant,
    'sans_clean': AlbumFontPreset.sansClean,
    'handwriting_soft': AlbumFontPreset.handwritingSoft,
    'display_modern': AlbumFontPreset.displayModern,
    'mono_note': AlbumFontPreset.monoNote,
  };
}

class AlbumBookDocument {
  const AlbumBookDocument({
    required this.title,
    required this.subtitle,
    required this.theme,
    required this.pageWidth,
    required this.pageHeight,
    required this.spreads,
    this.schemaVersion = AlbumBookDesignTokens.schemaVersion,
    this.layoutSource = 'manual',
  });

  final String schemaVersion;
  final String title;
  final String subtitle;
  final String theme;
  final double pageWidth;
  final double pageHeight;
  final List<AlbumSpreadModel> spreads;
  final String layoutSource;

  AlbumBookDocument copyWith({
    String? schemaVersion,
    String? title,
    String? subtitle,
    String? theme,
    double? pageWidth,
    double? pageHeight,
    List<AlbumSpreadModel>? spreads,
    String? layoutSource,
  }) {
    return AlbumBookDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      theme: theme ?? this.theme,
      pageWidth: pageWidth ?? this.pageWidth,
      pageHeight: pageHeight ?? this.pageHeight,
      spreads: spreads ?? this.spreads,
      layoutSource: layoutSource ?? this.layoutSource,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schema_version': schemaVersion,
      'album': <String, dynamic>{
        'title': title,
        'subtitle': subtitle,
        'theme': theme,
        'book': <String, dynamic>{
          'orientation': 'landscape',
          'page_width': pageWidth,
          'page_height': pageHeight,
          'spread_count': spreads.length,
        },
      },
      'spreads': spreads.map((spread) => spread.toJson()).toList(growable: false),
      'layout_source': layoutSource,
    };
  }

  String encodePretty() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }

  factory AlbumBookDocument.fromJson(Map<String, dynamic> json) {
    final album = (json['album'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final book = (album['book'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final rawSpreads = json['spreads'] as List? ?? const <dynamic>[];
    return AlbumBookDocument(
      schemaVersion: json['schema_version']?.toString() ?? AlbumBookDesignTokens.schemaVersion,
      title: album['title']?.toString() ?? '',
      subtitle: album['subtitle']?.toString() ?? '',
      theme: album['theme']?.toString() ?? 'memory_book',
      pageWidth: _asDouble(book['page_width'], fallback: 1200),
      pageHeight: _asDouble(book['page_height'], fallback: 900),
      spreads: rawSpreads
          .whereType<Map>()
          .map((item) => AlbumSpreadModel.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      layoutSource: json['layout_source']?.toString() ?? 'manual',
    );
  }
}

class AlbumSpreadModel {
  const AlbumSpreadModel({
    required this.spreadIndex,
    required this.templateId,
    required this.leftPage,
    required this.rightPage,
  });

  final int spreadIndex;
  final String templateId;
  final AlbumPageModel leftPage;
  final AlbumPageModel rightPage;

  AlbumSpreadModel copyWith({
    int? spreadIndex,
    String? templateId,
    AlbumPageModel? leftPage,
    AlbumPageModel? rightPage,
  }) {
    return AlbumSpreadModel(
      spreadIndex: spreadIndex ?? this.spreadIndex,
      templateId: templateId ?? this.templateId,
      leftPage: leftPage ?? this.leftPage,
      rightPage: rightPage ?? this.rightPage,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'spread_index': spreadIndex,
      'template_id': templateId,
      'left_page': leftPage.toJson(),
      'right_page': rightPage.toJson(),
    };
  }

  factory AlbumSpreadModel.fromJson(Map<String, dynamic> json) {
    return AlbumSpreadModel(
      spreadIndex: _asInt(json['spread_index']),
      templateId: json['template_id']?.toString() ?? 'custom',
      leftPage: AlbumPageModel.fromJson(
        (json['left_page'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
      ),
      rightPage: AlbumPageModel.fromJson(
        (json['right_page'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
      ),
    );
  }
}

class AlbumPageModel {
  const AlbumPageModel({
    required this.pageIndex,
    required this.side,
    required this.backgroundColorToken,
    required this.elements,
  });

  final int pageIndex;
  final AlbumPageSide side;
  final String backgroundColorToken;
  final List<AlbumElementModel> elements;

  AlbumPageModel copyWith({
    int? pageIndex,
    AlbumPageSide? side,
    String? backgroundColorToken,
    List<AlbumElementModel>? elements,
  }) {
    return AlbumPageModel(
      pageIndex: pageIndex ?? this.pageIndex,
      side: side ?? this.side,
      backgroundColorToken: backgroundColorToken ?? this.backgroundColorToken,
      elements: elements ?? this.elements,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'page_index': pageIndex,
      'side': side.name,
      'background': <String, dynamic>{'color_token': backgroundColorToken},
      'elements': elements.map((element) => element.toJson()).toList(growable: false),
    };
  }

  factory AlbumPageModel.fromJson(Map<String, dynamic> json) {
    final background = (json['background'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final rawElements = json['elements'] as List? ?? const <dynamic>[];
    return AlbumPageModel(
      pageIndex: _asInt(json['page_index']),
      side: AlbumPageSide.values.firstWhere(
        (value) => value.name == json['side']?.toString(),
        orElse: () => AlbumPageSide.left,
      ),
      backgroundColorToken: background['color_token']?.toString() ?? 'paper_warm',
      elements: rawElements
          .whereType<Map>()
          .map((item) => AlbumElementModel.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class AlbumElementModel {
  const AlbumElementModel({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.rotation,
    required this.zIndex,
    required this.locked,
    required this.payload,
    required this.style,
  });

  final String id;
  final AlbumElementType type;
  final double x;
  final double y;
  final double w;
  final double h;
  final double rotation;
  final int zIndex;
  final bool locked;
  final Map<String, dynamic> payload;
  final AlbumElementStyle style;

  AlbumElementModel copyWith({
    String? id,
    AlbumElementType? type,
    double? x,
    double? y,
    double? w,
    double? h,
    double? rotation,
    int? zIndex,
    bool? locked,
    Map<String, dynamic>? payload,
    AlbumElementStyle? style,
  }) {
    return AlbumElementModel(
      id: id ?? this.id,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      w: w ?? this.w,
      h: h ?? this.h,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
      locked: locked ?? this.locked,
      payload: payload ?? this.payload,
      style: style ?? this.style,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'x': x,
      'y': y,
      'w': w,
      'h': h,
      'rotation': rotation,
      'z_index': zIndex,
      'locked': locked,
      ...payload,
      'style': style.toJson(),
    };
  }

  factory AlbumElementModel.fromJson(Map<String, dynamic> json) {
    final payload = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('type')
      ..remove('x')
      ..remove('y')
      ..remove('w')
      ..remove('h')
      ..remove('rotation')
      ..remove('z_index')
      ..remove('locked')
      ..remove('style');
    return AlbumElementModel(
      id: json['id']?.toString() ?? '',
      type: AlbumElementType.values.firstWhere(
        (value) => value.name == json['type']?.toString(),
        orElse: () => AlbumElementType.text,
      ),
      x: _asDouble(json['x']),
      y: _asDouble(json['y']),
      w: _asDouble(json['w'], fallback: 0.3),
      h: _asDouble(json['h'], fallback: 0.2),
      rotation: _asDouble(json['rotation']),
      zIndex: _asInt(json['z_index']),
      locked: json['locked'] == true,
      payload: payload,
      style: AlbumElementStyle.fromJson(
        (json['style'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
      ),
    );
  }
}

class AlbumElementStyle {
  const AlbumElementStyle({
    this.fontId = 'sans_clean',
    this.fontSize = 20,
    this.colorToken = 'ink_soft',
    this.align = AlbumTextAlignValue.left,
    this.weight = '400',
    this.shadow = false,
    this.borderRadius = 0.04,
  });

  final String fontId;
  final double fontSize;
  final String colorToken;
  final AlbumTextAlignValue align;
  final String weight;
  final bool shadow;
  final double borderRadius;

  AlbumElementStyle copyWith({
    String? fontId,
    double? fontSize,
    String? colorToken,
    AlbumTextAlignValue? align,
    String? weight,
    bool? shadow,
    double? borderRadius,
  }) {
    return AlbumElementStyle(
      fontId: fontId ?? this.fontId,
      fontSize: fontSize ?? this.fontSize,
      colorToken: colorToken ?? this.colorToken,
      align: align ?? this.align,
      weight: weight ?? this.weight,
      shadow: shadow ?? this.shadow,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'font_id': fontId,
      'font_size': fontSize,
      'color_token': colorToken,
      'align': align.name,
      'weight': weight,
      'shadow': shadow,
      'border_radius': borderRadius,
    };
  }

  factory AlbumElementStyle.fromJson(Map<String, dynamic> json) {
    return AlbumElementStyle(
      fontId: json['font_id']?.toString() ?? 'sans_clean',
      fontSize: _asDouble(json['font_size'], fallback: 20),
      colorToken: json['color_token']?.toString() ?? 'ink_soft',
      align: AlbumTextAlignValue.values.firstWhere(
        (value) => value.name == json['align']?.toString(),
        orElse: () => AlbumTextAlignValue.left,
      ),
      weight: json['weight']?.toString() ?? '400',
      shadow: json['shadow'] == true,
      borderRadius: _asDouble(json['border_radius'], fallback: 0.04),
    );
  }
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
