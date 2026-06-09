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
  "query_type": "metadata | attribute | concrete | abstract | collection",
  "time_ranges": [],
  "local_time_windows": [],
  "locations": [],
  "coarse_tags": [],
  "tag_strictness": "strict | prefer | optional",
  "positive_semantics": [],
  "recall_semantics": [],
  "negative_semantics": [],
  "attributes": {"min_face_count": null, "max_face_count": null, "min_smile_probability": null, "min_joy_score": null, "media_kinds": []},
  "estimated_result_count": {"min": 0, "max": 0, "confidence": 0.0},
  "notes": ""
}

Rules:
0. Build a complete one-pass retrieval plan. The app will not ask you to reinterpret the query after retrieval. Separate non-negotiable metadata constraints from visual recall signals and describe every important part of the user's intent.
1. All values intended for visual or semantic matching must be English. MobileCLIP text alignment is English-first.
2. time_ranges are calendar/date constraints only. Use ISO 8601 strings with UTC offsets. For an unqualified recurring season such as "夏天", do not bind it to the current year; use {"recurring_start_month": 6, "recurring_end_month": 10}. Only use an absolute year when the user explicitly says this year, last year, or names a year.
3. local_time_windows are local time-of-day constraints such as night, morning, dusk, sunrise, or sunset. They are not date ranges. Include utc_offset when the place is known; otherwise still return the local window and leave utc_offset null.
4. For location queries, output a concise English canonical place name. Put the exact user-supplied surface form, native-language local names, common abbreviations, and romanizations in aliases. For scenic areas and POIs, aliases are critical. Do not enumerate nearby districts or tourist areas unless the user explicitly named them.
5. Do not put scene words such as beach, park, night view, grassland, or starry sky into locations unless they are part of an official place name.
6. A phrase such as "威海海边" contains a hard city constraint (Weihai) plus seaside visual semantics. Never replace it with another coastal city, and distinguish sea/coast from lakes and rivers with negative_semantics when needed.
7. Preserve specificity. "Qingdao West Coast" is more specific than "Qingdao"; "Nanjing Confucius Temple" is more specific than "Nanjing".
8. Choose coarse_tags only from the catalog below. Do not invent IDs. Use them as a high-precision index: include every clearly relevant category, but do not add a broad category merely because it could sometimes co-occur.
9. positive_semantics are the precision layer. Return 2 to 5 independent, concrete, visually observable English photo descriptions that jointly cover the required subject, scene, action, atmosphere, and distinguishing details. Avoid vague phrases such as "good memories" when concrete evidence exists.
10. recall_semantics are the controlled recall layer. Return 2 to 4 alternative visible formulations, synonyms, or compositions for the same intent. They may broaden appearance, but must never change explicit place, time, subject, medium, or scene type.
11. negative_semantics are contrastive exclusions. Add likely confusions and near-misses, not only screenshots. Examples: sea versus lake, food versus tableware, wedding versus ordinary group photo, snow versus bright clouds.
12. Set tag_strictness "strict" when a category is indispensable, "prefer" when it is strong evidence, and "optional" only when tags are genuinely not useful.
13. Use query_type "attribute" for measurable properties such as smiling people or group portraits; "metadata" only when no visual matching is needed.
   Put measurable requirements in attributes. Allowed media_kinds are image, dynamicImage, and video. Use conservative numeric thresholds: smiling usually means min_face_count 1 and min_smile_probability around 0.45; group photos usually mean min_face_count 2.
14. Do not use named places as a substitute for visible semantics. Put named places in locations, and separately describe what the desired scene should visibly contain.
15. If the query is ambiguous, choose the most literal interpretation and encode alternatives only in recall_semantics. Never invent a different city, event, or season.
16. Before returning, verify that every noun and modifier in the user query is represented by metadata, coarse_tags, positive_semantics, recall_semantics, or negative_semantics.

Available local indexes:
- timestamp and recurring month filters
- province, city, district, POI, and formatted address metadata
- coarse visual tags from the catalog
- MobileCLIP image/video embeddings
- limited face count, smile, and joy attributes

Few-shot examples:

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
    {"text": "a summer travel photo by the beach in Qingdao", "weight": 0.55},
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
    {"text": "a night sky photo full of stars in Hawaii", "weight": 0.7},
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
    {"id": "travel_landmark", "label_en": "travel landmark", "confidence": 0.86},
    {"id": "city_street", "label_en": "city street", "confidence": 0.58}
  ],
  "tag_strictness": "prefer",
  "positive_semantics": [
    {"text": "a travel photo at Nanjing Confucius Temple", "weight": 0.58},
    {"text": "a photo of traditional Chinese architecture and tourist streets", "weight": 0.42}
  ],
  "recall_semantics": [
    {"text": "a sightseeing photo of a historic temple area in Nanjing", "weight": 0.5},
    {"text": "a city travel photo with old buildings, lanterns, and a scenic street", "weight": 0.5}
  ],
  "negative_semantics": [
    {"text": "a screenshot of a text document or software interface", "weight": 1.0}
  ],
  "estimated_result_count": {"min": 1, "max": 80, "confidence": 0.65},
  "notes": "Keeps the POI specificity instead of reducing it to Nanjing."
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
    final queryType = _requireQueryType(jsonObject['query_type']);
    final timeRanges = _readTimeRanges(
      jsonObject['time_ranges'],
      localTimeWindows: jsonObject['local_time_windows'],
    );
    final normalizedTimeRanges = _normalizeRecurringSeason(
      rawQuery,
      timeRanges,
    );
    final locations = _readLocations(jsonObject['locations']);
    final coarseTags = _readCoarseTags(jsonObject['coarse_tags']);
    final positiveSemantics = _readSemanticItems(
      jsonObject['positive_semantics'],
    );
    final recallSemantics = _readSemanticItems(jsonObject['recall_semantics']);
    final negativeSemantics = _normalizeNegativeSemantics(
      rawQuery,
      _readSemanticItems(jsonObject['negative_semantics']),
    );
    final tagStrictness = _readTagStrictness(jsonObject['tag_strictness']);
    final estimatedResultCount = _readEstimatedResultCount(
      jsonObject['estimated_result_count'],
    );
    final attributes = _readAttributes(jsonObject['attributes']);

    _validateSearchPlan(
      queryType: queryType,
      locations: locations,
      positiveSemantics: positiveSemantics,
      recallSemantics: recallSemantics,
      estimatedResultCount: estimatedResultCount,
    );

    return SemanticSearchQuery(
      rawQuery: rawQuery,
      routeType: SemanticSearchRouteType.llmStructured,
      queryType: queryType,
      timeRanges: normalizedTimeRanges,
      locations: locations,
      coarseTags: coarseTags,
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
      usedLlm: usedLlm,
      llmConfigured: llmConfigured,
      parserSource: parserSource,
      debugJson: _prettyJson.convert(jsonObject),
      notes: (jsonObject['notes']?.toString().trim().isNotEmpty ?? false)
          ? '$baseNotes; ${jsonObject['notes'].toString().trim()}'
          : baseNotes,
    );
  }

  void _validateSearchPlan({
    required SemanticSearchQueryType queryType,
    required List<SemanticSearchLocation> locations,
    required List<SemanticSearchSemanticItem> positiveSemantics,
    required List<SemanticSearchSemanticItem> recallSemantics,
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
    if (!estimatedResultCount.isMeaningful) {
      throw FormatException('search plan has invalid result estimate');
    }
    for (final location in locations) {
      if (location.text.length < 2) {
        throw FormatException('search plan has invalid location');
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
    if (startTimeMs == null &&
        endTimeMs == null &&
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
    );
  }

  List<SemanticSearchTimeRange> _normalizeRecurringSeason(
    String rawQuery,
    List<SemanticSearchTimeRange> ranges,
  ) {
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
    final startMinute = _readMinuteOfDay(item['start']);
    final endMinute = _readMinuteOfDay(item['end']);
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
      );
      locations[location.text] = location;
    }
    return locations.values.toList(growable: false);
  }

  List<SemanticSearchSemanticItem> _normalizeNegativeSemantics(
    String rawQuery,
    List<SemanticSearchSemanticItem> items,
  ) {
    if (!rawQuery.contains('海边') || rawQuery.contains('湖')) {
      return items;
    }
    return _normalizeSemanticWeights(<SemanticSearchSemanticItem>[
      ...items,
      const SemanticSearchSemanticItem(
        text: 'a lake, lakeside, river, or riverside scene without the sea',
        weight: 1.0,
      ),
    ]);
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
    };
    if (allowed.contains(text)) {
      return text == 'location' ? 'poi' : text!;
    }
    throw FormatException('search plan has invalid location type');
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
