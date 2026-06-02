/// OCR 策略开关和判断逻辑，用于控制文字识别能力的启用方式。

import 'tag_sanitizer.dart';

class OcrPolicy {
  OcrPolicy._();

  static bool _mlKitEnabled = false;

  static bool get mlKitEnabled => _mlKitEnabled;

  static void setRuntimeEnabled(bool enabled) {
    _mlKitEnabled = enabled;
  }

  static List<String> effectiveTags(Iterable<String>? values, {int? maxTags}) {
    if (!mlKitEnabled) {
      return const <String>[];
    }
    return TagSanitizer.sanitizeOcrTags(
      values ?? const <String>[],
      maxTags: maxTags,
    );
  }

  static String effectiveText(String? value, {int? maxLength}) {
    if (!mlKitEnabled) {
      return '';
    }

    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }
    if (maxLength != null && trimmed.length > maxLength) {
      return trimmed.substring(0, maxLength);
    }
    return trimmed;
  }

  static String? effectiveSummary({
    Iterable<String>? tags,
    String? text,
    int maxTags = 3,
    int maxTextLength = 36,
    String separator = ' · ',
  }) {
    if (!mlKitEnabled) {
      return null;
    }

    final sanitizedTags = effectiveTags(tags, maxTags: maxTags);
    if (sanitizedTags.isNotEmpty) {
      return sanitizedTags.take(maxTags).join(separator);
    }

    final trimmed = effectiveText(text);
    if (trimmed.isEmpty) {
      return null;
    }

    return trimmed.length > maxTextLength
        ? '${trimmed.substring(0, maxTextLength)}...'
        : trimmed;
  }
}
