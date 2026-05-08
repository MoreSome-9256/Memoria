/// 照片描述服务，负责生成单张照片的标题和说明文字。

import 'dart:io';
import 'dart:math' as math;

import '../data/tag_taxonomy_v2.dart';
import '../utils/ocr_policy.dart';
import '../utils/tag_sanitizer.dart';
import 'llm_service.dart';

class PhotoCaptionService {
  PhotoCaptionService({LLMService? llmService})
    : _llmService = llmService ?? LLMService();

  final LLMService _llmService;

  bool get prefersAsyncGeneration => _llmService.isVisionApiConfigured;

  static const Set<String> _blockedRoleTags = <String>{
    '学生',
    '同学',
    '学者',
    '小伙子',
    '残疾人',
    '采购员',
    '房主',
    '房东',
    '未婚妻',
    '未婚夫',
    '套路',
  };

  static const Set<String> _nonDescriptiveVisualTags = <String>{
    memoriaOtherLabel,
  };

  static const Set<String> _textSceneTags = <String>{
    '文字',
    '文档',
    '课件',
    '屏幕',
    '截图',
    '试卷',
    '票据',
    '表格',
    '笔记',
    '论文',
    'PPT',
    'ppt',
  };

  Future<String> generateCaption({
    required File imageFile,
    required List<String> visualTags,
    required List<String> ocrTags,
    required String ocrText,
    required String? location,
    required DateTime takenAt,
    required bool isProbablyScreenshot,
    required int faceCount,
  }) async {
    final sanitizedVisualTags = _sanitizeCaptionTags(visualTags);
    final sanitizedOcrTags = OcrPolicy.effectiveTags(ocrTags, maxTags: 6);
    final trimmedOcrText = OcrPolicy.effectiveText(ocrText);

    if (_llmService.isVisionApiConfigured) {
      try {
        final imageBytes = await imageFile.readAsBytes();
        final caption = await _llmService.generatePhotoCaption(
          imageBytes: imageBytes,
          mimeType: _inferMimeType(imageFile.path),
          tags: sanitizedVisualTags,
          ocrTags: sanitizedOcrTags,
          ocrText: trimmedOcrText,
          location: _normalizeLocation(location),
          takenAt: takenAt,
          isTextHeavy:
              isProbablyScreenshot ||
              _looksTextHeavy(
                sanitizedVisualTags,
                sanitizedOcrTags,
                trimmedOcrText,
              ),
          faceCount: faceCount,
        );
        final cleaned = _cleanCaption(caption);
        if (cleaned != null) {
          return cleaned;
        }
      } catch (_) {
        // Fall back to local caption synthesis if the vision endpoint is not available.
      }
    }

    return _buildLocalCaption(
      visualTags: sanitizedVisualTags,
      ocrTags: sanitizedOcrTags,
      ocrText: trimmedOcrText,
      location: _normalizeLocation(location),
      takenAt: takenAt,
      isProbablyScreenshot: isProbablyScreenshot,
      faceCount: faceCount,
    );
  }

  List<String> _sanitizeCaptionTags(List<String> tags) {
    final sanitized = TagSanitizer.sanitizeVisualTags(tags, maxTags: 6);
    return sanitized
        .where(
          (tag) =>
              !_blockedRoleTags.contains(tag) &&
              !_nonDescriptiveVisualTags.contains(tag),
        )
        .toList(growable: false);
  }

  bool _looksTextHeavy(
    List<String> visualTags,
    List<String> ocrTags,
    String ocrText,
  ) {
    if (ocrTags.isNotEmpty) {
      return true;
    }
    if (ocrText.length >= 12) {
      return true;
    }
    return visualTags.any(_textSceneTags.contains);
  }

  String _buildLocalCaption({
    required List<String> visualTags,
    required List<String> ocrTags,
    required String ocrText,
    required String? location,
    required DateTime takenAt,
    required bool isProbablyScreenshot,
    required int faceCount,
  }) {
    final textHeavy =
        isProbablyScreenshot || _looksTextHeavy(visualTags, ocrTags, ocrText);
    final timePhrase = _timePhrase(takenAt);
    final locationPhrase = location == null ? '' : '在$location';

    if (textHeavy) {
      final textTopic = _pickTextTopic(ocrTags, ocrText, visualTags);
      if (textTopic != null) {
        if (locationPhrase.isNotEmpty) {
          return '$timePhrase$locationPhrase记录的$textTopic';
        }
        return '$timePhrase记录的$textTopic';
      }

      return locationPhrase.isNotEmpty
          ? '$timePhrase$locationPhrase的一页文字资料'
          : '$timePhrase的一页文字资料';
    }

    final subject = _pickVisualSubject(visualTags, faceCount);
    if (locationPhrase.isNotEmpty) {
      return '$timePhrase$locationPhrase的$subject';
    }
    return '$timePhrase的$subject';
  }

  String _pickVisualSubject(List<String> visualTags, int faceCount) {
    if (visualTags.isNotEmpty) {
      if (visualTags.length >= 2) {
        return '${visualTags[0]}与${visualTags[1]}画面';
      }
      return '${visualTags[0]}瞬间';
    }

    if (faceCount >= 2) {
      return '多人合影瞬间';
    }
    if (faceCount == 1) {
      return '一张室内人像';
    }
    return '一幅日常画面';
  }

  String? _pickTextTopic(
    List<String> ocrTags,
    String ocrText,
    List<String> visualTags,
  ) {
    if (ocrTags.isNotEmpty) {
      if (ocrTags.length >= 2) {
        return '${ocrTags[0]}与${ocrTags[1]}内容';
      }
      return '${ocrTags.first}内容';
    }

    final firstLine = ocrText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isNotEmpty) {
      final trimmed = firstLine.length > 14
          ? firstLine.substring(0, 14)
          : firstLine;
      return '$trimmed相关资料';
    }

    final textTag = visualTags.firstWhere(
      _textSceneTags.contains,
      orElse: () => '',
    );
    if (textTag.isNotEmpty) {
      return '$textTag画面';
    }

    return null;
  }

  String? _normalizeLocation(String? location) {
    final normalized = location?.trim();
    if (normalized == null || normalized.isEmpty || normalized == '未知地点') {
      return null;
    }
    return normalized;
  }

  String _timePhrase(DateTime takenAt) {
    final hour = takenAt.hour;
    if (hour >= 5 && hour < 11) {
      return '清晨';
    }
    if (hour >= 11 && hour < 14) {
      return '中午';
    }
    if (hour >= 14 && hour < 18) {
      return '午后';
    }
    if (hour >= 18 && hour < 23) {
      return '夜晚';
    }
    return '深夜';
  }

  String _inferMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  String? _cleanCaption(String? raw) {
    if (raw == null) {
      return null;
    }

    var cleaned = raw.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^[\d一二三四五六七八九十]+[、.：:\s]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'["“”]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleaned.isEmpty) {
      return null;
    }

    final firstSentence = cleaned
        .split(RegExp(r'[\n。！？!]'))
        .map((part) => part.trim())
        .firstWhere((part) => part.isNotEmpty, orElse: () => cleaned);
    cleaned = firstSentence;

    if (cleaned.length > 36) {
      cleaned = cleaned.substring(0, math.min(cleaned.length, 36)).trim();
    }

    if (cleaned.length < 4) {
      return null;
    }

    if (_blockedRoleTags.any(cleaned.contains)) {
      return null;
    }

    return cleaned;
  }
}
