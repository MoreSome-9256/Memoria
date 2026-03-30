import '../entity/photo_entity.dart';

enum SemanticSearchRouteType {
  shortSemantic,
  llmStructured,
  localFallback,
}

enum SemanticSearchQueryType {
  metadata,
  attribute,
  concrete,
  abstract,
  collection,
}

enum SemanticSearchTagStrictness {
  strict,
  prefer,
  optional,
}

class SemanticSearchTimeRange {
  const SemanticSearchTimeRange({
    required this.startTimeMs,
    required this.endTimeMs,
    required this.reason,
  });

  final int? startTimeMs;
  final int? endTimeMs;
  final String reason;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'start_time_ms': startTimeMs,
      'end_time_ms': endTimeMs,
      'reason': reason,
    };
  }
}

class SemanticSearchLocation {
  const SemanticSearchLocation({
    required this.text,
    required this.type,
  });

  final String text;
  final String type;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'text': text,
      'type': type,
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
  const SemanticSearchSemanticItem({
    required this.text,
    required this.weight,
  });

  final String text;
  final double weight;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'text': text,
      'weight': weight,
    };
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
    return <String, dynamic>{
      'min': min,
      'max': max,
      'confidence': confidence,
    };
  }
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
    required this.usedLlm,
    required this.llmConfigured,
    required this.parserSource,
    required this.debugJson,
    required this.notes,
  });

  factory SemanticSearchQuery.empty(String rawQuery) {
    return SemanticSearchQuery(
      rawQuery: rawQuery,
      routeType: SemanticSearchRouteType.localFallback,
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
      usedLlm: false,
      llmConfigured: false,
      parserSource: 'local',
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
  final bool usedLlm;
  final bool llmConfigured;
  final String parserSource;
  final String debugJson;
  final String notes;

  bool get hasTimeConstraints => timeRanges.isNotEmpty;
  bool get hasLocationConstraints => locations.isNotEmpty;
  bool get hasCoarseTags => coarseTags.isNotEmpty;
  bool get hasPositiveSemantics => positiveSemantics.isNotEmpty;
  bool get hasRecallSemantics => recallSemantics.isNotEmpty;
  bool get hasNegativeSemantics => negativeSemantics.isNotEmpty;
  bool get isShortSemanticRoute => routeType == SemanticSearchRouteType.shortSemantic;
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
    required this.usedFallback,
    required this.relaxationMessage,
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
  final bool usedFallback;
  final String? relaxationMessage;
  final int metadataCandidateCount;
  final int tagCandidateCount;
  final String? noExactMatchMessage;

  bool get hasExactMatches => exactPhotos.isNotEmpty;
  bool get hasRelatedMatches => relatedPhotos.isNotEmpty;
}
