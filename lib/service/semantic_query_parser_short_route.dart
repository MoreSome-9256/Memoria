/// 语义查询短路路径，用于快速命中简单意图的解析结果。

part of 'semantic_query_parser_service.dart';

extension _SemanticQueryParserShortRoute on SemanticQueryParserService {
  Future<SemanticSearchQuery?> _buildShortSemanticQueryIfNeeded(
    String rawQuery,
  ) async {
    if (!_isShortChineseQuery(rawQuery) || _containsStructuredCue(rawQuery)) {
      return null;
    }

    final seed = _resolveShortQuerySeed(rawQuery);
    if (seed == null) {
      return null;
    }

    final similarity = await _measureShortQueryCoarseSimilarity(rawQuery, seed);
    if (similarity < _shortRouteCoarseSimilarityThreshold) {
      return null;
    }

    final positive = _normalizeSemanticWeights(
      seed.shortPrompts
          .map(
            (prompt) => SemanticSearchSemanticItem(
              text: prompt,
              weight: 1 / seed.shortPrompts.length,
            ),
          )
          .toList(growable: false),
    );

    return SemanticSearchQuery(
      rawQuery: rawQuery,
      routeType: SemanticSearchRouteType.shortSemantic,
      queryType: _inferQueryType(rawQuery),
      timeRanges: const <SemanticSearchTimeRange>[],
      locations: const <SemanticSearchLocation>[],
      coarseTags: <SemanticSearchCoarseTag>[
        SemanticSearchCoarseTag(
          id: seed.id,
          labelZh: seed.labelZh,
          labelEn: seed.labelEn,
          confidence: similarity,
        ),
      ],
      tagStrictness: SemanticSearchTagStrictness.prefer,
      positiveSemantics: positive,
      recallSemantics:
          _buildRecallSemantics(rawQuery, <SemanticSearchCoarseTag>[
            SemanticSearchCoarseTag(
              id: seed.id,
              labelZh: seed.labelZh,
              labelEn: seed.labelEn,
              confidence: similarity,
            ),
          ]),
      negativeSemantics: _buildNegativeSemantics(rawQuery),
      estimatedResultCount: _estimateResultCount(
        rawQuery,
        _inferQueryType(rawQuery),
      ),
      usedLlm: false,
      llmConfigured: _llmService.isApiKeyConfigured,
      parserSource: 'short_semantic',
      debugJson: _prettyJson.convert(<String, dynamic>{
        'route': 'short_semantic',
        'query_type': _inferQueryType(rawQuery).name,
        'raw_query': rawQuery,
        'coarse_similarity': similarity,
        'coarse_tag': seed.toJson(),
        'positive_semantics': positive.map((e) => e.toJson()).toList(),
      }),
      notes: _noteShortRoute,
    );
  }

  bool _isShortChineseQuery(String rawQuery) {
    final trimmed = rawQuery.trim();
    return trimmed.isNotEmpty &&
        RegExp(r'^[\u4e00-\u9fff]{1,4}$').hasMatch(trimmed);
  }

  bool _containsStructuredCue(String rawQuery) {
    const cues = <String>[
      '\u53bb\u5e74',
      '\u4eca\u5e74',
      '\u524d\u5e74',
      '\u660e\u5e74',
      '\u4e0a\u6708',
      '\u8fd9\u4e2a\u6708',
      '\u672c\u6708',
      '\u6628\u5929',
      '\u4eca\u5929',
      '\u660e\u5929',
      '\u4e0d\u8981',
      '\u9664\u4e86',
      '\u4e0a\u6d77',
      '\u5317\u4eac',
      '\u5e7f\u5dde',
      '\u6df1\u5733',
      '\u676d\u5dde',
      '\u6210\u90fd',
      '\u91cd\u5e86',
      '\u5357\u4eac',
      '\u897f\u5b89',
      '\u9999\u6e2f',
      '\u6fb3\u95e8',
    ];
    return cues.any(rawQuery.contains);
  }

  _CoarseSeed? _resolveShortQuerySeed(String rawQuery) {
    _CoarseSeed? bestSeed;
    var bestScore = 0.0;
    for (final seed in _coarseSeeds) {
      final score = _aliasSimilarity(rawQuery, seed.aliases);
      if (score > bestScore) {
        bestScore = score;
        bestSeed = seed;
      }
    }
    return bestScore > 0 ? bestSeed : null;
  }

  Future<double> _measureShortQueryCoarseSimilarity(
    String rawQuery,
    _CoarseSeed seed,
  ) async {
    final lexicalScore = _aliasSimilarity(rawQuery, seed.aliases);
    if (lexicalScore >= 0.95) {
      return lexicalScore;
    }
    try {
      await _semanticService.warmUp();
      final queryVector = await _semanticService.embedText(
        _buildShortQueryProbeText(rawQuery),
      );
      final coarseVector = await _semanticService.embedText(
        seed.prototypePrompt,
      );
      final semanticScore = _semanticService
          .calculateSimilarity(queryVector, coarseVector)
          .clamp(0.0, 1.0);
      return semanticScore > lexicalScore ? semanticScore : lexicalScore;
    } catch (_) {
      return lexicalScore;
    }
  }

  double _aliasSimilarity(String rawQuery, List<String> aliases) {
    final normalized = rawQuery.trim();
    var best = 0.0;
    for (final alias in aliases) {
      final cleanAlias = alias.trim();
      if (normalized == cleanAlias) {
        return 1.0;
      }
      if (cleanAlias.length >= 2 &&
          (normalized.contains(cleanAlias) ||
              cleanAlias.contains(normalized))) {
        best = best < 0.72 ? 0.72 : best;
      }
      final overlap = normalized.runes
          .where((code) => cleanAlias.contains(String.fromCharCode(code)))
          .length;
      if (overlap < 2) {
        continue;
      }
      final score = overlap / cleanAlias.length;
      if (score >= 0.67 && score > best) {
        best = score;
      }
    }
    return best.clamp(0.0, 1.0);
  }

  String _buildShortQueryProbeText(String rawQuery) {
    final text = rawQuery.trim();
    if (text.isEmpty) {
      return 'a photo related to the query';
    }
    if (_looksLikeAttributeQuery(text)) {
      final templates = _attributeSemanticTemplates(text);
      if (templates.isNotEmpty) {
        return templates.first.text;
      }
    }
    return 'a photo related to $text';
  }
}
