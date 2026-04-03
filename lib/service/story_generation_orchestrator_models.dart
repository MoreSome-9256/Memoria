part of 'story_generation_orchestrator.dart';

class _StoryPhotoMaterial {
  const _StoryPhotoMaterial({
    required this.photo,
    required this.timeText,
    required this.locationText,
    required this.aiTags,
    required this.ocrTags,
    required this.ocrSummary,
    required this.existingCaption,
  });

  final PhotoEntity photo;
  final String timeText;
  final String locationText;
  final List<String> aiTags;
  final List<String> ocrTags;
  final String ocrSummary;
  final String? existingCaption;

  Map<String, dynamic> toJson({
    required int index,
    _CaptionResult? localCaptionResult,
  }) {
    final localCaption = localCaptionResult?.source == _CaptionSource.localVlm
        ? localCaptionResult!.text
        : '';
    final preferredCaption =
        (localCaptionResult?.text.trim().isNotEmpty ?? false)
        ? localCaptionResult!.text
        : (existingCaption ?? '');
    final preferredSource =
        localCaptionResult?.source.apiValue ??
        ((existingCaption?.trim().isNotEmpty ?? false)
            ? _CaptionSource.existingAiFallback.apiValue
            : _CaptionSource.none.apiValue);
    return <String, dynamic>{
      'index': index,
      'captured_at': timeText,
      'location': <String, dynamic>{
        'location_name': photo.locationName?.trim(),
        'district': photo.district?.trim(),
        'city': photo.city?.trim(),
        'province': photo.province?.trim(),
        'display_text': locationText,
      },
      'tags': aiTags,
      'ocr_tags': ocrTags,
      'ocr_summary': ocrSummary,
      'existing_caption': existingCaption ?? '',
      'local_vlm_caption': localCaption,
      'local_vlm_caption_source':
          localCaptionResult?.source.apiValue ?? _CaptionSource.none.apiValue,
      'preferred_caption': preferredCaption,
      'preferred_caption_source': preferredSource,
    };
  }
}

enum _CaptionSource {
  localVlm('local_vlm'),
  existingAiFallback('existing_ai_fallback'),
  none('none');

  const _CaptionSource(this.apiValue);

  final String apiValue;
}

class _CaptionResult {
  const _CaptionResult._({required this.text, required this.source});

  factory _CaptionResult.localVlm(String text) =>
      _CaptionResult._(text: text.trim(), source: _CaptionSource.localVlm);

  factory _CaptionResult.existingAiFallback(String text) => _CaptionResult._(
    text: text.trim(),
    source: _CaptionSource.existingAiFallback,
  );

  final String text;
  final _CaptionSource source;

  String toDisplayText() {
    if (text.trim().isEmpty) {
      return '';
    }
    switch (source) {
      case _CaptionSource.localVlm:
        return '本地 VLM：$text';
      case _CaptionSource.existingAiFallback:
        return '回退 AI Caption：$text';
      case _CaptionSource.none:
        return text;
    }
  }
}

class _StructuredStoryPayload {
  const _StructuredStoryPayload({
    required this.title,
    required this.subtitle,
    required this.story,
    required this.sections,
    required this.highlights,
  });

  final String title;
  final String subtitle;
  final String story;
  final List<String> sections;
  final List<String> highlights;

  factory _StructuredStoryPayload.fromParsedJson(
    Map<String, dynamic> json, {
    required String fallbackTitle,
    required String fallbackSubtitle,
    required int sectionCount,
  }) {
    final title = (json['title']?.toString().trim() ?? '').ifEmpty(
      fallbackTitle,
    );
    final subtitle = (json['subtitle']?.toString().trim() ?? '').ifEmpty(
      fallbackSubtitle,
    );
    final story = json['story']?.toString().trim() ?? '';
    final highlights = (json['highlights'] is List)
        ? (json['highlights'] as List)
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final sections = <String>[];
    if (json['sections'] is List) {
      for (final item in json['sections'] as List) {
        if (item is Map) {
          final text = item['text']?.toString().trim() ?? '';
          if (text.isNotEmpty) {
            sections.add(text);
          }
        }
      }
    }
    final normalizedSections = sections.length == sectionCount
        ? sections
        : const <String>[];
    return _StructuredStoryPayload(
      title: title,
      subtitle: subtitle,
      story: story,
      sections: normalizedSections,
      highlights: highlights,
    );
  }
}

class _LocalRuntime {
  const _LocalRuntime({required this.profile, required this.server});

  final OnDeviceInternvlProfile? profile;
  final OnDeviceInternvlServerStatus? server;
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
