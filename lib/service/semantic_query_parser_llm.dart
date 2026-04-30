part of 'semantic_query_parser_service.dart';

extension _SemanticQueryParserLlm on SemanticQueryParserService {
  Future<SemanticSearchQuery> _parseWithLlm(
    String rawQuery,
    Set<String> locationDictionary,
  ) async {
    final coarseCatalog = _coarseSeeds
        .map(
          (item) => <String, dynamic>{
            'id': item.id,
            'label_zh': item.labelZh,
            'label_en': item.labelEn,
          },
        )
        .toList(growable: false);

    final prompt =
        '''
\u8bf7\u628a\u7528\u6237\u7684\u76f8\u518c\u641c\u7d22\u8bed\u53e5\u89e3\u6790\u6210 JSON\u3002

\u4f60\u9700\u8981\u8f93\u51fa\u4ee5\u4e0b\u5b57\u6bb5\uff1a

{
  "query_type": "metadata | attribute | concrete | abstract | collection",
  "time_ranges": [
    {
      "start_time_ms": 0,
      "end_time_ms": 0,
      "reason": ""
    }
  ],
  "locations": [
    {
      "text": "",
      "type": "province | city | district"
    }
  ],
  "coarse_tags": [
    {
      "id": "",
      "label_zh": "",
      "label_en": "",
      "confidence": 0.0
    }
  ],
  "tag_strictness": "strict | prefer | optional",
  "positive_semantics": [
    {
      "text": "",
      "weight": 0.0
    }
  ],
  "recall_semantics": [
    {
      "text": "",
      "weight": 0.0
    }
  ],
  "negative_semantics": [
    {
      "text": "",
      "weight": 0.0
    }
  ],
  "estimated_result_count": {
    "min": 0,
    "max": 0,
    "confidence": 0.0
  },
  "notes": ""
}

\u5b57\u6bb5\u8981\u6c42\uff1a

1. query_type \u5fc5\u987b\u89e3\u91ca\u67e5\u8be2\u672c\u8d28\uff1a
   - metadata\uff1a\u7eaf\u65f6\u95f4/\u5730\u70b9\u8fc7\u6ee4
   - attribute\uff1a\u989c\u8272\u3001\u7a7f\u7740\u3001\u5c40\u90e8\u89c6\u89c9\u5c5e\u6027
   - concrete\uff1a\u5177\u4f53\u4e3b\u4f53\u6216\u5177\u4f53\u573a\u666f
   - abstract\uff1a\u62bd\u8c61\u60c5\u7eea\u3001\u6c1b\u56f4\u3001\u5b63\u8282\u611f
   - collection\uff1a\u96c6\u5408\u578b\u4e3b\u9898\uff0c\u8868\u793a\u7528\u6237\u60f3\u627e\u7684\u662f\u4e00\u6574\u7c7b\u7167\u7247\u96c6\u5408\uff0c\u800c\u4e0d\u662f\u5355\u4e00\u5bf9\u8c61\u6216\u5355\u4e00\u573a\u666f\uff1b\u4f8b\u5982\u201c\u65c5\u6e38\u7167\u7247\u201d\u201c\u6821\u56ed\u751f\u6d3b\u201d\u201c\u5bb6\u5ead\u805a\u4f1a\u7167\u7247\u201d\uff0c\u8fd9\u7c7b\u67e5\u8be2\u901a\u5e38\u8986\u76d6\u4eba\u7269\u3001\u8857\u666f\u3001\u5730\u6807\u3001\u7f8e\u98df\u3001\u81ea\u7136\u98ce\u666f\u7b49\u591a\u4e2a\u5b50\u573a\u666f\uff0c\u4e0d\u80fd\u89e3\u6790\u5f97\u8fc7\u7a84

2. time_ranges\uff1a
   - \u7528\u4e8e\u65f6\u95f4\u8fc7\u6ee4
   - \u53ef\u4ee5\u6709\u591a\u4e2a\u65f6\u95f4\u6bb5
   - \u65e0\u6cd5\u786e\u5b9a\u65f6\u53ef\u4ee5\u4e3a null

3. locations\uff1a
   - \u53ea\u4fdd\u7559\u771f\u5b9e\u5730\u7406\u4f4d\u7f6e\u540d\u79f0
   - \u4f8b\u5982\uff1a\u4e0a\u6d77\u3001\u676d\u5dde\u3001\u897f\u6e56\u533a
   - \u4e0d\u8981\u8f93\u51fa\u5750\u6807
   - \u4e0d\u8981\u628a\u6d77\u8fb9\u3001\u8349\u5730\u3001\u591c\u666f\u3001\u82b1\u6d77\u3001\u516c\u56ed\u653e\u8fdb locations
   - \u8fd9\u4e9b\u5730\u70b9\u6587\u672c\u540e\u7eed\u4f1a\u7528\u4e8e\u5339\u914d\u7167\u7247\u5df2\u9006\u5730\u7406\u7f16\u7801\u7684 city/province/district/locationName/formattedAddress \u5b57\u6bb5

4. coarse_tags\uff1a
   - \u53ea\u80fd\u4ece\u7ed9\u5b9a\u7c97\u6807\u7b7e\u5217\u8868\u4e2d\u9009\u62e9
   - \u53ef\u4ee5\u591a\u4e2a
   - \u4e0d\u80fd\u81ea\u9020\u65b0\u6807\u7b7e
   - \u96c6\u5408\u67e5\u8be2\u548c\u62bd\u8c61\u67e5\u8be2\u4e0d\u8981\u8fd4\u56de\u8fc7\u7a84\u7684\u7c97\u6807\u7b7e\u96c6\u5408

5. tag_strictness\uff1a
   - strict\uff1a\u5fc5\u987b\u547d\u4e2d\u8fd9\u4e9b\u7c97\u6807\u7b7e
   - prefer\uff1a\u4f18\u5148\u4f7f\u7528\u8fd9\u4e9b\u7c97\u6807\u7b7e\uff0c\u4f46\u5c11\u7ed3\u679c\u65f6\u53ef\u4ee5\u653e\u5bbd
   - optional\uff1a\u7c97\u6807\u7b7e\u4ec5\u4f5c\u8f85\u52a9\uff0c\u4e0d\u5e94\u963b\u585e\u53ec\u56de

6. positive_semantics\uff1a
   - \u7528\u4e8e\u6700\u7ec8\u7cbe\u6392
   - \u9700\u66f4\u51c6\u786e\u3001\u66f4\u96c6\u4e2d
   - \u5fc5\u987b\u8f93\u51fa\u9002\u5408\u641c\u56fe\u7684\u82f1\u6587\u77ed\u53e5\uff0c\u63a8\u8350\u4f7f\u7528 “a photo of ...” \u8fd9\u79cd\u5f62\u5f0f
   - \u4e0d\u8981\u8f93\u51fa\u5355\u4e2a\u8bcd\uff0c\u4e0d\u8981\u8f93\u51fa\u6807\u7b7e\u540d\uff0c\u4e0d\u8981\u8f93\u51fa\u4e2d\u6587
   - \u6bcf\u4e2a\u9879\u5305\u542b text \u548c weight

7. recall_semantics\uff1a
   - \u7528\u4e8e\u5c11\u7ed3\u679c\u65f6\u5bbd\u53ec\u56de
   - \u9700\u8986\u76d6\u76f8\u5173\u5b50\u573a\u666f\u3001\u8fd1\u4e49\u8868\u8fbe\u3001\u540c\u4e3b\u9898\u5178\u578b\u5185\u5bb9
   - \u5fc5\u987b\u8f93\u51fa\u9002\u5408\u641c\u56fe\u7684\u82f1\u6587\u77ed\u53e5\uff0c\u63a8\u8350\u4f7f\u7528 “a photo of ...” \u8fd9\u79cd\u5f62\u5f0f
   - \u4e0d\u8981\u8f93\u51fa\u5355\u4e2a\u8bcd\uff0c\u4e0d\u8981\u8f93\u51fa\u6807\u7b7e\u540d\uff0c\u4e0d\u8981\u8f93\u51fa\u4e2d\u6587
   - \u96c6\u5408\u67e5\u8be2\u548c\u62bd\u8c61\u67e5\u8be2\u5fc5\u987b\u8ba4\u771f\u8f93\u51fa\uff0c\u4e0d\u8981\u8fc7\u7a84

8. negative_semantics\uff1a
   - \u8868\u793a\u7528\u6237\u4e0d\u60f3\u8981\u7684\u5185\u5bb9
   - \u5fc5\u987b\u8f93\u51fa\u9002\u5408\u641c\u56fe\u7684\u82f1\u6587\u77ed\u53e5\uff0c\u63a8\u8350\u4f7f\u7528 “a photo of ...” \u6216 “a screenshot of ...” \u8fd9\u79cd\u5f62\u5f0f
   - \u4e0d\u8981\u8f93\u51fa\u5355\u4e2a\u8bcd\uff0c\u4e0d\u8981\u8f93\u51fa\u6807\u7b7e\u540d\uff0c\u4e0d\u8981\u8f93\u51fa\u4e2d\u6587
   - \u5982\u679c\u7528\u6237\u6ca1\u6709\u660e\u786e\u8bf4\u8981\u627e\u622a\u56fe/\u6587\u6863/\u4ee3\u7801\uff0c\u5219\u9ed8\u8ba4\u52a0\u5165\u622a\u56fe/\u6587\u6863\u7c7b\u8d1f\u5411\u8bed\u4e49

9. estimated_result_count\uff1a
   - \u4f30\u8ba1\u5408\u7406\u7ed3\u679c\u89c4\u6a21
   - \u9700\u8981\u8f93\u51fa min / max / confidence
   - \u62bd\u8c61\u67e5\u8be2\u3001\u96c6\u5408\u67e5\u8be2\u901a\u5e38\u6bd4\u5177\u4f53\u67e5\u8be2\u66f4\u591a

10. \u5bf9\u4e8e metadata \u7c7b\u67e5\u8be2\uff08\u53ea\u5305\u542b\u65f6\u95f4/\u5730\u70b9\u8fc7\u6ee4\uff09\uff1a
   - query_type \u5fc5\u987b\u662f metadata
   - coarse_tags \u8fd4\u56de []
   - positive_semantics \u8fd4\u56de []
   - recall_semantics \u8fd4\u56de []
   - negative_semantics \u8fd4\u56de []

11. \u53ea\u8f93\u51fa JSON\uff0c\u4e0d\u8981\u89e3\u91ca\u3002

\u7c97\u6807\u7b7e\u5217\u8868\uff1a
${jsonEncode(coarseCatalog)}

\u7528\u6237\u67e5\u8be2\uff1a
$rawQuery
''';

    final response = await _llmService.completeText(
      prompt: prompt,
      systemPrompt:
          '\u4f60\u662f\u201c\u76f8\u518c\u8bed\u4e49\u641c\u7d22\u89e3\u6790\u5668\u201d\u3002\u4f60\u7684\u552f\u4e00\u4efb\u52a1\u662f\u628a\u7528\u6237\u7684\u76f8\u518c\u641c\u7d22\u8bed\u53e5\u8f6c\u6210\u7ed3\u6784\u5316 JSON\u3002\u4f60\u8f93\u51fa\u7684\u4e0d\u662f\u89e3\u91ca\uff0c\u4e0d\u662f\u5efa\u8bae\uff0c\u800c\u662f\u201c\u641c\u7d22\u8ba1\u5212\u201d\u3002\u53ea\u8f93\u51fa\u4e00\u4e2a JSON \u5bf9\u8c61\uff0c\u4e0d\u8981\u8f93\u51fa Markdown\uff0c\u4e0d\u8981\u8f93\u51fa\u4ee3\u7801\u5757\uff0c\u4e0d\u8981\u8f93\u51fa\u4efb\u4f55\u989d\u5916\u6587\u672c\u3002',
    );

    final jsonObject = _decodeJsonObject(response);
    return _buildStructuredQueryFromJsonObject(
      rawQuery: rawQuery,
      jsonObject: jsonObject,
      locationDictionary: locationDictionary,
      usedLlm: true,
      llmConfigured: true,
      parserSource: 'llm',
      baseNotes: _noteLlm,
    );
  }

  SemanticSearchQuery _buildStructuredQueryFromJsonObject({
    required String rawQuery,
    required Map<String, dynamic> jsonObject,
    required Set<String> locationDictionary,
    required bool usedLlm,
    required bool llmConfigured,
    required String parserSource,
    required String baseNotes,
  }) {
    final timeRanges = _readTimeRanges(
      jsonObject['time_ranges'] ?? jsonObject['time'],
    );
    final locations = _readLocations(
      jsonObject['locations'] ?? jsonObject['location'],
      locationDictionary,
    );
    final coarseTags = _readCoarseTags(
      jsonObject['coarse_tags'] ?? jsonObject['tags'],
    );
    var positiveSemantics = _readSemanticItems(
      jsonObject['positive_semantics'] ?? jsonObject['semantic_query'],
    );
    var recallSemantics = _readSemanticItems(jsonObject['recall_semantics']);
    var negativeSemantics = _readSemanticItems(
      jsonObject['negative_semantics'] ?? jsonObject['negative_query'],
    );
    final queryType =
        _readQueryType(jsonObject['query_type']) ?? _inferQueryType(rawQuery);
    final tagStrictness =
        _readTagStrictness(jsonObject['tag_strictness']) ??
        _defaultTagStrictnessFor(queryType);
    final estimatedResultCount =
        _readEstimatedResultCount(jsonObject['estimated_result_count']) ??
        _estimateResultCount(rawQuery, queryType);

    var notes = baseNotes;
    if (queryType == SemanticSearchQueryType.metadata) {
      positiveSemantics = const <SemanticSearchSemanticItem>[];
      recallSemantics = const <SemanticSearchSemanticItem>[];
      negativeSemantics = const <SemanticSearchSemanticItem>[];
    } else if (positiveSemantics.isEmpty) {
      positiveSemantics = _buildPositiveSemantics(rawQuery, coarseTags);
      if (recallSemantics.isEmpty) {
        recallSemantics = _buildRecallSemantics(rawQuery, coarseTags);
      }
      notes = _appendNote(notes, _noteLlmSupplemented);
    }
    if (recallSemantics.isEmpty &&
        queryType != SemanticSearchQueryType.metadata) {
      recallSemantics = _buildRecallSemantics(rawQuery, coarseTags);
    }
    if (negativeSemantics.isEmpty &&
        queryType != SemanticSearchQueryType.metadata) {
      negativeSemantics = _buildNegativeSemantics(rawQuery);
    }

    return SemanticSearchQuery(
      rawQuery: rawQuery,
      routeType: SemanticSearchRouteType.llmStructured,
      queryType: queryType,
      timeRanges: timeRanges,
      locations: locations,
      coarseTags: coarseTags,
      tagStrictness: tagStrictness,
      positiveSemantics: positiveSemantics,
      recallSemantics: recallSemantics,
      negativeSemantics: negativeSemantics,
      estimatedResultCount: estimatedResultCount,
      usedLlm: usedLlm,
      llmConfigured: llmConfigured,
      parserSource: parserSource,
      debugJson: _prettyJson.convert(jsonObject),
      notes: notes,
    );
  }

  SemanticSearchQuery _mergeQueries(
    SemanticSearchQuery primary,
    SemanticSearchQuery fallback,
  ) {
    return primary.copyWith(
      queryType: primary.queryType,
      timeRanges: primary.timeRanges.isNotEmpty
          ? primary.timeRanges
          : fallback.timeRanges,
      locations: primary.locations.isNotEmpty
          ? primary.locations
          : fallback.locations,
      coarseTags: primary.coarseTags.isNotEmpty
          ? primary.coarseTags
          : fallback.coarseTags,
      tagStrictness: primary.tagStrictness,
      positiveSemantics: primary.positiveSemantics.isNotEmpty
          ? primary.positiveSemantics
          : fallback.positiveSemantics,
      recallSemantics: primary.recallSemantics.isNotEmpty
          ? primary.recallSemantics
          : fallback.recallSemantics,
      negativeSemantics: primary.negativeSemantics.isNotEmpty
          ? primary.negativeSemantics
          : fallback.negativeSemantics,
      estimatedResultCount: primary.estimatedResultCount.isMeaningful
          ? primary.estimatedResultCount
          : fallback.estimatedResultCount,
      notes: [
        primary.notes.trim(),
        if (fallback.notes.trim().isNotEmpty) _noteFallbackMerged,
      ].where((item) => item.isNotEmpty).join('\uff1b'),
    );
  }

  SemanticSearchQueryType? _readQueryType(dynamic value) {
    final text = value?.toString().trim().toLowerCase();
    switch (text) {
      case 'metadata':
        return SemanticSearchQueryType.metadata;
      case 'attribute':
        return SemanticSearchQueryType.attribute;
      case 'abstract':
        return SemanticSearchQueryType.abstract;
      case 'collection':
        return SemanticSearchQueryType.collection;
      case 'concrete':
        return SemanticSearchQueryType.concrete;
      default:
        return null;
    }
  }

  SemanticSearchTagStrictness? _readTagStrictness(dynamic value) {
    final text = value?.toString().trim().toLowerCase();
    switch (text) {
      case 'strict':
        return SemanticSearchTagStrictness.strict;
      case 'optional':
        return SemanticSearchTagStrictness.optional;
      case 'prefer':
        return SemanticSearchTagStrictness.prefer;
      default:
        return null;
    }
  }

  SemanticSearchEstimatedResultCount? _readEstimatedResultCount(dynamic value) {
    if (value is! Map) {
      return null;
    }
    final min = _toInt(value['min']) ?? 0;
    final max = _toInt(value['max']) ?? 0;
    final confidence = (_toDouble(value['confidence']) ?? 0.0).clamp(0.0, 1.0);
    if (min <= 0 && max <= 0) {
      return null;
    }
    return SemanticSearchEstimatedResultCount(
      min: min,
      max: max < min ? min : max,
      confidence: confidence,
    );
  }

  List<SemanticSearchTimeRange> _readTimeRanges(dynamic value) {
    if (value is! List) {
      return const <SemanticSearchTimeRange>[];
    }
    return value
        .whereType<Map>()
        .map((item) {
          return SemanticSearchTimeRange(
            startTimeMs: _toInt(item['start_time_ms'] ?? item['start']),
            endTimeMs: _toInt(item['end_time_ms'] ?? item['end']),
            reason: (item['reason'] ?? '').toString().trim(),
          );
        })
        .toList(growable: false);
  }

  List<SemanticSearchLocation> _readLocations(
    dynamic value,
    Set<String> locationDictionary,
  ) {
    if (value is! List) {
      return const <SemanticSearchLocation>[];
    }
    final results = <SemanticSearchLocation>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) {
        results.add(
          SemanticSearchLocation(
            text: item.trim(),
            type: _guessLocationType(item.trim()),
          ),
        );
        continue;
      }
      if (item is! Map) {
        continue;
      }
      final text = (item['text'] ?? item['name'] ?? '').toString().trim();
      if (text.isEmpty ||
          text == '\u6d77\u8fb9' ||
          text == '\u591c\u666f' ||
          text == '\u8349\u5730') {
        continue;
      }
      final type = (item['type'] ?? '').toString().trim();
      final inDictionary = locationDictionary.any(
        (candidate) =>
            candidate.contains(text) ||
            _stripLocationSuffixAscii(candidate) ==
                _stripLocationSuffixAscii(text),
      );
      if (!inDictionary && type.isEmpty) {
        continue;
      }
      results.add(
        SemanticSearchLocation(
          text: text,
          type: type.isEmpty ? _guessLocationType(text) : type,
        ),
      );
    }
    final unique = <String, SemanticSearchLocation>{};
    for (final item in results) {
      unique[item.text] = item;
    }
    return unique.values.toList(growable: false);
  }

  List<SemanticSearchCoarseTag> _readCoarseTags(dynamic value) {
    if (value is! List) {
      return const <SemanticSearchCoarseTag>[];
    }
    final results = <SemanticSearchCoarseTag>[];
    for (final item in value) {
      if (item is String) {
        final seed = _coarseTagFromLabelOrId(item);
        if (seed != null) {
          results.add(
            SemanticSearchCoarseTag(
              id: seed.id,
              labelZh: seed.labelZh,
              labelEn: seed.labelEn,
              confidence: 0.72,
            ),
          );
        }
        continue;
      }
      if (item is! Map) {
        continue;
      }
      final seed = _coarseTagFromLabelOrId(
        (item['id'] ?? item['label_zh'] ?? item['label_en'] ?? '').toString(),
      );
      if (seed == null) {
        continue;
      }
      results.add(
        SemanticSearchCoarseTag(
          id: seed.id,
          labelZh: seed.labelZh,
          labelEn: seed.labelEn,
          confidence: _toDouble(item['confidence']) ?? 0.72,
        ),
      );
    }
    final unique = <String, SemanticSearchCoarseTag>{};
    for (final item in results) {
      unique[item.id] = item;
    }
    return unique.values.toList(growable: false);
  }

  List<SemanticSearchSemanticItem> _readSemanticItems(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return <SemanticSearchSemanticItem>[
        SemanticSearchSemanticItem(text: value.trim(), weight: 1.0),
      ];
    }
    if (value is! List) {
      return const <SemanticSearchSemanticItem>[];
    }
    final results = <SemanticSearchSemanticItem>[];
    for (final item in value) {
      if (item is String && item.trim().isNotEmpty) {
        results.add(SemanticSearchSemanticItem(text: item.trim(), weight: 1.0));
        continue;
      }
      if (item is! Map) {
        continue;
      }
      final text = (item['text'] ?? item['query'] ?? item['prompt'] ?? '')
          .toString()
          .trim();
      if (text.isEmpty) {
        continue;
      }
      results.add(
        SemanticSearchSemanticItem(
          text: text,
          weight: _toDouble(item['weight']) ?? 1.0,
        ),
      );
    }
    return _normalizeSemanticWeights(results);
  }

  Map<String, dynamic> _decodeJsonObject(String? response) {
    if (response == null || response.trim().isEmpty) {
      throw const FormatException('Empty llm response');
    }
    final trimmed = response.trim();
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final slice = trimmed.substring(start, end + 1);
      final decoded = jsonDecode(slice);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    throw const FormatException('Unable to parse llm json');
  }

  List<SemanticSearchSemanticItem> _normalizeSemanticWeights(
    List<SemanticSearchSemanticItem> items,
  ) {
    if (items.isEmpty) {
      return const <SemanticSearchSemanticItem>[];
    }
    final merged = <String, double>{};
    for (final item in items) {
      final text = item.text.trim();
      if (text.isEmpty) {
        continue;
      }
      merged[text] = (merged[text] ?? 0.0) + item.weight;
    }
    if (merged.isEmpty) {
      return const <SemanticSearchSemanticItem>[];
    }
    final total = merged.values.fold<double>(0.0, (sum, item) => sum + item);
    return merged.entries
        .map(
          (entry) => SemanticSearchSemanticItem(
            text: entry.key,
            weight: total <= 0 ? 1 / merged.length : entry.value / total,
          ),
        )
        .toList(growable: false);
  }

  _CoarseSeed? _coarseTagFromLabelOrId(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    for (final seed in _coarseSeeds) {
      if (seed.id == text || seed.labelZh == text || seed.labelEn == text) {
        return seed;
      }
      if (seed.aliases.any((alias) => alias == text)) {
        return seed;
      }
    }
    return null;
  }

  String _appendNote(String current, String note) {
    return <String>[
      current.trim(),
      note.trim(),
    ].where((item) => item.isNotEmpty).join('\uff1b');
  }

  int? _toInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse(value.toString());
  }

  double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
