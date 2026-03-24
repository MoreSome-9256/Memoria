import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/tag_taxonomy_v2.dart';
import '../utils/tag_sanitizer.dart';
import 'semantic_matching_service.dart';

class MobileClipTagService {
  MobileClipTagService._internal();

  static final MobileClipTagService _instance =
      MobileClipTagService._internal();

  factory MobileClipTagService() => _instance;

  static const int _defaultTopK = memoriaFineTopK;
  static const int _defaultCoarseTopK = memoriaCoarseTopK;
  static const double _coarseScoreThreshold = 0.16;
  static const double _coarseProbabilityThreshold = 0.035;
  static const double _coarseScoreMargin = 0.075;
  static const Map<MemoriaTagDimension, double> _dimensionThresholds =
      <MemoriaTagDimension, double>{
        MemoriaTagDimension.subject: 0.165,
        MemoriaTagDimension.scene: 0.17,
        MemoriaTagDimension.activity: 0.18,
        MemoriaTagDimension.atmosphere: 0.19,
        MemoriaTagDimension.media: 0.205,
      };

  static const Set<String> _blockedTags = <String>{
    '套路',
    '未婚妻',
    '字幕',
    '房主',
    '采购员',
  };

  final SemanticMatchingService _semanticService = SemanticMatchingService();
  final Map<String, List<double>> _prototypeByLabel = <String, List<double>>{};
  final Map<String, List<double>> _coarsePrototypeById = <String, List<double>>{};

  bool _warmedUp = false;
  bool _startupWarmUpScheduled = false;
  Future<void>? _warmUpFuture;

  void scheduleWarmUpAtAppStart({
    Duration initialDelay = const Duration(milliseconds: 1200),
  }) {
    if (_warmedUp || _warmUpFuture != null || _startupWarmUpScheduled) {
      return;
    }
    _startupWarmUpScheduled = true;
    unawaited(_runScheduledWarmUp(initialDelay: initialDelay));
  }

  Future<void> warmUp() async {
    if (_warmedUp) {
      return;
    }
    if (_warmUpFuture != null) {
      await _warmUpFuture;
      return;
    }
    _warmUpFuture = Future<void>(() async {
      await _semanticService.warmUp();
      for (final definition in memoriaMasterTagDefinitions) {
        final promptVectors = await _embedPromptsSequentially(
          definition.prompts,
        );
        _prototypeByLabel[definition.label] = _meanAndNormalize(promptVectors);
        await Future<void>.delayed(Duration.zero);
      }
      for (final coarse in memoriaCoarseTagDefinitions) {
        if (coarse.prompts.isEmpty) {
          continue;
        }
        final promptVectors = await _embedPromptsSequentially(
          coarse.prompts,
        );
        _coarsePrototypeById[coarse.id] = _meanAndNormalize(promptVectors);
        await Future<void>.delayed(Duration.zero);
      }
      _warmedUp = true;
    });
    try {
      await _warmUpFuture;
    } finally {
      _warmUpFuture = null;
    }
  }

  Future<void> _runScheduledWarmUp({required Duration initialDelay}) async {
    try {
      if (initialDelay > Duration.zero) {
        await Future<void>.delayed(initialDelay);
      }
      await warmUp();
      debugPrint('✅ MobileCLIP 标签文本向量已在后台完成预热');
    } catch (error, stackTrace) {
      debugPrint('⚠️ MobileCLIP 标签文本向量后台预热失败: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _startupWarmUpScheduled = false;
    }
  }

  Future<List<List<double>>> _embedPromptsSequentially(
    Iterable<String> prompts,
  ) async {
    final vectors = <List<double>>[];
    for (final prompt in prompts) {
      vectors.add(await _semanticService.embedText(prompt));
      await Future<void>.delayed(Duration.zero);
    }
    return vectors;
  }

  Future<List<String>> retrieveTags(
    List<double> imageEmbedding, {
    int topK = _defaultTopK,
    int coarseTopK = _defaultCoarseTopK,
  }) async {
    final diagnostics = await retrieveTagDiagnostics(
      imageEmbedding,
      topK: topK,
      coarseTopK: coarseTopK,
    );
    return diagnostics.map((item) => item.tag).toList(growable: false);
  }

  Future<List<MobileClipCoarseDiagnostic>> retrieveCoarseTagDiagnostics(
    List<double> imageEmbedding, {
    int topK = _defaultCoarseTopK,
  }) async {
    if (imageEmbedding.isEmpty || topK <= 0) {
      return const <MobileClipCoarseDiagnostic>[];
    }

    await warmUp();

    final scored = <MobileClipCoarseDiagnostic>[];
    for (final definition in memoriaCoarseTagDefinitions) {
      final prototype = _coarsePrototypeById[definition.id];
      if (prototype == null ||
          prototype.isEmpty ||
          prototype.length != imageEmbedding.length) {
        continue;
      }
      final score = _semanticService.calculateSimilarity(imageEmbedding, prototype);
      scored.add(
        MobileClipCoarseDiagnostic(
          coarseId: definition.id,
          label: definition.label,
          score: score,
          probability: 0.0,
        ),
      );
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final normalized = _attachCoarseProbabilities(scored);
    final limited = normalized
        .take(math.min(topK, normalized.length))
        .toList(growable: false);
    return _filterConfidentCoarseCandidates(limited);
  }

  Future<List<MobileClipTagDiagnostic>> retrieveTagDiagnostics(
    List<double> imageEmbedding, {
    int topK = _defaultTopK,
    int coarseTopK = _defaultCoarseTopK,
  }) async {
    if (imageEmbedding.isEmpty) {
      return const <MobileClipTagDiagnostic>[];
    }

    await warmUp();

    final coarseDiagnostics = await retrieveCoarseTagDiagnostics(
      imageEmbedding,
      topK: coarseTopK,
    );
    if (coarseDiagnostics.isEmpty) {
      return _otherFallbackDiagnostics();
    }

    final selectedCoarseIds = coarseDiagnostics.map((item) => item.coarseId).toSet();
    final coarseProbabilityById = <String, double>{
      for (final item in coarseDiagnostics) item.coarseId: item.probability,
    };
    final scored = <_TagScoreCandidate>[];
    for (final definition in memoriaMasterTagDefinitions) {
      final label = definition.label.trim();
      if (label.isEmpty || _isBlockedLabel(label)) {
        continue;
      }
      final coarseId = memoriaFineLabelToCoarseId[label];
      if (coarseId == null || !selectedCoarseIds.contains(coarseId)) {
        continue;
      }
      final prototype = _prototypeByLabel[label];
      if (prototype == null ||
          prototype.isEmpty ||
          prototype.length != imageEmbedding.length) {
        continue;
      }
      final score = _semanticService.calculateSimilarity(imageEmbedding, prototype);
      final weightedScore = _applyCoarseWeight(
        score,
        coarseProbabilityById[coarseId] ?? 0,
      );
      final threshold =
          _dimensionThresholds[definition.primaryDimension] ?? 0.2;
      if (score < threshold) {
        continue;
      }
      scored.add(
        _TagScoreCandidate(
          definition: definition,
          score: score,
          weightedScore: weightedScore,
        ),
      );
    }

    if (scored.isEmpty) {
      return _otherFallbackDiagnostics();
    }

    scored.sort((a, b) => b.weightedScore.compareTo(a.weightedScore));
    final rankedCandidates = <_TagScoreCandidate>[...scored];

    final selected = <_TagScoreCandidate>[];
    final selectedLabels = <String>{};
    final dynamicFineTopK = _resolveDynamicFineTopK(
      rankedCandidates
          .map((candidate) => candidate.weightedScore)
          .toList(growable: false),
      maxTopK: topK,
      minTopK: math.max(5, coarseDiagnostics.length + 1),
    );

    void tryAdd(_TagScoreCandidate candidate) {
      if (selected.length >= dynamicFineTopK) {
        return;
      }
      final label = candidate.definition.label;
      if (selectedLabels.contains(label)) {
        return;
      }
      selected.add(candidate);
      selectedLabels.add(label);
    }

    for (final coarse in coarseDiagnostics) {
      final best = _bestCandidateForCoarse(scored, coarse.coarseId);
      if (best != null) {
        tryAdd(best);
      }
    }

    for (final candidate in rankedCandidates) {
      tryAdd(candidate);
      if (selected.length >= dynamicFineTopK) {
        break;
      }
    }

    if (selected.isEmpty) {
      return _otherFallbackDiagnostics();
    }

    return _attachFineProbabilities(selected);
  }

  bool _isBlockedLabel(String label) {
    if (_blockedTags.contains(label)) {
      return true;
    }
    return TagSanitizer.isBlockedExactTag(label);
  }

  _TagScoreCandidate? _bestCandidateForCoarse(
    List<_TagScoreCandidate> candidates,
    String coarseId,
  ) {
    for (final candidate in candidates) {
      if (memoriaFineLabelToCoarseId[candidate.definition.label] == coarseId) {
        return candidate;
      }
    }
    return null;
  }

  String _coarseLabelForFineTag(String label) {
    if (label == memoriaOtherLabel) {
      return memoriaOtherLabel;
    }
    final coarseId = memoriaFineLabelToCoarseId[label];
    if (coarseId == null) {
      return '未分类';
    }
    return memoriaCoarseIdToDefinition[coarseId]?.label ?? '未分类';
  }

  List<MobileClipCoarseDiagnostic> _attachCoarseProbabilities(
    List<MobileClipCoarseDiagnostic> candidates,
  ) {
    if (candidates.isEmpty) {
      return const <MobileClipCoarseDiagnostic>[];
    }
    final probabilities = _softmaxProbabilities(
      candidates.map((candidate) => candidate.score).toList(growable: false),
    );
    return List<MobileClipCoarseDiagnostic>.generate(
      candidates.length,
      (index) => MobileClipCoarseDiagnostic(
        coarseId: candidates[index].coarseId,
        label: candidates[index].label,
        score: candidates[index].score,
        probability: probabilities[index],
      ),
      growable: false,
    );
  }

  List<MobileClipTagDiagnostic> _attachFineProbabilities(
    List<_TagScoreCandidate> selected,
  ) {
    if (selected.isEmpty) {
      return const <MobileClipTagDiagnostic>[];
    }
    final probabilities = _softmaxProbabilities(
      selected.map((candidate) => candidate.score).toList(growable: false),
    );
    return List<MobileClipTagDiagnostic>.generate(
      selected.length,
      (index) {
        final entry = selected[index];
        return MobileClipTagDiagnostic(
          tag: entry.definition.label,
          score: entry.score,
          probability: probabilities[index],
          category: _coarseLabelForFineTag(entry.definition.label),
          coarseId: memoriaFineLabelToCoarseId[entry.definition.label] ?? '',
        );
      },
      growable: false,
    );
  }

  List<MobileClipCoarseDiagnostic> _filterConfidentCoarseCandidates(
    List<MobileClipCoarseDiagnostic> ranked,
  ) {
    if (ranked.isEmpty) {
      return const <MobileClipCoarseDiagnostic>[];
    }
    final bestScore = ranked.first.score;
    return ranked.where((candidate) {
      final closeToBest = (bestScore - candidate.score) <= _coarseScoreMargin;
      return candidate.score >= _coarseScoreThreshold &&
          (candidate.probability >= _coarseProbabilityThreshold || closeToBest);
    }).toList(growable: false);
  }

  List<MobileClipTagDiagnostic> _otherFallbackDiagnostics() {
    return const <MobileClipTagDiagnostic>[
      MobileClipTagDiagnostic(
        tag: memoriaOtherLabel,
        score: 0.0,
        probability: 1.0,
        category: memoriaOtherLabel,
        coarseId: memoriaOtherCoarseId,
      ),
    ];
  }

  int _resolveDynamicCoarseTopK(
    List<MobileClipCoarseDiagnostic> ranked, {
    required int maxTopK,
  }) {
    final limit = math.min(maxTopK, ranked.length);
    if (limit <= 3) {
      return limit;
    }

    var count = 3;
    final first = ranked[0].probability;
    if (limit >= 4) {
      final fourth = ranked[3].probability;
      final third = ranked[2].probability;
      final keepFourth =
          fourth >= 0.11 || fourth >= third * 0.74 || (first - fourth) <= 0.22;
      if (keepFourth) {
        count = 4;
      }
    }
    if (limit >= 5) {
      final fifth = ranked[4].probability;
      final anchor = ranked[count - 1].probability;
      final keepFifth =
          fifth >= 0.085 ||
          fifth >= anchor * 0.8 ||
          (first - fifth) <= 0.28;
      if (keepFifth) {
        count = 5;
      }
    }
    return count;
  }

  int _resolveDynamicFineTopK(
    List<double> rankedScores, {
    required int maxTopK,
    required int minTopK,
  }) {
    if (rankedScores.isEmpty) {
      return 0;
    }
    final limit = math.min(maxTopK, rankedScores.length);
    var count = minTopK.clamp(1, limit);
    final probabilities = _softmaxProbabilities(rankedScores.take(limit).toList());
    if (count >= limit) {
      return count;
    }

    final first = probabilities.first;
    final second = probabilities.length > 1 ? probabilities[1] : 0.0;
    final dominantFirst = first >= 0.56 && (first - second) >= 0.20;
    if (dominantFirst && count <= 1) {
      return 1;
    }

    for (var i = count; i < limit; i++) {
      final current = probabilities[i];
      final previous = probabilities[i - 1];
      final gap = previous - current;
      final shouldKeep =
          current >= 0.075 ||
          gap <= 0.1 ||
          (current / first) >= 0.33;
      if (!shouldKeep) {
        break;
      }
      count = i + 1;
      final cumulative = probabilities
          .take(count)
          .fold<double>(0.0, (sum, value) => sum + value);
      if (count >= 6 && cumulative >= 0.92 && gap > 0.12) {
        break;
      }
    }
    return count;
  }

  double _applyCoarseWeight(double fineScore, double coarseProbability) {
    final coarseBoost = 0.9 + (coarseProbability * 0.35);
    return fineScore * coarseBoost;
  }

  List<double> _softmaxProbabilities(List<double> scores) {
    if (scores.isEmpty) {
      return const <double>[];
    }
    final maxScore = scores.reduce(math.max);
    final exps = scores
        .map((score) => math.exp((score - maxScore) * 10))
        .toList(growable: false);
    final sum = exps.fold<double>(0.0, (total, value) => total + value);
    if (sum <= 0) {
      return List<double>.filled(scores.length, 1 / scores.length);
    }
    return exps.map((value) => value / sum).toList(growable: false);
  }

  List<double> _meanAndNormalize(List<List<double>> vectors) {
    if (vectors.isEmpty) {
      return const <double>[];
    }

    final dim = vectors.first.length;
    if (dim == 0 || vectors.any((vector) => vector.length != dim)) {
      return const <double>[];
    }

    final merged = List<double>.filled(dim, 0.0);
    for (final vector in vectors) {
      for (var i = 0; i < dim; i++) {
        merged[i] += vector[i];
      }
    }
    for (var i = 0; i < dim; i++) {
      merged[i] /= vectors.length;
    }

    var squaredSum = 0.0;
    for (final value in merged) {
      squaredSum += value * value;
    }
    if (squaredSum <= 0) {
      return merged;
    }
    final norm = squaredSum.sqrt();
    return merged.map((value) => value / norm).toList(growable: false);
  }
}

class MobileClipTagDiagnostic {
  const MobileClipTagDiagnostic({
    required this.tag,
    required this.score,
    required this.probability,
    required this.category,
    required this.coarseId,
  });

  final String tag;
  final double score;
  final double probability;
  final String category;
  final String coarseId;
}

class MobileClipCoarseDiagnostic {
  const MobileClipCoarseDiagnostic({
    required this.coarseId,
    required this.label,
    required this.score,
    required this.probability,
  });

  final String coarseId;
  final String label;
  final double score;
  final double probability;
}

class _TagScoreCandidate {
  const _TagScoreCandidate({
    required this.definition,
    required this.score,
    required this.weightedScore,
  });

  final MemoriaTagDefinition definition;
  final double score;
  final double weightedScore;
}

extension on double {
  double sqrt() {
    if (this <= 0) {
      return 0;
    }
    var x = this;
    var prev = 0.0;
    while ((x - prev).abs() > 1e-9) {
      prev = x;
      x = 0.5 * (x + this / x);
    }
    return x;
  }
}
