import '../entity/photo_entity.dart';

class SemanticSearchQuery {
  const SemanticSearchQuery({
    required this.rawQuery,
    required this.semanticQuery,
    required this.negativeSemanticQuery,
    required this.includeTags,
    required this.excludeTags,
    required this.includeLocations,
    required this.excludeLocations,
    required this.includeOcrTerms,
    required this.excludeOcrTerms,
    required this.allowScreenshots,
    required this.startTimeMs,
    required this.endTimeMs,
    required this.usedLlm,
    required this.llmConfigured,
    required this.parserSource,
    required this.debugJson,
  });

  factory SemanticSearchQuery.empty(String rawQuery) {
    return SemanticSearchQuery(
      rawQuery: rawQuery,
      semanticQuery: rawQuery.trim(),
      negativeSemanticQuery: '',
      includeTags: const <String>[],
      excludeTags: const <String>[],
      includeLocations: const <String>[],
      excludeLocations: const <String>[],
      includeOcrTerms: const <String>[],
      excludeOcrTerms: const <String>[],
      allowScreenshots: false,
      startTimeMs: null,
      endTimeMs: null,
      usedLlm: false,
      llmConfigured: false,
      parserSource: 'local',
      debugJson: '{}',
    );
  }

  final String rawQuery;
  final String semanticQuery;
  final String negativeSemanticQuery;
  final List<String> includeTags;
  final List<String> excludeTags;
  final List<String> includeLocations;
  final List<String> excludeLocations;
  final List<String> includeOcrTerms;
  final List<String> excludeOcrTerms;
  final bool allowScreenshots;
  final int? startTimeMs;
  final int? endTimeMs;
  final bool usedLlm;
  final bool llmConfigured;
  final String parserSource;
  final String debugJson;

  bool get hasSemanticQuery => semanticQuery.trim().isNotEmpty;
  bool get hasNegativeSemanticQuery => negativeSemanticQuery.trim().isNotEmpty;

  SemanticSearchQuery copyWith({
    String? rawQuery,
    String? semanticQuery,
    String? negativeSemanticQuery,
    List<String>? includeTags,
    List<String>? excludeTags,
    List<String>? includeLocations,
    List<String>? excludeLocations,
    List<String>? includeOcrTerms,
    List<String>? excludeOcrTerms,
    bool? allowScreenshots,
    int? startTimeMs,
    int? endTimeMs,
    bool? usedLlm,
    bool? llmConfigured,
    String? parserSource,
    String? debugJson,
  }) {
    return SemanticSearchQuery(
      rawQuery: rawQuery ?? this.rawQuery,
      semanticQuery: semanticQuery ?? this.semanticQuery,
      negativeSemanticQuery:
          negativeSemanticQuery ?? this.negativeSemanticQuery,
      includeTags: includeTags ?? this.includeTags,
      excludeTags: excludeTags ?? this.excludeTags,
      includeLocations: includeLocations ?? this.includeLocations,
      excludeLocations: excludeLocations ?? this.excludeLocations,
      includeOcrTerms: includeOcrTerms ?? this.includeOcrTerms,
      excludeOcrTerms: excludeOcrTerms ?? this.excludeOcrTerms,
      allowScreenshots: allowScreenshots ?? this.allowScreenshots,
      startTimeMs: startTimeMs ?? this.startTimeMs,
      endTimeMs: endTimeMs ?? this.endTimeMs,
      usedLlm: usedLlm ?? this.usedLlm,
      llmConfigured: llmConfigured ?? this.llmConfigured,
      parserSource: parserSource ?? this.parserSource,
      debugJson: debugJson ?? this.debugJson,
    );
  }
}

class SemanticSearchHit {
  const SemanticSearchHit({
    required this.photoId,
    required this.score,
    required this.semanticScore,
    required this.negativeScore,
    required this.tagScore,
    required this.ocrScore,
    required this.matchedTags,
    required this.matchedOcrTerms,
  });

  final int photoId;
  final double score;
  final double semanticScore;
  final double negativeScore;
  final double tagScore;
  final double ocrScore;
  final List<String> matchedTags;
  final List<String> matchedOcrTerms;
}

class SemanticSearchResult {
  const SemanticSearchResult({
    required this.query,
    required this.photos,
    required this.hitPhotoIds,
    required this.hits,
    required this.totalAnalyzedPhotos,
    required this.filteredCandidateCount,
    required this.usedFallback,
  });

  final SemanticSearchQuery query;
  final List<PhotoEntity> photos;
  final List<int> hitPhotoIds;
  final Map<int, SemanticSearchHit> hits;
  final int totalAnalyzedPhotos;
  final int filteredCandidateCount;
  final bool usedFallback;
}
