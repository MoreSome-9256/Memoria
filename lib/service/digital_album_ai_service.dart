/// 数字相册 AI 服务，负责封面、标题和版式相关的智能生成。

import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import '../models/vo/album_book_models.dart';
import '../models/vo/story_section.dart';
import '../models/vo/story_generation_models.dart';
import 'digital_album_layout_service.dart';
import 'llm_service.dart';

class DigitalAlbumAiService {
  const DigitalAlbumAiService();

  static const String latestLayoutSource = 'ai_assisted_v7';
  static const String latestCopySource = 'ai_copy_v1';
  static const Duration _minLayoutTimeout = Duration(seconds: 150);
  static const Duration _maxLayoutTimeout = Duration(seconds: 420);
  static const int _compactPlanThreshold = 9;
  static const DigitalAlbumLayoutService _layoutService =
      DigitalAlbumLayoutService();
  static const String structuredSystemPrompt =
      'You are a strict JSON-only album layout engine.\n'
      'Return exactly one UTF-8 JSON object.\n'
      'Do not return markdown fences.\n'
      'Do not return comments.\n'
      'Do not return any explanation before or after JSON.\n'
      'Use only double-quoted JSON strings and keys.\n'
      'Do not use trailing commas.\n'
      'Do not wrap the JSON inside another explanation object unless that wrapper still contains a complete album layout object.\n'
      'If unsure, still return the closest valid album-layout JSON object instead of prose.';

  bool get isAvailable => LLMService().isApiKeyConfigured;

  Future<AlbumBookDocument?> optimizeBook({
    required String title,
    required String subtitle,
    required List<StorySection> sections,
    required AlbumBookDocument fallback,
    AlbumBookStylePreset stylePreset = AlbumBookStylePreset.editorial,
  }) async {
    if (!isAvailable) {
      throw StateError('DeepSeek / LLM is not configured.');
    }
    if (sections.isEmpty) {
      throw StateError('No photo material is available for album layout.');
    }

    if (sections.length >= _compactPlanThreshold) {
      return _optimizeBookViaPlan(
        title: title,
        subtitle: subtitle,
        sections: sections,
        fallback: fallback,
        stylePreset: stylePreset,
      );
    }

    final prompt = _buildPrompt(
      title: title,
      subtitle: subtitle,
      sections: sections,
      fallback: fallback,
      stylePreset: stylePreset,
    );
    final requestTimeout = _timeoutForSectionCount(sections.length);
    String? response;
    try {
      response = await LLMService().completeText(
        prompt: prompt,
        systemPrompt: structuredSystemPrompt,
        jsonMode: true,
        temperature: 0.48,
        topP: 0.90,
        requestTimeout: requestTimeout,
      );
    } on TimeoutException {
      throw StateError('AI 排版请求超时（${requestTimeout.inSeconds} 秒），请稍后重试');
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('timeout')) {
        throw StateError('AI 排版请求超时（${requestTimeout.inSeconds} 秒），请稍后重试');
      }
      rethrow;
    }

    if (response == null) {
      throw StateError('模型没有返回可用的相册排版结果');
    }
    if (response.trim().isEmpty) {
      throw StateError('The model returned an empty album layout response.');
    }

    final parsed = await _parseAlbumJson(
      rawResponse: response,
      title: title,
      subtitle: subtitle,
      fallback: fallback,
      requestTimeout: requestTimeout,
    );
    if (parsed == null) {
      throw StateError('模型返回内容无法解析为相册排版 JSON');
    }

    final normalized = _normalizeAlbumJson(
      parsed,
      title: title,
      subtitle: subtitle,
      fallback: fallback,
    );

    try {
      final document = _stabilizeDocument(
        AlbumBookDocument.fromJson(normalized).copyWith(
          layoutSource: latestLayoutSource,
        ),
        fallback: fallback,
      );
      if (document.spreads.isEmpty) {
        throw StateError('模型返回的排版内容为空');
      }
      return document;
    } catch (error) {
      throw StateError('模型返回的排版 JSON 结构无效：$error');
    }
  }

  Future<AlbumBookDocument?> writeCopyForBook({
    required String title,
    required String subtitle,
    required List<StorySection> sections,
    required AlbumBookDocument document,
    String? storyTemplateId,
  }) async {
    if (!isAvailable) {
      throw StateError('DeepSeek / LLM is not configured.');
    }
    if (sections.isEmpty) {
      throw StateError('No photo material is available for album copywriting.');
    }

    final prompt = _buildCopyPrompt(
      title: title,
      subtitle: subtitle,
      sections: sections,
      document: document,
      storyTemplateId: storyTemplateId,
    );
    final requestTimeout = _timeoutForSectionCount(sections.length);
    String? response;
    try {
      response = await LLMService().completeText(
        prompt: prompt,
        systemPrompt: structuredSystemPrompt,
        jsonMode: true,
        temperature: 0.72,
        topP: 0.92,
        requestTimeout: requestTimeout,
      );
    } on TimeoutException {
      throw StateError('AI 写文案请求超时（${requestTimeout.inSeconds} 秒），请稍后重试');
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('timeout')) {
        throw StateError('AI 写文案请求超时（${requestTimeout.inSeconds} 秒），请稍后重试');
      }
      rethrow;
    }

    if (response == null || response.trim().isEmpty) {
      throw StateError('模型没有返回可用的相册文案结果');
    }

    final parsed = await _parseCopyJson(
      rawResponse: response,
      title: title,
      subtitle: subtitle,
      fallback: document,
      requestTimeout: requestTimeout,
    );
    if (parsed == null) {
      throw StateError('模型返回内容无法解析为文案 JSON');
    }

    final normalized = _normalizeCopyJson(parsed);
    return _applyCopyJson(document, normalized).copyWith(
      layoutSource: '${document.layoutSource}_$latestCopySource',
    );
  }

  Future<AlbumBookDocument?> _optimizeBookViaPlan({
    required String title,
    required String subtitle,
    required List<StorySection> sections,
    required AlbumBookDocument fallback,
    required AlbumBookStylePreset stylePreset,
  }) async {
    final prompt = _buildPlanPrompt(
      title: title,
      subtitle: subtitle,
      sections: sections,
      fallback: fallback,
      stylePreset: stylePreset,
    );
    final requestTimeout = _timeoutForSectionCount(sections.length);
    String? response;
    try {
      response = await LLMService().completeText(
        prompt: prompt,
        systemPrompt: structuredSystemPrompt,
        jsonMode: true,
        temperature: 0.42,
        topP: 0.86,
        requestTimeout: requestTimeout,
      );
    } on TimeoutException {
      throw StateError('AI 排版请求超时（${requestTimeout.inSeconds} 秒），请稍后重试');
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('timeout')) {
        throw StateError('AI 排版请求超时（${requestTimeout.inSeconds} 秒），请稍后重试');
      }
      rethrow;
    }

    if (response == null || response.trim().isEmpty) {
      throw StateError('模型没有返回可用的相册排版计划');
    }

    final parsed = await _parsePlanJson(
      rawResponse: response,
      title: title,
      subtitle: subtitle,
      fallback: fallback,
      requestTimeout: requestTimeout,
    );
    if (parsed == null) {
      throw StateError('模型返回内容无法解析为相册排版计划 JSON');
    }

    final plan = _normalizeAiPlan(
      parsed,
      sections: sections,
      stylePreset: stylePreset,
    );
    final document = _layoutService.buildBookFromAiPlan(
      title: title,
      subtitle: subtitle,
      sections: sections,
      plan: plan,
      preset: stylePreset,
    );
    return document.copyWith(layoutSource: latestLayoutSource);
  }

  String _buildPrompt({
    required String title,
    required String subtitle,
    required List<StorySection> sections,
    required AlbumBookDocument fallback,
    required AlbumBookStylePreset stylePreset,
  }) {
    final spreadsTarget = sections.length <= 2 ? 2 : ((sections.length / 2).ceil() + 2);
    final pageWidth = fallback.pageWidth.toInt();
    final pageHeight = fallback.pageHeight.toInt();
    final materialsJson = jsonEncode(
      <Map<String, dynamic>>[
        for (var i = 0; i < sections.length; i++) _buildMaterialEntry(i, sections[i]),
      ],
    );
    final suggestedGroupsJson = jsonEncode(
      _buildSuggestedGroups(sections).take(4).toList(growable: false),
    );
    final fallbackJson = jsonEncode(_compactFallback(fallback));

    return '''
You are a senior editorial designer, Chinese copy director, and sequencing editor for a premium landscape memory-book.
Return exactly one JSON object and nothing else.
Every text string inside the JSON must be Simplified Chinese.

Primary mission:
- make the album feel like a designed art book, not a template dump
- keep the imagery dominant, but make the text feel written, curated, and emotionally precise
- make typography, color, spacing, and image grouping feel intentional
- vary the rhythm across the whole book instead of repeating one layout pattern

What good output looks like:
- a text-led page should feel like a magazine opening or a printed essay page
- an image-led page should feel quiet, breathable, and visually confident
- a multi-photo spread should feel sequenced and curated, not mechanically tiled
- the book should alternate between tension and calm, density and blank space, close-up and spread-out

Typography direction:
- never solve design with one oversized black headline and one small generic paragraph
- every text-led page should usually contain:
  1. one small kicker, date whisper, category note, or art word in an accent color
  2. one refined main title
  3. one richer body paragraph when the layout has a dedicated text area
- use font, size, weight, and color as composition tools, not defaults
- font_size is a design-space value relative to the album page, not a phone-pixel value; the app will scale it to different devices
- body text should usually use serif_elegant, color ink_soft, font_size 18-22, weight 400, align left
- Chinese titles should usually prefer serif_elegant; only very short and bold titles may use display_modern
- meta/date labels should usually use mono_note with gold_accent or sage_accent
- short whispers can use handwriting_soft, but only when they remain elegant and readable
- use role "art_word" sparingly; many spreads should have no art_word at all
- never add a decorative art_word if it is only a generic season/flower/time word such as 春, 夏, 秋, 冬, 花, 樱, 春日, 夜樱
- text on the same page as an image must stay compact and composition-aware
- typography must respond to layout type, not follow one global size rule
- for a dedicated text page facing a strong image page:
  meta usually 14-17
  title usually 28-38
  body usually 21-26
- for a mixed page with image and text together:
  title usually 18-26
  body usually 14-20
  caption usually 12-18
- if a text-led page still has large blank paper area after placing title and body, increase text box size and font size instead of leaving the page under-designed
- let text occupy the page with intention: a refined text page should usually use about 35% to 60% of the available vertical rhythm, not just float as a tiny block in a large empty page
- if the title is longer than 10 Chinese characters, reduce the title font and allow 2 lines instead of forcing a giant single line
- title font_size on dedicated text pages should usually stay between 22 and 30, not billboard scale
- if you use a shape behind body text, let it hug the paragraph with modest padding instead of becoming a large empty box

Writing direction:
- title must be fresh, concrete, memorable, and image-specific
- avoid empty labels like 浜虹墿, 椋庢櫙, 鐢熸椿, 璁板綍, 鍥炲繂, 鏄ュぉ unless transformed into a new phrase
- body writing must be richer than a caption: literary, visual, and immersive, but still grounded in the photo
- do not narrate obvious facts one by one; distill the mood, gesture, light, rhythm, or relation
- short notes should be crisp and quotable
- do not repeat the same sentence cadence across adjacent spreads
- never use bland filler language
- never invent identities, relationships, or events not supported by the materials

Layout direction:
- coordinates are normalized per single page: x/y/w/h in [0.0, 1.0]
- elements must stay inside bounds
- book background is visible paper, not edge-to-edge canvas; respect paper margins and the center gutter
- text safe area:
  left_page -> keep text within x 0.08 to 0.88 and avoid the inner gutter on the right
  right_page -> keep text within x 0.12 to 0.92 and avoid the inner gutter on the left
  common text y range should usually stay within 0.08 to 0.90
- image safe area:
  left_page -> keep images within x 0.04 to 0.94
  right_page -> keep images within x 0.06 to 0.96
  common image y range should usually stay within 0.04 to 0.94
- if one page is text-led, the other page must still carry the dominant image or image group for that spread
- do not leave a page visually empty; a page with only a date or one tiny word is invalid
- keep image area dominant: normally 68% to 96% of the page or spread
- use shapes as subtle rhythm tools behind text blocks when useful
- treat image area and text area as separate editorial regions
- do not place title, body, caption, subtitle, or art_word directly on top of photos
- do not place text under a photo if the text still visually sits inside the photo rectangle
- image is image, text is text: separate them with paper margin, dedicated text block, or facing-page composition
- use near-full-bleed when the image is strong enough
- avoid mirrored left/right symmetry

Global sequencing rules:
- if there are 8 or more photos, use at least 4 distinct spread motifs
- do not repeat the same template_id on adjacent spreads
- do not use image-text split spreads for every spread
- no more than 2 consecutive spreads may share the same structural rhythm
- when a related photo group has 3 or more items, strongly prefer collage_board or triptych_rhythm at least sometimes
- do not dissolve every similar photo into isolated single-photo spreads
- every spread except cover_spread and ending_spread must contain at least one visible image
- diptych_memory should normally contain 2 images, triptych_rhythm 3 images, collage_board 3-4 images
- fallback reference is only a safety reference; do not imitate its geometry unless it is truly the best solution
- make the AI output visibly different from a simple default template when the materials allow it
- no title, body, caption, subtitle, note, or art_word may sit on top of a photo
- on a text-led page, title and body must occupy a substantial visual area; avoid tiny text islands floating in empty paper
- do not make the main body column narrower than about 35% of the page unless the page is an intentional statement layout with strong typographic contrast

Template recipes:
- cover_spread:
  one strong image page + one title page, elegant and restrained
- hero_full_bleed:
  one hero image page + facing text page with kicker + title + body + small whisper
- manifesto_quote:
  text-led editorial page facing one strong image; use accent, shape, and hierarchy
- diptych_memory:
  two connected photos with a tighter text system; one side may carry the title, the other a refined paragraph
- triptych_rhythm:
  one anchor photo + two supporting photos; text must stay compact and rhythm-based
- collage_board:
  3-4 semantically related photos arranged like a curated board; one anchor sentence and maybe one short title
- gallery_journal:
  one page with 3-4 photos in an asymmetric journal grid, facing page with a stronger title and a fuller paragraph block; the text page must feel substantial, not sparse
- family_statement:
  one or two large photos with a bold statement title block on clean paper, inspired by printed memory books
- margin_column:
  one large hero image page plus a fuller facing page: one support image near the top, then a strong title and a generous paragraph block on paper; never leave the facing page half empty
- portrait_feature:
  one hero portrait plus one or two supporting photos, text kept fully on paper as an editorial side block
- ending_spread:
  closing mood, lighter density, graceful exit

Allowed font tokens:
- serif_elegant
- sans_clean
- handwriting_soft
- display_modern
- mono_note

Allowed color tokens:
- paper_warm
- paper_rose
- paper_sage
- ink_black
- ink_soft
- rose_accent
- gold_accent
- sage_accent
- shadow_soft

Allowed element types:
- image
- text
- subtitle
- shape

If you use a shape element, store its opacity in payload field "fill_alpha" between 0.08 and 0.82.

Element-role guidance:
- role "title": main spread title
- role "body": rich paragraph
- role "caption": short note, kicker, whisper, or anchor sentence
- role "meta": date or date-location label only
- role "art_word": large single word or very short phrase used decoratively
- role "art_word" is optional, not required; omit it unless it adds clear meaning and visual value
- avoid type "subtitle" except for tiny meta labels outside the image

Album spec:
- orientation: landscape
- page_width: $pageWidth
- page_height: $pageHeight
- target_spread_count: $spreadsTarget
- album_title: $title
- album_subtitle: $subtitle
- preferred_album_style: ${stylePreset.name}

Material fields:
- visual_focus: most visible or emotionally useful signal
- narrative_seed: the richer source text to refine, not to copy
- microcopy_seed: a small seed line for compact note writing
- layout_hint: local suggestion, use it when useful
- writing_mode: tonal suggestion

Photo materials:
$materialsJson

Suggested related-photo groups:
$suggestedGroupsJson

Fallback layout reference:
$fallbackJson

Hard JSON contract:
- your first character must be "{"
- your last character must be "}"
- return one JSON object only
- never use ```json or ``` fences
- never add explanations, notes, apology text, or bullet points outside JSON
- all keys and string values must use standard double quotes
- do not use single-quoted pseudo JSON
- do not use comments
- do not use trailing commas
- if a field is unavailable, return an empty string, empty array, or empty elements list instead of prose
- every spread must contain "left_page" and "right_page"
- every page must contain "background" and "elements"
- every element must be a JSON object, never plain text

Required JSON schema:
{
  "schema_version": "${AlbumBookDesignTokens.schemaVersion}",
  "album": {
    "title": "$title",
    "subtitle": "$subtitle",
    "theme": "memory_book",
    "book": {
      "orientation": "landscape",
      "page_width": $pageWidth,
      "page_height": $pageHeight,
      "spread_count": $spreadsTarget
    }
  },
  "spreads": [
    {
      "spread_index": 0,
      "template_id": "cover_spread",
      "left_page": {
        "background": {"color_token": "paper_warm"},
        "elements": []
      },
      "right_page": {
        "background": {"color_token": "paper_warm"},
        "elements": []
      }
    }
  ],
  "layout_source": "$latestLayoutSource"
}

Per element requirements:
- all image elements must contain: id, type, photo_id, path, x, y, w, h, rotation, z_index, locked, crop, style
- all text/subtitle elements must contain: id, type, text, x, y, w, h, rotation, z_index, locked, style
- all style objects must contain: font_id, font_size, color_token, align, weight, shadow, border_radius
- if you return a shape behind text, the text box must fit inside that shape with roughly 0.02 to 0.05 padding on each side

Quality requirements:
- at least one accent-colored text element should appear on most text-led pages
- title, body, and meta should not all use the same font token
- do not return only black text unless the spread is intentionally austere
- for portrait or light-filled scenes, make the writing tender and specific
- for scenic or airy scenes, let the page breathe and keep hierarchy elegant
- for related multi-photo groups, create variation in crop size and spacing
- keep text block proportions tight and editorial: no giant empty cards, no oversized headlines
- output polished design, not placeholder design

Return JSON only.
''';
  }

  String _buildPlanPrompt({
    required String title,
    required String subtitle,
    required List<StorySection> sections,
    required AlbumBookDocument fallback,
    required AlbumBookStylePreset stylePreset,
  }) {
    final materialsJson = jsonEncode(
      <Map<String, dynamic>>[
        for (var i = 0; i < sections.length; i++) _buildCompactMaterialEntry(i, sections[i]),
      ],
    );
    final suggestedGroupsJson = jsonEncode(
      _buildSuggestedGroups(sections).take(8).toList(growable: false),
    );

    return '''
You are planning a premium Chinese memory-book for many photos.
Return one compact JSON object only.

Task:
- do not return full page coordinates
- instead return a compact album plan for the whole book
- group visually or semantically similar photos into the same spread when possible
- similarity can come from shared tags, repeated people, same place, same time window, or similar visual focus
- prefer grouping similar photos together and writing one richer summary paragraph for the whole group
- mix different templates across the same album; do not repeat one pattern all the way through
- make the result noticeably more varied than a default fallback layout
- image and text must remain separated; no overlay text on photos, even for art_word or note
- do not create a text page whose title and body together occupy only a tiny corner; make the text page feel designed and full

Preferred overall style preset: ${stylePreset.name}

Allowed template_id values:
- hero_full_bleed
- manifesto_quote
- diptych_memory
- triptych_rhythm
- collage_board
- gallery_journal
- margin_column
- portrait_feature
- family_statement

Compact plan schema:
{
  "style_preset": "${stylePreset.name}",
  "spreads": [
    {
      "template_id": "gallery_journal",
      "photo_ids": ["photo_a", "photo_b", "photo_c"],
      "title": "spread title",
      "body": "one refined paragraph summarizing the group",
      "meta": "date or date-location line",
      "note": "optional short note",
      "art_word": ""
    }
  ]
}

Rules:
- one spread plan per content spread
- each photo_id may appear at most once
- use 1 photo for hero_full_bleed or family_statement
- use 2 photos for diptych_memory or margin_column or portrait_feature
- use 3 photos for triptych_rhythm
- use 3-4 photos for collage_board or gallery_journal
- if there are many related photos, strongly prefer gallery_journal or collage_board
- body should be a summary paragraph for the grouped images, not separate mini captions
- art_word is optional and should usually be empty
- keep JSON compact and valid

Album title: $title
Album subtitle: $subtitle
Reference page size: ${fallback.pageWidth.toInt()} x ${fallback.pageHeight.toInt()}

Photo materials:
$materialsJson

Suggested related-photo groups:
$suggestedGroupsJson
''';
  }

  Map<String, dynamic> _buildCompactMaterialEntry(int index, StorySection section) {
    final visualFocus = _trim(_firstNonEmpty(<String>[
      section.photo.caption?.trim() ?? '',
      section.photo.ocrSummary?.trim() ?? '',
      section.text.trim(),
    ]), 24);
    return <String, dynamic>{
      'index': index + 1,
      'photo_id': section.photo.id,
      'date_label': _dateLabel(section),
      'location': _trim(section.photo.location?.trim() ?? '', 12),
      'tags': section.photo.tags.take(5).toList(growable: false),
      'visual_focus': visualFocus,
      'cluster_seed': _trim(
        <String>[
          section.photo.caption?.trim() ?? '',
          section.photo.tags.take(3).join(' '),
          section.photo.location?.trim() ?? '',
        ].where((item) => item.isNotEmpty).join(' | '),
        36,
      ),
    };
  }

  Map<String, dynamic> _buildMaterialEntry(int index, StorySection section) {
    final caption = section.photo.caption?.trim() ?? '';
    final storyText = section.text.trim();
    final location = section.photo.location?.trim() ?? '';
    final ocrSummary = section.photo.ocrSummary?.trim() ?? '';
    final tags = section.photo.tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(4)
        .toList(growable: false);
    final ocrTags = section.photo.ocrTags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(2)
        .toList(growable: false);
    final visualFocus = _firstNonEmpty(<String>[
      caption,
      ocrSummary,
      if (tags.isNotEmpty) tags.join(' / '),
      storyText,
    ]);

    return <String, dynamic>{
      'index': index + 1,
      'photo_id': section.photo.id,
      'taken_at': section.photo.dateTaken.toIso8601String(),
      'date_label': _dateLabel(section),
      'location': _trim(location, 20),
      'tags': tags,
      'ocr_tags': ocrTags,
      'existing_caption': _trim(caption, 28),
      'story_text': _trim(storyText, 72),
      'ocr_summary': _trim(ocrSummary, 24),
      'visual_focus': _trim(visualFocus, 36),
      'narrative_seed': _trim(_mergeNarrativeSeed(section), 96),
      'microcopy_seed': _trim(_microcopySeed(section), 16),
      'layout_hint': _layoutHint(section),
      'writing_mode': _writingMode(section),
    };
  }

  List<Map<String, dynamic>> _buildSuggestedGroups(List<StorySection> sections) {
    final groups = <Map<String, dynamic>>[];
    var cursor = 0;
    while (cursor < sections.length) {
      final remaining = sections.length - cursor;
      if (remaining >= 4) {
        final quad = sections.sublist(cursor, cursor + 4);
        if (_relatedScore(quad) >= 4.2) {
          groups.add(
            _groupSummary(
              startIndex: cursor,
              items: quad,
              recommendedTemplate: 'collage_board',
            ),
          );
          cursor += 4;
          continue;
        }
      }
      if (remaining >= 3) {
        final tri = sections.sublist(cursor, cursor + 3);
        if (_relatedScore(tri) >= 2.6) {
          groups.add(
            _groupSummary(
              startIndex: cursor,
              items: tri,
              recommendedTemplate: 'triptych_rhythm',
            ),
          );
          cursor += 3;
          continue;
        }
      }
      if (remaining >= 2) {
        final duo = sections.sublist(cursor, cursor + 2);
        if (_relatedScore(duo) >= 1.3) {
          groups.add(
            _groupSummary(
              startIndex: cursor,
              items: duo,
              recommendedTemplate: 'diptych_memory',
            ),
          );
          cursor += 2;
          continue;
        }
      }
      cursor += 1;
    }
    return groups;
  }

  Map<String, dynamic> _groupSummary({
    required int startIndex,
    required List<StorySection> items,
    required String recommendedTemplate,
  }) {
    final sharedTags = _sharedTags(items);
    return <String, dynamic>{
      'start_index': startIndex + 1,
      'indexes': <int>[
        for (var i = 0; i < items.length; i++) startIndex + i + 1,
      ],
      'photo_ids': items.map((item) => item.photo.id).toList(growable: false),
      'group_size': items.length,
      'recommended_template': recommendedTemplate,
      'shared_tags': sharedTags.take(4).toList(growable: false),
      'shared_location': _sharedLocation(items),
      'time_span_hours': _timeSpanHours(items),
      'group_hint': _groupHint(items, sharedTags),
    };
  }

  double _relatedScore(List<StorySection> items) {
    if (items.length <= 1) {
      return 0;
    }
    var score = 0.0;
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        score += _pairScore(items[i], items[j]);
      }
    }
    return score;
  }

  double _pairScore(StorySection a, StorySection b) {
    var score = 0.0;
    score += _sharedTagCount(a, b) * 0.65;
    if (_sameLocation(a.photo.location, b.photo.location)) {
      score += 0.9;
    }
    final hours = a.photo.dateTaken.difference(b.photo.dateTaken).inHours.abs();
    if (hours <= 6) {
      score += 0.85;
    } else if (hours <= 24) {
      score += 0.45;
    } else if (hours <= 72) {
      score += 0.18;
    }
    return score;
  }

  int _sharedTagCount(StorySection a, StorySection b) {
    final left = a.photo.tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final right = b.photo.tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet();
    return left.intersection(right).length;
  }

  List<String> _sharedTags(List<StorySection> items) {
    if (items.isEmpty) {
      return const <String>[];
    }
    Set<String>? shared;
    for (final item in items) {
      final current = item.photo.tags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet();
      shared = shared == null ? current : shared.intersection(current);
    }
    return (shared ?? const <String>{}).toList(growable: false);
  }

  String _sharedLocation(List<StorySection> items) {
    final locations = items
        .map((item) => item.photo.location?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (locations.isEmpty) {
      return '';
    }
    final first = locations.first;
    final allMatch = locations.every((value) => value == first || value.contains(first) || first.contains(value));
    return allMatch ? first : '';
  }

  int _timeSpanHours(List<StorySection> items) {
    if (items.length <= 1) {
      return 0;
    }
    var minTime = items.first.photo.dateTaken;
    var maxTime = items.first.photo.dateTaken;
    for (final item in items.skip(1)) {
      if (item.photo.dateTaken.isBefore(minTime)) {
        minTime = item.photo.dateTaken;
      }
      if (item.photo.dateTaken.isAfter(maxTime)) {
        maxTime = item.photo.dateTaken;
      }
    }
    return maxTime.difference(minTime).inHours.abs();
  }

  String _groupHint(List<StorySection> items, List<String> sharedTags) {
    final location = _sharedLocation(items);
    if (sharedTags.isNotEmpty) {
      return 'Related by shared visual tags: ${sharedTags.take(3).join(', ')}';
    }
    if (location.isNotEmpty) {
      return 'Related by location continuity: $location';
    }
    if (_timeSpanHours(items) <= 12) {
      return 'Related by close time continuity and similar scene rhythm';
    }
    return 'Related by local sequence and likely visual similarity';
  }

  bool _sameLocation(String? left, String? right) {
    final a = left?.trim() ?? '';
    final b = right?.trim() ?? '';
    if (a.isEmpty || b.isEmpty) {
      return false;
    }
    return a == b || a.contains(b) || b.contains(a);
  }

  String _dateLabel(StorySection section) {
    final takenAt = section.photo.dateTaken;
    return '${takenAt.year.toString().padLeft(4, '0')}.'
        '${takenAt.month.toString().padLeft(2, '0')}.'
        '${takenAt.day.toString().padLeft(2, '0')}';
  }

  String _mergeNarrativeSeed(StorySection section) {
    return <String>[
      section.text.trim(),
      section.photo.caption?.trim() ?? '',
      section.photo.location?.trim() ?? '',
      section.photo.ocrSummary?.trim() ?? '',
      section.photo.tags.take(6).join(' '),
      section.photo.ocrTags.take(4).join(' '),
    ].where((item) => item.isNotEmpty).join(' | ');
  }

  String _microcopySeed(StorySection section) {
    final candidates = <String>[
      section.photo.caption?.trim() ?? '',
      section.photo.location?.trim() ?? '',
      section.photo.tags.take(2).join(' '),
      section.photo.ocrSummary?.trim() ?? '',
    ].where((item) => item.isNotEmpty).toList(growable: false);
    return candidates.isEmpty ? section.text.trim() : candidates.first;
  }

  String _layoutHint(StorySection section) {
    final tags = section.photo.tags.map((tag) => tag.trim().toLowerCase()).toList(growable: false);
    final source = _mergeNarrativeSeed(section).toLowerCase();
    final portraitScore = _containsAny(source, const <String>[
      'portrait',
      'girl',
      'person',
      'face',
      'woman',
      'man',
    ]) ||
        tags.any((tag) => tag.contains('portrait') || tag.contains('person'));
    final scenicScore = _containsAny(source, const <String>[
      'flower',
      'tree',
      'lake',
      'water',
      'garden',
      'park',
      'scenery',
    ]) ||
        tags.any((tag) =>
            tag.contains('flower') ||
            tag.contains('tree') ||
            tag.contains('park') ||
            tag.contains('lake'));
    final nightScore = _containsAny(source, const <String>['night', 'light', 'moon', 'lamp']) ||
        tags.any((tag) => tag.contains('night') || tag.contains('light'));
    if (portraitScore && scenicScore) {
      return 'portrait split spread with rich prose on the facing page';
    }
    if (scenicScore) {
      return 'image-led scenic spread with breathing room and a refined text page';
    }
    if (nightScore) {
      return 'moody editorial spread with restrained note and stronger title styling';
    }
    return 'balanced image-text spread with one title, one paragraph, and one small accent note';
  }

  String _writingMode(StorySection section) {
    final tags = section.photo.tags.map((tag) => tag.trim().toLowerCase()).toList(growable: false);
    final source = _mergeNarrativeSeed(section).toLowerCase();
    final portrait = _containsAny(source, const <String>['portrait', 'person', 'face']) ||
        tags.any((tag) => tag.contains('portrait') || tag.contains('person'));
    final scenic = _containsAny(source, const <String>['flower', 'tree', 'lake', 'water', 'garden']) ||
        tags.any((tag) => tag.contains('flower') || tag.contains('tree') || tag.contains('lake'));
    final group = _containsAny(source, const <String>['friends', 'group', 'people', 'classmate']) ||
        tags.any((tag) => tag.contains('group') || tag.contains('friends'));

    if (portrait && scenic) {
      return 'tender portrait prose';
    }
    if (group) {
      return 'warm group memory';
    }
    if (scenic) {
      return 'lyrical scenic prose';
    }
    return 'memory-book editorial';
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  bool _containsAny(String source, Iterable<String> candidates) {
    for (final candidate in candidates) {
      if (candidate.isNotEmpty && source.contains(candidate.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  String _buildCopyPrompt({
    required String title,
    required String subtitle,
    required List<StorySection> sections,
    required AlbumBookDocument document,
    String? storyTemplateId,
  }) {
    final selectedTemplate = storyPromptTemplateById(storyTemplateId);
    final selectedTemplateExample = storyPromptTemplateExampleById(
      storyTemplateId,
    );
    final materialJson = jsonEncode(
      <Map<String, dynamic>>[
        for (var i = 0; i < sections.length; i++) _buildMaterialEntry(i, sections[i]),
      ],
    );
    final spreadJson = jsonEncode(_buildCopyTargets(document));
    final templateHint = selectedTemplate == null
        ? ''
        : '''

Selected writing template for this album:
- category: ${selectedTemplate.category.title}
- template: ${selectedTemplate.title}
- intended feeling: ${selectedTemplate.preview}
- guidance: ${selectedTemplate.instruction}
${selectedTemplateExample.isEmpty ? '' : '- reference example: $selectedTemplateExample'}

How to use this template in the digital album:
- inherit the template's tone, rhythm, emotional focus, and sentence texture
- DO NOT write long story paragraphs like the story result page
- compress the expression so it fits premium album typography and short editorial copy
- titles should stay crisp, memorable, and layout-friendly
- bodies should feel refined and condensed, like a polished album paragraph rather than a full narrative scene
- notes / captions / art words should be even shorter and more controlled
- learn from the example's writing method, but never copy its imagery, place names, or sentence content directly
''';
    return '''
You are a premium Chinese photo-book copywriter.
The layout is already fixed. You must NOT redesign, reorder, move, resize, add, or delete layout elements.
You only write the text that fits the existing templates and text slots.

Return exactly one JSON object and nothing else.
The first character must be { and the last character must be }.
No markdown fences.
No explanation.
No comments.
All user-visible strings must be Simplified Chinese.

Goal:
- write concise but evocative copy that feels literary, specific, and image-aware
- match the existing template and the number of photos on each spread
- if a spread contains multiple related photos, summarize their shared mood or sequence instead of describing each photo separately
- avoid generic decorative filler
- avoid repeating the same cadence on adjacent spreads
- do not write text on top of images in your reasoning; all text you produce will be placed into reserved text slots only
- rewrite the current copy instead of echoing it; existing_text is only a weak reference for role meaning, not text to preserve
- every non-meta slot that already exists should usually receive new wording unless it is truly already optimal
- this digital album is not the long-form story page: every piece of writing must be more concise, more typographic, and easier to place on a spread$templateHint

Template guidance:
- hero_full_bleed / portrait_feature:
  title 4-10 Chinese characters
  body 36-78 Chinese characters
  meta 4-18 Chinese characters
- manifesto_quote / margin_column:
  title 5-12 Chinese characters
  body 48-96 Chinese characters
  note 6-18 Chinese characters
  art_word optional, elegant, 2-4 Chinese characters only
- diptych_memory:
  title 5-10 Chinese characters
  body 32-72 Chinese characters
  note 6-16 Chinese characters
- triptych_rhythm / collage_board / gallery_journal:
  title 4-10 Chinese characters
  body 28-68 Chinese characters
  note 6-16 Chinese characters
  art_word optional, 2-4 Chinese characters only when it truly adds composition value

Hard writing rules:
- never output empty prose like 生活, 记录, 回忆, 风景 as a standalone title
- never output generic decorative words like 春, 花, 樱, 夜樱 as art_word unless they are transformed into a distinctive phrase
- do not invent people, relationships, places, or events not supported by the materials
- keep copy matched to the spread's existing roles; if a role is not useful, you may return an empty string for that role
- if you return an empty string for art_word or caption, the system may remove that slot

Output schema:
{
  "spreads": [
    {
      "spread_index": 1,
      "left_page": {
        "title": "",
        "body": "",
        "meta": "",
        "caption": "",
        "art_word": ""
      },
      "right_page": {
        "title": "",
        "body": "",
        "meta": "",
        "caption": "",
        "art_word": ""
      }
    }
  ]
}

Album title: $title
Album subtitle: $subtitle

Photo materials:
$materialJson

Fixed spread targets:
$spreadJson
''';
  }

  List<Map<String, dynamic>> _buildCopyTargets(AlbumBookDocument document) {
    return document.spreads.map((spread) {
      return <String, dynamic>{
        'spread_index': spread.spreadIndex,
        'template_id': spread.templateId,
        'left_page': _copyTargetForPage(spread.leftPage),
        'right_page': _copyTargetForPage(spread.rightPage),
      };
    }).toList(growable: false);
  }

  Map<String, dynamic> _copyTargetForPage(AlbumPageModel page) {
    final roles = <String, String>{};
    for (final element in page.elements) {
      if (element.type != AlbumElementType.text &&
          element.type != AlbumElementType.subtitle) {
        continue;
      }
      final role = element.payload['role']?.toString().trim() ?? '';
      if (role.isEmpty || roles.containsKey(role)) {
        continue;
      }
      roles[role] = element.payload['text']?.toString().trim() ?? '';
    }
    return <String, dynamic>{
      'side': page.side.name,
      'photo_ids': _pagePhotoIds(page),
      'roles': roles.keys.toList(growable: false),
      'existing_text': roles,
    };
  }

  List<String> _pagePhotoIds(AlbumPageModel page) {
    return page.elements
        .where((element) => element.type == AlbumElementType.image)
        .map((element) => element.payload['photo_id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Duration _timeoutForSectionCount(int count) {
    final seconds = 90 + count * 18;
    final clamped = seconds.clamp(
      _minLayoutTimeout.inSeconds,
      _maxLayoutTimeout.inSeconds,
    );
    return Duration(seconds: clamped);
  }

  Future<Map<String, dynamic>?> _parseAlbumJson({
    required String rawResponse,
    required String title,
    required String subtitle,
    required AlbumBookDocument fallback,
    required Duration requestTimeout,
  }) async {
    final direct = _tryParseJsonObject(rawResponse);
    if (direct != null) {
      return direct;
    }

    final locallyRepaired = _tryRepairJsonLocally(rawResponse);
    if (locallyRepaired != null) {
      return locallyRepaired;
    }

    final modelRepaired = await _repairJsonWithModel(
      rawResponse: rawResponse,
      title: title,
      subtitle: subtitle,
      fallback: fallback,
      requestTimeout: requestTimeout,
    );
    if (modelRepaired != null) {
      return modelRepaired;
    }

    return null;
  }

  Future<Map<String, dynamic>?> _parsePlanJson({
    required String rawResponse,
    required String title,
    required String subtitle,
    required AlbumBookDocument fallback,
    required Duration requestTimeout,
  }) async {
    final direct = _tryParseJsonObject(rawResponse);
    if (direct != null) {
      return direct;
    }

    final locallyRepaired = _tryRepairJsonLocally(rawResponse);
    if (locallyRepaired != null) {
      return locallyRepaired;
    }

    final modelRepaired = await _repairJsonWithModel(
      rawResponse: rawResponse,
      title: title,
      subtitle: subtitle,
      fallback: fallback,
      requestTimeout: requestTimeout,
    );
    return modelRepaired;
  }

  Future<Map<String, dynamic>?> _parseCopyJson({
    required String rawResponse,
    required String title,
    required String subtitle,
    required AlbumBookDocument fallback,
    required Duration requestTimeout,
  }) async {
    final direct = _tryParseJsonObject(rawResponse);
    if (direct != null) {
      return direct;
    }

    final locallyRepaired = _tryRepairJsonLocally(rawResponse);
    if (locallyRepaired != null) {
      return locallyRepaired;
    }

    return _repairJsonWithModel(
      rawResponse: rawResponse,
      title: title,
      subtitle: subtitle,
      fallback: fallback,
      requestTimeout: requestTimeout,
    );
  }

  Map<String, dynamic>? _tryParseJsonObject(String raw) {
    for (final candidate in _jsonCandidates(raw)) {
      final decoded = _decodeMap(candidate);
      if (decoded != null) {
        return decoded;
      }
    }

    return null;
  }

  Map<String, dynamic>? _tryRepairJsonLocally(String raw) {
    for (final candidate in _jsonCandidates(raw, includeNormalized: true)) {
      final normalized = _normalizeJsonCandidate(candidate);
      final decoded = _decodeMap(normalized);
      if (decoded != null) {
        return decoded;
      }

      final relaxed = _relaxJsonCandidate(normalized);
      if (relaxed != normalized) {
        final repaired = _decodeMap(relaxed);
        if (repaired != null) {
          return repaired;
        }
      }
    }
    return null;
  }

  Iterable<String> _jsonCandidates(
    String raw, {
    bool includeNormalized = false,
  }) sync* {
    final seen = <String>{};

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        seen.add(trimmed);
      }
    }

    add(raw);

    final fencedMatches = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      multiLine: true,
    ).allMatches(raw);
    for (final match in fencedMatches) {
      add(match.group(1) ?? '');
    }

    for (final slice in _extractBalancedJsonObjects(raw)) {
      add(slice);
    }

    if (includeNormalized) {
      final originals = seen.toList(growable: false);
      for (final candidate in originals) {
        add(_normalizeJsonCandidate(candidate));
      }
    }

    yield* seen;
  }

  List<String> _extractBalancedJsonObjects(String raw) {
    final results = <String>[];
    var inString = false;
    var escaped = false;
    var depth = 0;
    var start = -1;

    for (var i = 0; i < raw.length; i++) {
      final char = raw[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == '\\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{') {
        if (depth == 0) {
          start = i;
        }
        depth += 1;
        continue;
      }
      if (char == '}' && depth > 0) {
        depth -= 1;
        if (depth == 0 && start >= 0) {
          results.add(raw.substring(start, i + 1));
          start = -1;
        }
      }
    }

    results.sort((a, b) => b.length.compareTo(a.length));
    return results;
  }

  String _normalizeJsonCandidate(String input) {
    var text = input.trim();
    if (text.startsWith('```')) {
      text = text.replaceAll(RegExp(r'^```(?:json)?\s*'), '');
      text = text.replaceAll(RegExp(r'\s*```$'), '');
    }

    text = text
        .replaceAll('\uFEFF', '')
        .replaceAll('\u0000', '')
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\uFF1A', ':')
        .replaceAll('\uFF0C', ',')
        .replaceAll('\uFF08', '(')
        .replaceAll('\uFF09', ')')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    text = text.replaceFirst(RegExp(r'^(json|output|answer)\s*[:：]?\s*', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
    text = text.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

    text = text.replaceAll(RegExp(r',\s*([}\]])'), r'$1');

    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      text = text.substring(firstBrace, lastBrace + 1);
    }

    return text.trim();
  }

  String _relaxJsonCandidate(String input) {
    var text = input;
    text = text.replaceAllMapped(
      RegExp(r'([{,]\s*)([A-Za-z_][A-Za-z0-9_\-]*)(\s*:)'),
      (match) => '${match.group(1)}"${match.group(2)}"${match.group(3)}',
    );
    text = text.replaceAllMapped(
      RegExp(":\\s*'([^'\\\\]*(?:\\\\.[^'\\\\]*)*)'"),
      (match) => ': "${_escapeJsonString(match.group(1) ?? '')}"',
    );
    text = text.replaceAllMapped(
      RegExp("([{,]\\s*)'([^'\\\\]*(?:\\\\.[^'\\\\]*)*)'(\\s*:)"),
      (match) =>
          '${match.group(1)}"${_escapeJsonString(match.group(2) ?? '')}"${match.group(3)}',
    );
    text = text
        .replaceAll(RegExp(r'\bNone\b'), 'null')
        .replaceAll(RegExp(r'\bTrue\b'), 'true')
        .replaceAll(RegExp(r'\bFalse\b'), 'false');
    text = text.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
    return text.trim();
  }

  String _escapeJsonString(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
  }

  Map<String, dynamic>? _decodeMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is String) {
        final nested = decoded.trim();
        if (nested.isNotEmpty && nested != text) {
          return _decodeMap(nested);
        }
        return null;
      }
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            final map = item.map(
              (key, value) => MapEntry<String, dynamic>(key.toString(), value),
            );
            return _unwrapCandidateMap(map);
          }
        }
        return null;
      }
      if (decoded is Map<String, dynamic>) {
        return _unwrapCandidateMap(decoded);
      }
      if (decoded is Map) {
        return _unwrapCandidateMap(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, dynamic> _normalizeAlbumJson(
    Map<String, dynamic> parsed, {
    required String title,
    required String subtitle,
    required AlbumBookDocument fallback,
  }) {
    final root = _unwrapCandidateMap(parsed);
    final album = _asStringKeyMap(root['album']);
    final book = _asStringKeyMap(album['book']);
    final spreads = _normalizeSpreads(
      root['spreads'] ??
          root['pages'] ??
          root['layouts'] ??
          root['spreads_json'],
    );

    return <String, dynamic>{
      'schema_version': root['schema_version']?.toString() ??
          AlbumBookDesignTokens.schemaVersion,
      'album': <String, dynamic>{
        'title': _pickFirstText(<Object?>[
          album['title'],
          root['title'],
          title,
        ]),
        'subtitle': _pickFirstText(<Object?>[
          album['subtitle'],
          root['subtitle'],
          subtitle,
        ]),
        'theme': _pickFirstText(<Object?>[
          album['theme'],
          root['theme'],
          'memory_book',
        ]),
        'book': <String, dynamic>{
          'orientation': 'landscape',
          'page_width': _asNumOrFallback(book['page_width'], fallback.pageWidth),
          'page_height': _asNumOrFallback(book['page_height'], fallback.pageHeight),
          'spread_count': spreads.length,
        },
      },
      'spreads': spreads,
      'layout_source': latestLayoutSource,
    };
  }

  Map<String, dynamic> _normalizeCopyJson(Map<String, dynamic> parsed) {
    final root = _unwrapCandidateMap(parsed);
    final rawSpreads = root['spreads'] ??
        root['pages'] ??
        root['items'] ??
        root['copy_plan'] ??
        root['copy'];
    final spreads = <Map<String, dynamic>>[];
    if (rawSpreads is List) {
      for (final item in rawSpreads) {
        final map = _asStringKeyMap(item);
        if (map.isEmpty) {
          continue;
        }
        spreads.add(
          <String, dynamic>{
            'spread_index': _asIntOrFallback(
              map['spread_index'] ?? map['spread'] ?? map['index'],
              spreads.length,
            ),
            'left_page': _normalizeCopyPage(
              map['left_page'] ?? map['left'] ?? map['page_left'],
            ),
            'right_page': _normalizeCopyPage(
              map['right_page'] ?? map['right'] ?? map['page_right'],
            ),
          },
        );
      }
    }
    return <String, dynamic>{'spreads': spreads};
  }

  Map<String, dynamic> _normalizeCopyPage(Object? raw) {
    final page = _asStringKeyMap(raw);
    return <String, dynamic>{
      'title': _pickFirstText(<Object?>[page['title'], page['headline']]),
      'body': _pickFirstText(<Object?>[
        page['body'],
        page['summary'],
        page['paragraph'],
        page['copy'],
      ]),
      'meta': _pickFirstText(<Object?>[page['meta'], page['date_line']]),
      'caption': _pickFirstText(<Object?>[
        page['caption'],
        page['note'],
        page['whisper'],
      ]),
      'art_word': _pickFirstText(<Object?>[
        page['art_word'],
        page['word'],
      ]),
    };
  }

  AlbumBookDocument _applyCopyJson(
    AlbumBookDocument document,
    Map<String, dynamic> normalized,
  ) {
    final spreads = List<AlbumSpreadModel>.from(document.spreads);
    final rawSpreads = normalized['spreads'];
    if (rawSpreads is! List) {
      return document;
    }

    for (final item in rawSpreads) {
      final map = _asStringKeyMap(item);
      if (map.isEmpty) {
        continue;
      }
      final spreadIndex = _asIntOrFallback(
        map['spread_index'] ?? map['index'],
        -1,
      );
      var documentIndex = spreads.indexWhere((spread) => spread.spreadIndex == spreadIndex);
      if (documentIndex < 0 && spreadIndex > 0 && spreadIndex - 1 < spreads.length) {
        documentIndex = spreadIndex - 1;
      }
      if (documentIndex < 0 && spreadIndex == 0 && rawSpreads.length == spreads.length) {
        documentIndex = rawSpreads.indexOf(item);
      }
      if (documentIndex < 0) {
        final byOrder = rawSpreads.indexOf(item);
        if (byOrder >= 0 && byOrder < spreads.length) {
          documentIndex = byOrder;
        }
      }
      if (documentIndex < 0) {
        continue;
      }
      final spread = spreads[documentIndex];
      spreads[documentIndex] = spread.copyWith(
        leftPage: _applyCopyPage(
          spread.leftPage,
          _asStringKeyMap(map['left_page']),
        ),
        rightPage: _applyCopyPage(
          spread.rightPage,
          _asStringKeyMap(map['right_page']),
        ),
      );
    }

    return document.copyWith(spreads: spreads);
  }

  AlbumPageModel _applyCopyPage(
    AlbumPageModel page,
    Map<String, dynamic> pageCopy,
  ) {
    if (pageCopy.isEmpty) {
      return page;
    }

    final elements = <AlbumElementModel>[];
    for (final element in page.elements) {
      if (element.type != AlbumElementType.text &&
          element.type != AlbumElementType.subtitle) {
        elements.add(element);
        continue;
      }
      final role = element.payload['role']?.toString().trim() ?? '';
      final replacement = switch (role) {
        'title' => pageCopy['title']?.toString(),
        'body' => pageCopy['body']?.toString(),
        'meta' => pageCopy['meta']?.toString(),
        'subtitle' => pageCopy['caption']?.toString(),
        'caption' => pageCopy['caption']?.toString(),
        'art_word' => pageCopy['art_word']?.toString(),
        _ => null,
      };
      if (replacement == null) {
        elements.add(element);
        continue;
      }
      if ((role == 'caption' || role == 'subtitle' || role == 'art_word') &&
          replacement.trim().isEmpty) {
        continue;
      }
      if (replacement.trim().isEmpty) {
        elements.add(element);
        continue;
      }
      final payload = Map<String, dynamic>.from(element.payload);
      payload['text'] = replacement.trim();
      elements.add(element.copyWith(payload: payload));
    }
    return page.copyWith(elements: elements);
  }

  AlbumBookAiPlan _normalizeAiPlan(
    Map<String, dynamic> parsed, {
    required List<StorySection> sections,
    required AlbumBookStylePreset stylePreset,
  }) {
    final root = _unwrapCandidateMap(parsed);
    final rawSpreads = root['spreads'] ?? root['plans'] ?? root['spread_plans'] ?? root['layouts'];
    final sectionByIndex = <int, StorySection>{
      for (var i = 0; i < sections.length; i++) i + 1: sections[i],
    };
    final style = AlbumBookStylePresetX.fromName(
      _pickFirstText(<Object?>[
        root['style_preset'],
        root['album_style'],
        stylePreset.name,
      ]),
    );

    final spreads = <AlbumBookAiSpreadPlan>[];
    if (rawSpreads is List) {
      for (final item in rawSpreads) {
        final map = _asStringKeyMap(item);
        if (map.isEmpty) {
          continue;
        }
        final templateId = _pickFirstText(<Object?>[
          map['template_id'],
          map['template'],
          map['kind'],
          'hero_full_bleed',
        ]);
        final photoIds = <String>[];
        final rawPhotoIds = map['photo_ids'];
        if (rawPhotoIds is List) {
          for (final rawId in rawPhotoIds) {
            final id = rawId?.toString().trim() ?? '';
            if (id.isNotEmpty) {
              photoIds.add(id);
            }
          }
        }
        final rawIndexes = map['indexes'] ?? map['photo_indexes'];
        if (photoIds.isEmpty && rawIndexes is List) {
          for (final rawIndex in rawIndexes) {
            final index = int.tryParse(rawIndex?.toString() ?? '');
            final section = index == null ? null : sectionByIndex[index];
            final photoId = section?.photo.id.trim() ?? '';
            if (photoId.isNotEmpty) {
              photoIds.add(photoId);
            }
          }
        }
        if (photoIds.isEmpty) {
          continue;
        }
        spreads.add(
          AlbumBookAiSpreadPlan(
            templateId: templateId,
            photoIds: photoIds.toSet().toList(growable: false),
            title: _pickFirstText(<Object?>[map['title']]),
            body: _pickFirstText(<Object?>[map['body'], map['summary'], map['paragraph']]),
            meta: _pickFirstText(<Object?>[map['meta'], map['date_line']]),
            note: _pickFirstText(<Object?>[map['note'], map['caption'], map['whisper']]),
            artWord: _pickFirstText(<Object?>[map['art_word'], map['word']]),
          ),
        );
      }
    }

    return AlbumBookAiPlan(stylePreset: style, spreads: spreads);
  }

  AlbumBookDocument _stabilizeDocument(
    AlbumBookDocument document, {
    required AlbumBookDocument fallback,
  }) {
    final spreads = <AlbumSpreadModel>[];
    for (var i = 0; i < document.spreads.length; i++) {
      final spread = document.spreads[i];
      final fallbackSpread = i < fallback.spreads.length ? fallback.spreads[i] : null;
      spreads.add(_stabilizeSpread(spread, fallbackSpread));
    }
    return document.copyWith(spreads: spreads, layoutSource: latestLayoutSource);
  }

  AlbumSpreadModel _stabilizeSpread(
    AlbumSpreadModel spread,
    AlbumSpreadModel? fallbackSpread,
  ) {
    if (fallbackSpread == null) {
      return spread;
    }

    final totalImages = _imageCount(spread.leftPage) + _imageCount(spread.rightPage);
    if (totalImages == 0) {
      return fallbackSpread.copyWith(spreadIndex: spread.spreadIndex);
    }

    final leftPage = _shouldBorrowFallbackPage(spread.leftPage)
        ? fallbackSpread.leftPage.copyWith(pageIndex: spread.leftPage.pageIndex)
        : spread.leftPage;
    final rightPage = _shouldBorrowFallbackPage(spread.rightPage)
        ? fallbackSpread.rightPage.copyWith(pageIndex: spread.rightPage.pageIndex)
        : spread.rightPage;

    final stabilized = spread.copyWith(
      leftPage: leftPage,
      rightPage: rightPage,
    );

    final repairedImageCount = _imageCount(stabilized.leftPage) + _imageCount(stabilized.rightPage);
    if (_templateNeedsMultipleImages(stabilized.templateId) &&
        repairedImageCount < _minimumImageCount(stabilized.templateId)) {
      return fallbackSpread.copyWith(spreadIndex: spread.spreadIndex);
    }
    return stabilized;
  }

  bool _shouldBorrowFallbackPage(AlbumPageModel page) {
    final imageCount = _imageCount(page);
    if (imageCount > 0) {
      return false;
    }

    final substantialText = page.elements.where((element) {
      final role = element.payload['role']?.toString() ?? '';
      if (element.type != AlbumElementType.text && element.type != AlbumElementType.subtitle) {
        return false;
      }
      return role == 'title' || role == 'body' || role == 'art_word';
    }).length;
    final totalText = page.elements.where((element) {
      return element.type == AlbumElementType.text || element.type == AlbumElementType.subtitle;
    }).length;

    return substantialText == 0 && totalText <= 1;
  }

  int _imageCount(AlbumPageModel page) {
    return page.elements.where((element) => element.type == AlbumElementType.image).length;
  }

  bool _templateNeedsMultipleImages(String templateId) {
    return templateId == 'diptych_memory' ||
        templateId == 'triptych_rhythm' ||
        templateId == 'collage_board' ||
        templateId == 'gallery_journal' ||
        templateId == 'margin_column' ||
        templateId == 'portrait_feature';
  }

  int _minimumImageCount(String templateId) {
    switch (templateId) {
      case 'diptych_memory':
        return 2;
      case 'triptych_rhythm':
        return 3;
      case 'collage_board':
        return 3;
      case 'gallery_journal':
        return 3;
      case 'margin_column':
        return 2;
      case 'portrait_feature':
        return 2;
      default:
        return 1;
    }
  }

  Map<String, dynamic> _unwrapCandidateMap(Map<String, dynamic> map) {
    final nestedKeys = <String>[
      'output',
      'result',
      'data',
      'response',
      'content',
      'payload',
      'answer',
      'message',
      'document',
      'book_layout',
      'album_layout',
      'layout',
      'design',
    ];

    for (final key in nestedKeys) {
      final nested = map[key];
      if (nested is Map) {
        final child = nested.map(
          (childKey, value) => MapEntry<String, dynamic>(childKey.toString(), value),
        );
        if (_looksAlbumLike(child)) {
          return _unwrapCandidateMap(child);
        }
      }
      if (nested is String) {
        final decoded = _tryParseJsonObject(nested);
        if (decoded != null) {
          return _unwrapCandidateMap(decoded);
        }
      }
    }
    return map;
  }

  bool _looksAlbumLike(Map<String, dynamic> map) {
    return map.containsKey('spreads') ||
        map.containsKey('album') ||
        map.containsKey('pages') ||
        map.containsKey('layouts') ||
        map.containsKey('left_page') ||
        map.containsKey('right_page');
  }

  Future<Map<String, dynamic>?> _repairJsonWithModel({
    required String rawResponse,
    required String title,
    required String subtitle,
    required AlbumBookDocument fallback,
    required Duration requestTimeout,
  }) async {
    final trimmed = rawResponse.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final repairTimeoutSeconds = math.min(
      90,
      math.max(30, (requestTimeout.inSeconds / 3).round()),
    );
    final repairPrompt = _buildJsonRepairPrompt(
      rawResponse: trimmed,
      title: title,
      subtitle: subtitle,
      fallback: fallback,
    );

    try {
      final repairedText = await LLMService().completeText(
        prompt: repairPrompt,
        systemPrompt: structuredSystemPrompt,
        jsonMode: true,
        temperature: 0.1,
        topP: 0.2,
        requestTimeout: Duration(seconds: repairTimeoutSeconds),
      );
      if (repairedText == null || repairedText.trim().isEmpty) {
        return null;
      }

      return _tryRepairJsonLocally(repairedText) ?? _tryParseJsonObject(repairedText);
    } catch (_) {
      return null;
    }
  }

  String _buildJsonRepairPrompt({
    required String rawResponse,
    required String title,
    required String subtitle,
    required AlbumBookDocument fallback,
  }) {
    final fallbackJson = jsonEncode(_compactFallback(fallback));
    return '''
You are fixing a malformed DeepSeek album-layout response.
Your job is not to redesign the album. Your job is to convert the broken response into one valid JSON object that matches the album-layout schema.

Rules:
- return exactly one JSON object and nothing else
- do not add markdown fences
- do not add explanations
- preserve the original layout intent whenever possible
- if the original response contains wrapper fields like output/result/data/content/layout, unwrap them
- if some fields are missing, fill with safe defaults
- all strings must be Simplified Chinese where they are user-visible
- if a spread is unusable, keep a minimal but valid spread structure instead of prose

Album title: $title
Album subtitle: $subtitle
Fallback compact reference:
$fallbackJson

Broken response to repair:
${jsonEncode(rawResponse)}
''';
  }

  List<Map<String, dynamic>> _normalizeSpreads(Object? rawSpreads) {
    if (rawSpreads is! List) {
      return const <Map<String, dynamic>>[];
    }

    return rawSpreads.asMap().entries.map((entry) {
      final raw = _asStringKeyMap(entry.value);
      final leftPage = _normalizePage(
        raw['left_page'] ?? raw['left'] ?? raw['page_left'],
        pageIndex: entry.key * 2,
        side: 'left',
      );
      final rightPage = _normalizePage(
        raw['right_page'] ?? raw['right'] ?? raw['page_right'],
        pageIndex: entry.key * 2 + 1,
        side: 'right',
      );
      return <String, dynamic>{
        'spread_index': _asIntOrFallback(raw['spread_index'], entry.key),
        'template_id': _pickFirstText(<Object?>[
          raw['template_id'],
          raw['template'],
          raw['kind'],
          'custom',
        ]),
        'left_page': leftPage,
        'right_page': rightPage,
      };
    }).toList(growable: false);
  }

  Map<String, dynamic> _normalizePage(
    Object? rawPage, {
    required int pageIndex,
    required String side,
  }) {
    final page = _asStringKeyMap(rawPage);
    final background = _asStringKeyMap(page['background']);
    final rawElements = _collectPageElements(page);

    return <String, dynamic>{
      'page_index': _asIntOrFallback(page['page_index'], pageIndex),
      'side': _pickFirstText(<Object?>[page['side'], side]),
      'background': <String, dynamic>{
        'color_token': _pickFirstText(<Object?>[
          background['color_token'],
          page['background_color_token'],
          page['background_color'],
          'paper_warm',
        ]),
      },
      'elements': _normalizeElements(rawElements),
    };
  }

  List<Map<String, dynamic>> _collectPageElements(Map<String, dynamic> page) {
    final collected = <Map<String, dynamic>>[];

    void addAllFrom(String key, {String? forceType}) {
      final raw = page[key];
      if (raw is! List) {
        return;
      }
      for (final item in raw) {
        final map = _asStringKeyMap(item);
        if (map.isEmpty) {
          continue;
        }
        if (forceType != null && !(map['type']?.toString().trim().isNotEmpty ?? false)) {
          collected.add(<String, dynamic>{...map, 'type': forceType});
        } else {
          collected.add(map);
        }
      }
    }

    addAllFrom('elements');
    addAllFrom('items');
    addAllFrom('layers');
    addAllFrom('components');
    addAllFrom('blocks');
    addAllFrom('images', forceType: 'image');
    addAllFrom('photos', forceType: 'image');
    addAllFrom('texts', forceType: 'text');
    addAllFrom('captions', forceType: 'text');
    addAllFrom('shapes', forceType: 'shape');

    return collected;
  }

  List<Map<String, dynamic>> _normalizeElements(Object? rawElements) {
    if (rawElements is! List) {
      return const <Map<String, dynamic>>[];
    }

    return rawElements.asMap().entries.map((entry) {
      final element = _asStringKeyMap(entry.value);
      final style = _asStringKeyMap(element['style']);
      return <String, dynamic>{
        'id': _pickFirstText(<Object?>[
          element['id'],
          'element_${entry.key}',
        ]),
        'type': _normalizeElementType(
          _pickFirstText(<Object?>[
            element['type'],
            'text',
          ]),
        ),
        'x': _asNumOrFallback(element['x'], 0.1),
        'y': _asNumOrFallback(element['y'], 0.1),
        'w': _asNumOrFallback(element['w'], 0.3),
        'h': _asNumOrFallback(element['h'], 0.2),
        'rotation': _asNumOrFallback(element['rotation'], 0),
        'z_index': _asIntOrFallback(element['z_index'], entry.key),
        'locked': element['locked'] == true,
        ..._filterElementPayload(element),
        'style': <String, dynamic>{
          'font_id': _pickFirstText(<Object?>[
            style['font_id'],
            'sans_clean',
          ]),
          'font_size': _asNumOrFallback(style['font_size'], 18),
          'color_token': _pickFirstText(<Object?>[
            style['color_token'],
            'ink_soft',
          ]),
          'align': _normalizeAlign(
            _pickFirstText(<Object?>[
              style['align'],
              'left',
            ]),
          ),
          'weight': _pickFirstText(<Object?>[
            style['weight'],
            '400',
          ]),
          'shadow': style['shadow'] == true,
          'border_radius': _asNumOrFallback(style['border_radius'], 0.04),
        },
      };
    }).toList(growable: false);
  }

  Map<String, dynamic> _filterElementPayload(Map<String, dynamic> element) {
    final payload = Map<String, dynamic>.from(element)
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
    return payload;
  }

  String _normalizeElementType(String value) {
    switch (value.trim().toLowerCase()) {
      case 'photo':
      case 'picture':
      case 'image_element':
        return 'image';
      case 'textbox':
      case 'paragraph':
      case 'copy':
        return 'text';
      case 'label':
      case 'kicker':
      case 'note':
        return 'subtitle';
      case 'panel':
      case 'backdrop':
      case 'card':
        return 'shape';
      default:
        return value.trim().isEmpty ? 'text' : value.trim();
    }
  }

  String _normalizeAlign(String value) {
    switch (value.trim().toLowerCase()) {
      case 'centre':
      case 'middle':
        return 'center';
      case 'start':
        return 'left';
      case 'end':
        return 'right';
      default:
        return value.trim().isEmpty ? 'left' : value.trim();
    }
  }

  Map<String, dynamic> _asStringKeyMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry<String, dynamic>(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  String _pickFirstText(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  num _asNumOrFallback(Object? value, num fallback) {
    if (value is num) {
      return value;
    }
    return num.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int _asIntOrFallback(Object? value, int fallback) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Map<String, dynamic> _compactFallback(AlbumBookDocument fallback) {
    return <String, dynamic>{
      'layout_source': fallback.layoutSource,
      'page_width': fallback.pageWidth,
      'page_height': fallback.pageHeight,
      'spread_count': fallback.spreads.length,
      'text_page_recipe': <String, dynamic>{
        'meta': <String, dynamic>{'font': 'mono_note', 'font_size': 14, 'accent': true},
        'title': <String, dynamic>{'font': 'serif_elegant', 'font_size': 24},
        'body': <String, dynamic>{'font': 'serif_elegant', 'font_size': 19},
      },
    };
  }

  String _trim(String input, int maxChars) {
    final text = input.trim();
    if (text.runes.length <= maxChars) {
      return text;
    }
    return '${String.fromCharCodes(text.runes.take(math.max(0, maxChars - 3)))}...';
  }
}
