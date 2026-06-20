/// 数字相册版式服务，计算页面结构、排版和样式配置。

import 'dart:math' as math;

import '../models/vo/album_book_models.dart';
import '../models/vo/photo.dart';
import '../models/vo/story_section.dart';

enum _SpreadKind {
  heroQuote,
  manifesto,
  diptych,
  triptych,
  boardQuad,
  galleryJournal,
  marginColumn,
  portraitFeature,
}

enum AlbumBookStylePreset {
  editorial,
  journal,
  gallery,
  statement,
  cinema,
  narrative,
  keepsake,
  minimal,
}

extension AlbumBookStylePresetX on AlbumBookStylePreset {
  String get label {
    switch (this) {
      case AlbumBookStylePreset.editorial:
        return 'Editorial';
      case AlbumBookStylePreset.journal:
        return 'Journal';
      case AlbumBookStylePreset.gallery:
        return 'Gallery';
      case AlbumBookStylePreset.statement:
        return 'Statement';
      case AlbumBookStylePreset.cinema:
        return 'Cinema';
      case AlbumBookStylePreset.narrative:
        return 'Narrative';
      case AlbumBookStylePreset.keepsake:
        return 'Keepsake';
      case AlbumBookStylePreset.minimal:
        return 'Minimal';
    }
  }

  static AlbumBookStylePreset fromName(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'journal':
        return AlbumBookStylePreset.journal;
      case 'gallery':
        return AlbumBookStylePreset.gallery;
      case 'statement':
        return AlbumBookStylePreset.statement;
      case 'cinema':
        return AlbumBookStylePreset.cinema;
      case 'narrative':
        return AlbumBookStylePreset.narrative;
      case 'keepsake':
        return AlbumBookStylePreset.keepsake;
      case 'minimal':
        return AlbumBookStylePreset.minimal;
      default:
        return AlbumBookStylePreset.editorial;
    }
  }
}

class AlbumBookAiSpreadPlan {
  const AlbumBookAiSpreadPlan({
    required this.templateId,
    required this.photoIds,
    this.title = '',
    this.body = '',
    this.meta = '',
    this.note = '',
    this.artWord = '',
  });

  final String templateId;
  final List<String> photoIds;
  final String title;
  final String body;
  final String meta;
  final String note;
  final String artWord;
}

class AlbumBookAiPlan {
  const AlbumBookAiPlan({
    required this.spreads,
    this.stylePreset = AlbumBookStylePreset.editorial,
  });

  final AlbumBookStylePreset stylePreset;
  final List<AlbumBookAiSpreadPlan> spreads;
}

class _SpreadCopy {
  const _SpreadCopy({
    this.title = '',
    this.body = '',
    this.meta = '',
    this.note = '',
    this.artWord = '',
  });

  final String title;
  final String body;
  final String meta;
  final String note;
  final String artWord;
}

class _SectionGroup {
  const _SectionGroup({
    required this.kind,
    required this.sections,
    required this.variantSeed,
    this.copy,
  });

  final _SpreadKind kind;
  final List<StorySection> sections;
  final int variantSeed;
  final _SpreadCopy? copy;
}

class DigitalAlbumLayoutService {
  const DigitalAlbumLayoutService();

  static const String latestLayoutSource = 'local_composed_v6';
  static const double _pageWidth = 900;
  static const double _pageHeight = 860;
  static const String heroTemplateId = 'hero_full_bleed';
  static const String manifestoTemplateId = 'manifesto_quote';
  static const String diptychTemplateId = 'diptych_memory';
  static const String triptychTemplateId = 'triptych_rhythm';
  static const String boardTemplateId = 'collage_board';
  static const String journalTemplateId = 'gallery_journal';
  static const String marginTemplateId = 'margin_column';
  static const String portraitTemplateId = 'portrait_feature';
  static const List<String> selectableTemplateIds = <String>[
    heroTemplateId,
    manifestoTemplateId,
    diptychTemplateId,
    triptychTemplateId,
    boardTemplateId,
    journalTemplateId,
    marginTemplateId,
    portraitTemplateId,
  ];
  static const Set<String> defaultTemplateIds = <String>{
    heroTemplateId,
    manifestoTemplateId,
    diptychTemplateId,
    triptychTemplateId,
    boardTemplateId,
    journalTemplateId,
    marginTemplateId,
    portraitTemplateId,
  };
  static const Map<String, String> templateLabels = <String, String>{
    heroTemplateId: '大图文',
    manifestoTemplateId: '宣言页',
    diptychTemplateId: '双页照',
    triptychTemplateId: '三联页',
    boardTemplateId: '拼贴页',
    journalTemplateId: '日记页',
    marginTemplateId: '栏页',
    portraitTemplateId: '肖像页',
  };

  static bool supportsSinglePhoto(String templateId) {
    return templateId == heroTemplateId ||
        templateId == manifestoTemplateId ||
        templateId == marginTemplateId ||
        templateId == portraitTemplateId;
  }
  static const List<String> _universalInterludes = <String>[
    '这一页，替温柔留一个位置',
    '把目光停一停，故事就会慢下来',
    '平常的一瞬，也值得被郑重收藏',
    '有些心动，不必声张也会发亮',
    '日子被轻轻翻开，光也落进来了',
    '愿所有细小欢喜，都有地方安放',
    '把柔软留在纸页之间，回头时就能看见',
    '这一刻不急着过去，刚好适合记住',
    '风景与人声，都在这一页变得温柔',
    '时间没有停下，只是在这里放慢了脚步',
    '原来被认真看见，本身就很动人',
    '把此刻收好，往后翻也还是会喜欢',
    '有光经过的时候，连沉默都变得好看',
    '这一页不喧哗，却足够让人停留',
  ];
  static const List<String> _endingInterludes = <String>[
    '翻到这里，故事还没有结束',
    '这一页是停顿，不是告别',
    '合上相册时，余温还留在纸页之间',
    '那些被记住的瞬间，会在往后继续发亮',
    '故事暂时收束，心动仍在路上',
    '回头再看时，今天也会成为温柔的注脚',
    '纸页到这里，生活还在继续生长',
    '这一段被妥帖安放，下一段也正在赶来',
  ];

  AlbumBookDocument buildDefaultBook({
    required String title,
    required String subtitle,
    required List<StorySection> sections,
    AlbumBookStylePreset preset = AlbumBookStylePreset.editorial,
    Set<String>? allowedTemplateIds,
  }) {
    final cleanSections = sections
        .where((section) => section.photo.id.trim().isNotEmpty)
        .toList(growable: false);
    final uniqueSections = <StorySection>[];
    final seenPhotoKeys = <String>{};
    for (final section in cleanSections) {
      final key = section.photo.id.trim();
      if (seenPhotoKeys.add(key)) {
        uniqueSections.add(section);
      }
    }

    if (uniqueSections.isEmpty) {
      return AlbumBookDocument(
        title: title,
        subtitle: subtitle,
        theme: 'memory_book',
        pageWidth: _pageWidth,
        pageHeight: _pageHeight,
        layoutSource: latestLayoutSource,
        spreads: <AlbumSpreadModel>[
          _spread(
            spreadIndex: 0,
            templateId: 'cover_spread',
            leftBackground: 'paper_warm',
            rightBackground: 'paper_rose',
            leftElements: <AlbumElementModel>[
              _textElement(
                id: 'empty_title',
                text: title.trim().isEmpty
                    ? '\u8fd9\u4e00\u9875\uff0c\u7559\u7ed9\u56de\u5fc6'
                    : title.trim(),
                role: 'title',
                x: 0.10,
                y: 0.22,
                w: 0.72,
                h: 0.18,
                fontId: 'serif_elegant',
                fontSize: 40,
                weight: '700',
              ),
              _textElement(
                id: 'empty_body',
                text: subtitle.trim().isEmpty
                    ? '\u7b49\u6709\u4e86\u7167\u7247\uff0c\u518d\u628a\u6545\u4e8b\u6162\u6162\u653e\u8fdb\u6765\u3002'
                    : subtitle.trim(),
                role: 'body',
                x: 0.10,
                y: 0.54,
                w: 0.68,
                h: 0.18,
                fontId: 'serif_elegant',
                fontSize: 21,
                colorToken: 'ink_soft',
              ),
            ],
            rightElements: <AlbumElementModel>[
              _textElement(
                id: 'empty_word',
                text: '\u7559\u767d',
                role: 'art_word',
                x: 0.16,
                y: 0.34,
                w: 0.40,
                h: 0.18,
                fontId: 'display_modern',
                fontSize: 48,
                colorToken: 'rose_accent',
                weight: '700',
              ),
            ],
          ),
        ],
      );
    }

    final spreads = <AlbumSpreadModel>[
      _buildCoverSpread(
        spreadIndex: 0,
        title: title,
        subtitle: subtitle,
        hero: uniqueSections.first,
      ),
    ];

    final contentSections = uniqueSections.length > 2
        ? uniqueSections.sublist(1, uniqueSections.length - 1)
        : (uniqueSections.length > 1 ? uniqueSections.sublist(1) : uniqueSections);
    final groups = _buildGroups(
      contentSections,
      preset: preset,
      allowedTemplateIds: allowedTemplateIds,
    );
    for (final group in groups) {
      spreads.add(
        _buildContentSpread(
          spreadIndex: spreads.length,
          group: group,
        ),
      );
    }

    if (uniqueSections.length > 1) {
      spreads.add(
        _buildEndingSpread(
          spreadIndex: spreads.length,
          title: title,
          subtitle: subtitle,
          section: uniqueSections.last,
        ),
      );
    }

    return AlbumBookDocument(
      title: title,
      subtitle: subtitle,
      theme: 'memory_book',
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
      spreads: spreads,
      layoutSource: '${latestLayoutSource}_${preset.name}',
    );
  }

  AlbumBookDocument buildBookFromAiPlan({
    required String title,
    required String subtitle,
    required List<StorySection> sections,
    required AlbumBookAiPlan plan,
    AlbumBookStylePreset? preset,
  }) {
    final chosenPreset = preset ?? plan.stylePreset;
    if (plan.spreads.isEmpty) {
      return buildDefaultBook(
        title: title,
        subtitle: subtitle,
        sections: sections,
        preset: chosenPreset,
      );
    }

    final cleanSections = sections
        .where((section) => section.photo.id.trim().isNotEmpty)
        .toList(growable: false);
    if (cleanSections.isEmpty) {
      return buildDefaultBook(
        title: title,
        subtitle: subtitle,
        sections: sections,
        preset: chosenPreset,
      );
    }

    final uniqueSections = <StorySection>[];
    final seenPhotoKeys = <String>{};
    for (final section in cleanSections) {
      final key = section.photo.id.trim();
      if (seenPhotoKeys.add(key)) {
        uniqueSections.add(section);
      }
    }

    final contentSections = uniqueSections.length > 2
        ? uniqueSections.sublist(1, uniqueSections.length - 1)
        : (uniqueSections.length > 1 ? uniqueSections.sublist(1) : uniqueSections);
    final contentById = <String, StorySection>{
      for (final section in contentSections) section.photo.id: section,
    };

    final plannedGroups = <_SectionGroup>[];
    final usedPhotoIds = <String>{};
    for (var i = 0; i < plan.spreads.length; i++) {
      final spread = plan.spreads[i];
      final plannedSections = <StorySection>[];
      for (final photoId in spread.photoIds) {
        final section = contentById[photoId];
        if (section == null) {
          continue;
        }
        if (usedPhotoIds.add(photoId)) {
          plannedSections.add(section);
        }
      }
      if (plannedSections.isEmpty) {
        continue;
      }
      plannedGroups.add(
        _SectionGroup(
          kind: _kindFromTemplateId(spread.templateId, plannedSections),
          sections: plannedSections,
          variantSeed: i,
          copy: _SpreadCopy(
            title: spread.title,
            body: spread.body,
            meta: spread.meta,
            note: spread.note,
            artWord: spread.artWord,
          ),
        ),
      );
    }

    final leftovers = contentSections.where((section) => !usedPhotoIds.contains(section.photo.id)).toList(growable: false);
    final groups = <_SectionGroup>[
      ...plannedGroups,
      ..._buildGroups(
        leftovers,
        preset: chosenPreset,
        seedOffset: plannedGroups.length * 13,
      ),
    ];

    final spreads = <AlbumSpreadModel>[
      _buildCoverSpread(
        spreadIndex: 0,
        title: title,
        subtitle: subtitle,
        hero: uniqueSections.first,
      ),
    ];
    for (final group in groups) {
      spreads.add(
        _buildContentSpread(
          spreadIndex: spreads.length,
          group: group,
        ),
      );
    }
    if (uniqueSections.length > 1) {
      spreads.add(
        _buildEndingSpread(
          spreadIndex: spreads.length,
          title: title,
          subtitle: subtitle,
          section: uniqueSections.last,
        ),
      );
    }

    return AlbumBookDocument(
      title: title,
      subtitle: subtitle,
      theme: 'memory_book',
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
      spreads: spreads,
      layoutSource: 'ai_plan_${chosenPreset.name}',
    );
  }

  List<_SectionGroup> _buildGroups(
    List<StorySection> sections, {
    required AlbumBookStylePreset preset,
    int seedOffset = 0,
    Set<String>? allowedTemplateIds,
  }) {
    if (sections.isEmpty) {
      return const <_SectionGroup>[];
    }

    final allowedKinds = _normalizeAllowedKinds(allowedTemplateIds);
    final preferredSizes = _preferredGroupSizes(allowedKinds);
    final groups = <_SectionGroup>[];
    var cursor = 0;
    while (cursor < sections.length) {
      final remaining = sections.length - cursor;
      final chosenSize = _pickGroupSize(
        remaining: remaining,
        availableSizes: preferredSizes,
        sections: sections,
        cursor: cursor,
      );
      final take = math.min(chosenSize, remaining);
      final slice = sections.sublist(cursor, cursor + take);
      groups.add(
        _SectionGroup(
          kind: _pickKindForSize(
            preset,
            seedOffset + cursor,
            allowedKinds,
            take,
          ),
          sections: slice,
          variantSeed: seedOffset + cursor,
        ),
      );
      cursor += take;
    }

    return groups;
  }

  List<int> _preferredGroupSizes(Set<_SpreadKind>? allowedKinds) {
    final sizes = <int>[];
    if (_allowsGroupSize(allowedKinds, 4)) {
      sizes.add(4);
    }
    if (_allowsGroupSize(allowedKinds, 3)) {
      sizes.add(3);
    }
    if (_allowsGroupSize(allowedKinds, 2)) {
      sizes.add(2);
    }
    if (_allowsGroupSize(allowedKinds, 1)) {
      sizes.add(1);
    }
    return sizes.isEmpty ? <int>[1] : sizes;
  }

  int _pickGroupSize({
    required int remaining,
    required List<int> availableSizes,
    required List<StorySection> sections,
    required int cursor,
  }) {
    if (remaining <= 1) {
      return 1;
    }
    for (final size in availableSizes) {
      if (size > remaining) {
        continue;
      }
      if (size == 4) {
        final quad = sections.sublist(cursor, cursor + 4);
        if (_clusterScore(quad) >= 3.0 || remaining == 4) {
          return 4;
        }
        continue;
      }
      if (size == 3) {
        final tri = sections.sublist(cursor, cursor + 3);
        if (_clusterScore(tri) >= 1.8 || remaining == 3) {
          return 3;
        }
        continue;
      }
      if (size == 2) {
        final duo = sections.sublist(cursor, cursor + 2);
        if (_areRelated(duo.first, duo.last) || remaining == 2) {
          return 2;
        }
        continue;
      }
      if (size == 1) {
        return 1;
      }
    }
    return availableSizes.firstWhere((size) => size <= remaining, orElse: () => 1);
  }

  _SpreadKind _pickKindForSize(
    AlbumBookStylePreset preset,
    int seed,
    Set<_SpreadKind>? allowedKinds,
    int size,
  ) {
    switch (size) {
      case 4:
        return _pickQuadKind(preset, seed, allowedKinds);
      case 3:
        return _pickTriKind(preset, seed, allowedKinds);
      case 2:
        return _pickDuoKind(preset, seed, allowedKinds);
      default:
        return _pickSingleKind(preset, seed, allowedKinds);
    }
  }

  Set<_SpreadKind>? _normalizeAllowedKinds(Set<String>? allowedTemplateIds) {
    if (allowedTemplateIds == null || allowedTemplateIds.isEmpty) {
      return null;
    }
    final kinds = allowedTemplateIds
        .map(_kindForTemplateId)
        .whereType<_SpreadKind>()
        .toSet();
    return kinds.isEmpty ? null : kinds;
  }

  bool _allowsGroupSize(Set<_SpreadKind>? allowedKinds, int size) {
    final kinds = switch (size) {
      4 => const <_SpreadKind>{_SpreadKind.boardQuad, _SpreadKind.galleryJournal},
      3 => const <_SpreadKind>{_SpreadKind.triptych, _SpreadKind.galleryJournal},
      2 => const <_SpreadKind>{
          _SpreadKind.diptych,
          _SpreadKind.marginColumn,
          _SpreadKind.portraitFeature,
        },
      _ => const <_SpreadKind>{
          _SpreadKind.heroQuote,
          _SpreadKind.manifesto,
          _SpreadKind.marginColumn,
          _SpreadKind.portraitFeature,
        },
    };
    return allowedKinds == null || allowedKinds.any(kinds.contains);
  }

  List<_SpreadKind> _filterAllowedKinds(
    List<_SpreadKind> options,
    Set<_SpreadKind>? allowedKinds,
  ) {
    if (allowedKinds == null || allowedKinds.isEmpty) {
      return options;
    }
    final filtered = options.where(allowedKinds.contains).toList(growable: false);
    return filtered.isEmpty ? <_SpreadKind>[options.first] : filtered;
  }

  _SpreadKind? _kindForTemplateId(String templateId) {
    switch (templateId) {
      case heroTemplateId:
        return _SpreadKind.heroQuote;
      case manifestoTemplateId:
        return _SpreadKind.manifesto;
      case diptychTemplateId:
        return _SpreadKind.diptych;
      case triptychTemplateId:
        return _SpreadKind.triptych;
      case boardTemplateId:
        return _SpreadKind.boardQuad;
      case journalTemplateId:
        return _SpreadKind.galleryJournal;
      case marginTemplateId:
        return _SpreadKind.marginColumn;
      case portraitTemplateId:
        return _SpreadKind.portraitFeature;
      default:
        return null;
    }
  }

  _SpreadKind _pickQuadKind(
    AlbumBookStylePreset preset,
    int seed,
    Set<_SpreadKind>? allowedKinds,
  ) {
    final options = _filterAllowedKinds(switch (preset) {
      AlbumBookStylePreset.editorial => const <_SpreadKind>[
          _SpreadKind.boardQuad,
          _SpreadKind.galleryJournal,
        ],
      AlbumBookStylePreset.journal => const <_SpreadKind>[
          _SpreadKind.galleryJournal,
          _SpreadKind.boardQuad,
        ],
      AlbumBookStylePreset.gallery => const <_SpreadKind>[
          _SpreadKind.galleryJournal,
          _SpreadKind.boardQuad,
        ],
      AlbumBookStylePreset.statement => const <_SpreadKind>[
          _SpreadKind.galleryJournal,
          _SpreadKind.boardQuad,
        ],
      AlbumBookStylePreset.cinema => const <_SpreadKind>[
          _SpreadKind.boardQuad,
          _SpreadKind.galleryJournal,
        ],
      AlbumBookStylePreset.narrative => const <_SpreadKind>[
          _SpreadKind.boardQuad,
          _SpreadKind.galleryJournal,
        ],
      AlbumBookStylePreset.keepsake => const <_SpreadKind>[
          _SpreadKind.galleryJournal,
          _SpreadKind.boardQuad,
        ],
      AlbumBookStylePreset.minimal => const <_SpreadKind>[
          _SpreadKind.galleryJournal,
          _SpreadKind.boardQuad,
        ],
    }, allowedKinds);
    return options[seed.abs() % options.length];
  }

  _SpreadKind _pickTriKind(
    AlbumBookStylePreset preset,
    int seed,
    Set<_SpreadKind>? allowedKinds,
  ) {
    final options = _filterAllowedKinds(switch (preset) {
      AlbumBookStylePreset.editorial => const <_SpreadKind>[
          _SpreadKind.triptych,
          _SpreadKind.galleryJournal,
        ],
      AlbumBookStylePreset.journal => const <_SpreadKind>[
          _SpreadKind.galleryJournal,
          _SpreadKind.triptych,
        ],
      AlbumBookStylePreset.gallery => const <_SpreadKind>[
          _SpreadKind.galleryJournal,
          _SpreadKind.triptych,
        ],
      AlbumBookStylePreset.statement => const <_SpreadKind>[
          _SpreadKind.galleryJournal,
          _SpreadKind.triptych,
        ],
      AlbumBookStylePreset.cinema => const <_SpreadKind>[
          _SpreadKind.triptych,
          _SpreadKind.galleryJournal,
        ],
      AlbumBookStylePreset.narrative => const <_SpreadKind>[
          _SpreadKind.triptych,
          _SpreadKind.galleryJournal,
        ],
      AlbumBookStylePreset.keepsake => const <_SpreadKind>[
          _SpreadKind.galleryJournal,
          _SpreadKind.triptych,
        ],
      AlbumBookStylePreset.minimal => const <_SpreadKind>[
          _SpreadKind.galleryJournal,
          _SpreadKind.triptych,
        ],
    }, allowedKinds);
    return options[seed.abs() % options.length];
  }

  _SpreadKind _pickDuoKind(
    AlbumBookStylePreset preset,
    int seed,
    Set<_SpreadKind>? allowedKinds,
  ) {
    final options = _filterAllowedKinds(switch (preset) {
      AlbumBookStylePreset.editorial => const <_SpreadKind>[
          _SpreadKind.diptych,
          _SpreadKind.marginColumn,
        ],
      AlbumBookStylePreset.journal => const <_SpreadKind>[
          _SpreadKind.marginColumn,
          _SpreadKind.diptych,
        ],
      AlbumBookStylePreset.gallery => const <_SpreadKind>[
          _SpreadKind.portraitFeature,
          _SpreadKind.diptych,
        ],
      AlbumBookStylePreset.statement => const <_SpreadKind>[
          _SpreadKind.marginColumn,
          _SpreadKind.portraitFeature,
        ],
      AlbumBookStylePreset.cinema => const <_SpreadKind>[
          _SpreadKind.diptych,
          _SpreadKind.portraitFeature,
        ],
      AlbumBookStylePreset.narrative => const <_SpreadKind>[
          _SpreadKind.marginColumn,
          _SpreadKind.diptych,
        ],
      AlbumBookStylePreset.keepsake => const <_SpreadKind>[
          _SpreadKind.portraitFeature,
          _SpreadKind.marginColumn,
        ],
      AlbumBookStylePreset.minimal => const <_SpreadKind>[
          _SpreadKind.marginColumn,
          _SpreadKind.diptych,
        ],
    }, allowedKinds);
    return options[seed.abs() % options.length];
  }

  _SpreadKind _pickSingleKind(
    AlbumBookStylePreset preset,
    int seed,
    Set<_SpreadKind>? allowedKinds,
  ) {
    final options = _filterAllowedKinds(switch (preset) {
      AlbumBookStylePreset.editorial => const <_SpreadKind>[
          _SpreadKind.heroQuote,
          _SpreadKind.manifesto,
        ],
      AlbumBookStylePreset.journal => const <_SpreadKind>[
          _SpreadKind.marginColumn,
          _SpreadKind.heroQuote,
        ],
      AlbumBookStylePreset.gallery => const <_SpreadKind>[
          _SpreadKind.portraitFeature,
          _SpreadKind.heroQuote,
        ],
      AlbumBookStylePreset.statement => const <_SpreadKind>[
          _SpreadKind.manifesto,
          _SpreadKind.marginColumn,
        ],
      AlbumBookStylePreset.cinema => const <_SpreadKind>[
          _SpreadKind.portraitFeature,
          _SpreadKind.manifesto,
        ],
      AlbumBookStylePreset.narrative => const <_SpreadKind>[
          _SpreadKind.heroQuote,
          _SpreadKind.marginColumn,
        ],
      AlbumBookStylePreset.keepsake => const <_SpreadKind>[
          _SpreadKind.heroQuote,
          _SpreadKind.portraitFeature,
        ],
      AlbumBookStylePreset.minimal => const <_SpreadKind>[
          _SpreadKind.manifesto,
          _SpreadKind.heroQuote,
        ],
    }, allowedKinds);
    return options[seed.abs() % options.length];
  }

  _SpreadKind _kindFromTemplateId(String templateId, List<StorySection> sections) {
    switch (templateId) {
      case 'hero_full_bleed':
        return _SpreadKind.heroQuote;
      case 'manifesto_quote':
      case 'family_statement':
        return _SpreadKind.manifesto;
      case 'diptych_memory':
        return _SpreadKind.diptych;
      case 'triptych_rhythm':
        return _SpreadKind.triptych;
      case 'gallery_journal':
        return _SpreadKind.galleryJournal;
      case 'margin_column':
        return _SpreadKind.marginColumn;
      case 'portrait_feature':
        return _SpreadKind.portraitFeature;
      case 'collage_board':
      default:
        return sections.length >= 4 ? _SpreadKind.boardQuad : _SpreadKind.diptych;
    }
  }

  double _clusterScore(List<StorySection> sections) {
    if (sections.length <= 1) {
      return 0;
    }

    double score = 0;
    for (var i = 0; i < sections.length; i++) {
      for (var j = i + 1; j < sections.length; j++) {
        if (_areRelated(sections[i], sections[j])) {
          score += 1.2;
        }
        score += _sharedTags(sections[i], sections[j]) * 0.35;
        score += _semanticSimilarity(sections[i], sections[j]) * 0.9;
        if (_sameLocation(sections[i].photo.location, sections[j].photo.location)) {
          score += 0.6;
        }
        final hours = sections[i]
            .photo
            .dateTaken
            .difference(sections[j].photo.dateTaken)
            .inHours
            .abs();
        if (hours <= 6) {
          score += 0.45;
        } else if (hours <= 18) {
          score += 0.2;
        }
      }
    }
    return score;
  }

  bool _areRelated(StorySection a, StorySection b) {
    if (_sharedTags(a, b) > 0) {
      return true;
    }
    if (_semanticSimilarity(a, b) >= 0.28) {
      return true;
    }
    if (_sameLocation(a.photo.location, b.photo.location)) {
      return true;
    }
    final hours = a.photo.dateTaken.difference(b.photo.dateTaken).inHours.abs();
    return hours <= 18;
  }

  double _semanticSimilarity(StorySection a, StorySection b) {
    final left = _tokenWeightsForSection(a);
    final right = _tokenWeightsForSection(b);
    if (left.isEmpty || right.isEmpty) {
      return 0;
    }

    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (final entry in left.entries) {
      final value = entry.value;
      leftNorm += value * value;
      dot += value * (right[entry.key] ?? 0);
    }
    for (final value in right.values) {
      rightNorm += value * value;
    }
    if (leftNorm <= 0 || rightNorm <= 0) {
      return 0;
    }
    return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }

  Map<String, double> _tokenWeightsForSection(StorySection section) {
    final raw = <String>[
      section.text,
      section.photo.caption ?? '',
      section.photo.location ?? '',
      section.photo.ocrSummary ?? '',
      section.photo.tags.join(' '),
      section.photo.ocrTags.join(' '),
    ].join(' ').toLowerCase();

    final tokens = raw
        .split(RegExp(r'[^0-9a-zA-Z\u4e00-\u9fa5]+'))
        .map((token) => token.trim())
        .where((token) => token.runes.length >= 2)
        .take(80);

    final weights = <String, double>{};
    for (final token in tokens) {
      weights[token] = (weights[token] ?? 0) + 1;
    }
    return weights;
  }

  int _sharedTags(StorySection a, StorySection b) {
    final left = a.photo.tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toSet();
    final right = b.photo.tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toSet();
    return left.intersection(right).length;
  }

  bool _sameLocation(String? left, String? right) {
    final a = left?.trim() ?? '';
    final b = right?.trim() ?? '';
    if (a.isEmpty || b.isEmpty) {
      return false;
    }
    return a == b || a.contains(b) || b.contains(a);
  }

  AlbumSpreadModel _buildContentSpread({
    required int spreadIndex,
    required _SectionGroup group,
  }) {
    switch (group.kind) {
      case _SpreadKind.heroQuote:
        return _buildHeroQuoteSpread(spreadIndex: spreadIndex, group: group);
      case _SpreadKind.manifesto:
        return _buildManifestoSpread(spreadIndex: spreadIndex, group: group);
      case _SpreadKind.diptych:
        return _buildDiptychSpread(spreadIndex: spreadIndex, group: group);
      case _SpreadKind.triptych:
        return _buildTriptychSpread(spreadIndex: spreadIndex, group: group);
      case _SpreadKind.boardQuad:
        return _buildBoardQuadSpread(spreadIndex: spreadIndex, group: group);
      case _SpreadKind.galleryJournal:
        return _buildGalleryJournalSpread(spreadIndex: spreadIndex, group: group);
      case _SpreadKind.marginColumn:
        return _buildMarginColumnSpread(spreadIndex: spreadIndex, group: group);
      case _SpreadKind.portraitFeature:
        return _buildPortraitFeatureSpread(spreadIndex: spreadIndex, group: group);
    }
  }

  String _groupWord(_SectionGroup group) {
    final override = group.copy?.artWord.trim() ?? '';
    return override.isNotEmpty ? override : _spreadWord(group.sections);
  }

  String _groupTitle(_SectionGroup group) {
    final override = group.copy?.title.trim() ?? '';
    return override.isNotEmpty ? override : _spreadTitle(group.sections);
  }

  String _groupBody(_SectionGroup group) {
    final override = group.copy?.body.trim() ?? '';
    return override.isNotEmpty ? override : _spreadBody(group.sections);
  }

  String _groupNote(_SectionGroup group) {
    final override = group.copy?.note.trim() ?? '';
    return override.isNotEmpty
        ? override
        : _spreadInterlude(group.sections, group.variantSeed);
  }

  String _groupMeta(_SectionGroup group, Photo photo) {
    final override = group.copy?.meta.trim() ?? '';
    return override.isNotEmpty ? override : _metaLine(photo);
  }

  AlbumSpreadModel _buildCoverSpread({
    required int spreadIndex,
    required String title,
    required String subtitle,
    required StorySection hero,
  }) {
    final coverTitle = title.trim().isNotEmpty ? title.trim() : _spreadTitle(<StorySection>[hero]);
    final coverBody = subtitle.trim().isNotEmpty
        ? _trimText(subtitle.trim(), 42)
        : _spreadBody(<StorySection>[hero]);

    return _spread(
      spreadIndex: spreadIndex,
      templateId: 'cover_spread',
      leftBackground: 'paper_warm',
      rightBackground: 'paper_rose',
      leftElements: <AlbumElementModel>[
        _textElement(
          id: 'cover_year',
          text: '${hero.photo.dateTaken.year}',
          role: 'meta',
          x: 0.10,
          y: 0.12,
          w: 0.22,
          h: 0.07,
          fontId: 'mono_note',
          fontSize: 19,
          colorToken: 'gold_accent',
        ),
        _textElement(
          id: 'cover_title',
          text: coverTitle,
          role: 'title',
          x: 0.10,
          y: 0.22,
          w: 0.72,
          h: 0.18,
          fontId: 'serif_elegant',
          fontSize: 38,
          weight: '700',
        ),
        _shapeElement(
          id: 'cover_word_shape',
          x: 0.10,
          y: 0.46,
          w: 0.34,
          h: 0.12,
          colorToken: 'rose_accent',
          fillAlpha: 0.10,
          borderRadius: 0.08,
        ),
        _textElement(
          id: 'cover_word',
          text: _spreadWord(<StorySection>[hero]),
          role: 'art_word',
          x: 0.12,
          y: 0.44,
          w: 0.34,
          h: 0.14,
          fontId: 'display_modern',
          fontSize: 42,
          colorToken: 'rose_accent',
          weight: '700',
        ),
        _textElement(
          id: 'cover_body',
          text: coverBody,
          role: 'body',
          x: 0.10,
          y: 0.66,
          w: 0.68,
          h: 0.14,
          fontId: 'serif_elegant',
          fontSize: 21,
          colorToken: 'ink_soft',
        ),
      ],
      rightElements: <AlbumElementModel>[
        _imageElement(
          id: 'cover_image',
          photo: hero.photo,
          x: 0.03,
          y: 0.05,
          w: 0.94,
          h: 0.90,
          borderRadius: 0.03,
        ),
      ],
    );
  }

  AlbumSpreadModel _buildHeroQuoteSpread({
    required int spreadIndex,
    required _SectionGroup group,
  }) {
    final section = group.sections.first;
    return _spread(
      spreadIndex: spreadIndex,
      templateId: 'hero_full_bleed',
      leftBackground: _backgroundFor(group.kind, group.variantSeed, false),
      rightBackground: _backgroundFor(group.kind, group.variantSeed, true),
      leftElements: <AlbumElementModel>[
        _imageElement(
          id: 'hero_${spreadIndex}_image',
          photo: section.photo,
          x: 0.02,
          y: 0.02,
          w: 0.96,
          h: 0.96,
          borderRadius: 0.025,
        ),
      ],
      rightElements: <AlbumElementModel>[
        _textElement(
          id: 'hero_${spreadIndex}_meta',
          text: _groupMeta(group, section.photo),
          role: 'meta',
          x: 0.10,
          y: 0.10,
          w: 0.60,
          h: 0.06,
          fontId: 'mono_note',
          fontSize: 18,
          colorToken: 'gold_accent',
        ),
        _textElement(
          id: 'hero_${spreadIndex}_word',
          text: _groupWord(group),
          role: 'art_word',
          x: 0.10,
          y: 0.18,
          w: 0.44,
          h: 0.15,
          fontId: 'display_modern',
          fontSize: 44,
          colorToken: 'rose_accent',
          weight: '700',
        ),
        _textElement(
          id: 'hero_${spreadIndex}_title',
          text: _groupTitle(group),
          role: 'title',
          x: 0.10,
          y: 0.38,
          w: 0.76,
          h: 0.15,
          fontId: 'serif_elegant',
          fontSize: 34,
          weight: '700',
        ),
        _textElement(
          id: 'hero_${spreadIndex}_body',
          text: _groupBody(group),
          role: 'body',
          x: 0.12,
          y: 0.56,
          w: 0.72,
          h: 0.20,
          fontId: 'serif_elegant',
          fontSize: 22,
          colorToken: 'ink_soft',
        ),
        _textElement(
          id: 'hero_${spreadIndex}_whisper',
          text: _groupNote(group),
          role: 'caption',
          x: 0.12,
          y: 0.83,
          w: 0.70,
          h: 0.06,
          fontId: 'handwriting_soft',
          fontSize: 18,
          colorToken: 'ink_soft',
        ),
      ],
    );
  }

  AlbumSpreadModel _buildManifestoSpread({
    required int spreadIndex,
    required _SectionGroup group,
  }) {
    final section = group.sections.first;
    return _spread(
      spreadIndex: spreadIndex,
      templateId: 'manifesto_quote',
      leftBackground: _backgroundFor(group.kind, group.variantSeed, false),
      rightBackground: _backgroundFor(group.kind, group.variantSeed, true),
      leftElements: <AlbumElementModel>[
        _shapeElement(
          id: 'manifesto_${spreadIndex}_shape',
          x: 0.08,
          y: 0.10,
          w: 0.42,
          h: 0.15,
          colorToken: 'sage_accent',
          fillAlpha: 0.12,
          borderRadius: 0.08,
        ),
        _textElement(
          id: 'manifesto_${spreadIndex}_word',
          text: _groupWord(group),
          role: 'art_word',
          x: 0.10,
          y: 0.12,
          w: 0.38,
          h: 0.12,
          fontId: 'display_modern',
          fontSize: 40,
          colorToken: 'gold_accent',
          weight: '700',
        ),
        _textElement(
          id: 'manifesto_${spreadIndex}_title',
          text: _groupTitle(group),
          role: 'title',
          x: 0.10,
          y: 0.34,
          w: 0.76,
          h: 0.16,
          fontId: 'serif_elegant',
          fontSize: 32,
          weight: '700',
        ),
        _textElement(
          id: 'manifesto_${spreadIndex}_body',
          text: _groupBody(group),
          role: 'body',
          x: 0.12,
          y: 0.58,
          w: 0.66,
          h: 0.22,
          fontId: 'serif_elegant',
          fontSize: 21,
          colorToken: 'ink_soft',
        ),
      ],
      rightElements: <AlbumElementModel>[
        _imageElement(
          id: 'manifesto_${spreadIndex}_image',
          photo: section.photo,
          x: 0.02,
          y: 0.04,
          w: 0.96,
          h: 0.88,
          borderRadius: 0.025,
        ),
      ],
    );
  }

  AlbumSpreadModel _buildDiptychSpread({
    required int spreadIndex,
    required _SectionGroup group,
  }) {
    final left = group.sections.first;
    final right = group.sections.last;
    return _spread(
      spreadIndex: spreadIndex,
      templateId: 'diptych_memory',
      leftBackground: _backgroundFor(group.kind, group.variantSeed, false),
      rightBackground: _backgroundFor(group.kind, group.variantSeed, true),
      leftElements: <AlbumElementModel>[
        _imageElement(
          id: 'diptych_${spreadIndex}_left_image',
          photo: left.photo,
          x: 0.03,
          y: 0.05,
          w: 0.90,
          h: 0.58,
          borderRadius: 0.03,
        ),
        _textElement(
          id: 'diptych_${spreadIndex}_left_meta',
          text: _groupMeta(group, left.photo),
          role: 'meta',
          x: 0.08,
          y: 0.70,
          w: 0.42,
          h: 0.05,
          fontId: 'mono_note',
          fontSize: 17,
          colorToken: 'gold_accent',
        ),
        _textElement(
          id: 'diptych_${spreadIndex}_left_title',
          text: _groupTitle(group),
          role: 'title',
          x: 0.08,
          y: 0.78,
          w: 0.74,
          h: 0.11,
          fontId: 'serif_elegant',
          fontSize: 29,
          weight: '700',
        ),
      ],
      rightElements: <AlbumElementModel>[
        _shapeElement(
          id: 'diptych_${spreadIndex}_word_shape',
          x: 0.08,
          y: 0.10,
          w: 0.64,
          h: 0.12,
          colorToken: 'paper_warm',
          fillAlpha: 0.22,
          borderRadius: 0.08,
        ),
        _textElement(
          id: 'diptych_${spreadIndex}_word',
          text: _groupWord(group),
          role: 'art_word',
          x: 0.10,
          y: 0.11,
          w: 0.40,
          h: 0.10,
          fontId: 'display_modern',
          fontSize: 34,
          colorToken: 'rose_accent',
          weight: '700',
        ),
        _imageElement(
          id: 'diptych_${spreadIndex}_right_image',
          photo: right.photo,
          x: 0.10,
          y: 0.23,
          w: 0.82,
          h: 0.48,
          borderRadius: 0.03,
        ),
        _textElement(
          id: 'diptych_${spreadIndex}_body',
          text: _groupBody(group),
          role: 'body',
          x: 0.12,
          y: 0.78,
          w: 0.72,
          h: 0.12,
          fontId: 'serif_elegant',
          fontSize: 19,
          colorToken: 'ink_soft',
        ),
      ],
    );
  }

  AlbumSpreadModel _buildTriptychSpread({
    required int spreadIndex,
    required _SectionGroup group,
  }) {
    final first = group.sections[0];
    final second = group.sections[1];
    final third = group.sections[2];
    return _spread(
      spreadIndex: spreadIndex,
      templateId: 'triptych_rhythm',
      leftBackground: _backgroundFor(group.kind, group.variantSeed, false),
      rightBackground: _backgroundFor(group.kind, group.variantSeed, true),
      leftElements: <AlbumElementModel>[
        _imageElement(
          id: 'triptych_${spreadIndex}_hero',
          photo: first.photo,
          x: 0.03,
          y: 0.04,
          w: 0.68,
          h: 0.90,
          borderRadius: 0.03,
        ),
        _textElement(
          id: 'triptych_${spreadIndex}_word',
          text: _verticalizeShortText(_groupWord(group)),
          role: 'art_word',
          x: 0.71,
          y: 0.26,
          w: 0.16,
          h: 0.24,
          fontId: 'display_modern',
          fontSize: 30,
          colorToken: 'gold_accent',
          weight: '700',
          align: AlbumTextAlignValue.center,
        ),
        _textElement(
          id: 'triptych_${spreadIndex}_whisper',
          text: _groupNote(group),
          role: 'caption',
          x: 0.70,
          y: 0.56,
          w: 0.18,
          h: 0.18,
          fontId: 'handwriting_soft',
          fontSize: 17,
          colorToken: 'ink_soft',
          align: AlbumTextAlignValue.center,
        ),
      ],
      rightElements: <AlbumElementModel>[
        _imageElement(
          id: 'triptych_${spreadIndex}_upper',
          photo: second.photo,
          x: 0.08,
          y: 0.06,
          w: 0.76,
          h: 0.24,
          borderRadius: 0.03,
        ),
        _imageElement(
          id: 'triptych_${spreadIndex}_lower',
          photo: third.photo,
          x: 0.08,
          y: 0.37,
          w: 0.76,
          h: 0.24,
          borderRadius: 0.03,
        ),
        _textElement(
          id: 'triptych_${spreadIndex}_body',
          text: _groupBody(group),
          role: 'body',
          x: 0.08,
          y: 0.72,
          w: 0.78,
          h: 0.14,
          fontId: 'serif_elegant',
          fontSize: 17,
          colorToken: 'ink_soft',
        ),
      ],
    );
  }

  AlbumSpreadModel _buildBoardQuadSpread({
    required int spreadIndex,
    required _SectionGroup group,
  }) {
    final a = group.sections[0];
    final b = group.sections[1];
    final c = group.sections[2];
    final d = group.sections[3];
    return _spread(
      spreadIndex: spreadIndex,
      templateId: 'collage_board',
      leftBackground: _backgroundFor(group.kind, group.variantSeed, false),
      rightBackground: _backgroundFor(group.kind, group.variantSeed, true),
      leftElements: <AlbumElementModel>[
        _imageElement(
          id: 'board_${spreadIndex}_a',
          photo: a.photo,
          x: 0.04,
          y: 0.05,
          w: 0.82,
          h: 0.36,
          borderRadius: 0.028,
        ),
        _imageElement(
          id: 'board_${spreadIndex}_b',
          photo: b.photo,
          x: 0.08,
          y: 0.44,
          w: 0.68,
          h: 0.387,
          borderRadius: 0.028,
        ),
        _textElement(
          id: 'board_${spreadIndex}_word',
          text: _groupWord(group),
          role: 'art_word',
          x: 0.16,
          y: 0.855,
          w: 0.12,
          h: 0.06,
          fontId: 'display_modern',
          fontSize: 24,
          colorToken: 'rose_accent',
          weight: '700',
          align: AlbumTextAlignValue.right,
          zIndex: 3,
        ),
        _textElement(
          id: 'board_${spreadIndex}_caption',
          text: _trimText(_groupNote(group), 12),
          role: 'caption',
          x: 0.30,
          y: 0.855,
          w: 0.46,
          h: 0.06,
          fontId: 'handwriting_soft',
          fontSize: 15,
          colorToken: 'ink_soft',
          align: AlbumTextAlignValue.left,
          zIndex: 3,
        ),
      ],
      rightElements: <AlbumElementModel>[
        _imageElement(
          id: 'board_${spreadIndex}_c',
          photo: c.photo,
          x: 0.10,
          y: 0.05,
          w: 0.76,
          h: 0.26,
          borderRadius: 0.028,
        ),
        _imageElement(
          id: 'board_${spreadIndex}_d',
          photo: d.photo,
          x: 0.05,
          y: 0.38,
          w: 0.84,
          h: 0.38,
          borderRadius: 0.028,
        ),
        _textElement(
          id: 'board_${spreadIndex}_title',
          text: _groupTitle(group),
          role: 'title',
          x: 0.08,
          y: 0.82,
          w: 0.72,
          h: 0.08,
          fontId: 'serif_elegant',
          fontSize: 19,
          weight: '700',
        ),
      ],
    );
  }

  AlbumSpreadModel _buildEndingSpread({
    required int spreadIndex,
    required String title,
    required String subtitle,
    required StorySection section,
  }) {
    return _spread(
      spreadIndex: spreadIndex,
      templateId: 'ending_spread',
      leftBackground: 'paper_sage',
      rightBackground: 'paper_warm',
      leftElements: <AlbumElementModel>[
        _textElement(
          id: 'ending_word',
          text: title.trim().isNotEmpty
              ? _trimText(title.trim(), 8)
              : _spreadWord(<StorySection>[section]),
          role: 'art_word',
          x: 0.10,
          y: 0.18,
          w: 0.46,
          h: 0.15,
          fontId: 'display_modern',
          fontSize: 38,
          colorToken: 'sage_accent',
          weight: '700',
        ),
        _textElement(
          id: 'ending_body',
          text: subtitle.trim().isNotEmpty
              ? _trimText(subtitle.trim(), 46)
              : _spreadBody(<StorySection>[section]),
          role: 'body',
          x: 0.10,
          y: 0.54,
          w: 0.62,
          h: 0.18,
          fontId: 'serif_elegant',
          fontSize: 21,
          colorToken: 'ink_soft',
        ),
      ],
      rightElements: <AlbumElementModel>[
        _imageElement(
          id: 'ending_image',
          photo: section.photo,
          x: 0.10,
          y: 0.10,
          w: 0.78,
          h: 0.62,
          borderRadius: 0.03,
        ),
        _textElement(
          id: 'ending_whisper',
          text: _endingInterlude(
            <StorySection>[section],
            seed: spreadIndex + section.photo.dateTaken.day,
          ),
          role: 'caption',
          x: 0.16,
          y: 0.80,
          w: 0.66,
          h: 0.08,
          fontId: 'handwriting_soft',
          fontSize: 20,
          colorToken: 'ink_soft',
        ),
      ],
    );
  }

  AlbumSpreadModel _spread({
    required int spreadIndex,
    required String templateId,
    required String leftBackground,
    required String rightBackground,
    required List<AlbumElementModel> leftElements,
    required List<AlbumElementModel> rightElements,
  }) {
    return AlbumSpreadModel(
      spreadIndex: spreadIndex,
      templateId: templateId,
      leftPage: _page(
        spreadIndex: spreadIndex,
        side: AlbumPageSide.left,
        backgroundColorToken: leftBackground,
        elements: leftElements,
      ),
      rightPage: _page(
        spreadIndex: spreadIndex,
        side: AlbumPageSide.right,
        backgroundColorToken: rightBackground,
        elements: rightElements,
      ),
    );
  }

  AlbumSpreadModel _buildGalleryJournalSpread({
    required int spreadIndex,
    required _SectionGroup group,
  }) {
    final sections = group.sections;
    final a = sections[0];
    final b = sections.length > 1 ? sections[1] : sections[0];
    final c = sections.length > 2 ? sections[2] : sections.last;
    final d = sections.length > 3 ? sections[3] : sections.last;
    final hasFourth = sections.length > 3;
    return _spread(
      spreadIndex: spreadIndex,
      templateId: 'gallery_journal',
      leftBackground: _backgroundFor(group.kind, group.variantSeed, false),
      rightBackground: _backgroundFor(group.kind, group.variantSeed, true),
      leftElements: hasFourth
          ? <AlbumElementModel>[
              _imageElement(
                id: 'journal_${spreadIndex}_a',
                photo: a.photo,
                x: 0.05,
                y: 0.07,
                w: 0.80,
                h: 0.28,
                borderRadius: 0.022,
              ),
              _imageElement(
                id: 'journal_${spreadIndex}_b',
                photo: b.photo,
                x: 0.05,
                y: 0.42,
                w: 0.80,
                h: 0.36,
                borderRadius: 0.024,
              ),
            ]
          : <AlbumElementModel>[
              _imageElement(
                id: 'journal_${spreadIndex}_a',
                photo: a.photo,
                x: 0.06,
                y: 0.10,
                w: 0.78,
                h: 0.66,
                borderRadius: 0.024,
              ),
            ],
      rightElements: <AlbumElementModel>[
        _imageElement(
          id: 'journal_${spreadIndex}_detail',
          photo: hasFourth ? c.photo : b.photo,
          x: 0.07,
          y: 0.08,
          w: 0.36,
          h: 0.20,
          borderRadius: 0.02,
        ),
        _imageElement(
          id: 'journal_${spreadIndex}_echo',
          photo: hasFourth ? d.photo : c.photo,
          x: 0.47,
          y: 0.08,
          w: 0.36,
          h: 0.20,
          borderRadius: 0.02,
        ),
        _textElement(
          id: 'journal_${spreadIndex}_meta',
          text: _groupMeta(group, a.photo),
          role: 'meta',
          x: 0.08,
          y: 0.34,
          w: 0.52,
          h: 0.05,
          fontId: 'mono_note',
          fontSize: 16,
          colorToken: 'gold_accent',
        ),
        _textElement(
          id: 'journal_${spreadIndex}_title',
          text: _groupTitle(group),
          role: 'title',
          x: 0.08,
          y: 0.42,
          w: 0.72,
          h: 0.12,
          fontId: 'serif_elegant',
          fontSize: 30,
          weight: '700',
        ),
        _shapeElement(
          id: 'journal_${spreadIndex}_shape',
          x: 0.08,
          y: 0.56,
          w: 0.76,
          h: 0.25,
          colorToken: 'paper_warm',
          fillAlpha: 0.18,
          borderRadius: 0.06,
        ),
        _textElement(
          id: 'journal_${spreadIndex}_body',
          text: _trimText(_groupBody(group), 86),
          role: 'body',
          x: 0.11,
          y: 0.61,
          w: 0.70,
          h: 0.17,
          fontId: 'serif_elegant',
          fontSize: 20,
          colorToken: 'ink_soft',
        ),
      ],
    );
  }

  AlbumSpreadModel _buildMarginColumnSpread({
    required int spreadIndex,
    required _SectionGroup group,
  }) {
    final primary = group.sections.first;
    final secondary = group.sections.length > 1 ? group.sections.last : group.sections.first;
    return _spread(
      spreadIndex: spreadIndex,
      templateId: 'margin_column',
      leftBackground: _backgroundFor(group.kind, group.variantSeed, false),
      rightBackground: _backgroundFor(group.kind, group.variantSeed, true),
      leftElements: <AlbumElementModel>[
        _imageElement(
          id: 'column_${spreadIndex}_hero',
          photo: primary.photo,
          x: 0.04,
          y: 0.05,
          w: 0.86,
          h: 0.82,
          borderRadius: 0.025,
        ),
      ],
      rightElements: <AlbumElementModel>[
        _textElement(
          id: 'column_${spreadIndex}_meta',
          text: _groupMeta(group, primary.photo),
          role: 'meta',
          x: 0.08,
          y: 0.10,
          w: 0.32,
          h: 0.05,
          fontId: 'mono_note',
          fontSize: 16,
          colorToken: 'gold_accent',
        ),
        _imageElement(
          id: 'column_${spreadIndex}_support',
          photo: secondary.photo,
          x: 0.08,
          y: 0.18,
          w: 0.76,
          h: 0.24,
          borderRadius: 0.022,
        ),
        _textElement(
          id: 'column_${spreadIndex}_title',
          text: _groupTitle(group),
          role: 'title',
          x: 0.08,
          y: 0.48,
          w: 0.72,
          h: 0.12,
          fontId: 'serif_elegant',
          fontSize: 32,
          weight: '700',
        ),
        _shapeElement(
          id: 'column_${spreadIndex}_body_shape',
          x: 0.08,
          y: 0.62,
          w: 0.76,
          h: 0.24,
          colorToken: 'paper_warm',
          fillAlpha: 0.18,
          borderRadius: 0.06,
        ),
        _textElement(
          id: 'column_${spreadIndex}_body',
          text: _trimText(_groupBody(group), 88),
          role: 'body',
          x: 0.12,
          y: 0.68,
          w: 0.64,
          h: 0.14,
          fontId: 'serif_elegant',
          fontSize: 21,
          colorToken: 'ink_soft',
        ),
      ],
    );
  }

  AlbumSpreadModel _buildPortraitFeatureSpread({
    required int spreadIndex,
    required _SectionGroup group,
  }) {
    final primary = group.sections.first;
    return _spread(
      spreadIndex: spreadIndex,
      templateId: 'portrait_feature',
      leftBackground: _backgroundFor(group.kind, group.variantSeed, false),
      rightBackground: _backgroundFor(group.kind, group.variantSeed, true),
      leftElements: <AlbumElementModel>[
        _imageElement(
          id: 'portrait_${spreadIndex}_hero',
          photo: primary.photo,
          x: 0.04,
          y: 0.06,
          w: 0.72,
          h: 0.80,
          borderRadius: 0.025,
        ),
      ],
      rightElements: <AlbumElementModel>[
        _textElement(
          id: 'portrait_${spreadIndex}_meta',
          text: _groupMeta(group, primary.photo),
          role: 'meta',
          x: 0.10,
          y: 0.10,
          w: 0.38,
          h: 0.05,
          fontId: 'mono_note',
          fontSize: 15,
          colorToken: 'gold_accent',
        ),
        _textElement(
          id: 'portrait_${spreadIndex}_title',
          text: _groupTitle(group),
          role: 'title',
          x: 0.10,
          y: 0.20,
          w: 0.72,
          h: 0.12,
          fontId: 'serif_elegant',
          fontSize: 32,
          weight: '700',
        ),
        _shapeElement(
          id: 'portrait_${spreadIndex}_shape',
          x: 0.08,
          y: 0.40,
          w: 0.78,
          h: 0.24,
          colorToken: 'paper_warm',
          fillAlpha: 0.18,
          borderRadius: 0.06,
        ),
        _textElement(
          id: 'portrait_${spreadIndex}_body',
          text: _trimText(_groupBody(group), 92),
          role: 'body',
          x: 0.12,
          y: 0.45,
          w: 0.68,
          h: 0.16,
          fontId: 'serif_elegant',
          fontSize: 20,
          colorToken: 'ink_soft',
        ),
        _textElement(
          id: 'portrait_${spreadIndex}_note',
          text: _groupNote(group),
          role: 'caption',
          x: 0.12,
          y: 0.74,
          w: 0.56,
          h: 0.08,
          fontId: 'handwriting_soft',
          fontSize: 18,
          colorToken: 'ink_soft',
        ),
      ],
    );
  }

  AlbumPageModel _page({
    required int spreadIndex,
    required AlbumPageSide side,
    required String backgroundColorToken,
    required List<AlbumElementModel> elements,
  }) {
    return AlbumPageModel(
      pageIndex: spreadIndex * 2 + (side == AlbumPageSide.right ? 1 : 0),
      side: side,
      backgroundColorToken: backgroundColorToken,
      elements: elements,
    );
  }

  AlbumElementModel _imageElement({
    required String id,
    required Photo photo,
    required double x,
    required double y,
    required double w,
    required double h,
    double rotation = 0,
    int zIndex = 0,
    double borderRadius = 0.03,
  }) {
    final focus = _cropFocusForPhoto(photo);
    return AlbumElementModel(
      id: id,
      type: AlbumElementType.image,
      x: x,
      y: y,
      w: w,
      h: h,
      rotation: rotation,
      zIndex: zIndex,
      locked: false,
      payload: <String, dynamic>{
        'role': 'photo',
        'photo_id': photo.id,
        'crop': <String, dynamic>{
          'mode': 'cover',
          'focus_x': focus.$1,
          'focus_y': focus.$2,
        },
      },
      style: AlbumElementStyle(
        borderRadius: borderRadius,
        colorToken: 'shadow_soft',
      ),
    );
  }

  (double, double) _cropFocusForPhoto(Photo photo) {
    final source = <String>[
      photo.caption ?? '',
      photo.ocrSummary ?? '',
      photo.location ?? '',
      photo.tags.join(' '),
      photo.ocrTags.join(' '),
    ].join(' ').toLowerCase();

    if (_containsAny(source, const <String>['生日', '蛋糕', '蜡烛', '甜品', '咖啡', '奶茶', '美食'])) {
      return (0.50, 0.40);
    }
    if (_containsAny(source, const <String>['人物', '人像', '朋友', '同学', '自拍', '合影'])) {
      return (0.50, 0.42);
    }
    if (_containsAny(source, const <String>['花', '樱', '树', '湖', '水', '桥', '风景', '天空'])) {
      return (0.52, 0.46);
    }
    return (0.50, 0.50);
  }

  AlbumElementModel _textElement({
    required String id,
    required String text,
    required String role,
    required double x,
    required double y,
    required double w,
    required double h,
    String fontId = 'sans_clean',
    double fontSize = 22,
    String colorToken = 'ink_black',
    AlbumTextAlignValue align = AlbumTextAlignValue.left,
    String weight = '400',
    bool shadow = false,
    int zIndex = 1,
    double rotation = 0,
  }) {
    return AlbumElementModel(
      id: id,
      type: role == 'meta' ? AlbumElementType.subtitle : AlbumElementType.text,
      x: x,
      y: y,
      w: w,
      h: h,
      rotation: rotation,
      zIndex: zIndex,
      locked: false,
      payload: <String, dynamic>{
        'text': text,
        'role': role,
      },
      style: AlbumElementStyle(
        fontId: fontId,
        fontSize: fontSize,
        colorToken: colorToken,
        align: align,
        weight: weight,
        shadow: shadow,
      ),
    );
  }

  AlbumElementModel _shapeElement({
    required String id,
    required double x,
    required double y,
    required double w,
    required double h,
    required String colorToken,
    required double fillAlpha,
    double borderRadius = 0.06,
    int zIndex = 1,
  }) {
    return AlbumElementModel(
      id: id,
      type: AlbumElementType.shape,
      x: x,
      y: y,
      w: w,
      h: h,
      rotation: 0,
      zIndex: zIndex,
      locked: false,
      payload: <String, dynamic>{'fill_alpha': fillAlpha},
      style: AlbumElementStyle(
        colorToken: colorToken,
        borderRadius: borderRadius,
      ),
    );
  }

  String _backgroundFor(_SpreadKind kind, int seed, bool rightPage) {
    final options = switch (kind) {
      _SpreadKind.heroQuote => rightPage
          ? const <String>['paper_rose', 'paper_sage']
          : const <String>['paper_warm', 'paper_sage'],
      _SpreadKind.manifesto => rightPage
          ? const <String>['paper_warm', 'paper_rose']
          : const <String>['paper_sage', 'paper_warm'],
      _SpreadKind.diptych => rightPage
          ? const <String>['paper_sage', 'paper_rose']
          : const <String>['paper_warm', 'paper_rose'],
      _SpreadKind.triptych => rightPage
          ? const <String>['paper_warm', 'paper_sage']
          : const <String>['paper_rose', 'paper_warm'],
      _SpreadKind.boardQuad => rightPage
          ? const <String>['paper_warm', 'paper_sage']
          : const <String>['paper_warm', 'paper_rose'],
      _SpreadKind.galleryJournal => rightPage
          ? const <String>['paper_warm', 'paper_rose']
          : const <String>['paper_warm', 'paper_sage'],
      _SpreadKind.marginColumn => rightPage
          ? const <String>['paper_sage', 'paper_warm']
          : const <String>['paper_warm', 'paper_rose'],
      _SpreadKind.portraitFeature => rightPage
          ? const <String>['paper_rose', 'paper_warm']
          : const <String>['paper_warm', 'paper_sage'],
    };
    return options[seed % options.length];
  }

  String _spreadWord(List<StorySection> sections) {
    final source = _joinedSource(sections);
    if (_containsAny(source, const <String>[
      '\u751f\u65e5',
      '\u86cb\u7cd5',
      '\u8721\u70db',
      '\u5e86\u751f',
    ])) {
      return '\u70db\u5149';
    }
    if (_containsAny(source, const <String>[
      '\u706b\u9505',
      '\u70e7\u70e4',
      '\u805a\u9910',
      '\u996d\u5c40',
    ])) {
      return '\u70ed\u5e2d';
    }
    if (_containsAny(source, const <String>[
      '\u82b1',
      '\u6a31',
      '\u6625',
      '\u6811',
    ])) {
      return '\u82b1\u4e8b';
    }
    if (_containsAny(source, const <String>[
      '\u591c',
      '\u6708',
      '\u706f',
      '\u665a',
    ])) {
      return '\u591c\u8272';
    }
    if (_containsAny(source, const <String>[
      '\u670b\u53cb',
      '\u540c\u5b66',
      '\u5408\u5f71',
      '\u4e00\u8d77',
    ])) {
      return '\u540c\u9891';
    }
    if (_containsAny(source, const <String>[
      '\u5bb6',
      '\u4eb2\u4eba',
      '\u5168\u5bb6',
      '\u56e2\u805a',
    ])) {
      return '\u56e2\u5706';
    }
    if (_containsAny(source, const <String>[
      '\u6e56',
      '\u6c34',
      '\u6865',
      '\u98ce\u666f',
    ])) {
      return '\u98ce\u666f';
    }
    if (_containsAny(source, const <String>[
      '\u5496\u5561',
      '\u5976\u8336',
      '\u751c\u54c1',
      '\u7f8e\u98df',
    ])) {
      return '\u98ce\u5473';
    }
    final tags = sections.expand((section) => section.photo.tags).where((tag) => tag.trim().isNotEmpty);
    if (tags.isNotEmpty) {
      return _trimText(tags.first.trim(), 4);
    }
    return '\u6b64\u523b';
  }

  String _spreadTitle(List<StorySection> sections) {
    final source = _joinedSource(sections);
    if (_containsAny(source, const <String>['\u751f\u65e5', '\u86cb\u7cd5', '\u8721\u70db'])) {
      return '\u628a\u70db\u5149\u7559\u5728\u8fd9\u4e00\u9875';
    }
    if (_containsAny(source, const <String>['\u706b\u9505', '\u70e7\u70e4', '\u805a\u9910'])) {
      return '\u8fd9\u4e00\u665a\uff0c\u70ed\u6c14\u5148\u62b5\u8fbe';
    }
    if (_containsAny(source, const <String>['\u82b1', '\u6a31', '\u6625'])) {
      return '\u6625\u98ce\u4ece\u82b1\u68a2\u4e0a\u7ecf\u8fc7';
    }
    if (_containsAny(source, const <String>['\u670b\u53cb', '\u5408\u5f71', '\u540c\u5b66'])) {
      return '\u6709\u4eba\u4e00\u8d77\uff0c\u7167\u7247\u5c31\u6709\u4e86\u56de\u58f0';
    }
    if (_containsAny(source, const <String>['\u591c', '\u6708', '\u706f'])) {
      return '\u6708\u5149\u628a\u6811\u68a2\u7167\u5f97\u5f88\u8fd1';
    }
    if (_containsAny(source, const <String>['\u6e56', '\u6c34', '\u6865'])) {
      return '\u98ce\u4ece\u6c34\u8fb9\u7ecf\u8fc7\u7684\u65f6\u5019';
    }
    return '\u628a\u8fd9\u4e00\u523b\u6162\u6162\u7ffb\u5f00';
  }

  String _spreadMicroCopy(List<StorySection> sections) {
    final source = _joinedSource(sections);
    if (_containsAny(source, const <String>['\u751f\u65e5', '\u86cb\u7cd5', '\u8721\u70db'])) {
      return '\u613f\u671b\u521a\u597d\u53d1\u4eae';
    }
    if (_containsAny(source, const <String>['\u706b\u9505', '\u70e7\u70e4', '\u805a\u9910'])) {
      return '\u70ed\u6c14\u5148\u628a\u4eba\u7559\u4f4f';
    }
    if (_containsAny(source, const <String>['\u82b1', '\u6a31', '\u6625'])) {
      return '\u82b1\u5f71\u6b63\u8f7b';
    }
    if (_containsAny(source, const <String>['\u670b\u53cb', '\u5408\u5f71', '\u4e00\u8d77'])) {
      return '\u7b11\u58f0\u843d\u5728\u540c\u4e00\u5f20\u9875\u4e0a';
    }
    if (_containsAny(source, const <String>['\u591c', '\u6708', '\u706f'])) {
      return '\u628a\u591c\u8272\u6536\u6210\u4e00\u53e5\u8bdd';
    }
    if (_containsAny(source, const <String>['\u6e56', '\u6c34', '\u6865', '\u98ce\u666f'])) {
      return '\u98ce\u4ece\u6c34\u8fb9\u8d70\u8fc7';
    }
    return '\u8fd9\u4e00\u9875\uff0c\u9002\u5408\u6162\u6162\u770b';
  }

  String _spreadInterlude(List<StorySection> sections, int seed) {
    final contextual = _spreadMicroCopy(sections);
    final universal = _universalInterludes[seed.abs() % _universalInterludes.length];
    if (seed % 3 == 0 || contextual == '\u8fd9\u4e00\u9875\uff0c\u9002\u5408\u6162\u6162\u770b') {
      return universal;
    }
    return contextual;
  }

  String _endingInterlude(List<StorySection> sections, {required int seed}) {
    final source = _joinedSource(sections);
    if (_containsAny(source, const <String>['\u751f\u65e5', '\u86cb\u7cd5', '\u8721\u70db'])) {
      return '\u613f\u671b\u5439\u8fc7\u4e4b\u540e\uff0c\u5149\u8fd8\u5728';
    }
    if (_containsAny(source, const <String>['\u82b1', '\u6a31', '\u6625'])) {
      return '\u82b1\u5f00\u8fc7\u4e00\u5b63\uff0c\u4e0d\u4f1a\u53ea\u7559\u4e0b\u989c\u8272';
    }
    if (_containsAny(source, const <String>['\u670b\u53cb', '\u5408\u5f71', '\u4e00\u8d77'])) {
      return '\u8fd9\u4e00\u9875\u5408\u4e0a\uff0c\u7b11\u58f0\u4ecd\u7136\u6709\u56de\u97f3';
    }
    return _endingInterludes[seed.abs() % _endingInterludes.length];
  }

  String _spreadBody(List<StorySection> sections) {
    final source = _joinedSource(sections);
    if (_containsAny(source, const <String>['\u751f\u65e5', '\u86cb\u7cd5', '\u8721\u70db'])) {
      return '\u70db\u706b\u628a\u56f4\u5750\u7684\u4eba\u90fd\u7167\u5f97\u6e29\u67d4\u8d77\u6765\uff0c\u539f\u6765\u6700\u503c\u5f97\u7eaa\u5ff5\u7684\uff0c\u4e0d\u53ea\u662f\u613f\u671b\uff0c\u8fd8\u6709\u4e00\u8d77\u5439\u706d\u706f\u5149\u7684\u4eba\u3002';
    }
    if (_containsAny(source, const <String>['\u706b\u9505', '\u70e7\u70e4', '\u805a\u9910'])) {
      return '\u9505\u6c14\u7ffb\u6d8c\uff0c\u8bdd\u9898\u5728\u6cb8\u70b9\u9644\u8fd1\u6253\u8f6c\uff0c\u665a\u996d\u88ab\u70ed\u5ea6\u548c\u7b11\u58f0\u4e00\u8d77\u7aef\u4e0a\u6765\uff0c\u666e\u901a\u7684\u4e00\u591c\u4fbf\u6709\u4e86\u56de\u7518\u3002';
    }
    if (_containsAny(source, const <String>['\u82b1', '\u6a31', '\u6625'])) {
      return '\u679d\u53f6\u548c\u82b1\u74e3\u628a\u98ce\u4e5f\u67d3\u5f97\u67d4\u8f6f\uff0c\u76ee\u5149\u505c\u5728\u8fd9\u91cc\u65f6\uff0c\u50cf\u662f\u88ab\u6625\u5929\u6084\u6084\u6309\u4e0b\u4e86\u6162\u653e\u3002';
    }
    if (_containsAny(source, const <String>['\u670b\u53cb', '\u540c\u5b66', '\u5408\u5f71', '\u4e00\u8d77'])) {
      return '\u4eba\u7fa4\u6328\u5f97\u5f88\u8fd1\uff0c\u7b11\u5bb9\u6ca1\u6709\u6392\u7ec3\uff0c\u5374\u628a\u8fd9\u4e00\u523b\u62fc\u6210\u4e86\u6700\u5b8c\u6574\u7684\u753b\u9762\uff0c\u8fde\u6c89\u9ed8\u90fd\u663e\u5f97\u719f\u6089\u3002';
    }
    if (_containsAny(source, const <String>['\u591c', '\u6708', '\u706f'])) {
      return '\u591c\u8272\u628a\u80cc\u666f\u538b\u4f4e\uff0c\u5149\u7ebf\u4ece\u7f1d\u9699\u91cc\u843d\u4e0b\u6765\uff0c\u50cf\u66ff\u90a3\u4e9b\u8bf4\u4e0d\u51fa\u53e3\u7684\u60c5\u7eea\u8865\u4e0a\u4e86\u4e00\u53e5\u65c1\u767d\u3002';
    }
    if (_containsAny(source, const <String>['\u6e56', '\u6c34', '\u6865', '\u98ce\u666f'])) {
      return '\u98ce\u4ece\u6c34\u8fb9\u7ecf\u8fc7\uff0c\u666f\u8272\u6ca1\u6709\u8bf4\u8bdd\uff0c\u5374\u628a\u5fc3\u60c5\u6258\u4f4f\u3002\u7b49\u56de\u5934\u518d\u770b\u65f6\uff0c\u5b89\u9759\u672c\u8eab\u5c31\u5df2\u7ecf\u8db3\u591f\u52a8\u4eba\u3002';
    }
    return '\u955c\u5934\u6309\u4e0b\u53bb\u7684\u90a3\u4e00\u523b\uff0c\u7ec6\u788e\u65e5\u5e38\u5ffd\u7136\u6709\u4e86\u53ef\u4ee5\u56de\u770b\u7684\u91cd\u91cf\uff0c\u50cf\u628a\u65f6\u95f4\u8f7b\u8f7b\u538b\u8fdb\u4e86\u7eb8\u9875\u4e4b\u95f4\u3002';
  }

  String _verticalizeShortText(String text) {
    final clean = text.trim();
    if (clean.isEmpty) {
      return clean;
    }
    final runes = clean.runes.toList(growable: false);
    if (runes.length < 2 || runes.length > 4) {
      return clean;
    }
    return String.fromCharCodes(runes).split('').join('\n');
  }

  String _metaLine(Photo photo) {
    final date =
        '${photo.dateTaken.year.toString().padLeft(4, '0')}.${photo.dateTaken.month.toString().padLeft(2, '0')}.${photo.dateTaken.day.toString().padLeft(2, '0')}';
    final location = photo.location?.trim() ?? '';
    if (location.isEmpty) {
      return date;
    }
    return '$date  |  ${_trimText(location, 12)}';
  }

  String _joinedSource(List<StorySection> sections) {
    return sections
        .map(
          (section) => <String>[
            section.text,
            section.photo.caption ?? '',
            section.photo.location ?? '',
            section.photo.ocrSummary ?? '',
            section.photo.tags.join(' '),
            section.photo.ocrTags.join(' '),
          ].join(' '),
        )
        .join(' ')
        .toLowerCase();
  }

  bool _containsAny(String source, Iterable<String> candidates) {
    for (final candidate in candidates) {
      if (candidate.isNotEmpty && source.contains(candidate.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  String _trimText(String text, int maxLength) {
    final clean = text.trim();
    if (clean.runes.length <= maxLength) {
      return clean;
    }
    return '${String.fromCharCodes(clean.runes.take(math.max(0, maxLength - 3)))}...';
  }
}
