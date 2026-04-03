import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/vo/semantic_search_models.dart';
import 'llm_service.dart';
import 'semantic_matching_service.dart';

class SemanticQueryParserService {
  SemanticQueryParserService._internal();

  static final SemanticQueryParserService _instance =
      SemanticQueryParserService._internal();

  factory SemanticQueryParserService() => _instance;

  final LLMService _llmService = LLMService();
  final SemanticMatchingService _semanticService = SemanticMatchingService();

  static const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');
  static const double _shortRouteCoarseSimilarityThreshold = 0.18;

  static const String _noteShortRoute =
      '\u77ed\u67e5\u8be2\u76f4\u63a5\u8d70\u8bed\u4e49\u68c0\u7d22\uff0c\u672a\u8c03\u7528 DeepSeek';
  static const String _noteLocal =
      '\u5f53\u524d\u4f7f\u7528\u672c\u5730\u89c4\u5219\u89e3\u6790\u67e5\u8be2';
  static const String _noteLlm =
      '\u5f53\u524d\u4f7f\u7528 DeepSeek \u89e3\u6790\u67e5\u8be2';
  static const String _noteLlmMissing =
      '\u672a\u914d\u7f6e DeepSeek\uff0c\u5df2\u4f7f\u7528\u672c\u5730\u89e3\u6790';
  static const String _noteLlmFailed =
      'DeepSeek \u89e3\u6790\u5931\u8d25\uff0c\u5df2\u56de\u9000\u5230\u672c\u5730\u89e3\u6790';
  static const String _noteLlmSupplemented =
      'DeepSeek \u672a\u8fd4\u56de\u6709\u6548\u7684\u6b63\u5411\u8bed\u4e49\uff0c\u5df2\u8865\u5145\u672c\u5730\u8bed\u4e49\u63d0\u793a';
  static const String _noteFallbackMerged =
      '\u672c\u5730\u89c4\u5219\u5df2\u4f5c\u4e3a\u8865\u5145\u515c\u5e95';

  static const List<SemanticSearchSemanticItem> _defaultNegativeSemantics =
      <SemanticSearchSemanticItem>[
    SemanticSearchSemanticItem(
      text: 'a screenshot of a text document article chat message email or webpage',
      weight: 0.5,
    ),
    SemanticSearchSemanticItem(
      text: 'a screenshot of a computer screen software interface programming code or IDE',
      weight: 0.5,
    ),
  ];

  static const List<_CoarseSeed> _coarseSeeds = <_CoarseSeed>[
    _CoarseSeed(
      id: 'people',
      labelZh: '\u4eba\u7269',
      labelEn: 'people',
      aliases: <String>[
        '\u4eba',
        '\u4eba\u7269',
        '\u4eba\u50cf',
        '\u8096\u50cf',
        '\u81ea\u62cd',
        '\u5408\u5f71',
        '\u5bb6\u4eba',
        '\u5bb6\u5ead',
      ],
      prototypePrompt: 'a photo of people or human portraits',
      shortPrompts: <String>[
        'a photo of a person or people',
        'a portrait photo of family or friends',
      ],
    ),
    _CoarseSeed(
      id: 'food_drink',
      labelZh: '\u7f8e\u98df\u996e\u54c1',
      labelEn: 'food and drink',
      aliases: <String>[
        '\u5403',
        '\u996d',
        '\u805a\u9910',
        '\u7f8e\u98df',
        '\u996e\u54c1',
        '\u706b\u9505',
        '\u997a\u5b50',
      ],
      prototypePrompt: 'a photo of food dishes dining table or drinks',
      shortPrompts: <String>[
        'a photo of food or dishes',
        'a photo of people eating together at a table',
      ],
    ),
    _CoarseSeed(
      id: 'pets_animals',
      labelZh: '\u5ba0\u7269\u52a8\u7269',
      labelEn: 'pets and animals',
      aliases: <String>[
        '\u5ba0\u7269',
        '\u732b',
        '\u72d7',
        '\u52a8\u7269',
      ],
      prototypePrompt: 'a photo of pets animals cat dog or wildlife',
      shortPrompts: <String>[
        'a photo of a pet animal',
        'a photo of a cat or dog',
      ],
    ),
    _CoarseSeed(
      id: 'flowers_plants',
      labelZh: '\u82b1\u8349\u690d\u7269',
      labelEn: 'flowers and plants',
      aliases: <String>[
        '\u82b1',
        '\u82b1\u8349',
        '\u690d\u7269',
        '\u9c9c\u82b1',
        '\u7eff\u690d',
      ],
      prototypePrompt: 'a photo of flowers blossoms plants or leaves',
      shortPrompts: <String>[
        'a photo of flowers or blossoms',
        'a photo of plants or green leaves',
      ],
    ),
    _CoarseSeed(
      id: 'natural_landscape',
      labelZh: '\u81ea\u7136\u98ce\u5149',
      labelEn: 'natural landscape',
      aliases: <String>[
        '\u98ce\u666f',
        '\u81ea\u7136',
        '\u5c71',
        '\u8349\u539f',
        '\u68ee\u6797',
        '\u96ea\u666f',
      ],
      prototypePrompt: 'a photo of nature mountains forest snow or outdoor scenery',
      shortPrompts: <String>[
        'a photo of natural scenery',
        'a photo of mountains forest or outdoor landscape',
      ],
    ),
    _CoarseSeed(
      id: 'city_street',
      labelZh: '\u57ce\u5e02\u8857\u666f',
      labelEn: 'city street',
      aliases: <String>[
        '\u57ce\u5e02',
        '\u8857\u666f',
        '\u8857\u9053',
        '\u9ad8\u697c',
        '\u5efa\u7b51',
        '\u90fd\u5e02',
      ],
      prototypePrompt: 'a photo of city streets tall buildings road or urban landscape',
      shortPrompts: <String>[
        'a photo of a city street',
        'a photo of tall buildings road or urban landscape',
      ],
    ),
    _CoarseSeed(
      id: 'travel_landmark',
      labelZh: '\u65c5\u884c\u5730\u6807',
      labelEn: 'travel landmark',
      aliases: <String>[
        '\u65c5\u884c',
        '\u65c5\u6e38',
        '\u666f\u70b9',
        '\u5730\u6807',
      ],
      prototypePrompt: 'a photo of travel landmarks attractions or sightseeing',
      shortPrompts: <String>[
        'a travel photo of a landmark',
        'a sightseeing photo at a famous place',
      ],
    ),
    _CoarseSeed(
      id: 'beach_water',
      labelZh: '\u6d77\u8fb9\u6c34\u57df',
      labelEn: 'beach and water',
      aliases: <String>[
        '\u6d77',
        '\u6d77\u8fb9',
        '\u6d77\u6ee9',
        '\u6e56',
        '\u6c5f',
        '\u6cb3',
        '\u6c34\u8fb9',
      ],
      prototypePrompt: 'a photo of beach sea ocean river lake or waterside scenery',
      shortPrompts: <String>[
        'a photo of the beach or seaside',
        'a photo of river lake or water scenery',
      ],
    ),
    _CoarseSeed(
      id: 'sky_sunset',
      labelZh: '\u5929\u7a7a\u65e5\u843d',
      labelEn: 'sky and sunset',
      aliases: <String>[
        '\u5929\u7a7a',
        '\u4e91',
        '\u665a\u971e',
        '\u5915\u9633',
        '\u65e5\u843d',
      ],
      prototypePrompt: 'a photo of the sky clouds sunset dusk or colorful evening light',
      shortPrompts: <String>[
        'a photo of the sky and clouds',
        'a photo of sunset or evening glow',
      ],
    ),
    _CoarseSeed(
      id: 'festival_celebration',
      labelZh: '\u8282\u65e5\u5e86\u5178',
      labelEn: 'festival celebration',
      aliases: <String>[
        '\u8282\u65e5',
        '\u6625\u8282',
        '\u8fc7\u5e74',
        '\u751f\u65e5',
        '\u70df\u82b1',
      ],
      prototypePrompt: 'a photo of celebrations festival reunion birthday wedding or fireworks',
      shortPrompts: <String>[
        'a photo of a festival celebration',
        'a reunion or holiday celebration photo',
      ],
    ),
    _CoarseSeed(
      id: 'document_screenshot',
      labelZh: '\u6587\u6863\u622a\u56fe',
      labelEn: 'document screenshot',
      aliases: <String>[
        '\u6587\u6863',
        '\u622a\u56fe',
        '\u8bfe\u4ef6',
        '\u5c4f\u5e55',
        '\u8d44\u6599',
      ],
      prototypePrompt: 'a screenshot or photo of documents slides notes or text-heavy pages',
      shortPrompts: <String>[
        'a screenshot of a document or slides',
        'a photo of text-heavy notes or study materials',
      ],
    ),
    _CoarseSeed(
      id: 'screen_code',
      labelZh: '\u5c4f\u5e55\u4ee3\u7801',
      labelEn: 'screen code',
      aliases: <String>[
        '\u4ee3\u7801',
        '\u7f16\u7a0b',
        '\u7ec8\u7aef',
        '\u63a7\u5236\u53f0',
        'IDE',
      ],
      prototypePrompt: 'a screenshot of code terminal development tools or software interface',
      shortPrompts: <String>[
        'a screenshot of code or IDE',
        'a screenshot of terminal or software interface',
      ],
    ),
    _CoarseSeed(
      id: 'medical_related',
      labelZh: '\u533b\u7597\u76f8\u5173',
      labelEn: 'medical related',
      aliases: <String>[
        '\u533b\u9662',
        '\u533b\u751f',
        '\u75c5\u623f',
        '\u4f53\u68c0',
        '\u836f',
      ],
      prototypePrompt: 'a photo related to hospital clinic medicine or medical scenes',
      shortPrompts: <String>[
        'a photo at a hospital or clinic',
        'a medical related photo',
      ],
    ),
  ];

  static final Map<String, _CoarseSeed> _coarseIdToSeed =
      <String, _CoarseSeed>{for (final item in _coarseSeeds) item.id: item};

  Future<SemanticSearchQuery> parseQuery(
    String rawQuery, {
    Set<String> locationDictionary = const <String>{},
  }) async {
    final normalized = rawQuery.trim();
    if (normalized.isEmpty) {
      return SemanticSearchQuery.empty(rawQuery);
    }

    final shortQuery = await _buildShortSemanticQueryIfNeeded(normalized);
    if (shortQuery != null) {
      return shortQuery;
    }

    final localFallback = _buildLocalFallbackQuery(
      normalized,
      locationDictionary,
    );

    if (_isMetadataOnlyQuery(normalized, localFallback)) {
      return localFallback;
    }

    if (!_llmService.isApiKeyConfigured) {
      return localFallback.copyWith(
        llmConfigured: false,
        notes: _appendNote(localFallback.notes, _noteLlmMissing),
      );
    }

    try {
      final llmQuery = await _parseWithLlm(normalized, locationDictionary);
      return _mergeQueries(llmQuery, localFallback);
    } catch (error) {
      debugPrint('SemanticQueryParserService parse with llm failed: $error');
      return localFallback.copyWith(
        llmConfigured: true,
        notes: _appendNote(localFallback.notes, _noteLlmFailed),
      );
    }
  }

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
      recallSemantics: _buildRecallSemantics(
        rawQuery,
        <SemanticSearchCoarseTag>[
          SemanticSearchCoarseTag(
            id: seed.id,
            labelZh: seed.labelZh,
            labelEn: seed.labelEn,
            confidence: similarity,
          ),
        ],
      ),
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
    final coarseTags =
        isMetadataOnly ? const <SemanticSearchCoarseTag>[] : _extractCoarseTags(rawQuery);
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

    final prompt = '''
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
    final timeRanges =
        _readTimeRanges(jsonObject['time_ranges'] ?? jsonObject['time']);
    final locations = _readLocations(
      jsonObject['locations'] ?? jsonObject['location'],
      locationDictionary,
    );
    final coarseTags =
        _readCoarseTags(jsonObject['coarse_tags'] ?? jsonObject['tags']);
    var positiveSemantics = _readSemanticItems(
      jsonObject['positive_semantics'] ?? jsonObject['semantic_query'],
    );
    var recallSemantics = _readSemanticItems(jsonObject['recall_semantics']);
    var negativeSemantics = _readSemanticItems(
      jsonObject['negative_semantics'] ?? jsonObject['negative_query'],
    );
    final queryType = _readQueryType(jsonObject['query_type']) ??
        _inferQueryType(rawQuery);
    final tagStrictness =
        _readTagStrictness(jsonObject['tag_strictness']) ??
            _defaultTagStrictnessFor(queryType);
    final estimatedResultCount = _readEstimatedResultCount(
          jsonObject['estimated_result_count'],
        ) ??
        _estimateResultCount(rawQuery, queryType);

    var notes = _noteLlm;
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
    if (recallSemantics.isEmpty && queryType != SemanticSearchQueryType.metadata) {
      recallSemantics = _buildRecallSemantics(rawQuery, coarseTags);
    }
    if (negativeSemantics.isEmpty && queryType != SemanticSearchQueryType.metadata) {
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
      usedLlm: true,
      llmConfigured: true,
      parserSource: 'llm',
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
      timeRanges:
          primary.timeRanges.isNotEmpty ? primary.timeRanges : fallback.timeRanges,
      locations:
          primary.locations.isNotEmpty ? primary.locations : fallback.locations,
      coarseTags:
          primary.coarseTags.isNotEmpty ? primary.coarseTags : fallback.coarseTags,
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
    if (query.hasCoarseTags || query.hasPositiveSemantics || query.hasNegativeSemantics) {
      return false;
    }
    return _looksLikeMetadataOnlyQuery(rawQuery, query.timeRanges, query.locations);
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
      RegExp(
        r'(今年|去年|前年|明年|本月|这个月|上月|今天|昨天|前天|最近|今年的|去年的)',
      ),
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
      final coarseVector = await _semanticService.embedText(seed.prototypePrompt);
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
          (normalized.contains(cleanAlias) || cleanAlias.contains(normalized))) {
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
      ranges.add(_dayRange(now.subtract(const Duration(days: 1)), '\u6628\u5929'));
    }

    final yearMatches = RegExp(r'((?:20)?\d{2})\u5e74').allMatches(rawQuery);
    for (final match in yearMatches) {
      final value = _toInt(match.group(1));
      if (value == null) {
        continue;
      }
      final year = value < 100 ? 2000 + value : value;
      final monthMatch =
          RegExp('${match.group(0)}(\\d{1,2})\\u6708').firstMatch(rawQuery);
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
        ranges.add(_monthRange(now.year, month, '${now.year}\u5e74$month\u6708'));
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

    if (rawQuery.contains('\u6625\u8282') || rawQuery.contains('\u8fc7\u5e74')) {
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

    if (rawQuery.contains('\u65c5\u6e38') || rawQuery.contains('\u65c5\u884c')) {
      items.addAll(const <SemanticSearchSemanticItem>[
        SemanticSearchSemanticItem(
          text: 'a travel portrait during a trip',
          weight: 0.24,
        ),
        SemanticSearchSemanticItem(
          text: 'a scenic photo taken during travel',
          weight: 0.22,
        ),
        SemanticSearchSemanticItem(
          text: 'a travel food photo',
          weight: 0.18,
        ),
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

    if (rawQuery.contains('\u6625\u5929') || rawQuery.contains('\u6c14\u606f')) {
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

  List<SemanticSearchTimeRange> _readTimeRanges(dynamic value) {
    if (value is! List) {
      return const <SemanticSearchTimeRange>[];
    }
    return value.whereType<Map>().map((item) {
      return SemanticSearchTimeRange(
        startTimeMs: _toInt(item['start_time_ms'] ?? item['start']),
        endTimeMs: _toInt(item['end_time_ms'] ?? item['end']),
        reason: (item['reason'] ?? '').toString().trim(),
      );
    }).toList(growable: false);
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
            _stripLocationSuffixAscii(candidate) == _stripLocationSuffixAscii(text),
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
      final text =
          (item['text'] ?? item['query'] ?? item['prompt'] ?? '').toString().trim();
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
    return <String>[current.trim(), note.trim()]
        .where((item) => item.isNotEmpty)
        .join('\uff1b');
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

  SemanticSearchTimeRange _yearRange(int year, String reason) {
    final start = DateTime(year, 1, 1);
    final end =
        DateTime(year + 1, 1, 1).subtract(const Duration(milliseconds: 1));
    return SemanticSearchTimeRange(
      startTimeMs: start.millisecondsSinceEpoch,
      endTimeMs: end.millisecondsSinceEpoch,
      reason: reason,
    );
  }

  SemanticSearchTimeRange _monthRange(int year, int month, String reason) {
    final start = DateTime(year, month, 1);
    final end =
        DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));
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
    return value
        .replaceAll(
          RegExp(r'(省|市|区|县|自治州|自治区|特别行政区)$'),
          '',
        )
        .trim();
  }

  String _stripLocationSuffixSafe(String value) {
    return value
        .replaceAll(
          RegExp(r'(省|市|区|县|自治州|自治区|特别行政区)$'),
          '',
        )
        .trim();
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

class _CoarseSeed {
  const _CoarseSeed({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    required this.aliases,
    required this.prototypePrompt,
    required this.shortPrompts,
  });

  final String id;
  final String labelZh;
  final String labelEn;
  final List<String> aliases;
  final String prototypePrompt;
  final List<String> shortPrompts;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label_zh': labelZh,
      'label_en': labelEn,
      'aliases': aliases,
      'prototype_prompt': prototypePrompt,
      'short_prompts': shortPrompts,
    };
  }
}
