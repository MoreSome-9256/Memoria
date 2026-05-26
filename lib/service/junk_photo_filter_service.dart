/// 垃圾照片过滤服务，用于识别截图、模糊图和低质量内容。

import 'dart:math' as math;

import '../models/entity/photo_entity.dart';
import 'semantic_matching_service.dart';

class JunkPhotoCategoryDefinition {
  const JunkPhotoCategoryDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.prototypePrompts,
    required this.threshold,
    this.screenshotBoost = 0.0,
    this.ocrBoostThreshold = 0,
    this.ocrBoost = 0.0,
    this.extraKeywordHints = const <String>[],
  });

  final String id;
  final String label;
  final String description;
  final List<String> prototypePrompts;
  final double threshold;
  final double screenshotBoost;
  final int ocrBoostThreshold;
  final double ocrBoost;
  final List<String> extraKeywordHints;
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
  const JunkPhotoDecision({
    required this.shouldFilter,
    required this.hits,
  });

  factory JunkPhotoDecision.keep() {
    return const JunkPhotoDecision(
      shouldFilter: false,
      hits: <JunkPhotoHit>[],
    );
  }

  final bool shouldFilter;
  final List<JunkPhotoHit> hits;

  JunkPhotoHit? get primaryHit => hits.isEmpty ? null : hits.first;
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

  List<String> get orderedReasonSummaries {
    final entries = reasonCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((entry) => '${entry.key}${entry.value}张').toList();
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
      final labels = candidate.reasons
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

  static final JunkPhotoFilterService _instance =
      JunkPhotoFilterService._internal();

  factory JunkPhotoFilterService() => _instance;

  static const List<JunkPhotoCategoryDefinition> _definitions =
      <JunkPhotoCategoryDefinition>[
        JunkPhotoCategoryDefinition(
          id: 'screenshot',
          label: '截图/界面',
          description: '聊天截图、支付页、设置页、APP 界面一类的屏幕内容。',
          prototypePrompts: <String>[
            'a mobile phone screenshot',
            'a screenshot of a chat application',
            'a screenshot of a payment app',
            'a screenshot of a settings page',
            'a screenshot of a shopping app interface',
          ],
          threshold: 0.24,
          screenshotBoost: 0.08,
          ocrBoostThreshold: 24,
          ocrBoost: 0.02,
          extraKeywordHints: <String>['screenshot', 'screen', 'ui'],
        ),
        JunkPhotoCategoryDefinition(
          id: 'document',
          label: '文档/表格',
          description: '纸质文件、课件、报表、白板文字、拍屏文档等。',
          prototypePrompts: <String>[
            'a photo of a printed document',
            'a scanned paper document',
            'a close-up photo of text on paper',
            'a spreadsheet or report document',
            'a photo of presentation slides on a screen',
          ],
          threshold: 0.255,
          ocrBoostThreshold: 40,
          ocrBoost: 0.035,
          extraKeywordHints: <String>['document', 'paper', 'text'],
        ),
        JunkPhotoCategoryDefinition(
          id: 'receipt',
          label: '票据/账单',
          description: '小票、发票、快递面单、支付凭证、收据等工具型图片。',
          prototypePrompts: <String>[
            'a photo of a receipt',
            'a bill or invoice document',
            'a shipping label on a package',
            'a payment receipt with text',
          ],
          threshold: 0.27,
          ocrBoostThreshold: 28,
          ocrBoost: 0.03,
          extraKeywordHints: <String>['receipt', 'invoice', 'bill'],
        ),
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
          threshold: 0.275,
          ocrBoostThreshold: 12,
          ocrBoost: 0.015,
          extraKeywordHints: <String>['qr', 'barcode', 'code'],
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
          threshold: 0.285,
          ocrBoostThreshold: 8,
          ocrBoost: 0.015,
          extraKeywordHints: <String>['meme', 'sticker', 'reaction', '梗图', '表情包'],
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
          threshold: 0.295,
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
          threshold: 0.3,
        ),
      ];

  final SemanticMatchingService _semanticService = SemanticMatchingService();
  final Map<String, List<double>> _prototypeCache = <String, List<double>>{};

  bool _isWarmedUp = false;

  List<JunkPhotoCategoryDefinition> get definitions => _definitions;

  /// 可被 `compute()` 序列化的原型缓存
  Map<String, List<double>> get prototypeCache => Map<String, List<double>>.unmodifiable(_prototypeCache);

  /// 可被 `compute()` 序列化的分类定义列表
  List<Map<String, Object?>> get definitionsJson {
    return _definitions.map((d) => <String, Object?>{
      'id': d.id,
      'label': d.label,
      'description': d.description,
      'threshold': d.threshold,
      'screenshotBoost': d.screenshotBoost,
      'ocrBoostThreshold': d.ocrBoostThreshold,
      'ocrBoost': d.ocrBoost,
    }).toList(growable: false);
  }

  Future<void> warmUp() async {
    if (_isWarmedUp) {
      return;
    }
    await _semanticService.warmUp();
    for (final definition in _definitions) {
      _prototypeCache[definition.id] = await _buildPrototype(definition);
    }
    _isWarmedUp = true;
  }

  Future<JunkPhotoDecision> evaluatePhoto({
    required PhotoEntity photo,
    required List<double> imageEmbedding,
    String ocrText = '',
  }) async {
    if (imageEmbedding.isEmpty) {
      return JunkPhotoDecision.keep();
    }

    await warmUp();
    final trimmedOcr = ocrText.trim();
    final hits = <JunkPhotoHit>[];

    for (final definition in _definitions) {
      final prototype = _prototypeCache[definition.id];
      if (prototype == null || prototype.length != imageEmbedding.length) {
        continue;
      }

      var score = _semanticService.calculateSimilarity(imageEmbedding, prototype);
      if (definition.screenshotBoost > 0 && photo.isProbablyScreenshot) {
        score += definition.screenshotBoost;
      }
      if (definition.ocrBoost > 0 &&
          trimmedOcr.length >= definition.ocrBoostThreshold) {
        score += definition.ocrBoost;
      }
      if (_containsKeywordHint(trimmedOcr, definition.extraKeywordHints)) {
        score += 0.015;
      }
      score = score.clamp(-1.0, 1.0);

      if (score >= definition.threshold) {
        hits.add(
          JunkPhotoHit(
            categoryId: definition.id,
            label: definition.label,
            description: definition.description,
            score: score,
            threshold: definition.threshold,
          ),
        );
      }
    }

    hits.sort((a, b) => b.score.compareTo(a.score));
    return JunkPhotoDecision(
      shouldFilter: hits.isNotEmpty,
      hits: List<JunkPhotoHit>.unmodifiable(hits),
    );
  }

  Future<List<double>> _buildPrototype(
    JunkPhotoCategoryDefinition definition,
  ) async {
    final promptVectors = <List<double>>[];
    for (final prompt in definition.prototypePrompts) {
      promptVectors.add(await _semanticService.embedText(prompt));
    }
    return _meanAndNormalize(promptVectors);
  }

  bool _containsKeywordHint(String text, List<String> hints) {
    if (text.isEmpty || hints.isEmpty) {
      return false;
    }
    final lower = text.toLowerCase();
    return hints.any((hint) => lower.contains(hint));
  }

  List<double> _meanAndNormalize(List<List<double>> vectors) {
    if (vectors.isEmpty) {
      return const <double>[];
    }

    final dim = vectors.first.length;
    if (dim == 0 || vectors.any((vector) => vector.length != dim)) {
      return const <double>[];
    }

    final mean = List<double>.filled(dim, 0.0);
    for (final vector in vectors) {
      for (var i = 0; i < dim; i++) {
        mean[i] += vector[i];
      }
    }
    for (var i = 0; i < dim; i++) {
      mean[i] /= vectors.length;
    }

    final norm = math.sqrt(
      mean.fold<double>(0.0, (sum, value) => sum + value * value),
    );
    if (norm <= 0) {
      return mean;
    }
    return mean.map((value) => value / norm).toList(growable: false);
  }
}
