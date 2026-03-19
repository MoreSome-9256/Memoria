import 'dart:math' as math;

import '../data/tag_dictionary.dart';
import 'semantic_matching_service.dart';
import '../utils/tag_sanitizer.dart';

class MobileClipTagService {
  MobileClipTagService._internal();

  static final MobileClipTagService _instance =
      MobileClipTagService._internal();

  factory MobileClipTagService() => _instance;

  static const int _defaultTopK = 5;
  static const double _minimumScore = 0.16;
  static const double _displayScoreGap = 0.04;

  static const Set<String> _blockedTags = <String>{
    '套路',
    '未婚妻',
    '字幕',
    '房主',
    '采购员',
  };

  final SemanticMatchingService _semanticService = SemanticMatchingService();

  bool _warmedUp = false;

  Future<void> warmUp() async {
    if (_warmedUp) {
      return;
    }
    await _semanticService.warmUp();
    await _semanticService.preCacheTagMap(memoriaMasterTaxonomyPromptToLabel);
    _warmedUp = true;
  }

  Future<List<String>> retrieveTags(
    List<double> imageEmbedding, {
    int topK = _defaultTopK,
  }) async {
    final diagnostics = await retrieveTagDiagnostics(
      imageEmbedding,
      topK: topK,
    );
    return diagnostics.map((item) => item.tag).toList(growable: false);
  }

  Future<List<MobileClipTagDiagnostic>> retrieveTagDiagnostics(
    List<double> imageEmbedding, {
    int topK = _defaultTopK,
  }) async {
    if (imageEmbedding.isEmpty) {
      return const <MobileClipTagDiagnostic>[];
    }

    await warmUp();

    final scored = await _semanticService.scoreTagsForImage(
      imageVector: imageEmbedding,
      tagMap: memoriaMasterTaxonomyPromptToLabel,
      topK: math.max(topK * 3, 24),
      threshold: 0.0,
    );

    if (scored.isEmpty) {
      return const <MobileClipTagDiagnostic>[];
    }

    final compact = <MapEntry<String, double>>[];
    final seen = <String>{};
    for (final item in scored) {
      final label = item.label.trim();
      if (label.isEmpty) {
        continue;
      }
      if (_isBlockedLabel(label)) {
        continue;
      }
      if (seen.contains(label)) {
        continue;
      }
      seen.add(label);
      compact.add(MapEntry<String, double>(label, item.score));
    }

    if (compact.isEmpty) {
      return const <MobileClipTagDiagnostic>[];
    }

    final topScore = compact.first.value;
    final displayThreshold = math.max(_minimumScore, topScore - _displayScoreGap);

    final display = compact
        .where((entry) => entry.value >= displayThreshold)
        .take(topK)
        .toList(growable: false);

    final selected = display.isNotEmpty
        ? display
        : compact.take(topK).toList(growable: false);

    return selected
        .map(
          (entry) => MobileClipTagDiagnostic(
            tag: entry.key,
            score: entry.value,
            category: _categoryForLabel(entry.key),
          ),
        )
        .toList(growable: false);
  }

  bool _isBlockedLabel(String label) {
    if (_blockedTags.contains(label)) {
      return true;
    }
    return TagSanitizer.isBlockedExactTag(label);
  }

  String _categoryForLabel(String label) {
    switch (label) {
      case '人物自拍':
      case '合影留念':
      case '婴幼儿/儿童':
      case '二次元/动漫':
        return '人物与群体';
      case '美食饮品':
      case '宠物':
      case '文档截图':
      case '屏幕/代码':
      case '花卉/植物':
      case '交通工具':
        return '物体与特写';
      default:
        return '场景与环境';
    }
  }
}

class MobileClipTagDiagnostic {
  const MobileClipTagDiagnostic({
    required this.tag,
    required this.score,
    required this.category,
  });

  final String tag;
  final double score;
  final String category;
}
