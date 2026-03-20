import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../utils/ocr_policy.dart';
import '../utils/tag_sanitizer.dart';

class OcrService {
  OcrService._internal();

  static final OcrService _instance = OcrService._internal();

  factory OcrService() => _instance;

  static const Set<String> _textHintTags = <String>{
    '文字',
    '文本',
    '文档',
    '屏幕',
    '截图',
    '海报',
    '书页',
    '书本',
    '课件',
    'PPT',
    'ppt',
    '纸张',
    '广告',
    '菜单',
    '招牌',
    '试卷',
    '作业',
    '黑板',
    '牌子',
    'Text',
    'Document',
    'Poster',
    'Screen',
    'Book',
    'Menu',
    'Sign',
  };

  static const Set<String> _blockedExactTags = <String>{
    '欢迎使用智能影记',
    '欢迎使用智能影记!',
    '欢迎使用智能影记！',
    '我的相册',
    '智能影记',
    '首页',
    '相册',
    '设置',
    '我的',
    '发现',
    '我的作品',
    '创建',
    '编辑',
    '分享',
  };

  static const Set<String> _blockedContainsTags = <String>{
    '开始创作',
    '检测到',
    '张图片',
    '继续创作',
    '生成视频',
    '智能影记',
    '我的相册',
    '我的作品',
  };

  final TextRecognizer _chineseRecognizer = TextRecognizer(
    script: TextRecognitionScript.chinese,
  );
  final TextRecognizer _latinRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  static bool shouldRunOcr(
    List<String> tags, {
    double? aspectRatio,
  }) {
    if (!OcrPolicy.mlKitEnabled) {
      return false;
    }
    final hasHintTag = tags.any(_textHintTags.contains);
    final screenshotLike =
        aspectRatio != null && (aspectRatio < 0.6 || aspectRatio > 1.8);
    return hasHintTag || screenshotLike;
  }

  Future<OcrResult> analyzeImageFile(File imageFile) async {
    if (!OcrPolicy.mlKitEnabled) {
      return OcrResult.empty();
    }
    try {
      final inputImage = InputImage.fromFile(imageFile);
      var recognized = await _chineseRecognizer.processImage(inputImage);

      if (_isEffectivelyEmpty(recognized.text)) {
        recognized = await _latinRecognizer.processImage(inputImage);
      }

      final normalizedText = _normalizeText(recognized.text);
      if (normalizedText.isEmpty) {
        return OcrResult.empty();
      }

      final lines = recognized.blocks
          .expand((block) => block.lines)
          .map((line) => _normalizeText(line.text))
          .where((line) => line.isNotEmpty)
          .toList(growable: false);

      final meaningfulLines = lines
          .where((line) => !_isNoisyLine(line))
          .toList(growable: false);
      if (meaningfulLines.isEmpty) {
        return OcrResult.empty();
      }

      final meaningfulText = meaningfulLines.join(' ');
      final tags = _extractTags(meaningfulLines, meaningfulText);
      final summary = _buildSummary(meaningfulLines, meaningfulText);
      return OcrResult(
        text: meaningfulText.length > 2000
            ? meaningfulText.substring(0, 2000)
            : meaningfulText,
        tags: tags,
        summary: summary,
      );
    } catch (error) {
      debugPrint('❌ OCR 识别失败: $error');
      return OcrResult.empty();
    }
  }

  bool _isEffectivelyEmpty(String text) => _normalizeText(text).isEmpty;

  String _normalizeText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _extractTags(List<String> lines, String normalizedText) {
    final ordered = <String>[];

    void addTag(String value) {
      final tag = TagSanitizer.sanitizeOcrTag(value);
      if (tag == null || ordered.contains(tag)) {
        return;
      }
      if (RegExp(r'^\d+$').hasMatch(tag)) {
        return;
      }
      if (_isNoisyTag(tag)) {
        return;
      }
      ordered.add(tag);
    }

    for (final line in lines) {
      if (_isNoisyLine(line)) {
        continue;
      }

      if (line.length >= 2 && line.length <= 12) {
        addTag(line);
      }

      final tokens = line
          .split(RegExp(r'[，。；：、“”‘’（）()【】\[\]\-—_/,.;:!?！？\s]+'))
          .map((token) => token.trim())
          .where((token) => token.length >= 2 && token.length <= 16);
      for (final token in tokens) {
        addTag(token);
        if (ordered.length >= 5) {
          return ordered;
        }
      }
    }

    if (ordered.isEmpty && normalizedText.isNotEmpty) {
      addTag(normalizedText.length > 12 ? normalizedText.substring(0, 12) : normalizedText);
    }

    return TagSanitizer.sanitizeOcrTags(ordered, maxTags: 5);
  }

  String _buildSummary(List<String> lines, String normalizedText) {
    final meaningfulLines = lines
        .where((line) => !_isNoisyLine(line))
        .toList(growable: false);

    if (meaningfulLines.isNotEmpty) {
      final bestLine = meaningfulLines.firstWhere(
        (line) => line.length >= 4,
        orElse: () => meaningfulLines.first,
      );
      return bestLine.length > 40 ? '${bestLine.substring(0, 40)}...' : bestLine;
    }
    return normalizedText.length > 40
        ? '${normalizedText.substring(0, 40)}...'
        : normalizedText;
  }

  bool _isNoisyLine(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return true;
    }

    if (_blockedExactTags.contains(normalized)) {
      return true;
    }

    if (_blockedContainsTags.any(normalized.contains)) {
      return true;
    }

    if (_looksLikeDateOrTime(normalized)) {
      return true;
    }

    if (_looksLikeUiNoise(normalized) || _looksLikeAsciiNoise(normalized)) {
      return true;
    }

    if (normalized.contains('欢迎使用智能影记')) {
      return true;
    }

    if (normalized.contains('我的相册') || normalized.contains('我的作品')) {
      return true;
    }

    return false;
  }

  bool _isNoisyTag(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return true;
    }

    if (_blockedExactTags.contains(normalized)) {
      return true;
    }

    if (_blockedContainsTags.any(normalized.contains)) {
      return true;
    }

    if (_looksLikeDateOrTime(normalized)) {
      return true;
    }

    if (_looksLikeUiNoise(normalized) || _looksLikeAsciiNoise(normalized)) {
      return true;
    }

    if (RegExp(r'^(19|20)\d{2}[·./-](春天|夏天|秋天|冬天)$').hasMatch(normalized)) {
      return true;
    }

    if (RegExp(r'^\d{1,2}月\d{1,2}日$').hasMatch(normalized)) {
      return true;
    }

    if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(normalized)) {
      return true;
    }

    if (normalized.contains('智能影记') || normalized.contains('我的相册')) {
      return true;
    }

    return false;
  }

  bool _looksLikeDateOrTime(String value) {
    return RegExp(r'^(\d{1,2}:\d{2})(\s*[·•]\s*.*)?$').hasMatch(value) ||
        RegExp(r'^(19|20)\d{2}[年./-]\d{1,2}[月./-]\d{1,2}日?$').hasMatch(value) ||
        RegExp(r'^(19|20)\d{2}\s*[·•]\s*(春天|夏天|秋天|冬天)$').hasMatch(value) ||
        RegExp(r'^\d{1,2}月\s*[·•]\s*').hasMatch(value);
  }

  bool _looksLikeUiNoise(String value) {
    if (value.contains('|') || value.contains('>')) {
      return true;
    }

    if (RegExp(r'^第?\d+[页张个条篇项]$').hasMatch(value)) {
      return true;
    }

    if (RegExp(r'^\d+\s*[张页个条项]$').hasMatch(value)) {
      return true;
    }

    if (RegExp(r'^[·•|丨lI]+').hasMatch(value)) {
      return true;
    }

    return false;
  }

  bool _looksLikeAsciiNoise(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^[A-Z]{2,6}$').hasMatch(compact)) {
      return true;
    }

    if (RegExp(r'^[A-Za-z0-9_./-]{2,10}$').hasMatch(compact) &&
        !RegExp(r'[\u4e00-\u9fff]').hasMatch(compact)) {
      return true;
    }

    return false;
  }

  Future<void> dispose() async {
    await _chineseRecognizer.close();
    await _latinRecognizer.close();
  }
}

class OcrResult {
  const OcrResult({
    required this.text,
    required this.tags,
    required this.summary,
  });

  factory OcrResult.empty() {
    return const OcrResult(text: '', tags: <String>[], summary: '');
  }

  final String text;
  final List<String> tags;
  final String summary;

  bool get hasText => text.isNotEmpty;
}
