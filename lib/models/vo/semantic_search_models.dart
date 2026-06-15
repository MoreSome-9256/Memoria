/// 语义检索相关类型集合，定义查询严格度和路由模式等枚举。

import '../entity/photo_entity.dart';

enum SemanticSearchRouteType { llmStructured }

enum SemanticSearchQueryType {
  metadata,
  attribute,
  concrete,
  abstract,
  collection,
}

enum SemanticSearchTagStrictness { strict, prefer, optional }

class SemanticSearchTimeRange {
  const SemanticSearchTimeRange({
    required this.startTimeMs,
    required this.endTimeMs,
    required this.reason,
    this.startIso,
    this.endIso,
    this.timezone,
    this.utcOffsetMinutes,
    this.localStartMinute,
    this.localEndMinute,
    this.recurringStartMonth,
    this.recurringEndMonth,
    this.annualStartDay,
    this.annualEndDay,
  });

  final int? startTimeMs;
  final int? endTimeMs;
  final String reason;
  final String? startIso;
  final String? endIso;
  final String? timezone;
  final int? utcOffsetMinutes;
  final int? localStartMinute;
  final int? localEndMinute;
  final int? recurringStartMonth;
  final int? recurringEndMonth;
  final int? annualStartDay;
  final int? annualEndDay;

  bool get hasDateBoundary => startTimeMs != null || endTimeMs != null;
  bool get hasLocalTimeWindow =>
      localStartMinute != null && localEndMinute != null;
  bool get hasRecurringMonthRange =>
      recurringStartMonth != null && recurringEndMonth != null;
  bool get hasAnnualDayRange => annualStartDay != null && annualEndDay != null;
  bool get hasConstraint =>
      hasDateBoundary ||
      hasLocalTimeWindow ||
      hasRecurringMonthRange ||
      hasAnnualDayRange;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'start_time_ms': startTimeMs,
      'end_time_ms': endTimeMs,
      'start_iso': startIso,
      'end_iso': endIso,
      'timezone': timezone,
      'utc_offset_minutes': utcOffsetMinutes,
      'local_start_minute': localStartMinute,
      'local_end_minute': localEndMinute,
      'recurring_start_month': recurringStartMonth,
      'recurring_end_month': recurringEndMonth,
      'annual_start_day': annualStartDay,
      'annual_end_day': annualEndDay,
      'reason': reason,
    };
  }
}

class SemanticSearchLocation {
  const SemanticSearchLocation({
    required this.text,
    required this.type,
    this.aliases = const <String>[],
    this.timezone,
    this.utcOffsetMinutes,
    this.strictness = 'exact',
    this.allowDescendants = false,
    this.allowNearbySiblings = false,
    this.countryCandidates = const <String>[],
    this.amapPoiId,
    this.amapAoiId,
    this.adcode,
    this.centerLatAmapE6,
    this.centerLonAmapE6,
    this.coreRadiusMeters = 300,
    this.softRadiusMeters = 1000,
  });

  final String text;
  final String type;
  final List<String> aliases;
  final String? timezone;
  final int? utcOffsetMinutes;
  final String strictness;
  final bool allowDescendants;
  final bool allowNearbySiblings;
  final List<String> countryCandidates;
  final String? amapPoiId;
  final String? amapAoiId;
  final String? adcode;
  final int? centerLatAmapE6;
  final int? centerLonAmapE6;
  final int coreRadiusMeters;
  final int softRadiusMeters;

  bool get hasResolvedCenter =>
      centerLatAmapE6 != null && centerLonAmapE6 != null;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'text': text,
      'type': type,
      'aliases': aliases,
      'timezone': timezone,
      'utc_offset_minutes': utcOffsetMinutes,
      'strictness': strictness,
      'allow_descendants': allowDescendants,
      'allow_nearby_siblings': allowNearbySiblings,
      'country_candidates': countryCandidates,
      'amap_poi_id': amapPoiId,
      'amap_aoi_id': amapAoiId,
      'adcode': adcode,
      'center_lat_amap_e6': centerLatAmapE6,
      'center_lon_amap_e6': centerLonAmapE6,
      'core_radius_meters': coreRadiusMeters,
      'soft_radius_meters': softRadiusMeters,
    };
  }
}

class SemanticSearchCoarseTag {
  const SemanticSearchCoarseTag({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    required this.confidence,
  });

  final String id;
  final String labelZh;
  final String labelEn;
  final double confidence;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label_zh': labelZh,
      'label_en': labelEn,
      'confidence': confidence,
    };
  }
}

class SemanticSearchSemanticItem {
  const SemanticSearchSemanticItem({required this.text, required this.weight});

  static final RegExp _cjkPattern = RegExp(
    r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\u3040-\u30ff\uac00-\ud7af]',
  );

  final String text;
  final double weight;

  bool get containsCjk => _cjkPattern.hasMatch(text);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'text': text, 'weight': weight};
  }
}

class SemanticSearchEstimatedResultCount {
  const SemanticSearchEstimatedResultCount({
    required this.min,
    required this.max,
    required this.confidence,
  });

  final int min;
  final int max;
  final double confidence;

  bool get isMeaningful => max > 0 || min > 0;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'min': min, 'max': max, 'confidence': confidence};
  }
}

class SemanticSearchAttributes {
  const SemanticSearchAttributes({
    this.minFaceCount,
    this.maxFaceCount,
    this.minSmileProbability,
    this.minJoyScore,
    this.mediaKinds = const <String>[],
  });

  final int? minFaceCount;
  final int? maxFaceCount;
  final double? minSmileProbability;
  final double? minJoyScore;
  final List<String> mediaKinds;

  bool get hasConstraints =>
      minFaceCount != null ||
      maxFaceCount != null ||
      minSmileProbability != null ||
      minJoyScore != null ||
      mediaKinds.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'min_face_count': minFaceCount,
    'max_face_count': maxFaceCount,
    'min_smile_probability': minSmileProbability,
    'min_joy_score': minJoyScore,
    'media_kinds': mediaKinds,
  };
}

class SemanticSearchQuery {
  const SemanticSearchQuery({
    required this.rawQuery,
    required this.routeType,
    required this.queryType,
    required this.timeRanges,
    required this.locations,
    required this.coarseTags,
    required this.tagStrictness,
    required this.positiveSemantics,
    required this.recallSemantics,
    required this.negativeSemantics,
    required this.estimatedResultCount,
    required this.attributes,
    this.weekdays = const <int>[],
    required this.usedLlm,
    required this.llmConfigured,
    required this.parserSource,
    required this.debugJson,
    required this.notes,
  });

  factory SemanticSearchQuery.empty(String rawQuery) {
    return SemanticSearchQuery(
      rawQuery: rawQuery,
      routeType: SemanticSearchRouteType.llmStructured,
      queryType: SemanticSearchQueryType.metadata,
      timeRanges: const <SemanticSearchTimeRange>[],
      locations: const <SemanticSearchLocation>[],
      coarseTags: const <SemanticSearchCoarseTag>[],
      tagStrictness: SemanticSearchTagStrictness.optional,
      positiveSemantics: const <SemanticSearchSemanticItem>[],
      recallSemantics: const <SemanticSearchSemanticItem>[],
      negativeSemantics: const <SemanticSearchSemanticItem>[],
      estimatedResultCount: const SemanticSearchEstimatedResultCount(
        min: 0,
        max: 0,
        confidence: 0.0,
      ),
      attributes: const SemanticSearchAttributes(),
      usedLlm: false,
      llmConfigured: false,
      parserSource: 'empty',
      debugJson: '{}',
      notes: '',
    );
  }

  final String rawQuery;
  final SemanticSearchRouteType routeType;
  final SemanticSearchQueryType queryType;
  final List<SemanticSearchTimeRange> timeRanges;
  final List<SemanticSearchLocation> locations;
  final List<SemanticSearchCoarseTag> coarseTags;
  final SemanticSearchTagStrictness tagStrictness;
  final List<SemanticSearchSemanticItem> positiveSemantics;
  final List<SemanticSearchSemanticItem> recallSemantics;
  final List<SemanticSearchSemanticItem> negativeSemantics;
  final SemanticSearchEstimatedResultCount estimatedResultCount;
  final SemanticSearchAttributes attributes;
  final List<int> weekdays;
  final bool usedLlm;
  final bool llmConfigured;
  final String parserSource;
  final String debugJson;
  final String notes;

  bool get hasTimeConstraints =>
      weekdays.isNotEmpty || timeRanges.any((item) => item.hasConstraint);
  bool get hasLocationConstraints => locations.isNotEmpty;
  bool get hasCoarseTags => coarseTags.isNotEmpty;
  bool get hasPositiveSemantics => positiveSemantics.isNotEmpty;
  bool get hasRecallSemantics => recallSemantics.isNotEmpty;
  bool get hasNegativeSemantics => negativeSemantics.isNotEmpty;
  bool get hasAttributeConstraints => attributes.hasConstraints;
  bool get isMetadataOnly => queryType == SemanticSearchQueryType.metadata;

  List<String> get locationTexts =>
      locations.map((item) => item.text).toList(growable: false);

  List<String> get coarseTagLabels =>
      coarseTags.map((item) => item.labelZh).toList(growable: false);

  List<String> get positiveSemanticTexts =>
      positiveSemantics.map((item) => item.text).toList(growable: false);

  List<String> get recallSemanticTexts =>
      recallSemantics.map((item) => item.text).toList(growable: false);

  List<String> get negativeSemanticTexts =>
      negativeSemantics.map((item) => item.text).toList(growable: false);

  String get semanticQuery => positiveSemanticTexts.join(' | ');
  String get negativeSemanticQuery => negativeSemanticTexts.join(' | ');

  SemanticSearchQuery copyWith({
    String? rawQuery,
    SemanticSearchRouteType? routeType,
    SemanticSearchQueryType? queryType,
    List<SemanticSearchTimeRange>? timeRanges,
    List<SemanticSearchLocation>? locations,
    List<SemanticSearchCoarseTag>? coarseTags,
    SemanticSearchTagStrictness? tagStrictness,
    List<SemanticSearchSemanticItem>? positiveSemantics,
    List<SemanticSearchSemanticItem>? recallSemantics,
    List<SemanticSearchSemanticItem>? negativeSemantics,
    SemanticSearchEstimatedResultCount? estimatedResultCount,
    SemanticSearchAttributes? attributes,
    List<int>? weekdays,
    bool? usedLlm,
    bool? llmConfigured,
    String? parserSource,
    String? debugJson,
    String? notes,
  }) {
    return SemanticSearchQuery(
      rawQuery: rawQuery ?? this.rawQuery,
      routeType: routeType ?? this.routeType,
      queryType: queryType ?? this.queryType,
      timeRanges: timeRanges ?? this.timeRanges,
      locations: locations ?? this.locations,
      coarseTags: coarseTags ?? this.coarseTags,
      tagStrictness: tagStrictness ?? this.tagStrictness,
      positiveSemantics: positiveSemantics ?? this.positiveSemantics,
      recallSemantics: recallSemantics ?? this.recallSemantics,
      negativeSemantics: negativeSemantics ?? this.negativeSemantics,
      estimatedResultCount: estimatedResultCount ?? this.estimatedResultCount,
      attributes: attributes ?? this.attributes,
      weekdays: weekdays ?? this.weekdays,
      usedLlm: usedLlm ?? this.usedLlm,
      llmConfigured: llmConfigured ?? this.llmConfigured,
      parserSource: parserSource ?? this.parserSource,
      debugJson: debugJson ?? this.debugJson,
      notes: notes ?? this.notes,
    );
  }
}

class SemanticSearchHit {
  const SemanticSearchHit({
    required this.photoId,
    required this.score,
    required this.semanticScore,
    required this.qualifiedPositiveScore,
    required this.negativeScore,
    required this.coarseTagBonus,
    required this.matchedCoarseTags,
    required this.matchedLocations,
    required this.bestPositiveSemantic,
    required this.bestNegativeSemantic,
    required this.explanation,
    required this.isExactMatch,
  });

  final int photoId;
  final double score;
  final double semanticScore;
  final double qualifiedPositiveScore;
  final double negativeScore;
  final double coarseTagBonus;
  final List<String> matchedCoarseTags;
  final List<String> matchedLocations;
  final String? bestPositiveSemantic;
  final String? bestNegativeSemantic;
  final List<String> explanation;
  final bool isExactMatch;
}

class SemanticSearchResult {
  const SemanticSearchResult({
    required this.query,
    required this.exactPhotos,
    required this.relatedPhotos,
    required this.hits,
    required this.totalAnalyzedPhotos,
    required this.filteredCandidateCount,
    required this.metadataCandidateCount,
    required this.tagCandidateCount,
    required this.noExactMatchMessage,
  });

  final SemanticSearchQuery query;
  final List<PhotoEntity> exactPhotos;
  final List<PhotoEntity> relatedPhotos;
  final Map<int, SemanticSearchHit> hits;
  final int totalAnalyzedPhotos;
  final int filteredCandidateCount;
  final int metadataCandidateCount;
  final int tagCandidateCount;
  final String? noExactMatchMessage;

  bool get hasExactMatches => exactPhotos.isNotEmpty;
  bool get hasRelatedMatches => relatedPhotos.isNotEmpty;
}
