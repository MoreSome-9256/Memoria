class TagSanitizer {
  TagSanitizer._();

  // Empirically bad tags seen in real output. Block them centrally so OCR,
  // MobileCLIP and event aggregation behave consistently.
  static const Set<String> _blockedExactTags = <String>{
    '炕头',
    '炕洞',
    '月票',
    '当票',
  };

  static String? sanitizeVisualTag(String? value) {
    final normalized = _normalize(value);
    if (normalized == null || _blockedExactTags.contains(normalized)) {
      return null;
    }
    return normalized;
  }

  static String? sanitizeOcrTag(String? value) {
    final normalized = _normalize(value);
    if (normalized == null || _blockedExactTags.contains(normalized)) {
      return null;
    }
    return normalized;
  }

  static String? sanitizeDisplayTag(String? value) {
    final normalized = _normalize(value);
    if (normalized == null || _blockedExactTags.contains(normalized)) {
      return null;
    }
    return normalized;
  }

  static List<String> sanitizeVisualTags(Iterable<String> values, {int? maxTags}) {
    return _sanitize(values, sanitizer: sanitizeVisualTag, maxTags: maxTags);
  }

  static List<String> sanitizeOcrTags(Iterable<String> values, {int? maxTags}) {
    return _sanitize(values, sanitizer: sanitizeOcrTag, maxTags: maxTags);
  }

  static List<String> sanitizeDisplayTags(Iterable<String> values, {int? maxTags}) {
    return _sanitize(values, sanitizer: sanitizeDisplayTag, maxTags: maxTags);
  }

  static bool isBlockedExactTag(String value) {
    return _blockedExactTags.contains(value.trim());
  }

  static List<String> _sanitize(
    Iterable<String> values, {
    required String? Function(String? value) sanitizer,
    int? maxTags,
  }) {
    final result = <String>[];
    for (final value in values) {
      final sanitized = sanitizer(value);
      if (sanitized == null || result.contains(sanitized)) {
        continue;
      }
      result.add(sanitized);
      if (maxTags != null && result.length >= maxTags) {
        break;
      }
    }
    return result;
  }

  static String? _normalize(String? value) {
    final normalized = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized == null || normalized.isEmpty || normalized.length == 1) {
      return null;
    }
    return normalized;
  }
}