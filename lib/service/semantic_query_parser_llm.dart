/// LLM-only semantic query parser.
///
/// The parser follows the common output-parser pattern used by agent
/// frameworks: ask for a strict JSON plan, validate it locally, then ask the
/// model to repair only the invalid plan when parsing or validation fails.

part of 'semantic_query_parser_service.dart';

extension _SemanticQueryParserLlm on SemanticQueryParserService {
  static const int _maxPlanAttempts = 2;

  Future<SemanticSearchQuery> _parseWithLlm(String rawQuery) async {
    final prompt = _buildParserPrompt(rawQuery);
    String? response;
    Object? lastError;

    for (var attempt = 0; attempt < _maxPlanAttempts; attempt++) {
      response = await _llmService.completeText(
        prompt: attempt == 0
            ? prompt
            : _buildPlanRepairPrompt(
                rawQuery: rawQuery,
                invalidResponse: response,
                error: lastError,
              ),
        systemPrompt: _parserSystemPrompt,
        jsonMode: true,
        temperature: attempt == 0 ? 0.1 : 0.0,
        topP: 0.2,
        requestTimeout: const Duration(seconds: 30),
      );

      try {
        final jsonObject = _decodeJsonObject(response);
        return _buildStructuredQueryFromJsonObject(
          rawQuery: rawQuery,
          jsonObject: jsonObject,
          usedLlm: true,
          llmConfigured: true,
          parserSource: attempt == 0 ? 'llm' : 'llm_repaired',
          baseNotes: attempt == 0
              ? 'LLM structured parser'
              : 'LLM repaired structured parser',
        );
      } catch (error) {
        lastError = error;
      }
    }

    throw FormatException(
      'LLM search plan is invalid after repair: $lastError',
    );
  }

  String _buildParserPrompt(String rawQuery) {
    final now = DateTime.now();
    final nowOffset = _formatUtcOffset(now.timeZoneOffset);
    final nowIso = '${now.toIso8601String()}$nowOffset';
    final coarseCatalog = _coarseSeeds
        .map(
          (item) => <String, dynamic>{'id': item.id, 'label_en': item.labelEn},
        )
        .toList(growable: false);

    return '''
Convert the user's natural-language photo search into one strict JSON search plan.

Current date and time: $nowIso.
Device UTC offset: $nowOffset.
Resolve relative dates against the current date above.

Return exactly one JSON object. Do not return Markdown, comments, prose, or code fences.

Required top-level schema:
{
  "version": 1,
  "raw_query": "$rawQuery",
  "embedding_queries_en": [],
  "objectbox_filters": {
    "absolute_date_ranges": [],
    "annual_day_ranges": [],
    "minute_of_day_ranges": [],
    "weekdays": [],
    "geo": []
  },
  "soft_filters": {"visual_terms_original": [], "visual_terms_en": [], "geo": []},
  "negative_filters": {"visual_terms_en": [], "geo_terms": []},
  "fallback_policy": {"enable_possible_results": true, "show_possible_only_when_strict_empty": true}
}

Rules:
0. Build a complete one-pass QueryPlan. Put every mechanically filterable condition in objectbox_filters.
1. Every text value in embedding_queries_en, soft_filters.visual_terms_en, and negative_filters.visual_terms_en must be English. MobileCLIP text alignment is English-first.
   These fields must contain visual meaning only. Never repeat exact dates, years, clock times, named cities, districts, POIs, coordinates, or other precise metadata in semantic text.
   Abstract visible context such as "a coastal city", "spring scenery", "afternoon light", or "night atmosphere" is allowed.
2. Use absolute_date_ranges for explicit years or relative dates, annual_day_ranges for recurring dates or seasons, minute_of_day_ranges for local time-of-day, and weekdays for weekday constraints.
   Also extract high-confidence implicit mechanical meaning. For example, sunset/晚霞/黄昏 implies late afternoon through early evening, sunrise/朝霞 implies early morning, and a starry sky implies night. Keep the visible concept in semantic fields as well. Do not invent weak or controversial time constraints from objects that can occur all day.
3. Keep Chinese place names in objectbox_filters.geo. Do not translate raw_name, normalized_names, or amap_query_keywords. Never invent coordinates or decide that two places are identical.
4. For exact POIs use strictness="exact". For countries, provinces, cities, and districts use strictness="broad". Set allow_nearby_siblings=true only when the user explicitly says nearby, around, 周边, 附近, or 旁边.
5. Do not put scene words such as beach, park, night view, grassland, or starry sky into objectbox_filters.geo unless they are part of an official place name.
6. A phrase such as "威海海边" contains a hard city constraint (威海) plus seaside visual semantics. Never replace it with another coastal city, and distinguish sea/coast from lakes and rivers with negative_filters.visual_terms_en when needed.
7. Preserve specificity. "青岛西海岸" is more specific than "青岛"; "南京夫子庙" is more specific than "南京".
8. embedding_queries_en is the precision layer. Return 2 to 5 independent, concrete, visually observable English descriptions that jointly cover the required subject, scene, action, atmosphere, and distinguishing details.
9. soft_filters.visual_terms_en is the controlled recall layer. Return 2 to 4 alternative visible formulations for the same intent. They must never change explicit place, time, subject, medium, or scene type.
10. negative_filters.visual_terms_en contains contrastive exclusions and likely near-misses, such as sea versus lake or wedding versus an ordinary group photo.
11. Keep exact facts hard. Do not silently move explicit dates, weekdays, times, or named places into soft_filters.
12. Geo strictness and descendant flags describe user intent only. The app, local cache, and Amap resolve actual place facts.
13. If no visual matching is needed, embedding_queries_en may be empty. Never add a generic visual query merely to fill the field.
14. Do not use named places as a substitute for visible semantics. Put named places in objectbox_filters.geo and separately describe visible content.
15. If the query is ambiguous, choose the most literal interpretation and encode alternatives only in soft_filters. Never invent a different city, event, or season.
16. Before returning, verify that every noun and modifier in the user query is represented by objectbox_filters, embedding_queries_en, soft_filters, or negative_filters.
17. Remove all mechanically searchable place and time meaning from visual semantics. For "青岛的海边", geo must contain 青岛 and visual semantics should describe only beach, sea, coast, and waves. Do not mention Qingdao or a coastal city in visual semantics.
18. If the query contains only an administrative place such as a country, province, city, or district, or only a date/time filter, leave embedding_queries_en and soft_filters.visual_terms_en empty. For "青岛", return geo filters and no visual semantics so all mechanically matching photos remain eligible.
19. A specific POI, scenic area, campus, business area, or landmark may use concise visible semantics based on stable place knowledge, because photo metadata may be shifted or incomplete. The place itself must still be written to objectbox_filters.geo, but semantic fields must contain no place names, translated place names, aliases, city names, district names, or POI names. For "五四广场", keep 五四广场 as a POI geo filter and use only visible semantics such as "a city square" and "a square near the sea with a large red landmark sculpture". Never write "五四广场", "May Fourth Square", "青岛", or "Qingdao" in semantic fields.
20. Prefer precision for implicit mechanical constraints: add them only when the phrase itself strongly entails the constraint. "晚霞" must include a local late-afternoon/evening window and sunset semantics so it does not retrieve morning glow; "朝霞" must include an early-morning window. Explicit user time always overrides an inferred window.

Available local indexes:
- timestamp and recurring month filters
- province, city, district, POI, and formatted address metadata
- coarse visual tags from the catalog
- MobileCLIP image/video embeddings
- limited face count, smile, and joy attributes

Few-shot examples:
The examples below illustrate intent separation. Always emit the QueryPlan v1 schema above, not the legacy field names shown in examples.

User: 去年夏天青岛海边的记忆
JSON:
{
  "query_type": "collection",
  "time_ranges": [
    {"start": "2025-06-01T00:00:00+08:00", "end": "2025-09-30T23:59:59+08:00", "timezone": "Asia/Shanghai", "reason": "previous summer"}
  ],
  "local_time_windows": [],
  "locations": [
    {"text": "Qingdao", "type": "city", "aliases": ["青岛", "青岛市", "Qingdao"], "timezone": "Asia/Shanghai", "utc_offset": "+08:00"}
  ],
  "coarse_tags": [
    {"id": "beach_water", "label_en": "beach and water", "confidence": 0.9},
    {"id": "travel_landmark", "label_en": "travel landmark", "confidence": 0.55}
  ],
  "tag_strictness": "prefer",
  "positive_semantics": [
    {"text": "a summer travel photo by the beach", "weight": 0.55},
    {"text": "a seaside memory with ocean waves and coast", "weight": 0.45}
  ],
  "recall_semantics": [
    {"text": "a photo of people or scenery near the sea during summer travel", "weight": 0.45},
    {"text": "a coastal travel photo with beach, sea, sky, and vacation atmosphere", "weight": 0.55}
  ],
  "negative_semantics": [
    {"text": "a screenshot of a text document or software interface", "weight": 1.0}
  ],
  "estimated_result_count": {"min": 8, "max": 120, "confidence": 0.72},
  "notes": "English CLIP plan with date, city, and beach-water semantics."
}

User: 美国夏威夷夜晚的星空
JSON:
{
  "query_type": "concrete",
  "time_ranges": [],
  "local_time_windows": [
    {"start": "19:00", "end": "04:59", "timezone": "Pacific/Honolulu", "utc_offset": "-10:00", "reason": "night in Hawaii local time"}
  ],
  "locations": [
    {"text": "Hawaii", "type": "province", "aliases": ["Hawaii"], "timezone": "Pacific/Honolulu", "utc_offset": "-10:00"}
  ],
  "coarse_tags": [
    {"id": "sky_sunset", "label_en": "sky and sunset", "confidence": 0.88},
    {"id": "natural_landscape", "label_en": "natural landscape", "confidence": 0.65}
  ],
  "tag_strictness": "prefer",
  "positive_semantics": [
    {"text": "a night sky photo full of stars", "weight": 0.7},
    {"text": "a dark outdoor landscape under a starry sky", "weight": 0.3}
  ],
  "recall_semantics": [
    {"text": "a photo of stars, night sky, and dark natural scenery", "weight": 0.6},
    {"text": "an outdoor travel photo taken at night under the sky", "weight": 0.4}
  ],
  "negative_semantics": [
    {"text": "a screenshot of a text document or software interface", "weight": 1.0}
  ],
  "estimated_result_count": {"min": 1, "max": 40, "confidence": 0.62},
  "notes": "Uses Hawaii local night instead of device local night."
}

User: 南京夫子庙
JSON:
{
  "query_type": "concrete",
  "time_ranges": [],
  "local_time_windows": [],
  "locations": [
    {"text": "Nanjing Confucius Temple", "type": "poi", "aliases": ["南京夫子庙", "夫子庙", "Fuzimiao", "Confucius Temple"], "timezone": "Asia/Shanghai", "utc_offset": "+08:00"}
  ],
  "coarse_tags": [
    {"id": "travel_landmark", "label_en": "travel landmark", "confidence": 0.8}
  ],
  "tag_strictness": "prefer",
  "positive_semantics": [
    {"text": "traditional Chinese architecture beside a historic pedestrian street", "weight": 0.6},
    {"text": "a sightseeing area with old buildings and lanterns", "weight": 0.4}
  ],
  "recall_semantics": [
    {"text": "a historic Chinese tourist street", "weight": 1.0}
  ],
  "negative_semantics": [],
  "estimated_result_count": {"min": 1, "max": 80, "confidence": 0.65},
  "notes": "Specific POI keeps geo matching and adds stable visible semantics without repeating its name."
}

User: 五四广场
JSON:
{
  "query_type": "concrete",
  "time_ranges": [],
  "local_time_windows": [],
  "locations": [
    {"text": "五四广场", "type": "poi", "aliases": ["五四广场"], "timezone": "Asia/Shanghai", "utc_offset": "+08:00"}
  ],
  "coarse_tags": [
    {"id": "city_street", "label_en": "city street", "confidence": 0.7},
    {"id": "travel_landmark", "label_en": "travel landmark", "confidence": 0.8}
  ],
  "tag_strictness": "prefer",
  "positive_semantics": [
    {"text": "a city square", "weight": 0.45},
    {"text": "a square near the sea with a large red landmark sculpture", "weight": 0.55}
  ],
  "recall_semantics": [
    {"text": "an open urban plaza near a coastal waterfront", "weight": 1.0}
  ],
  "negative_semantics": [],
  "estimated_result_count": {"min": 1, "max": 80, "confidence": 0.65},
  "notes": "Specific POI uses stable visible characteristics to recover photos with incomplete or shifted location metadata."
}

User: 晚霞
JSON:
{
  "query_type": "concrete",
  "time_ranges": [],
  "local_time_windows": [
    {"start": "15:30", "end": "21:00", "reason": "sunset and evening glow occur from late afternoon into early evening"}
  ],
  "locations": [],
  "coarse_tags": [
    {"id": "sky_sunset", "label_en": "sky and sunset", "confidence": 0.95}
  ],
  "tag_strictness": "prefer",
  "positive_semantics": [
    {"text": "a vivid sunset sky with warm evening glow", "weight": 0.7},
    {"text": "colorful clouds illuminated after sunset", "weight": 0.3}
  ],
  "recall_semantics": [
    {"text": "orange red and purple clouds in an evening sky", "weight": 1.0}
  ],
  "negative_semantics": [
    {"text": "sunrise and morning glow", "weight": 1.0}
  ],
  "estimated_result_count": {"min": 1, "max": 120, "confidence": 0.8},
  "notes": "Sunset has both visible semantics and a high-confidence local time constraint."
}

Coarse tag catalog:
${jsonEncode(coarseCatalog)}

User query:
$rawQuery
''';
  }

  SemanticSearchQuery _buildStructuredQueryFromJsonObject({
    required String rawQuery,
    required Map<String, dynamic> jsonObject,
    required bool usedLlm,
    required bool llmConfigured,
    required String parserSource,
    required String baseNotes,
  }) {
    final plan = _normalizeQueryPlanSchema(rawQuery, jsonObject);
    final requestedQueryType = _requireQueryType(plan['query_type']);
    final timeRanges = _readTimeRanges(
      plan['time_ranges'],
      localTimeWindows: plan['local_time_windows'],
    );
    final normalizedTimeRanges = _normalizeRecurringSeason(
      rawQuery,
      timeRanges,
    );
    final locations = _readLocations(plan['locations']);
    final coarseTags = _readCoarseTags(plan['coarse_tags']);
    final pureMechanicalQuery = _isPureMechanicalQuery(
      rawQuery,
      locations: locations,
      timeRanges: normalizedTimeRanges,
      weekdays: _readWeekdays(plan['weekdays']),
    );
    final queryType = pureMechanicalQuery
        ? SemanticSearchQueryType.metadata
        : requestedQueryType;
    final positiveSemantics = pureMechanicalQuery
        ? const <SemanticSearchSemanticItem>[]
        : _removeNamedLocationsFromSemantics(
            _readSemanticItems(plan['positive_semantics']),
            locations,
          );
    final recallSemantics = pureMechanicalQuery
        ? const <SemanticSearchSemanticItem>[]
        : _removeNamedLocationsFromSemantics(
            _readSemanticItems(plan['recall_semantics']),
            locations,
          );
    final negativeSemantics = pureMechanicalQuery
        ? const <SemanticSearchSemanticItem>[]
        : _normalizeNegativeSemantics(
            rawQuery,
            _removeNamedLocationsFromSemantics(
              _readSemanticItems(plan['negative_semantics']),
              locations,
            ),
          );
    final tagStrictness = _readTagStrictness(plan['tag_strictness']);
    final estimatedResultCount = _readEstimatedResultCount(
      plan['estimated_result_count'],
    );
    final attributes = _readAttributes(plan['attributes']);
    final weekdays = _readWeekdays(plan['weekdays']);

    _validateSearchPlan(
      queryType: queryType,
      locations: locations,
      positiveSemantics: positiveSemantics,
      recallSemantics: recallSemantics,
      negativeSemantics: negativeSemantics,
      estimatedResultCount: estimatedResultCount,
    );

    return SemanticSearchQuery(
      rawQuery: rawQuery,
      routeType: SemanticSearchRouteType.llmStructured,
      queryType: queryType,
      timeRanges: normalizedTimeRanges,
      locations: locations,
      coarseTags: pureMechanicalQuery
          ? const <SemanticSearchCoarseTag>[]
          : coarseTags,
      tagStrictness: tagStrictness,
      positiveSemantics: queryType == SemanticSearchQueryType.metadata
          ? const <SemanticSearchSemanticItem>[]
          : positiveSemantics,
      recallSemantics: queryType == SemanticSearchQueryType.metadata
          ? const <SemanticSearchSemanticItem>[]
          : recallSemantics,
      negativeSemantics: queryType == SemanticSearchQueryType.metadata
          ? const <SemanticSearchSemanticItem>[]
          : negativeSemantics,
      estimatedResultCount: estimatedResultCount,
      attributes: attributes,
      weekdays: weekdays,
      usedLlm: usedLlm,
      llmConfigured: llmConfigured,
      parserSource: parserSource,
      debugJson: _prettyJson.convert(plan),
      notes: (plan['notes']?.toString().trim().isNotEmpty ?? false)
          ? '$baseNotes; ${plan['notes'].toString().trim()}'
          : baseNotes,
    );
  }

  Map<String, dynamic> _normalizeQueryPlanSchema(
    String rawQuery,
    Map<String, dynamic> jsonObject,
  ) {
    if (jsonObject['objectbox_filters'] is! Map) return jsonObject;
    final filters = jsonObject['objectbox_filters'] as Map;
    final embeddings = _readFlexibleStringList(
      jsonObject['embedding_queries_en'],
    );
    final soft = jsonObject['soft_filters'] is Map
        ? jsonObject['soft_filters'] as Map
        : const <String, dynamic>{};
    final negative = jsonObject['negative_filters'] is Map
        ? jsonObject['negative_filters'] as Map
        : const <String, dynamic>{};
    final geo = filters['geo'] is List ? filters['geo'] as List : const [];
    return <String, dynamic>{
      'query_type': embeddings.isEmpty ? 'metadata' : 'concrete',
      'time_ranges': <dynamic>[
        ..._mapAbsoluteRanges(filters['absolute_date_ranges']),
        ..._mapAnnualDayRanges(filters['annual_day_ranges']),
      ],
      'local_time_windows': _mapMinuteRanges(filters['minute_of_day_ranges']),
      'weekdays': filters['weekdays'] ?? const <int>[],
      'locations': geo
          .whereType<Map>()
          .map((item) {
            final rawName = (item['raw_name'] ?? '').toString().trim();
            return <String, dynamic>{
              'text': rawName,
              'type': _normalizeGeoKind(item['kind_hint']),
              'aliases': <String>{
                rawName,
                ..._readFlexibleStringList(item['normalized_names']),
                ..._readFlexibleStringList(item['amap_query_keywords']),
                (item['province_hint'] ?? '').toString().trim(),
                (item['city_hint'] ?? '').toString().trim(),
                (item['district_hint'] ?? '').toString().trim(),
              }.where((value) => value.isNotEmpty).toList(growable: false),
              'strictness': item['strictness'],
              'allow_descendants': item['allow_descendants'],
              'allow_nearby_siblings': item['allow_nearby_siblings'],
              'country_candidates': item['country_candidates'],
            };
          })
          .toList(growable: false),
      'coarse_tags': const <Object>[],
      'tag_strictness': 'optional',
      'positive_semantics': _weightedItems(embeddings),
      'recall_semantics': _weightedItems(
        _readFlexibleStringList(soft['visual_terms_en']).isEmpty
            ? embeddings
            : _readFlexibleStringList(soft['visual_terms_en']),
      ),
      'negative_semantics': _weightedItems(
        _readFlexibleStringList(negative['visual_terms_en']),
      ),
      'attributes': const <String, dynamic>{},
      'estimated_result_count': const <String, dynamic>{
        'min': 1,
        'max': 240,
        'confidence': 0.5,
      },
      'notes': 'QueryPlan v${jsonObject['version'] ?? 1}',
      'raw_query': jsonObject['raw_query'] ?? rawQuery,
    };
  }

  List<Map<String, dynamic>> _mapAbsoluteRanges(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map(
          (item) => <String, dynamic>{
            'start_time_ms': item['start_millis'],
            'end_time_ms': item['end_millis'],
            'reason': 'absolute date range',
          },
        )
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _mapAnnualDayRanges(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map(
          (item) => <String, dynamic>{
            'annual_start_day': item['start_day_of_year'] ?? item['start_day'],
            'annual_end_day': item['end_day_of_year'] ?? item['end_day'],
            'reason': 'annual day range',
          },
        )
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _mapMinuteRanges(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map(
          (item) => <String, dynamic>{
            'start_minute': item['start_minute'],
            'end_minute': item['end_minute'],
            'reason': 'minute of day range',
          },
        )
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _weightedItems(List<String> values) {
    if (values.isEmpty) return const <Map<String, dynamic>>[];
    final weight = 1 / values.length;
    return values
        .map((text) => <String, dynamic>{'text': text, 'weight': weight})
        .toList(growable: false);
  }

  List<String> _readFlexibleStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item is Map ? item['text'] : item)
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String _normalizeGeoKind(dynamic value) {
    final kind = value?.toString().trim().toLowerCase() ?? '';
    if (const <String>{
      'country',
      'province',
      'city',
      'district',
    }.contains(kind)) {
      return kind;
    }
    if (kind == 'scenic') return 'scenic_area';
    if (kind == 'region_concept') return 'region_concept';
    if (const <String>{
      'development_zone',
      'township',
      'business_area',
      'neighborhood',
      'campus',
    }.contains(kind)) {
      return kind;
    }
    return 'poi';
  }

  void _validateSearchPlan({
    required SemanticSearchQueryType queryType,
    required List<SemanticSearchLocation> locations,
    required List<SemanticSearchSemanticItem> positiveSemantics,
    required List<SemanticSearchSemanticItem> recallSemantics,
    required List<SemanticSearchSemanticItem> negativeSemantics,
    required SemanticSearchEstimatedResultCount estimatedResultCount,
  }) {
    if (queryType != SemanticSearchQueryType.metadata &&
        positiveSemantics.isEmpty) {
      throw FormatException('search plan has no positive_semantics');
    }
    if (queryType != SemanticSearchQueryType.metadata &&
        recallSemantics.isEmpty) {
      throw FormatException('search plan has no recall_semantics');
    }
    if (queryType != SemanticSearchQueryType.metadata) {
      _validateEnglishVisualSemantics('positive_semantics', positiveSemantics);
      _validateEnglishVisualSemantics('recall_semantics', recallSemantics);
      _validateEnglishVisualSemantics('negative_semantics', negativeSemantics);
    }
    if (!estimatedResultCount.isMeaningful) {
      throw FormatException('search plan has invalid result estimate');
    }
    for (final location in locations) {
      if (location.text.length < 2) {
        throw FormatException('search plan has invalid location');
      }
    }
  }

  void _validateEnglishVisualSemantics(
    String fieldName,
    List<SemanticSearchSemanticItem> items,
  ) {
    for (final item in items) {
      if (item.containsCjk) {
        throw FormatException(
          '$fieldName must contain English MobileCLIP prompts: ${item.text}',
        );
      }
    }
  }

  List<SemanticSearchTimeRange> _readTimeRanges(
    dynamic dateRanges, {
    required dynamic localTimeWindows,
  }) {
    final results = <SemanticSearchTimeRange>[];
    if (dateRanges is List) {
      for (final item in dateRanges.whereType<Map>()) {
        final range = _readDateRange(item);
        if (range != null) {
          results.add(range);
        }
      }
    }
    if (localTimeWindows is List) {
      for (final item in localTimeWindows.whereType<Map>()) {
        final range = _readLocalTimeWindow(item);
        if (range != null) {
          results.add(range);
        }
      }
    }
    return results;
  }

  SemanticSearchTimeRange? _readDateRange(Map item) {
    final recurringStartMonth = _readMonth(item['recurring_start_month']);
    final recurringEndMonth = _readMonth(item['recurring_end_month']);
    final startRaw =
        item['start'] ?? item['start_iso'] ?? item['start_time_ms'];
    final endRaw = item['end'] ?? item['end_iso'] ?? item['end_time_ms'];
    final startTimeMs = _toTimestampMs(startRaw);
    final endTimeMs = _toTimestampMs(endRaw);
    final annualStartDay = _readDayOfYear(item['annual_start_day']);
    final annualEndDay = _readDayOfYear(item['annual_end_day']);
    if (startTimeMs == null &&
        endTimeMs == null &&
        (annualStartDay == null || annualEndDay == null) &&
        (recurringStartMonth == null || recurringEndMonth == null)) {
      return null;
    }
    return SemanticSearchTimeRange(
      startTimeMs: startTimeMs,
      endTimeMs: endTimeMs,
      reason: (item['reason'] ?? '').toString().trim(),
      startIso: startRaw is String ? startRaw.trim() : null,
      endIso: endRaw is String ? endRaw.trim() : null,
      timezone: _readOptionalString(item['timezone']),
      recurringStartMonth: recurringStartMonth,
      recurringEndMonth: recurringEndMonth,
      annualStartDay: annualStartDay,
      annualEndDay: annualEndDay,
    );
  }

  List<SemanticSearchTimeRange> _normalizeRecurringSeason(
    String rawQuery,
    List<SemanticSearchTimeRange> ranges,
  ) {
    if (ranges.any((range) => range.hasAnnualDayRange)) {
      return ranges;
    }
    if (RegExp(r'(今年|当年|去年|前年|明年|\d{4}\s*年)').hasMatch(rawQuery)) {
      return ranges;
    }
    List<int>? season;
    if (rawQuery.contains('春天') || rawQuery.contains('春季')) {
      season = const <int>[3, 5];
    } else if (rawQuery.contains('夏天') || rawQuery.contains('夏季')) {
      season = const <int>[6, 10];
    } else if (rawQuery.contains('秋天') || rawQuery.contains('秋季')) {
      season = const <int>[9, 11];
    } else if (rawQuery.contains('冬天') || rawQuery.contains('冬季')) {
      season = const <int>[12, 2];
    }
    if (season == null) {
      return ranges;
    }
    return <SemanticSearchTimeRange>[
      SemanticSearchTimeRange(
        startTimeMs: null,
        endTimeMs: null,
        reason: 'recurring season in any year',
        recurringStartMonth: season[0],
        recurringEndMonth: season[1],
      ),
    ];
  }

  SemanticSearchTimeRange? _readLocalTimeWindow(Map item) {
    final startMinute =
        _toMinuteOfDay(item['start_minute']) ?? _readMinuteOfDay(item['start']);
    final endMinute =
        _toMinuteOfDay(item['end_minute']) ?? _readMinuteOfDay(item['end']);
    final offsetMinutes = _readUtcOffsetMinutes(item['utc_offset']);
    if (startMinute == null || endMinute == null) {
      return null;
    }
    return SemanticSearchTimeRange(
      startTimeMs: null,
      endTimeMs: null,
      reason: (item['reason'] ?? '').toString().trim(),
      timezone: _readOptionalString(item['timezone']),
      utcOffsetMinutes: offsetMinutes,
      localStartMinute: startMinute,
      localEndMinute: endMinute,
    );
  }

  List<SemanticSearchLocation> _readLocations(dynamic value) {
    if (value is! List) {
      return const <SemanticSearchLocation>[];
    }
    final locations = <String, SemanticSearchLocation>{};
    for (final item in value.whereType<Map>()) {
      final text = (item['text'] ?? '').toString().trim();
      if (text.isEmpty || _isSceneWord(text)) {
        continue;
      }
      final location = SemanticSearchLocation(
        text: text,
        type: _readLocationType(item['type']),
        aliases: _readStringList(item['aliases']),
        timezone: _readOptionalString(item['timezone']),
        utcOffsetMinutes: _readUtcOffsetMinutes(item['utc_offset']),
        strictness: _readGeoStrictness(item['strictness']),
        allowDescendants: item['allow_descendants'] == true,
        allowNearbySiblings: item['allow_nearby_siblings'] == true,
        countryCandidates: _readStringList(item['country_candidates']),
      );
      locations[location.text] = location;
    }
    return locations.values.toList(growable: false);
  }

  List<SemanticSearchSemanticItem> _normalizeNegativeSemantics(
    String rawQuery,
    List<SemanticSearchSemanticItem> items,
  ) {
    final normalized = <SemanticSearchSemanticItem>[...items];
    if (rawQuery.contains('海边') && !rawQuery.contains('湖')) {
      normalized.add(
        const SemanticSearchSemanticItem(
          text: 'a lake, lakeside, river, or riverside scene without the sea',
          weight: 1.0,
        ),
      );
    }
    return _normalizeSemanticWeights(normalized);
  }

  List<SemanticSearchCoarseTag> _readCoarseTags(dynamic value) {
    if (value is! List) {
      return const <SemanticSearchCoarseTag>[];
    }
    final tags = <String, SemanticSearchCoarseTag>{};
    for (final item in value.whereType<Map>()) {
      final seed = _coarseSeedById[(item['id'] ?? '').toString().trim()];
      if (seed == null) {
        continue;
      }
      tags[seed.id] = SemanticSearchCoarseTag(
        id: seed.id,
        labelZh: seed.labelZh,
        labelEn: seed.labelEn,
        confidence: (_toDouble(item['confidence']) ?? 0.7)
            .clamp(0.0, 1.0)
            .toDouble(),
      );
    }
    return tags.values.toList(growable: false);
  }

  List<SemanticSearchSemanticItem> _readSemanticItems(dynamic value) {
    if (value is! List) {
      return const <SemanticSearchSemanticItem>[];
    }
    final items = <SemanticSearchSemanticItem>[];
    for (final item in value.whereType<Map>()) {
      final text = (item['text'] ?? '').toString().trim();
      if (text.isEmpty) {
        continue;
      }
      items.add(
        SemanticSearchSemanticItem(
          text: text,
          weight: (_toDouble(item['weight']) ?? 1.0)
              .clamp(0.0, 10.0)
              .toDouble(),
        ),
      );
    }
    return _normalizeSemanticWeights(items);
  }

  List<SemanticSearchSemanticItem> _removeNamedLocationsFromSemantics(
    List<SemanticSearchSemanticItem> items,
    List<SemanticSearchLocation> locations,
  ) {
    final namedTerms =
        <String>{
              for (final location in locations) location.text,
              for (final location in locations) ...location.aliases,
            }
            .map((value) => value.trim())
            .where((value) => value.length >= 2)
            .toList(growable: false)
          ..sort((a, b) => b.length.compareTo(a.length));
    if (namedTerms.isEmpty) {
      return items;
    }
    final sanitized = <SemanticSearchSemanticItem>[];
    for (final item in items) {
      var text = item.text;
      for (final term in namedTerms) {
        text = text.replaceAll(
          RegExp(RegExp.escape(term), caseSensitive: false),
          ' ',
        );
      }
      text = text
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAllMapped(
            RegExp(r'\s+([,.;:])'),
            (match) => match.group(1) ?? '',
          )
          .trim();
      if (text.isEmpty) {
        continue;
      }
      sanitized.add(
        SemanticSearchSemanticItem(text: text, weight: item.weight),
      );
    }
    return _normalizeSemanticWeights(sanitized);
  }

  bool _isPureMechanicalQuery(
    String rawQuery, {
    required List<SemanticSearchLocation> locations,
    required List<SemanticSearchTimeRange> timeRanges,
    required List<int> weekdays,
  }) {
    if (locations.isEmpty && timeRanges.isEmpty && weekdays.isEmpty) {
      return false;
    }
    if (locations.any(
      (location) => !_isAdministrativeLocation(location.type),
    )) {
      return false;
    }
    var remainder = rawQuery.trim().toLowerCase();
    final mechanicalTerms =
        <String>{
              for (final location in locations) location.text,
              for (final location in locations) ...location.aliases,
            }
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
          ..sort((a, b) => b.length.compareTo(a.length));
    for (final term in mechanicalTerms) {
      remainder = remainder.replaceAll(term, '');
    }
    remainder = remainder
        .replaceAll(
          RegExp(
            r'(今天|昨日|昨天|前天|明天|后天|本周|这周|上周|下周|本月|这个月|上个月|下个月|今年|去年|前年|明年|周末|星期[一二三四五六日天]|周[一二三四五六日天]|\d{4}\s*年|\d{1,2}\s*月|\d{1,2}\s*[日号])',
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'(照片|图片|相片|影像|记忆|回忆|拍摄|拍的|拍过的|找找|查找|搜索|寻找|看看|看一下|给我看|显示|所有|全部)',
          ),
          '',
        )
        .replaceAll(RegExp(r'(的|在|于|从|到|里|内|附近|周边|旁边)'), '')
        .replaceAll(RegExp(r'[\s,，.。;；:：\-_/\\()（）\[\]【】]+'), '')
        .trim();
    return remainder.isEmpty;
  }

  bool _isAdministrativeLocation(String type) {
    return const <String>{
      'country',
      'province',
      'city',
      'district',
      'development_zone',
      'township',
      'region_concept',
    }.contains(type);
  }

  SemanticSearchQueryType _requireQueryType(dynamic value) {
    final text = value?.toString().trim().toLowerCase();
    switch (text) {
      case 'metadata':
        return SemanticSearchQueryType.metadata;
      case 'attribute':
        return SemanticSearchQueryType.attribute;
      case 'concrete':
        return SemanticSearchQueryType.concrete;
      case 'abstract':
        return SemanticSearchQueryType.abstract;
      case 'collection':
        return SemanticSearchQueryType.collection;
      default:
        throw FormatException('search plan has invalid query_type');
    }
  }

  SemanticSearchTagStrictness _readTagStrictness(dynamic value) {
    final text = value?.toString().trim().toLowerCase();
    switch (text) {
      case 'strict':
        return SemanticSearchTagStrictness.strict;
      case 'optional':
        return SemanticSearchTagStrictness.optional;
      case 'prefer':
        return SemanticSearchTagStrictness.prefer;
      default:
        throw FormatException('search plan has invalid tag_strictness');
    }
  }

  SemanticSearchEstimatedResultCount _readEstimatedResultCount(dynamic value) {
    if (value is! Map) {
      throw FormatException('search plan has no estimated_result_count');
    }
    final min = _toInt(value['min']) ?? 0;
    final max = _toInt(value['max']) ?? 0;
    final confidence = (_toDouble(value['confidence']) ?? 0.0)
        .clamp(0.0, 1.0)
        .toDouble();
    return SemanticSearchEstimatedResultCount(
      min: min,
      max: max < min ? min : max,
      confidence: confidence,
    );
  }

  SemanticSearchAttributes _readAttributes(dynamic value) {
    if (value is! Map) {
      return const SemanticSearchAttributes();
    }
    const allowedMediaKinds = <String>{'image', 'dynamicImage', 'video'};
    final mediaKinds = _readStringList(
      value['media_kinds'],
    ).where(allowedMediaKinds.contains).toList(growable: false);
    return SemanticSearchAttributes(
      minFaceCount: _nonNegativeInt(value['min_face_count']),
      maxFaceCount: _nonNegativeInt(value['max_face_count']),
      minSmileProbability: _probability(value['min_smile_probability']),
      minJoyScore: _probability(value['min_joy_score']),
      mediaKinds: mediaKinds,
    );
  }

  int? _nonNegativeInt(dynamic value) {
    final result = _toInt(value);
    return result != null && result >= 0 ? result : null;
  }

  double? _probability(dynamic value) {
    final result = _toDouble(value);
    return result?.clamp(0.0, 1.0).toDouble();
  }

  Map<String, dynamic> _decodeJsonObject(String? response) {
    if (response == null || response.trim().isEmpty) {
      throw const FormatException('empty LLM response');
    }
    final decoded = jsonDecode(response.trim());
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const FormatException('LLM response is not a JSON object');
  }

  List<SemanticSearchSemanticItem> _normalizeSemanticWeights(
    List<SemanticSearchSemanticItem> items,
  ) {
    if (items.isEmpty) {
      return const <SemanticSearchSemanticItem>[];
    }
    final merged = <String, double>{};
    for (final item in items) {
      merged[item.text] = (merged[item.text] ?? 0.0) + item.weight;
    }
    final total = merged.values.fold<double>(0.0, (sum, item) => sum + item);
    if (total <= 0) {
      final weight = 1 / merged.length;
      return merged.keys
          .map((text) => SemanticSearchSemanticItem(text: text, weight: weight))
          .toList(growable: false);
    }
    return merged.entries
        .map(
          (entry) => SemanticSearchSemanticItem(
            text: entry.key,
            weight: entry.value / total,
          ),
        )
        .toList(growable: false);
  }

  String _readLocationType(dynamic value) {
    final text = value?.toString().trim().toLowerCase();
    const allowed = <String>{
      'country',
      'province',
      'city',
      'district',
      'scenic_area',
      'poi',
      'location',
      'development_zone',
      'township',
      'business_area',
      'neighborhood',
      'campus',
      'region_concept',
    };
    if (allowed.contains(text)) {
      return text == 'location' ? 'poi' : text!;
    }
    throw FormatException('search plan has invalid location type');
  }

  String _readGeoStrictness(dynamic value) {
    final text = value?.toString().trim().toLowerCase();
    return const <String>{'exact', 'broad', 'nearby'}.contains(text)
        ? text!
        : 'exact';
  }

  String? _readOptionalString(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  List<String> _readStringList(dynamic value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  int? _toTimestampMs(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final numeric = int.tryParse(text);
    if (numeric != null) {
      return numeric > 0 && numeric < 10000000000 ? numeric * 1000 : numeric;
    }
    return DateTime.tryParse(text)?.millisecondsSinceEpoch;
  }

  int? _readMinuteOfDay(dynamic value) {
    final text = value?.toString().trim() ?? '';
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
    if (match == null) {
      return null;
    }
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) {
      return null;
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return null;
    }
    return hour * 60 + minute;
  }

  int? _readUtcOffsetMinutes(dynamic value) {
    final text = value?.toString().trim() ?? '';
    final match = RegExp(r'^([+-])(\d{1,2}):(\d{2})$').firstMatch(text);
    if (match == null) {
      return null;
    }
    final sign = match.group(1) == '-' ? -1 : 1;
    final hours = int.tryParse(match.group(2) ?? '');
    final minutes = int.tryParse(match.group(3) ?? '');
    if (hours == null || minutes == null || hours > 14 || minutes > 59) {
      return null;
    }
    return sign * (hours * 60 + minutes);
  }

  int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  int? _readMonth(dynamic value) {
    final month = _toInt(value);
    return month != null && month >= 1 && month <= 12 ? month : null;
  }

  int? _readDayOfYear(dynamic value) {
    final day = _toInt(value);
    return day != null && day >= 1 && day <= 366 ? day : null;
  }

  int? _toMinuteOfDay(dynamic value) {
    final minute = _toInt(value);
    return minute != null && minute >= 0 && minute <= 1439 ? minute : null;
  }

  List<int> _readWeekdays(dynamic value) {
    if (value is! List) return const <int>[];
    return value
        .map(_toInt)
        .whereType<int>()
        .where((item) => item >= 1 && item <= 7)
        .toSet()
        .toList(growable: false);
  }

  double? _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  String _formatUtcOffset(Duration offset) {
    final totalMinutes = offset.inMinutes;
    final sign = totalMinutes < 0 ? '-' : '+';
    final absolute = totalMinutes.abs();
    final hours = absolute ~/ 60;
    final minutes = absolute % 60;
    return '$sign${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  bool _isSceneWord(String value) {
    const sceneWords = <String>{
      'beach',
      'grassland',
      'night view',
      'starry sky',
      'flower field',
      'park',
      'night',
      'sky',
    };
    return sceneWords.contains(value.trim().toLowerCase());
  }
}

const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

const String _parserSystemPrompt =
    'You are a query-planning agent for natural-language photo search. '
    'Return exactly one JSON object that can directly drive local retrieval. '
    'Do not explain, chat, or output Markdown.';

String _buildPlanRepairPrompt({
  required String rawQuery,
  required String? invalidResponse,
  required Object? error,
}) {
  return '''
The previous response could not be parsed or validated as a search plan.

User query:
$rawQuery

Validation error:
${error ?? 'unknown error'}

Invalid response:
${invalidResponse ?? ''}

Repair task:
Return exactly one corrected JSON object following the same schema. Keep all semantic phrases in English. Do not include Markdown or explanation.
''';
}
