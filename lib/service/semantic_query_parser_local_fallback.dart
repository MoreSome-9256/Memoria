/// 语义查询解析的本地回退实现，在离线或失败时提供保底解析。

part of 'semantic_query_parser_service.dart';

extension _SemanticQueryParserLocalFallback on SemanticQueryParserService {
  SemanticSearchQuery _buildLocalFallbackQuery(
    String rawQuery,
    Set<String> locationDictionary,
  ) {
    final timeRanges = _extractTimeRanges(rawQuery);
    final locations = _extractLocations(rawQuery, locationDictionary);
    final isMetadataOnly = _looksLikeMetadataOnlyQuery(
      rawQuery,
      timeRanges,
      locations,
    );
    final coarseTags = isMetadataOnly
        ? const <SemanticSearchCoarseTag>[]
        : _extractCoarseTags(rawQuery);
    final positiveSemantics = isMetadataOnly
        ? const <SemanticSearchSemanticItem>[]
        : _buildPositiveSemantics(rawQuery, coarseTags);
    final recallSemantics = isMetadataOnly
        ? const <SemanticSearchSemanticItem>[]
        : _buildRecallSemantics(rawQuery, coarseTags);
    final negativeSemantics = isMetadataOnly
        ? const <SemanticSearchSemanticItem>[]
        : _buildNegativeSemantics(rawQuery);
    final queryType = isMetadataOnly
        ? SemanticSearchQueryType.metadata
        : _inferQueryType(rawQuery);

    return SemanticSearchQuery(
      rawQuery: rawQuery,
      routeType: SemanticSearchRouteType.localFallback,
      queryType: queryType,
      timeRanges: timeRanges,
      locations: locations,
      coarseTags: coarseTags,
      tagStrictness: _defaultTagStrictnessFor(queryType),
      positiveSemantics: positiveSemantics,
      recallSemantics: recallSemantics,
      negativeSemantics: negativeSemantics,
      estimatedResultCount: _estimateResultCount(rawQuery, queryType),
      usedLlm: false,
      llmConfigured: _llmService.isApiKeyConfigured,
      parserSource: 'local',
      debugJson: _prettyJson.convert(<String, dynamic>{
        'route': 'local_fallback',
        'raw_query': rawQuery,
        'query_type': queryType.name,
        'metadata_only': isMetadataOnly,
        'time_ranges': timeRanges.map((e) => e.toJson()).toList(),
        'locations': locations.map((e) => e.toJson()).toList(),
        'coarse_tags': coarseTags.map((e) => e.toJson()).toList(),
        'positive_semantics': positiveSemantics.map((e) => e.toJson()).toList(),
        'recall_semantics': recallSemantics.map((e) => e.toJson()).toList(),
        'negative_semantics': negativeSemantics.map((e) => e.toJson()).toList(),
      }),
      notes: _noteLocal,
    );
  }

  SemanticSearchQueryType _inferQueryType(String rawQuery) {
    if (_looksLikeAttributeQuery(rawQuery)) {
      return SemanticSearchQueryType.attribute;
    }
    if (_looksLikeAbstractQuery(rawQuery)) {
      return SemanticSearchQueryType.abstract;
    }
    if (_looksLikeCollectionQuery(rawQuery)) {
      return SemanticSearchQueryType.collection;
    }
    return SemanticSearchQueryType.concrete;
  }

  bool _looksLikeAttributeQuery(String rawQuery) {
    const colors = <String>[
      '\u7ea2',
      '\u7ea2\u8272',
      '\u7eff',
      '\u7eff\u8272',
      '\u84dd',
      '\u84dd\u8272',
      '\u767d',
      '\u767d\u8272',
      '\u9ed1',
      '\u9ed1\u8272',
      '\u9ec4',
      '\u9ec4\u8272',
      '\u7c89',
      '\u7c89\u8272',
    ];
    const apparel = <String>[
      '\u4e0a\u8863',
      '\u88d9\u5b50',
      '\u88e4\u5b50',
      '\u5916\u5957',
      '\u8863\u670d',
      '\u5e3d\u5b50',
      '\u886c\u886b',
      '\u77ed\u8896',
      '\u957f\u88d9',
    ];
    return colors.any(rawQuery.contains) && apparel.any(rawQuery.contains);
  }

  bool _looksLikeAbstractQuery(String rawQuery) {
    const abstractWords = <String>[
      '\u6c14\u606f',
      '\u611f\u89c9',
      '\u6c1b\u56f4',
      '\u65f6\u5149',
      '\u56de\u5fc6',
      '\u5feb\u4e50',
      '\u5f00\u5fc3',
      '\u5e78\u798f',
      '\u6d6a\u6f2b',
      '\u6e29\u99a8',
      '\u6cbb\u6108',
      '\u6625\u5929',
      '\u590f\u5929',
      '\u79cb\u5929',
      '\u51ac\u5929',
    ];
    return abstractWords.any(rawQuery.contains);
  }

  bool _looksLikeCollectionQuery(String rawQuery) {
    const collectionWords = <String>[
      '\u65c5\u6e38',
      '\u65c5\u884c',
      '\u6821\u56ed',
      '\u751f\u6d3b',
      '\u65e5\u5e38',
      '\u56de\u5fc6',
      '\u8bb0\u5f55',
      '\u76f8\u518c',
      '\u96c6\u5408',
      '\u4e00\u7ec4',
    ];
    return collectionWords.any(rawQuery.contains);
  }

  SemanticSearchTagStrictness _defaultTagStrictnessFor(
    SemanticSearchQueryType queryType,
  ) {
    switch (queryType) {
      case SemanticSearchQueryType.metadata:
      case SemanticSearchQueryType.attribute:
        return SemanticSearchTagStrictness.optional;
      case SemanticSearchQueryType.abstract:
      case SemanticSearchQueryType.collection:
        return SemanticSearchTagStrictness.prefer;
      case SemanticSearchQueryType.concrete:
        return SemanticSearchTagStrictness.prefer;
    }
  }

  bool _isMetadataOnlyQuery(String rawQuery, SemanticSearchQuery query) {
    if (query.hasCoarseTags ||
        query.hasPositiveSemantics ||
        query.hasNegativeSemantics) {
      return false;
    }
    return _looksLikeMetadataOnlyQuery(
      rawQuery,
      query.timeRanges,
      query.locations,
    );
  }

  bool _looksLikeMetadataOnlyQuery(
    String rawQuery,
    List<SemanticSearchTimeRange> timeRanges,
    List<SemanticSearchLocation> locations,
  ) {
    if (timeRanges.isEmpty && locations.isEmpty) {
      return false;
    }

    var normalized = rawQuery.trim();
    final genericTokens = <String>[
      '\u56fe\u7247',
      '\u7167\u7247',
      '\u76f8\u7247',
      '\u76f8\u518c',
      '\u62cd\u7684',
      '\u5728',
      '\u91cc',
      '\u91cc\u7684',
      '\u7684',
      '\u67e5\u627e',
      '\u641c\u7d22',
      '\u6240\u6709',
      '\u5168\u90e8',
      '\u90a3\u4e9b',
      '\u8fd9\u4e9b',
    ];
    for (final token in genericTokens) {
      normalized = normalized.replaceAll(token, '');
    }
    normalized = normalized.replaceAll(RegExp(r'\d{4}年?'), '');
    normalized = normalized.replaceAll(RegExp(r'\d{1,2}月'), '');
    normalized = normalized.replaceAll(RegExp(r'\d{1,2}日'), '');
    normalized = normalized.replaceAll(
      RegExp(r'(今年|去年|前年|明年|本月|这个月|上月|今天|昨天|前天|最近|今年的|去年的)'),
      '',
    );
    for (final location in locations) {
      final text = location.text.trim();
      if (text.isEmpty) {
        continue;
      }
      normalized = normalized.replaceAll(text, '');
      final stripped = _stripLocationSuffixAscii(text);
      if (stripped.isNotEmpty) {
        normalized = normalized.replaceAll(stripped, '');
      }
    }
    normalized = normalized.replaceAll(RegExp(r'\s+'), '');
    return normalized.isEmpty;
  }

  List<SemanticSearchTimeRange> _extractTimeRanges(String rawQuery) {
    final now = DateTime.now();
    final ranges = <SemanticSearchTimeRange>[];

    if (rawQuery.contains('\u53bb\u5e74')) {
      ranges.add(_yearRange(now.year - 1, '\u53bb\u5e74'));
    }
    if (rawQuery.contains('\u4eca\u5e74')) {
      ranges.add(_yearRange(now.year, '\u4eca\u5e74'));
    }
    if (rawQuery.contains('\u524d\u5e74')) {
      ranges.add(_yearRange(now.year - 2, '\u524d\u5e74'));
    }
    if (rawQuery.contains('\u672c\u6708') ||
        rawQuery.contains('\u8fd9\u4e2a\u6708')) {
      ranges.add(_monthRange(now.year, now.month, '\u672c\u6708'));
    }
    if (rawQuery.contains('\u4e0a\u6708')) {
      final prev = DateTime(now.year, now.month - 1, 1);
      ranges.add(_monthRange(prev.year, prev.month, '\u4e0a\u6708'));
    }
    if (rawQuery.contains('\u4eca\u5929')) {
      ranges.add(_dayRange(now, '\u4eca\u5929'));
    }
    if (rawQuery.contains('\u6628\u5929')) {
      ranges.add(
        _dayRange(now.subtract(const Duration(days: 1)), '\u6628\u5929'),
      );
    }

    final yearMatches = RegExp(r'((?:20)?\d{2})\u5e74').allMatches(rawQuery);
    for (final match in yearMatches) {
      final value = _toInt(match.group(1));
      if (value == null) {
        continue;
      }
      final year = value < 100 ? 2000 + value : value;
      final monthMatch = RegExp(
        '${match.group(0)}(\\d{1,2})\\u6708',
      ).firstMatch(rawQuery);
      if (monthMatch != null) {
        final month = _toInt(monthMatch.group(1));
        if (month != null && month >= 1 && month <= 12) {
          ranges.add(_monthRange(year, month, '$year\u5e74$month\u6708'));
          continue;
        }
      }
      ranges.add(_yearRange(year, '$year\u5e74'));
    }

    if (ranges.isEmpty) {
      final monthMatches = RegExp(r'(\d{1,2})\u6708').allMatches(rawQuery);
      for (final match in monthMatches) {
        final month = _toInt(match.group(1));
        if (month == null || month < 1 || month > 12) {
          continue;
        }
        ranges.add(
          _monthRange(now.year, month, '${now.year}\u5e74$month\u6708'),
        );
      }
    }

    final unique = <String, SemanticSearchTimeRange>{};
    for (final item in ranges) {
      unique['${item.startTimeMs}-${item.endTimeMs}-${item.reason}'] = item;
    }
    return unique.values.toList(growable: false);
  }

  List<SemanticSearchLocation> _extractLocations(
    String rawQuery,
    Set<String> locationDictionary,
  ) {
    final results = <SemanticSearchLocation>[];
    final sortedDictionary = locationDictionary.toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final location in sortedDictionary) {
      final text = location.trim();
      if (text.length < 2) {
        continue;
      }
      final stripped = _stripLocationSuffixAscii(text);
      if (rawQuery.contains(text) ||
          (stripped.length >= 2 && rawQuery.contains(stripped))) {
        results.add(
          SemanticSearchLocation(text: text, type: _guessLocationType(text)),
        );
      }
    }

    const manualCandidates = <String>[
      '\u4e0a\u6d77',
      '\u5317\u4eac',
      '\u5e7f\u5dde',
      '\u6df1\u5733',
      '\u676d\u5dde',
      '\u5357\u4eac',
      '\u6210\u90fd',
      '\u91cd\u5e86',
      '\u897f\u5b89',
      '\u82cf\u5dde',
      '\u6b66\u6c49',
      '\u5929\u6d25',
      '\u957f\u6c99',
      '\u9999\u6e2f',
      '\u6fb3\u95e8',
    ];
    for (final candidate in manualCandidates) {
      if (rawQuery.contains(candidate) &&
          !results.any((item) => item.text.contains(candidate))) {
        results.add(
          SemanticSearchLocation(
            text: candidate,
            type: _guessLocationType(candidate),
          ),
        );
      }
    }

    final unique = <String, SemanticSearchLocation>{};
    for (final item in results) {
      unique[item.text] = item;
    }
    return unique.values.toList(growable: false);
  }

  List<SemanticSearchCoarseTag> _extractCoarseTags(String rawQuery) {
    final results = <SemanticSearchCoarseTag>[];
    for (final seed in _coarseSeeds) {
      final score = _aliasSimilarity(rawQuery, seed.aliases);
      if (score >= 0.34) {
        results.add(
          SemanticSearchCoarseTag(
            id: seed.id,
            labelZh: seed.labelZh,
            labelEn: seed.labelEn,
            confidence: score.clamp(0.35, 0.98),
          ),
        );
      }
    }
    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    return results.take(6).toList(growable: false);
  }

  List<SemanticSearchSemanticItem> _buildPositiveSemantics(
    String rawQuery,
    List<SemanticSearchCoarseTag> coarseTags,
  ) {
    final items = <SemanticSearchSemanticItem>[];

    if (coarseTags.isNotEmpty) {
      for (final coarseTag in coarseTags.take(4)) {
        final seed = _coarseIdToSeed[coarseTag.id];
        if (seed == null) {
          continue;
        }
        items.add(
          SemanticSearchSemanticItem(
            text: seed.shortPrompts.first,
            weight: coarseTag.id == coarseTags.first.id ? 0.58 : 0.42,
          ),
        );
      }
    }

    if (rawQuery.contains('\u6625\u8282') ||
        rawQuery.contains('\u8fc7\u5e74')) {
      items.add(
        const SemanticSearchSemanticItem(
          text: 'a photo of chinese new year reunion celebration',
          weight: 0.9,
        ),
      );
    }
    if (rawQuery.contains('\u56e2\u805a') ||
        rawQuery.contains('\u5bb6\u4eba') ||
        rawQuery.contains('\u5bb6\u5ead')) {
      items.add(
        const SemanticSearchSemanticItem(
          text: 'a photo of family reunion together',
          weight: 0.9,
        ),
      );
    }
    if (rawQuery.contains('\u805a\u9910') ||
        rawQuery.contains('\u5403') ||
        rawQuery.contains('\u997a\u5b50')) {
      items.add(
        const SemanticSearchSemanticItem(
          text: 'a photo of people eating together at a dining table',
          weight: 0.9,
        ),
      );
    }
    if (rawQuery.contains('\u65c5\u6e38') ||
        rawQuery.contains('\u65c5\u884c')) {
      items.add(
        const SemanticSearchSemanticItem(
          text: 'a travel photo during a trip',
          weight: 0.8,
        ),
      );
    }
    if (rawQuery.contains('\u6d77\u8fb9')) {
      items.add(
        const SemanticSearchSemanticItem(
          text: 'a photo by the beach or seaside',
          weight: 0.85,
        ),
      );
    }
    if (rawQuery.contains('\u591c\u666f')) {
      items.add(
        const SemanticSearchSemanticItem(
          text: 'a photo of city lights at night',
          weight: 0.8,
        ),
      );
    }
    if (rawQuery.contains('\u82b1') ||
        rawQuery.contains('\u9c9c\u82b1') ||
        rawQuery.contains('\u690d\u7269')) {
      items.add(
        const SemanticSearchSemanticItem(
          text: 'a photo of flowers blossoms or plants',
          weight: 0.88,
        ),
      );
    }

    if (items.isEmpty) {
      final seed = _resolveShortQuerySeed(rawQuery);
      if (seed != null) {
        items.addAll(
          seed.shortPrompts.map(
            (prompt) => SemanticSearchSemanticItem(
              text: prompt,
              weight: 1 / seed.shortPrompts.length,
            ),
          ),
        );
      } else {
        items.add(
          const SemanticSearchSemanticItem(
            text: 'a photo related to the user query',
            weight: 1.0,
          ),
        );
      }
    }

    return _normalizeSemanticWeights(items);
  }

  List<SemanticSearchSemanticItem> _buildRecallSemantics(
    String rawQuery,
    List<SemanticSearchCoarseTag> coarseTags,
  ) {
    final items = <SemanticSearchSemanticItem>[
      ..._buildPositiveSemantics(rawQuery, coarseTags),
    ];

    if (rawQuery.contains('\u65c5\u6e38') ||
        rawQuery.contains('\u65c5\u884c')) {
      items.addAll(const <SemanticSearchSemanticItem>[
        SemanticSearchSemanticItem(
          text: 'a travel portrait during a trip',
          weight: 0.24,
        ),
        SemanticSearchSemanticItem(
          text: 'a scenic photo taken during travel',
          weight: 0.22,
        ),
        SemanticSearchSemanticItem(text: 'a travel food photo', weight: 0.18),
        SemanticSearchSemanticItem(
          text: 'a city street scene during travel',
          weight: 0.18,
        ),
      ]);
    }

    if (rawQuery.contains('\u7b11') ||
        rawQuery.contains('\u5fae\u7b11') ||
        rawQuery.contains('\u5f00\u5fc3')) {
      items.addAll(const <SemanticSearchSemanticItem>[
        SemanticSearchSemanticItem(
          text: 'a happy person smiling',
          weight: 0.28,
        ),
        SemanticSearchSemanticItem(
          text: 'a cheerful group photo',
          weight: 0.24,
        ),
        SemanticSearchSemanticItem(
          text: 'a happy travel portrait',
          weight: 0.18,
        ),
      ]);
    }

    if (rawQuery.contains('\u6625\u5929') ||
        rawQuery.contains('\u6c14\u606f')) {
      items.addAll(const <SemanticSearchSemanticItem>[
        SemanticSearchSemanticItem(
          text: 'a park scene in spring',
          weight: 0.22,
        ),
        SemanticSearchSemanticItem(
          text: 'a person among flowers in spring',
          weight: 0.24,
        ),
        SemanticSearchSemanticItem(
          text: 'a bright outdoor spring day',
          weight: 0.20,
        ),
      ]);
    }

    if (_looksLikeAttributeQuery(rawQuery)) {
      final template = _attributeSemanticTemplates(rawQuery);
      items.addAll(template);
    }

    return _normalizeSemanticWeights(items);
  }

  List<SemanticSearchSemanticItem> _attributeSemanticTemplates(
    String rawQuery,
  ) {
    final items = <SemanticSearchSemanticItem>[];
    final color = _extractColorWord(rawQuery);
    final garment = _extractGarmentWord(rawQuery);
    if (color != null && garment != null) {
      items.add(
        SemanticSearchSemanticItem(
          text: 'a person wearing a $color $garment',
          weight: 0.45,
        ),
      );
      items.add(
        SemanticSearchSemanticItem(
          text: 'a portrait with $color clothing',
          weight: 0.30,
        ),
      );
      items.add(
        SemanticSearchSemanticItem(
          text: 'upper body clothing in $color',
          weight: 0.25,
        ),
      );
    }
    return items;
  }

  String? _extractColorWord(String rawQuery) {
    const mapping = <String, String>{
      '\u7ea2\u8272': 'red',
      '\u7ea2': 'red',
      '\u7eff\u8272': 'green',
      '\u7eff': 'green',
      '\u84dd\u8272': 'blue',
      '\u84dd': 'blue',
      '\u767d\u8272': 'white',
      '\u767d': 'white',
      '\u9ed1\u8272': 'black',
      '\u9ed1': 'black',
      '\u9ec4\u8272': 'yellow',
      '\u9ec4': 'yellow',
      '\u7c89\u8272': 'pink',
      '\u7c89': 'pink',
    };
    for (final entry in mapping.entries) {
      if (rawQuery.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  String? _extractGarmentWord(String rawQuery) {
    const mapping = <String, String>{
      '\u4e0a\u8863': 'top',
      '\u8863\u670d': 'clothes',
      '\u886c\u886b': 'shirt',
      '\u88d9\u5b50': 'dress',
      '\u88e4\u5b50': 'pants',
      '\u5916\u5957': 'jacket',
      '\u5e3d\u5b50': 'hat',
      '\u77ed\u8896': 't-shirt',
    };
    for (final entry in mapping.entries) {
      if (rawQuery.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  List<SemanticSearchSemanticItem> _buildNegativeSemantics(String rawQuery) {
    if (_wantsScreenContent(rawQuery)) {
      return const <SemanticSearchSemanticItem>[];
    }
    final items = <SemanticSearchSemanticItem>[..._defaultNegativeSemantics];
    if (rawQuery.contains('\u4e0d\u8981\u5355\u4eba') ||
        rawQuery.contains('\u4e0d\u8981\u4e00\u4e2a\u4eba')) {
      items.add(
        const SemanticSearchSemanticItem(
          text: 'a photo of a single person alone',
          weight: 0.35,
        ),
      );
    }
    if (rawQuery.contains('\u4e0d\u8981\u6a21\u7cca')) {
      items.add(
        const SemanticSearchSemanticItem(
          text: 'a blurry out of focus photo',
          weight: 0.35,
        ),
      );
    }
    return _normalizeSemanticWeights(items);
  }

  SemanticSearchEstimatedResultCount _estimateResultCount(
    String rawQuery,
    SemanticSearchQueryType queryType,
  ) {
    if (queryType == SemanticSearchQueryType.metadata) {
      return const SemanticSearchEstimatedResultCount(
        min: 10,
        max: 500,
        confidence: 0.55,
      );
    }
    if (queryType == SemanticSearchQueryType.attribute) {
      return const SemanticSearchEstimatedResultCount(
        min: 1,
        max: 20,
        confidence: 0.62,
      );
    }
    if (queryType == SemanticSearchQueryType.abstract) {
      return const SemanticSearchEstimatedResultCount(
        min: 12,
        max: 160,
        confidence: 0.58,
      );
    }
    if (queryType == SemanticSearchQueryType.collection ||
        rawQuery.contains('\u65c5\u6e38') ||
        rawQuery.contains('\u65c5\u884c')) {
      return const SemanticSearchEstimatedResultCount(
        min: 24,
        max: 240,
        confidence: 0.7,
      );
    }
    return const SemanticSearchEstimatedResultCount(
      min: 1,
      max: 40,
      confidence: 0.6,
    );
  }

  SemanticSearchTimeRange _yearRange(int year, String reason) {
    final start = DateTime(year, 1, 1);
    final end = DateTime(
      year + 1,
      1,
      1,
    ).subtract(const Duration(milliseconds: 1));
    return SemanticSearchTimeRange(
      startTimeMs: start.millisecondsSinceEpoch,
      endTimeMs: end.millisecondsSinceEpoch,
      reason: reason,
    );
  }

  SemanticSearchTimeRange _monthRange(int year, int month, String reason) {
    final start = DateTime(year, month, 1);
    final end = DateTime(
      year,
      month + 1,
      1,
    ).subtract(const Duration(milliseconds: 1));
    return SemanticSearchTimeRange(
      startTimeMs: start.millisecondsSinceEpoch,
      endTimeMs: end.millisecondsSinceEpoch,
      reason: reason,
    );
  }

  SemanticSearchTimeRange _dayRange(DateTime date, String reason) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return SemanticSearchTimeRange(
      startTimeMs: start.millisecondsSinceEpoch,
      endTimeMs: end.millisecondsSinceEpoch,
      reason: reason,
    );
  }

  String _stripLocationSuffix(String value) {
    return value.replaceAll(RegExp(r'(省|市|区|县|自治州|自治区|特别行政区)$'), '').trim();
  }

  String _stripLocationSuffixSafe(String value) {
    return value.replaceAll(RegExp(r'(省|市|区|县|自治州|自治区|特别行政区)$'), '').trim();
  }

  String _stripLocationSuffixAscii(String value) {
    return value
        .replaceAll(
          RegExp(
            '(\u7701|\u5e02|\u533a|\u53bf|\u81ea\u6cbb\u5dde|\u81ea\u6cbb\u533a|\u7279\u522b\u884c\u653f\u533a)\$',
          ),
          '',
        )
        .trim();
  }

  String _guessLocationType(String text) {
    if (text.endsWith('\u7701')) {
      return 'province';
    }
    if (text.endsWith('\u5e02')) {
      return 'city';
    }
    if (text.endsWith('\u533a') || text.endsWith('\u53bf')) {
      return 'district';
    }
    return 'city';
  }

  bool _wantsScreenContent(String rawQuery) {
    const screenWords = <String>[
      '\u622a\u56fe',
      '\u622a\u5c4f',
      '\u6587\u6863',
      '\u4ee3\u7801',
      '\u8bfe\u4ef6',
      '\u5c4f\u5e55',
      'IDE',
      '\u7ec8\u7aef',
      '\u804a\u5929\u8bb0\u5f55',
    ];
    return screenWords.any(rawQuery.contains);
  }
}
