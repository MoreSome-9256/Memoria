// 垃圾照片过滤服务，用于识别严重模糊、遮挡和低事件价值内容。

import 'dart:math' as math;

import 'semantic_matching_service.dart';

class JunkPhotoCategoryDefinition {
  const JunkPhotoCategoryDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.prototypePrompts,
    required this.threshold,
    this.alwaysMarkAboveThreshold = false,
  });

  final String id;
  final String label;
  final String description;
  final List<String> prototypePrompts;
  final double threshold;
  final bool alwaysMarkAboveThreshold;
}

class JunkPhotoHit {
  const JunkPhotoHit({
    required this.categoryId,
    required this.label,
    required this.description,
    required this.score,
    required this.threshold,
  });

  final String categoryId;
  final String label;
  final String description;
  final double score;
  final double threshold;
}

class JunkPhotoDecision {
  const JunkPhotoDecision({required this.shouldFilter, required this.hits});

  factory JunkPhotoDecision.keep() {
    return const JunkPhotoDecision(shouldFilter: false, hits: <JunkPhotoHit>[]);
  }

  final bool shouldFilter;
  final List<JunkPhotoHit> hits;

  JunkPhotoHit? get primaryHit => hits.isEmpty ? null : hits.first;
}

class JunkPhotoBatchResult {
  const JunkPhotoBatchResult({required this.decisions});

  final Map<int, JunkPhotoDecision> decisions;

  JunkPhotoDecision decisionFor(int photoId) =>
      decisions[photoId] ?? JunkPhotoDecision.keep();
}

class JunkPhotoCleanupCandidate {
  const JunkPhotoCleanupCandidate({
    required this.photoId,
    required this.assetId,
    required this.path,
    required this.timestamp,
    required this.reasons,
  });

  final int photoId;
  final String assetId;
  final String path;
  final int timestamp;
  final List<JunkPhotoHit> reasons;

  String get primaryLabel => reasons.isEmpty ? '低价值照片' : reasons.first.label;
}

class JunkPhotoReasonSummary {
  const JunkPhotoReasonSummary({
    required this.categoryId,
    required this.label,
    required this.count,
  });

  final String categoryId;
  final String label;
  final int count;
}

class JunkPhotoCleanupReport {
  const JunkPhotoCleanupReport({
    required this.reportId,
    required this.totalCount,
    required this.candidates,
    required this.reasonCounts,
  });

  final String reportId;
  final int totalCount;
  final List<JunkPhotoCleanupCandidate> candidates;
  final Map<String, int> reasonCounts;

  bool get hasCandidates => totalCount > 0;

  List<JunkPhotoReasonSummary> get reasonSummaries {
    final summaries = <JunkPhotoReasonSummary>[];
    final countsById = <String, int>{};
    final labelsById = <String, String>{};
    for (final candidate in candidates) {
      final reasons = candidate.reasons.isEmpty
          ? const <JunkPhotoHit>[JunkPhotoFilterService.unknownReason]
          : candidate.reasons;
      for (final reason in reasons) {
        if (!countsById.containsKey(reason.categoryId)) {
          labelsById[reason.categoryId] = reason.label;
        }
        countsById[reason.categoryId] =
            (countsById[reason.categoryId] ?? 0) + 1;
      }
    }
    for (final entry in countsById.entries) {
      summaries.add(
        JunkPhotoReasonSummary(
          categoryId: entry.key,
          label: labelsById[entry.key] ?? entry.key,
          count: entry.value,
        ),
      );
    }
    summaries.sort((a, b) {
      final countOrder = b.count.compareTo(a.count);
      return countOrder != 0 ? countOrder : a.label.compareTo(b.label);
    });
    return List<JunkPhotoReasonSummary>.unmodifiable(summaries);
  }

  List<String> get orderedReasonSummaries {
    return reasonSummaries
        .map((summary) => '${summary.label}${summary.count}张')
        .toList(growable: false);
  }

  List<String> get assetIds => candidates
      .map((candidate) => candidate.assetId)
      .where((assetId) => assetId.trim().isNotEmpty)
      .toList(growable: false);

  static JunkPhotoCleanupReport fromCandidates(
    List<JunkPhotoCleanupCandidate> candidates,
  ) {
    final reasonCounts = <String, int>{};
    for (final candidate in candidates) {
      final labels =
          (candidate.reasons.isEmpty
                  ? const <JunkPhotoHit>[JunkPhotoFilterService.unknownReason]
                  : candidate.reasons)
              .map((reason) => reason.label)
              .toSet()
              .toList(growable: false);
      for (final label in labels) {
        reasonCounts[label] = (reasonCounts[label] ?? 0) + 1;
      }
    }
    return JunkPhotoCleanupReport(
      reportId: DateTime.now().toUtc().toIso8601String(),
      totalCount: candidates.length,
      candidates: List<JunkPhotoCleanupCandidate>.from(
        candidates,
        growable: false,
      ),
      reasonCounts: Map<String, int>.unmodifiable(reasonCounts),
    );
  }
}

class JunkPhotoFilterService {
  JunkPhotoFilterService._internal();

  static const String junkCandidateTag = '__junk_candidate__';
  static const String pendingJunkCandidateTag = '__junk_pending__';
  static const String keptJunkCandidateTag = '__junk_kept__';
  static const String junkReasonTagPrefix = '__junk_reason__:';
  static const String unknownReasonCategoryId = 'unknown';
  static const JunkPhotoHit unknownReason = JunkPhotoHit(
    categoryId: unknownReasonCategoryId,
    label: '原因待复核',
    description: '该候选来自旧版本或手动操作，未记录自动识别原因，请人工确认。',
    score: 0,
    threshold: 0,
  );

  static final JunkPhotoFilterService _instance =
      JunkPhotoFilterService._internal();

  factory JunkPhotoFilterService() => _instance;

  static const List<JunkPhotoCategoryDefinition> _definitions =
      <JunkPhotoCategoryDefinition>[
        JunkPhotoCategoryDefinition(
          id: 'code',
          label: '二维码/海报码',
          description: '付款码、二维码海报、条形码、取件码等检索价值较低的图片。',
          prototypePrompts: <String>[
            'a QR code poster',
            'a payment QR code',
            'a barcode or QR code on a screen',
            'a poster with a large QR code',
          ],
          threshold: 0.2,
          alwaysMarkAboveThreshold: true,
        ),
        JunkPhotoCategoryDefinition(
          id: 'meme',
          label: '表情包/梗图',
          description: '聊天表情包、网络梗图、二次创作配文图等重复消费型图片。',
          prototypePrompts: <String>[
            'a meme image with text overlay',
            'a funny reaction meme or sticker',
            'a social media meme screenshot',
            'a captioned joke image template',
          ],
          threshold: 0.2,
        ),
        JunkPhotoCategoryDefinition(
          id: 'plain_selfie',
          label: '低信息自拍/证件照',
          description: '纯大头自拍、证件照或没有背景、他人和事件线索的人像。多人场景、旅行和活动合照不应命中。',
          prototypePrompts: <String>[
            'a plain close-up selfie headshot with no background context',
            'an ID photo portrait against a plain background',
            'a passport photo or document portrait',
            'a close-up face selfie without environment or event context',
          ],
          threshold: 0.2,
        ),
        JunkPhotoCategoryDefinition(
          id: 'advertisement_poster',
          label: '广告/海报',
          description: '程序生成的分享海报、营销广告、纯宣传图。街景或活动照片中出现广告牌不应命中。',
          prototypePrompts: <String>[
            'a generated advertising poster image',
            'a promotional marketing poster with text',
            'a social media share poster advertisement',
            'a product advertisement image with graphic design',
          ],
          threshold: 0.2,
        ),
        JunkPhotoCategoryDefinition(
          id: 'screenshot',
          label: '应用/网页截图',
          description: '手机应用、聊天、网页、桌面界面等直接截取的屏幕内容。',
          prototypePrompts: <String>[
            'a smartphone app screenshot with user interface',
            'a chat conversation screenshot',
            'a webpage screenshot with interface controls',
            'a desktop software screenshot',
          ],
          threshold: 0.2,
          alwaysMarkAboveThreshold: true,
        ),
        JunkPhotoCategoryDefinition(
          id: 'document',
          label: '文档/资料',
          description: '文档、试卷、课件、书页、票据或以阅读文字为主要目的的资料图片。',
          prototypePrompts: <String>[
            'a photographed document page filled with text',
            'a scanned paper document',
            'a worksheet or presentation slide',
            'a receipt invoice or printed form',
          ],
          threshold: 0.2,
          alwaysMarkAboveThreshold: true,
        ),
        JunkPhotoCategoryDefinition(
          id: 'abstract_low_value',
          label: '低事件价值图形',
          description: '抽象图案、纯装饰图、无具体事件意义或生活线索的图片。',
          prototypePrompts: <String>[
            'an abstract graphic pattern with no real world event',
            'a decorative wallpaper image',
            'a simple abstract art image without people or place',
            'a generated geometric pattern image',
          ],
          threshold: 0.2,
        ),
        JunkPhotoCategoryDefinition(
          id: 'dark_or_occluded',
          label: '严重遮挡/过暗',
          description: '黑屏、口袋误拍、镜头被遮挡、几乎不可辨认的照片。',
          prototypePrompts: <String>[
            'a nearly black photo',
            'a very dark blurry accidental photo',
            'a photo blocked by a finger',
            'an accidental pocket shot',
            'a heavily shadowed image with no clear subject',
          ],
          threshold: 0.2,
        ),
        JunkPhotoCategoryDefinition(
          id: 'low_value_landmark',
          label: '低价值地标/路牌',
          description: '路牌、门牌号、停车位标识、交通指示牌等只有单一信息维度的内容。',
          prototypePrompts: <String>[
            'a street sign or road sign',
            'a house number or address plate',
            'a parking space sign',
            'a directional signpost',
          ],
          threshold: 0.2,
        ),
        JunkPhotoCategoryDefinition(
          id: 'blurred_or_broken',
          label: '残缺/严重模糊',
          description: '构图严重缺失、抖动模糊、误触拍摄、主体无法辨认的照片。',
          prototypePrompts: <String>[
            'a blurry accidental photo',
            'a heavily motion blurred image',
            'a cropped incomplete accidental photo',
            'a partial broken image with no clear subject',
          ],
          threshold: 0.15,
        ),
      ];

  final SemanticMatchingService _semanticService = SemanticMatchingService();
  final Map<String, List<List<double>>> _promptVectorCache =
      <String, List<List<double>>>{};

  bool _isWarmedUp = false;

  List<JunkPhotoCategoryDefinition> get definitions => _definitions;

  static bool isInternalJunkTag(String value) {
    final trimmed = value.trim();
    return trimmed == junkCandidateTag ||
        trimmed == pendingJunkCandidateTag ||
        trimmed == keptJunkCandidateTag ||
        trimmed.startsWith(junkReasonTagPrefix);
  }

  static String reasonTag(String categoryId) =>
      '$junkReasonTagPrefix${categoryId.trim()}';

  List<JunkPhotoHit> reasonsFromTags(Iterable<String>? tags) {
    if (tags == null) return const <JunkPhotoHit>[];
    final definitionById = <String, JunkPhotoCategoryDefinition>{
      for (final definition in _definitions) definition.id: definition,
    };
    final hits = <JunkPhotoHit>[];
    for (final tag in tags) {
      if (!tag.startsWith(junkReasonTagPrefix)) continue;
      final definition =
          definitionById[tag.substring(junkReasonTagPrefix.length)];
      if (definition == null) continue;
      hits.add(
        JunkPhotoHit(
          categoryId: definition.id,
          label: definition.label,
          description: definition.description,
          score: definition.threshold,
          threshold: definition.threshold,
        ),
      );
    }
    return List<JunkPhotoHit>.unmodifiable(hits);
  }

  static bool isQuarantined(Iterable<String>? tags) {
    if (tags == null) return false;
    return tags.contains(junkCandidateTag) ||
        tags.contains(pendingJunkCandidateTag);
  }

  static bool isConfirmedJunk(Iterable<String>? tags) {
    if (tags == null) return false;
    return tags.contains(junkCandidateTag);
  }

  static bool hasFinalDecision(Iterable<String>? tags) {
    if (tags == null) return false;
    return tags.contains(junkCandidateTag) ||
        tags.contains(keptJunkCandidateTag);
  }

  /// 可被 `compute()` 序列化的分类定义列表
  List<Map<String, Object?>> get definitionsJson {
    return _definitions
        .map(
          (d) => <String, Object?>{
            'id': d.id,
            'label': d.label,
            'description': d.description,
            'threshold': d.threshold,
          },
        )
        .toList(growable: false);
  }

  Future<void> warmUp() async {
    if (_isWarmedUp) {
      return;
    }
    await _semanticService.warmUp();
    for (final definition in _definitions) {
      _promptVectorCache[definition.id] = await _buildPromptVectors(definition);
    }
    _isWarmedUp = true;
  }

  Future<JunkPhotoBatchResult> evaluateBatch(
    Map<int, List<double>> imageEmbeddings,
  ) async {
    final validEmbeddings = Map<int, List<double>>.fromEntries(
      imageEmbeddings.entries.where((entry) => entry.value.isNotEmpty),
    );
    if (validEmbeddings.isEmpty) {
      return const JunkPhotoBatchResult(decisions: <int, JunkPhotoDecision>{});
    }
    await warmUp();
    final hitsByPhotoId = <int, List<JunkPhotoHit>>{};

    for (final definition in _definitions) {
      final promptVectors = _promptVectorCache[definition.id];
      if (promptVectors == null || promptVectors.isEmpty) {
        continue;
      }
      final scores = <int, double>{};
      for (final entry in validEmbeddings.entries) {
        scores[entry.key] = _bestPromptScore(entry.value, promptVectors);
      }
      final outlierIds = definition.alwaysMarkAboveThreshold
          ? scores.entries
                .where((entry) => entry.value >= definition.threshold)
                .map((entry) => entry.key)
                .toSet()
          : significantOutlierIds(scores, absoluteFloor: definition.threshold);
      for (final photoId in outlierIds) {
        hitsByPhotoId
            .putIfAbsent(photoId, () => <JunkPhotoHit>[])
            .add(
              JunkPhotoHit(
                categoryId: definition.id,
                label: definition.label,
                description: definition.description,
                score: scores[photoId]!,
                threshold: definition.threshold,
              ),
            );
      }
    }

    final decisions = <int, JunkPhotoDecision>{};
    for (final photoId in validEmbeddings.keys) {
      final hits = hitsByPhotoId[photoId] ?? <JunkPhotoHit>[];
      hits.sort((a, b) => b.score.compareTo(a.score));
      decisions[photoId] = JunkPhotoDecision(
        shouldFilter: hits.isNotEmpty,
        hits: List<JunkPhotoHit>.unmodifiable(hits),
      );
    }
    return JunkPhotoBatchResult(decisions: Map.unmodifiable(decisions));
  }

  static Set<int> significantOutlierIds(
    Map<int, double> scores, {
    required double absoluteFloor,
  }) {
    if (scores.length <= 8) {
      return scores.entries
          .where((entry) => entry.value >= absoluteFloor)
          .map((entry) => entry.key)
          .toSet();
    }
    final sorted = scores.values.toList(growable: false)..sort();
    final median = _median(sorted);
    final deviations =
        sorted.map((score) => (score - median).abs()).toList(growable: false)
          ..sort();
    final mad = _median(deviations);
    final robustSpread = math.max(mad * 1.4826, 0.008);
    final minimumLift = scores.length < 20 ? 0.05 : 0.04;
    final cutoff = math.max(
      absoluteFloor,
      math.max(median + minimumLift, median + robustSpread * 3.5),
    );
    return scores.entries
        .where((entry) => entry.value >= cutoff)
        .map((entry) => entry.key)
        .toSet();
  }

  double _bestPromptScore(
    List<double> imageEmbedding,
    List<List<double>> promptVectors,
  ) {
    var score = -1.0;
    for (final promptVector in promptVectors) {
      if (promptVector.length != imageEmbedding.length) continue;
      final similarity = _semanticService
          .calculateSimilarity(imageEmbedding, promptVector)
          .clamp(-1.0, 1.0);
      if (similarity > score) score = similarity;
    }
    return score;
  }

  static double _median(List<double> sortedValues) {
    if (sortedValues.isEmpty) return 0;
    final middle = sortedValues.length ~/ 2;
    if (sortedValues.length.isOdd) return sortedValues[middle];
    return (sortedValues[middle - 1] + sortedValues[middle]) / 2;
  }

  Future<List<List<double>>> _buildPromptVectors(
    JunkPhotoCategoryDefinition definition,
  ) async {
    final promptVectors = <List<double>>[];
    for (final prompt in definition.prototypePrompts) {
      promptVectors.add(await _semanticService.embedText(prompt));
    }
    return promptVectors
        .where((vector) => vector.isNotEmpty)
        .toList(growable: false);
  }
}
