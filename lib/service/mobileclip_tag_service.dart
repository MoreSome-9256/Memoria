/// MobileCLIP 标签服务，把图像向量映射到可读的视觉标签。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/tag_taxonomy_v2.dart';
import '../utils/tag_sanitizer.dart';
import 'mobileclip_litert_service.dart';
import 'semantic_matching_service.dart';

typedef MobileClipTagWarmUpProgress =
    FutureOr<void> Function(int completed, int total, String message);

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
  static const double _coarseFallbackScoreFloor = 0.04;
  static const double _fineScoreFloor = 0.04;
  static const double _fineDisplayScoreGap = 0.055;

  static const Set<String> _blockedTags = <String>{};

  final SemanticMatchingService _semanticService = SemanticMatchingService();
  final Map<String, List<double>> _prototypeByLabel = <String, List<double>>{};
  final Map<String, List<double>> _coarsePrototypeById =
      <String, List<double>>{};
  static const Duration _defaultIdleDisposeDelay = Duration(minutes: 3);

  bool _warmedUp = false;
  bool _startupWarmUpScheduled = false;
  Future<void>? _warmUpFuture;
  int _workflowLeaseCount = 0;
  Timer? _idleDisposeTimer;
  static const String _prototypeCacheFilename = 'tag_prototype_cache.json';
  String? _prototypeCacheKey;

  Future<void> beginWorkflowSession() async {
    _workflowLeaseCount++;
    _cancelIdleDisposeTimer();
  }

  Future<void> endWorkflowSession({
    Duration idleDisposeDelay = _defaultIdleDisposeDelay,
  }) async {
    if (_workflowLeaseCount > 0) {
      _workflowLeaseCount--;
    }
    if (_workflowLeaseCount == 0) {
      _scheduleIdleDispose(idleDisposeDelay);
    }
  }

  /// 可被 `compute()` 序列化的细粒度标签原型（标签名 → 向量）
  Map<String, List<double>> get finePrototypes =>
      Map<String, List<double>>.unmodifiable(_prototypeByLabel);

  /// 可被 `compute()` 序列化的粗粒度类别原型（类别ID → 向量）
  Map<String, List<double>> get coarsePrototypes =>
      Map<String, List<double>>.unmodifiable(_coarsePrototypeById);

  bool get isWarmedUp => _warmedUp;

  void _touchUsage() {
    _cancelIdleDisposeTimer();
  }

  void _cancelIdleDisposeTimer() {
    _idleDisposeTimer?.cancel();
    _idleDisposeTimer = null;
  }

  void _scheduleIdleDispose(Duration delay) {
    _cancelIdleDisposeTimer();
    _idleDisposeTimer = Timer(delay, () async {
      if (_workflowLeaseCount > 0) {
        return;
      }
      await dispose();
    });
  }

  Future<void> dispose() async {
    _cancelIdleDisposeTimer();
    await _semanticService.dispose();
    _prototypeByLabel.clear();
    _coarsePrototypeById.clear();
    _warmedUp = false;
    _warmUpFuture = null;
  }

  void scheduleWarmUpAtAppStart({
    Duration initialDelay = const Duration(milliseconds: 1200),
  }) {
    if (_warmedUp || _warmUpFuture != null || _startupWarmUpScheduled) {
      return;
    }
    _startupWarmUpScheduled = true;
    unawaited(_runScheduledWarmUp(initialDelay: initialDelay));
  }

  Future<void> warmUp({MobileClipTagWarmUpProgress? onProgress}) async {
    _touchUsage();
    if (_warmedUp) {
      await onProgress?.call(1, 1, '标签原型已就绪');
      return;
    }
    if (_warmUpFuture != null) {
      await _warmUpFuture;
      await onProgress?.call(1, 1, '标签原型已就绪');
      return;
    }
    _warmUpFuture = Future<void>(() async {
      _prototypeCacheKey = _computePrototypeCacheKey();
      _prototypeByLabel.clear();
      _coarsePrototypeById.clear();
      if (await _tryLoadPrototypesFromCache()) {
        _warmedUp = true;
        await onProgress?.call(1, 1, '已读取标签原型缓存');
        return;
      }

      final fineTotal = memoriaMasterTagDefinitions.length;
      final coarseTotal = memoriaCoarseTagDefinitions
          .where((definition) => definition.prompts.isNotEmpty)
          .length;
      final total = 1 + fineTotal + coarseTotal;
      var completed = 0;
      await onProgress?.call(completed, total, '加载文本语义模型');
      await _semanticService.warmUp();
      completed++;
      await onProgress?.call(completed, total, '构建细粒度标签原型');
      for (final definition in memoriaMasterTagDefinitions) {
        final prototype = await _buildPrototype(definition.prompts);
        if (prototype.isNotEmpty) {
          _prototypeByLabel[definition.label] = prototype;
        }
        completed++;
        await onProgress?.call(
          completed,
          total,
          '构建细粒度标签原型 ${completed - 1}/$fineTotal',
        );
        await Future<void>.delayed(Duration.zero);
      }
      var coarseCompleted = 0;
      for (final coarse in memoriaCoarseTagDefinitions) {
        if (coarse.prompts.isEmpty) continue;
        final prototype = await _buildPrototype(coarse.prompts);
        if (prototype.isNotEmpty) {
          _coarsePrototypeById[coarse.id] = prototype;
        }
        coarseCompleted++;
        completed++;
        await onProgress?.call(
          completed,
          total,
          '构建粗粒度标签原型 $coarseCompleted/$coarseTotal',
        );
        await Future<void>.delayed(Duration.zero);
      }
      await _savePrototypesToCache();
      _warmedUp = true;
    });
    try {
      await _warmUpFuture;
    } finally {
      _warmUpFuture = null;
    }
  }

  /// 生成标签定义的缓存键——拼接所有标签+prompts 然后做 base64
  String _computePrototypeCacheKey() {
    final buffer = StringBuffer();
    buffer.write('mobileclip-tag-prototypes-real-text-v3');
    buffer.write(MobileClipLiteRtService.modelVersion);
    for (final def in memoriaMasterTagDefinitions) {
      buffer.write(def.label);
      for (final p in def.prompts) {
        buffer.write(p);
      }
    }
    for (final def in memoriaCoarseTagDefinitions) {
      buffer.write(def.id);
      buffer.write(def.label);
      for (final p in def.prompts) {
        buffer.write(p);
      }
    }
    final bytes = utf8.encode(buffer.toString());
    return base64Encode(bytes);
  }

  /// 从本地缓存加载原型向量，返回 true 表示加载成功
  Future<bool> _tryLoadPrototypesFromCache() async {
    try {
      final file = await _prototypeCacheFile();
      if (!await file.exists()) {
        return false;
      }
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      if ((json['key'] as String?) != _prototypeCacheKey) {
        return false;
      }
      final fineRaw = json['fine'] as List<Object?>;
      for (final entry in fineRaw) {
        final pair = entry as List<Object?>;
        final label = pair[0] as String;
        final vec = (pair[1] as List<Object?>)
            .cast<num>()
            .map((n) => n.toDouble())
            .toList();
        _prototypeByLabel[label] = vec;
      }
      final coarseRaw = json['coarse'] as List<Object?>;
      for (final entry in coarseRaw) {
        final pair = entry as List<Object?>;
        final id = pair[0] as String;
        final vec = (pair[1] as List<Object?>)
            .cast<num>()
            .map((n) => n.toDouble())
            .toList();
        _coarsePrototypeById[id] = vec;
      }
      debugPrint(
        '✅ 从缓存加载标签原型向量成功 fine=${_prototypeByLabel.length} coarse=${_coarsePrototypeById.length}',
      );
      return true;
    } catch (e) {
      debugPrint('⚠️ 标签原型缓存加载失败: $e');
      return false;
    }
  }

  /// 将原型向量保存到本地缓存
  Future<void> _savePrototypesToCache() async {
    try {
      final fineList = _prototypeByLabel.entries
          .map((e) => <Object?>[e.key, e.value])
          .toList();
      final coarseList = _coarsePrototypeById.entries
          .map((e) => <Object?>[e.key, e.value])
          .toList();
      final json = <String, Object?>{
        'key': _prototypeCacheKey,
        'fine': fineList,
        'coarse': coarseList,
      };
      final file = await _prototypeCacheFile();
      await file.writeAsString(jsonEncode(json), flush: true);
      debugPrint(
        '✅ 已缓存标签原型向量 fine=${fineList.length} coarse=${coarseList.length}',
      );
    } catch (e) {
      debugPrint('⚠️ 标签原型缓存写入失败: $e');
    }
  }

  Future<File> _prototypeCacheFile() async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/$_prototypeCacheFilename');
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

  Future<List<double>> _buildPrototype(Iterable<String> prompts) async {
    final vectors = await _embedPromptsSequentially(
      prompts.where((prompt) => prompt.trim().isNotEmpty),
    );
    if (vectors.isEmpty) return const <double>[];
    final dim = vectors.first.length;
    if (dim == 0) return const <double>[];
    final sum = List<double>.filled(dim, 0);
    var count = 0;
    for (final vector in vectors) {
      if (vector.length != dim) continue;
      for (var i = 0; i < dim; i++) {
        sum[i] += vector[i];
      }
      count++;
    }
    if (count == 0) return const <double>[];
    for (var i = 0; i < dim; i++) {
      sum[i] /= count;
    }
    return _l2Normalize(sum);
  }

  List<double> _l2Normalize(List<double> vector) {
    var norm = 0.0;
    for (final value in vector) {
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm <= 0 || norm.isNaN || norm.isInfinite) {
      return const <double>[];
    }
    return vector.map((value) => value / norm).toList(growable: false);
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
    _touchUsage();
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
      final score = _semanticService.calculateSimilarity(
        imageEmbedding,
        prototype,
      );
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
    return selectCoarseCandidatesForTesting(limited);
  }

  Future<List<MobileClipTagDiagnostic>> retrieveTagDiagnostics(
    List<double> imageEmbedding, {
    int topK = _defaultTopK,
    int coarseTopK = _defaultCoarseTopK,
  }) async {
    _touchUsage();
    if (imageEmbedding.isEmpty) {
      return const <MobileClipTagDiagnostic>[];
    }

    await warmUp();

    final rankedCandidates = _rankFineCandidates(imageEmbedding);
    final selected = _selectFineCandidates(rankedCandidates, topK: topK);
    if (selected.isEmpty) {
      return _otherFallbackDiagnostics();
    }

    return _attachFineProbabilities(selected);
  }

  List<_TagScoreCandidate> _rankFineCandidates(List<double> imageEmbedding) {
    final scored = <_TagScoreCandidate>[];
    for (final definition in memoriaMasterTagDefinitions) {
      final label = definition.label.trim();
      if (label.isEmpty || _isBlockedLabel(label)) {
        continue;
      }
      final prototype = _prototypeByLabel[label];
      if (prototype == null ||
          prototype.isEmpty ||
          prototype.length != imageEmbedding.length) {
        continue;
      }
      final score = _semanticService.calculateSimilarity(
        imageEmbedding,
        prototype,
      );
      final candidate = _TagScoreCandidate(
        definition: definition,
        score: score,
        weightedScore: score,
      );
      scored.add(candidate);
    }
    scored.sort((a, b) => b.weightedScore.compareTo(a.weightedScore));
    return scored;
  }

  List<_TagScoreCandidate> _selectFineCandidates(
    List<_TagScoreCandidate> rankedCandidates, {
    required int topK,
  }) {
    if (rankedCandidates.isEmpty || topK <= 0) {
      return const <_TagScoreCandidate>[];
    }
    final topScore = rankedCandidates.first.score;
    if (!topScore.isFinite || topScore < _fineScoreFloor) {
      return const <_TagScoreCandidate>[];
    }
    final displayThreshold = math.max(
      _fineScoreFloor,
      topScore - _fineDisplayScoreGap,
    );

    final selected = <_TagScoreCandidate>[];
    final selectedLabels = <String>{};
    final dynamicTopK = _resolveDynamicFineTopK(
      rankedCandidates
          .map((candidate) => candidate.weightedScore)
          .toList(growable: false),
      maxTopK: topK,
      minTopK: 1,
    );

    void tryAdd(_TagScoreCandidate candidate) {
      if (selected.length >= dynamicTopK ||
          candidate.score < displayThreshold) {
        return;
      }
      final label = candidate.definition.label;
      if (selectedLabels.contains(label)) {
        return;
      }
      selected.add(candidate);
      selectedLabels.add(label);
    }

    for (final candidate in rankedCandidates) {
      tryAdd(candidate);
      if (selected.length >= dynamicTopK) {
        break;
      }
    }
    return selected;
  }

  bool _isBlockedLabel(String label) {
    if (_blockedTags.contains(label)) {
      return true;
    }
    return TagSanitizer.isBlockedExactTag(label);
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
    return List<MobileClipTagDiagnostic>.generate(selected.length, (index) {
      final entry = selected[index];
      return MobileClipTagDiagnostic(
        tag: entry.definition.label,
        score: entry.score,
        probability: probabilities[index],
        category: _coarseLabelForFineTag(entry.definition.label),
        coarseId: memoriaFineLabelToCoarseId[entry.definition.label] ?? '',
      );
    }, growable: false);
  }

  List<MobileClipCoarseDiagnostic> _filterConfidentCoarseCandidates(
    List<MobileClipCoarseDiagnostic> ranked,
  ) {
    if (ranked.isEmpty) {
      return const <MobileClipCoarseDiagnostic>[];
    }
    final bestScore = ranked.first.score;
    return ranked
        .where((candidate) {
          final closeToBest =
              (bestScore - candidate.score) <= _coarseScoreMargin;
          return candidate.score >= _coarseScoreThreshold &&
              (candidate.probability >= _coarseProbabilityThreshold ||
                  closeToBest);
        })
        .toList(growable: false);
  }

  @visibleForTesting
  List<MobileClipCoarseDiagnostic> selectCoarseCandidatesForTesting(
    List<MobileClipCoarseDiagnostic> ranked,
  ) {
    final confident = _filterConfidentCoarseCandidates(ranked);
    if (confident.isNotEmpty) {
      return confident;
    }
    return _fallbackCoarseCandidates(ranked);
  }

  List<MobileClipCoarseDiagnostic> _fallbackCoarseCandidates(
    List<MobileClipCoarseDiagnostic> ranked,
  ) {
    if (ranked.isEmpty) {
      return const <MobileClipCoarseDiagnostic>[];
    }
    final bestScore = ranked.first.score;
    if (!bestScore.isFinite || bestScore < _coarseFallbackScoreFloor) {
      return const <MobileClipCoarseDiagnostic>[];
    }
    return <MobileClipCoarseDiagnostic>[ranked.first];
  }

  @visibleForTesting
  List<MobileClipTagDiagnostic> selectFineTagsForTesting(
    Map<String, double> scoreByLabel, {
    int topK = _defaultTopK,
  }) {
    final scored = <_TagScoreCandidate>[];
    for (final definition in memoriaMasterTagDefinitions) {
      final label = definition.label.trim();
      final score = scoreByLabel[label];
      if (score == null || label.isEmpty || _isBlockedLabel(label)) {
        continue;
      }
      scored.add(
        _TagScoreCandidate(
          definition: definition,
          score: score,
          weightedScore: score,
        ),
      );
    }
    scored.sort((a, b) => b.weightedScore.compareTo(a.weightedScore));
    final selected = _selectFineCandidates(scored, topK: topK);
    if (selected.isEmpty) {
      return _otherFallbackDiagnostics();
    }
    return _attachFineProbabilities(selected);
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
    final probabilities = _softmaxProbabilities(
      rankedScores.take(limit).toList(),
    );
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
          current >= 0.075 || gap <= 0.1 || (current / first) >= 0.33;
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
