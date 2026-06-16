// 语义照片搜索服务，串联查询解析、向量检索和结果排序。

import 'package:flutter/foundation.dart';
import '../models/entity/photo_entity.dart';
import '../models/vo/semantic_search_models.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import 'app_ai_settings_service.dart';
import 'mobileclip_embedding_service.dart';
import 'semantic_matching_service.dart';
import 'semantic_search_metadata_matcher.dart';
import 'semantic_query_parser_service.dart';
import 'photo_service.dart';
import 'photo_search_index_service.dart';
import 'place_resolver_service.dart';
import 'searchable_photo_policy.dart';
import 'semantic_query_plan_compiler.dart';
import '../utils/ocr_policy.dart';

class SemanticPhotoSearchService {
  SemanticPhotoSearchService._internal();

  static final SemanticPhotoSearchService _instance =
      SemanticPhotoSearchService._internal();

  factory SemanticPhotoSearchService() => _instance;

  final SemanticMatchingService _semanticService = SemanticMatchingService();
  final SemanticQueryParserService _queryParser = SemanticQueryParserService();
  final MobileClipEmbeddingService _mobileClipEmbeddingService =
      MobileClipEmbeddingService();
  final PhotoEmbeddingIndexRepository _photoEmbeddingIndexRepository =
      PhotoEmbeddingIndexRepository();
  final SemanticSearchMetadataMatcher _metadataMatcher =
      const SemanticSearchMetadataMatcher();
  final SemanticQueryPlanCompiler _queryPlanCompiler =
      const SemanticQueryPlanCompiler();

  static const double _positiveSemanticParticipationThreshold = 0.17;
  static const double _exactPositiveThreshold = 0.23;
  static const double _relatedSemanticThreshold = 0.17;
  static const double _negativePenaltyAlpha = 0.72;
  static const double _coarseTagBonus = 0.055;
  static const double _textFeatureMaxBonus = 0.22;
  static const double _textFeatureFallbackThreshold = 0.18;
  static const double _minimumFinalScore = 0.15;
  static const double _minimumRelatedFinalScore = 0.10;
  static const int _maxResultsPerBucket = 240;
  static const int _minimumRelatedBeforeRelaxing = 12;

  static const String _messageNoExactRelated = '没有找到完全匹配的照片，下面是可能相关的结果。';

  Future<SemanticSearchResult> search(String rawQuery) async {
    final query = await _resolvePlaces(await _queryParser.parseQuery(rawQuery));
    final photos = await _loadCandidatePhotos(query);
    return _searchParsedQuery(rawQuery: rawQuery, query: query, photos: photos);
  }

  Future<SemanticSearchResult> searchWithQuery(
    SemanticSearchQuery query,
  ) async {
    query = await _resolvePlaces(query);
    final photos = await _loadCandidatePhotos(query);
    return _searchParsedQuery(
      rawQuery: query.rawQuery,
      query: query,
      photos: photos,
    );
  }

  Future<SemanticSearchQuery> _resolvePlaces(SemanticSearchQuery query) async {
    if (query.locations.isEmpty) return query;
    final locations = await PlaceResolverService.instance.resolveAll(
      query.locations,
    );
    return query.copyWith(locations: locations);
  }

  Future<SemanticSearchResult> _searchParsedQuery({
    required String rawQuery,
    required SemanticSearchQuery query,
    required List<PhotoEntity> photos,
  }) async {
    final activeModelVersion = await _mobileClipEmbeddingService
        .getSelectedModelVersion();
    final totalAnalyzedPhotos = _countAnalyzedPhotos();

    if (rawQuery.trim().isEmpty) {
      return _emptyResult(query, totalAnalyzedPhotos);
    }

    final strictMetadataCandidates = _filterByMetadata(photos, query);
    final metadataCandidateCount = strictMetadataCandidates.length;
    debugPrint(
      '[semantic-search] query="$rawQuery" analyzed=$totalAnalyzedPhotos '
      'loaded=${photos.length} strictMetadata=$metadataCandidateCount '
      'locations=${query.locations.map((item) => '${item.text}:${item.type}').join('|')} '
      'time=${_debugTimeConstraints(query)} '
      'positive=${query.positiveSemantics.length} recall=${query.recallSemantics.length}',
    );

    if (query.isMetadataOnly ||
        (!query.hasPositiveSemantics && !query.hasNegativeSemantics)) {
      if (strictMetadataCandidates.isEmpty) {
        final possible = await _loadCandidatePhotos(query, relaxed: true);
        if (possible.isEmpty) return _emptyResult(query, totalAnalyzedPhotos);
        return SemanticSearchResult(
          query: query,
          exactPhotos: const <PhotoEntity>[],
          relatedPhotos: _sortMetadataOnlyPhotos(possible, query),
          hits: _metadataOnlyHits(possible, query, isExact: false),
          totalAnalyzedPhotos: totalAnalyzedPhotos,
          filteredCandidateCount: possible.length,
          metadataCandidateCount: 0,
          tagCandidateCount: possible.length,
          noExactMatchMessage: _messageNoExactRelated,
        );
      }
      final metadataOnlyPhotos = _sortMetadataOnlyPhotos(
        strictMetadataCandidates,
        query,
      );
      return SemanticSearchResult(
        query: query,
        exactPhotos: metadataOnlyPhotos,
        relatedPhotos: const <PhotoEntity>[],
        hits: _metadataOnlyHits(metadataOnlyPhotos, query, isExact: true),
        totalAnalyzedPhotos: totalAnalyzedPhotos,
        filteredCandidateCount: metadataOnlyPhotos.length,
        metadataCandidateCount: metadataCandidateCount,
        tagCandidateCount: metadataOnlyPhotos.length,
        noExactMatchMessage: null,
      );
    }

    _validateSemanticVectorInputs(query);

    final primaryMetadataCandidates = _filterByMetadata(photos, query);
    final vectors = await _buildSemanticVectors(query);
    final primaryTagCandidates = _applyTagStrategy(
      primaryMetadataCandidates,
      query,
    );
    final taggedCandidates = _filterByCoarseTags(
      primaryMetadataCandidates,
      query.coarseTags,
    );
    final primaryTagCandidateCount = taggedCandidates.length;

    final primaryScores = _scoreCandidates(
      primaryTagCandidates,
      activeModelVersion: activeModelVersion,
      vectors: vectors,
      coarseTags: query.coarseTags,
      tagStrictness: query.tagStrictness,
      locations: query.locations,
      rawQuery: rawQuery,
    );

    final exactPhotos = _orderedPhotosForHits(
      primaryTagCandidates,
      primaryScores.hits.values
          .where((hit) => hit.isExactMatch)
          .toList(growable: false)
        ..sort((a, b) => b.score.compareTo(a.score)),
    );

    final relatedHits = <int, SemanticSearchHit>{};
    var possibleCandidates = <PhotoEntity>[...primaryMetadataCandidates];
    final possibleIds = possibleCandidates.map((photo) => photo.id).toSet();
    final strictRelatedScores = _scoreCandidates(
      _applyTagStrategy(possibleCandidates, query),
      activeModelVersion: activeModelVersion,
      vectors: vectors,
      coarseTags: query.coarseTags,
      tagStrictness: query.tagStrictness,
      locations: query.locations,
      rawQuery: rawQuery,
      semanticThreshold: 0.10,
      forceRelated: true,
    );
    relatedHits.addAll(strictRelatedScores.hits);
    final exactIds = exactPhotos.map((photo) => photo.id).toSet();
    relatedHits.removeWhere((photoId, _) => exactIds.contains(photoId));

    if (relatedHits.length < _minimumRelatedBeforeRelaxing) {
      final relaxedCandidates = await _loadCandidatePhotos(
        query,
        relaxed: true,
      );
      for (final photo in relaxedCandidates) {
        if (possibleIds.add(photo.id)) {
          possibleCandidates.add(photo);
        }
      }
      final relaxedScores = _scoreCandidates(
        _applyTagStrategy(relaxedCandidates, query),
        activeModelVersion: activeModelVersion,
        vectors: vectors,
        coarseTags: query.coarseTags,
        tagStrictness: query.tagStrictness,
        locations: query.locations,
        rawQuery: rawQuery,
        semanticThreshold: 0.12,
        forceRelated: true,
      );
      for (final entry in relaxedScores.hits.entries) {
        if (!exactIds.contains(entry.key)) {
          relatedHits.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }

    final metadataFallbackHits = _metadataFallbackHitsIfNeeded(
      query: query,
      strictMetadataCandidates: strictMetadataCandidates
          .where((photo) => !exactIds.contains(photo.id))
          .toList(growable: false),
      existingRelatedHits: relatedHits,
    );
    if (metadataFallbackHits.isNotEmpty) {
      for (final photo in strictMetadataCandidates) {
        if (possibleIds.add(photo.id)) {
          possibleCandidates.add(photo);
        }
      }
      relatedHits.addAll(metadataFallbackHits);
      debugPrint(
        '[semantic-search] semantic fallback used '
        'metadataMatches=${metadataFallbackHits.length}',
      );
    }

    final textFallbackCandidates =
        (query.hasTimeConstraints ||
            query.hasLocationConstraints ||
            query.hasAttributeConstraints)
        ? strictMetadataCandidates
        : possibleCandidates;
    final textFallbackHits = _textFeatureFallbackHits(
      rawQuery: rawQuery,
      candidates: textFallbackCandidates,
      exactIds: exactIds,
      existingRelatedHits: relatedHits,
    );
    if (textFallbackHits.isNotEmpty) {
      for (final photo in textFallbackCandidates) {
        if (possibleIds.add(photo.id)) {
          possibleCandidates.add(photo);
        }
      }
      relatedHits.addAll(textFallbackHits);
      debugPrint(
        '[semantic-search] text fallback used '
        'textMatches=${textFallbackHits.length}',
      );
    }

    final relatedPhotos = _orderedPhotosForHits(
      possibleCandidates,
      relatedHits.values.toList(growable: false)
        ..sort((a, b) => b.score.compareTo(a.score)),
    );

    final hits = <int, SemanticSearchHit>{
      if (exactPhotos.isNotEmpty) ...primaryScores.hits,
      ...relatedHits,
    };
    debugPrint(
      '[semantic-search] result exact=${exactPhotos.length} '
      'related=${relatedPhotos.length} primaryScored=${primaryScores.hits.length} '
      'possibleLoaded=${possibleCandidates.length}',
    );

    return SemanticSearchResult(
      query: query,
      exactPhotos: exactPhotos
          .take(_maxResultsPerBucket)
          .toList(growable: false),
      relatedPhotos: relatedPhotos
          .take(_maxResultsPerBucket)
          .toList(growable: false),
      hits: hits,
      totalAnalyzedPhotos: totalAnalyzedPhotos,
      filteredCandidateCount: exactPhotos.length + relatedPhotos.length,
      metadataCandidateCount: metadataCandidateCount,
      tagCandidateCount: primaryTagCandidateCount,
      noExactMatchMessage: exactPhotos.isEmpty && relatedPhotos.isNotEmpty
          ? _messageNoExactRelated
          : null,
    );
  }

  Future<List<PhotoEntity>> _loadCandidatePhotos(
    SemanticSearchQuery query, {
    bool relaxed = false,
  }) async {
    await PhotoSearchIndexService.backfillMissingIndexes();
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final q = photoBox
        .query(_queryPlanCompiler.compile(query, relaxed: relaxed))
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    final photos = q.find();
    q.close();
    final settings = await AppAiSettingsService.instance.load();
    final accessible = await PhotoService().reconcileAccessiblePhotos(
      SearchablePhotoPolicy.filter(photos, settings: settings),
    );
    final located = accessible
        .where(
          (photo) =>
              (photo.locationName?.trim().isNotEmpty ?? false) ||
              (photo.formattedAddress?.trim().isNotEmpty ?? false) ||
              (photo.city?.trim().isNotEmpty ?? false) ||
              (photo.latAmapE6 != null && photo.lonAmapE6 != null),
        )
        .length;
    debugPrint(
      '[semantic-search] candidates relaxed=$relaxed objectBox=${photos.length} '
      'accessible=${accessible.length} located=$located',
    );
    return relaxed ? accessible : _filterByMetadata(accessible, query);
  }

  int _countAnalyzedPhotos() {
    final box = ObjectBoxService().store.box<PhotoEntity>();
    final query = box.query(PhotoEntity_.isAiAnalyzed.equals(true)).build();
    final count = query.count();
    query.close();
    return count;
  }

  List<PhotoEntity> _searchablePhotos(List<PhotoEntity> allPhotos) {
    return SearchablePhotoPolicy.filter(allPhotos);
  }

  void _validateSemanticVectorInputs(SemanticSearchQuery query) {
    if (query.isMetadataOnly) {
      return;
    }
    for (final entry
        in <({String field, List<SemanticSearchSemanticItem> items})>[
          (field: 'positive_semantics', items: query.positiveSemantics),
          (field: 'recall_semantics', items: query.recallSemantics),
          (field: 'negative_semantics', items: query.negativeSemantics),
        ]) {
      for (final item in entry.items) {
        if (item.containsCjk) {
          throw FormatException(
            '${entry.field} must contain English MobileCLIP prompts: ${item.text}',
          );
        }
      }
    }
  }

  @visibleForTesting
  List<PhotoEntity> searchablePhotosForTesting(List<PhotoEntity> allPhotos) {
    return _searchablePhotos(allPhotos);
  }

  @visibleForTesting
  List<PhotoEntity> metadataCandidatesForTesting(
    List<PhotoEntity> allPhotos,
    SemanticSearchQuery query,
  ) {
    return _filterByMetadata(_searchablePhotos(allPhotos), query);
  }

  @visibleForTesting
  void validateSemanticVectorInputsForTesting(SemanticSearchQuery query) {
    _validateSemanticVectorInputs(query);
  }

  SemanticSearchResult _emptyResult(
    SemanticSearchQuery query,
    int totalAnalyzedPhotos,
  ) {
    return SemanticSearchResult(
      query: query,
      exactPhotos: const <PhotoEntity>[],
      relatedPhotos: const <PhotoEntity>[],
      hits: const <int, SemanticSearchHit>{},
      totalAnalyzedPhotos: totalAnalyzedPhotos,
      filteredCandidateCount: 0,
      metadataCandidateCount: 0,
      tagCandidateCount: 0,
      noExactMatchMessage: null,
    );
  }

  List<PhotoEntity> _filterByMetadata(
    List<PhotoEntity> photos,
    SemanticSearchQuery query,
  ) {
    return photos
        .where((photo) {
          if (query.hasTimeConstraints && !_matchesAnyTimeRange(photo, query)) {
            return false;
          }
          if (query.hasLocationConstraints &&
              !_matchesAnyLocation(photo, query.locations)) {
            return false;
          }
          if (query.hasAttributeConstraints &&
              !_matchesAttributes(photo, query.attributes)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  bool _matchesAnyTimeRange(PhotoEntity photo, SemanticSearchQuery query) {
    return _metadataMatcher.matchesTime(photo, query);
  }

  String _debugTimeConstraints(SemanticSearchQuery query) {
    final parts = <String>[];
    for (final range in query.timeRanges) {
      if (range.hasLocalTimeWindow) {
        parts.add('minute:${range.localStartMinute}-${range.localEndMinute}');
      } else if (range.hasAnnualDayRange) {
        parts.add(
          'annual:${range.annualStartMonth}-${range.annualStartDayOfMonth}'
          '..${range.annualEndMonth}-${range.annualEndDayOfMonth}',
        );
      } else if (range.hasRecurringMonthRange) {
        parts.add(
          'month:${range.recurringStartMonth}-${range.recurringEndMonth}',
        );
      } else if (range.hasDateBoundary) {
        parts.add('absolute');
      }
    }
    if (query.weekdays.isNotEmpty) {
      parts.add('weekday:${query.weekdays.join(',')}');
    }
    return parts.isEmpty ? '-' : parts.join('|');
  }

  bool _matchesAnyLocation(
    PhotoEntity photo,
    List<SemanticSearchLocation> locations,
  ) {
    return _metadataMatcher.matchesLocation(photo, locations);
  }

  bool _matchesAttributes(
    PhotoEntity photo,
    SemanticSearchAttributes attributes,
  ) {
    final minFaces = attributes.minFaceCount;
    final maxFaces = attributes.maxFaceCount;
    final minSmile = attributes.minSmileProbability;
    final minJoy = attributes.minJoyScore;
    if (minFaces != null && photo.faceCount < minFaces) return false;
    if (maxFaces != null && photo.faceCount > maxFaces) return false;
    if (minSmile != null && photo.smileProb < minSmile) return false;
    if (minJoy != null && (photo.joyScore ?? 0) < minJoy) return false;
    if (attributes.mediaKinds.isNotEmpty &&
        !attributes.mediaKinds.contains(photo.mediaKind)) {
      return false;
    }
    return true;
  }

  List<PhotoEntity> _applyTagStrategy(
    List<PhotoEntity> candidates,
    SemanticSearchQuery query,
  ) {
    if (!query.hasCoarseTags) {
      return candidates;
    }

    final filtered = _filterByCoarseTags(candidates, query.coarseTags);
    switch (query.tagStrictness) {
      case SemanticSearchTagStrictness.strict:
        return filtered;
      case SemanticSearchTagStrictness.prefer:
      case SemanticSearchTagStrictness.optional:
        return candidates;
    }
  }

  List<PhotoEntity> _filterByCoarseTags(
    List<PhotoEntity> photos,
    List<SemanticSearchCoarseTag> coarseTags,
  ) {
    if (coarseTags.isEmpty) {
      return photos;
    }
    final targetIds = coarseTags.map((item) => item.id).toSet();
    return photos
        .where((photo) {
          final coarseIds = _metadataMatcher.photoCoarseIds(photo);
          return coarseIds.any(targetIds.contains);
        })
        .toList(growable: false);
  }

  Future<_SemanticVectorBundle> _buildSemanticVectors(
    SemanticSearchQuery query,
  ) async {
    try {
      await _semanticService.warmUp();
      final positiveVectors = <_SemanticVector>[];
      for (final item in query.positiveSemantics) {
        positiveVectors.add(
          _SemanticVector(
            text: item.text,
            weight: item.weight,
            vector: await _semanticService.embedText(item.text),
          ),
        );
      }
      final recallVectors = <_SemanticVector>[];
      for (final item in query.recallSemantics) {
        recallVectors.add(
          _SemanticVector(
            text: item.text,
            weight: item.weight,
            vector: await _semanticService.embedText(item.text),
          ),
        );
      }
      final negativeVectors = <_SemanticVector>[];
      for (final item in query.negativeSemantics) {
        negativeVectors.add(
          _SemanticVector(
            text: item.text,
            weight: item.weight,
            vector: await _semanticService.embedText(item.text),
          ),
        );
      }
      return _SemanticVectorBundle(
        positiveVectors: positiveVectors,
        recallVectors: recallVectors,
        negativeVectors: negativeVectors,
      );
    } catch (error) {
      throw StateError('语义向量模型不可用，无法完成本次搜索: $error');
    }
  }

  _ScoreCandidatesResult _scoreCandidates(
    List<PhotoEntity> candidates, {
    required String activeModelVersion,
    required _SemanticVectorBundle vectors,
    required List<SemanticSearchCoarseTag> coarseTags,
    required SemanticSearchTagStrictness tagStrictness,
    required List<SemanticSearchLocation> locations,
    required String rawQuery,
    double semanticThreshold = _relatedSemanticThreshold,
    bool forceRelated = false,
  }) {
    final hits = <int, SemanticSearchHit>{};
    for (final photo in candidates) {
      final hit = _scorePhoto(
        photo,
        activeModelVersion: activeModelVersion,
        vectors: vectors,
        coarseTags: coarseTags,
        tagStrictness: tagStrictness,
        locations: locations,
        rawQuery: rawQuery,
        semanticThreshold: semanticThreshold,
        forceRelated: forceRelated,
      );
      if (hit == null) {
        continue;
      }
      hits[photo.id] = hit;
    }
    return _ScoreCandidatesResult(hits: hits);
  }

  SemanticSearchHit? _scorePhoto(
    PhotoEntity photo, {
    required String activeModelVersion,
    required _SemanticVectorBundle vectors,
    required List<SemanticSearchCoarseTag> coarseTags,
    required SemanticSearchTagStrictness tagStrictness,
    required List<SemanticSearchLocation> locations,
    required String rawQuery,
    required double semanticThreshold,
    required bool forceRelated,
  }) {
    final embeddingChoice = _readSearchEmbedding(
      photo,
      activeModelVersion: activeModelVersion,
    );
    if (embeddingChoice == null || embeddingChoice.embedding.isEmpty) {
      return null;
    }

    final negativeVectors = vectors.negativeVectors;
    if (vectors.positiveVectors.isEmpty) {
      return null;
    }

    final primary = _scorePositiveSemantics(
      embeddingChoice.embedding,
      vectors.positiveVectors,
    );
    final recall = _scorePositiveSemantics(
      embeddingChoice.embedding,
      vectors.recallVectors,
    );
    if (primary.semanticScore < semanticThreshold &&
        recall.semanticScore < semanticThreshold) {
      return null;
    }

    final negative = _scoreNegativeSemantics(
      embeddingChoice.embedding,
      negativeVectors,
    );
    final coarseTagMatch = _metadataMatcher.matchCoarseTags(photo, coarseTags);
    final locationMatch = _metadataMatcher.matchLocation(photo, locations);
    final textFeatureMatch = _textFeatureMatch(photo, rawQuery);
    final tagBonus = coarseTagMatch.matchedLabels.isEmpty
        ? 0.0
        : _coarseTagBonus;
    final recallScore = recall.qualifiedPositiveScore * 0.9;
    final rankingSemanticScore = primary.qualifiedPositiveScore > recallScore
        ? primary.qualifiedPositiveScore
        : recallScore;
    final finalScore =
        rankingSemanticScore +
        tagBonus -
        (_negativePenaltyAlpha * negative.negativeScore) +
        textFeatureMatch.score;
    final coarseTagRequiredForExact =
        coarseTags.isNotEmpty &&
        tagStrictness == SemanticSearchTagStrictness.strict &&
        coarseTagMatch.matchedLabels.isEmpty;
    final coarseTagRequiredForRelated = coarseTagRequiredForExact;
    final minimumFinalScore = forceRelated
        ? _minimumRelatedFinalScore
        : _minimumFinalScore;

    final isExact =
        !forceRelated &&
        primary.qualifiedPositiveScore >= _exactPositiveThreshold &&
        !coarseTagRequiredForExact &&
        finalScore >= minimumFinalScore;
    final isRelated =
        !isExact &&
        (forceRelated
            ? rankingSemanticScore >= semanticThreshold
            : recall.qualifiedPositiveScore >= _relatedSemanticThreshold) &&
        !coarseTagRequiredForRelated &&
        finalScore >= minimumFinalScore;
    if (!isExact && !isRelated) {
      return null;
    }

    final matchedCoarseTags = coarseTagMatch.matchedLabels;
    final matchedLocations = locationMatch.matchedLocations;

    final explanation = <String>[];
    if (primary.bestPositiveSemantic != null) {
      explanation.add('primary semantic: ${primary.bestPositiveSemantic}');
    }
    if (!isExact && recall.bestPositiveSemantic != null) {
      explanation.add('recall semantic: ${recall.bestPositiveSemantic}');
    }
    if (matchedCoarseTags.isNotEmpty) {
      explanation.add('coarse tags: ${matchedCoarseTags.join(' / ')}');
    }
    if (matchedLocations.isNotEmpty) {
      explanation.add('location: ${matchedLocations.join(' / ')}');
    }
    if (textFeatureMatch.score > 0) {
      explanation.add(
        'text features: ${textFeatureMatch.matchedTerms.join(' / ')}',
      );
    }
    if (negative.bestNegativeSemantic != null &&
        negative.negativeScore >= 0.18) {
      explanation.add('negative: ${negative.bestNegativeSemantic}');
    }
    return SemanticSearchHit(
      photoId: photo.id,
      score: finalScore,
      semanticScore: primary.semanticScore > recall.semanticScore
          ? primary.semanticScore
          : recall.semanticScore,
      qualifiedPositiveScore: rankingSemanticScore,
      negativeScore: negative.negativeScore,
      coarseTagBonus: tagBonus,
      matchedCoarseTags: matchedCoarseTags,
      matchedLocations: matchedLocations,
      bestPositiveSemantic: primary.bestPositiveSemantic,
      bestNegativeSemantic: negative.bestNegativeSemantic,
      explanation: explanation,
      isExactMatch: isExact,
    );
  }

  List<PhotoEntity> _sortMetadataOnlyPhotos(
    List<PhotoEntity> photos,
    SemanticSearchQuery query,
  ) {
    final sorted = photos.toList(growable: false);
    sorted.sort((left, right) {
      if (query.locations.isNotEmpty) {
        final rightLocation = _bestLocationScore(right, query.locations);
        final leftLocation = _bestLocationScore(left, query.locations);
        final locationCompare = rightLocation.compareTo(leftLocation);
        if (locationCompare != 0) {
          return locationCompare;
        }
      }
      final rightText = _textFeatureMatch(right, query.rawQuery).score;
      final leftText = _textFeatureMatch(left, query.rawQuery).score;
      final textCompare = rightText.compareTo(leftText);
      if (textCompare != 0) {
        return textCompare;
      }
      return right.timestamp.compareTo(left.timestamp);
    });
    return sorted;
  }

  Map<int, SemanticSearchHit> _metadataOnlyHits(
    List<PhotoEntity> photos,
    SemanticSearchQuery query, {
    required bool isExact,
  }) {
    return <int, SemanticSearchHit>{
      for (final photo in photos)
        photo.id: _metadataOnlyHit(photo, query, isExact: isExact),
    };
  }

  Map<int, SemanticSearchHit> _metadataFallbackHitsIfNeeded({
    required SemanticSearchQuery query,
    required List<PhotoEntity> strictMetadataCandidates,
    required Map<int, SemanticSearchHit> existingRelatedHits,
  }) {
    if (strictMetadataCandidates.isEmpty ||
        (!query.hasTimeConstraints &&
            !query.hasLocationConstraints &&
            !query.hasAttributeConstraints)) {
      return const <int, SemanticSearchHit>{};
    }
    final hits = _metadataOnlyHits(
      strictMetadataCandidates,
      query,
      isExact: false,
    );
    return <int, SemanticSearchHit>{
      for (final entry in hits.entries)
        if (!existingRelatedHits.containsKey(entry.key)) entry.key: entry.value,
    };
  }

  bool _shouldUseGlobalPoiSemanticRecall(
    SemanticSearchQuery query,
    List<PhotoEntity> relaxedCandidates,
  ) {
    return false;
  }

  @visibleForTesting
  bool shouldUseGlobalPoiSemanticRecallForTesting(
    SemanticSearchQuery query,
    List<PhotoEntity> relaxedCandidates,
  ) {
    return _shouldUseGlobalPoiSemanticRecall(query, relaxedCandidates);
  }

  @visibleForTesting
  Map<int, SemanticSearchHit> metadataFallbackHitsForTesting({
    required SemanticSearchQuery query,
    required List<PhotoEntity> strictMetadataCandidates,
    Map<int, SemanticSearchHit> existingRelatedHits =
        const <int, SemanticSearchHit>{},
  }) {
    return _metadataFallbackHitsIfNeeded(
      query: query,
      strictMetadataCandidates: strictMetadataCandidates,
      existingRelatedHits: existingRelatedHits,
    );
  }

  SemanticSearchHit _metadataOnlyHit(
    PhotoEntity photo,
    SemanticSearchQuery query, {
    required bool isExact,
  }) {
    final location = _metadataMatcher.matchLocation(photo, query.locations);
    final textFeatureMatch = _textFeatureMatch(photo, query.rawQuery);
    final explanation = <String>[
      if (query.hasTimeConstraints) 'time filters matched',
      if (location.matchedLocations.isNotEmpty)
        'location: ${location.matchedLocations.join(' / ')}',
      if (query.hasAttributeConstraints) 'photo attributes matched',
      if (textFeatureMatch.score > 0)
        'text features: ${textFeatureMatch.matchedTerms.join(' / ')}',
      if (!isExact) 'relaxed metadata match',
    ];
    final locationScore = query.locations.isEmpty ? 1.0 : location.score;
    final score = locationScore + textFeatureMatch.score;
    return SemanticSearchHit(
      photoId: photo.id,
      score: isExact ? score : score * 0.8,
      semanticScore: 0,
      qualifiedPositiveScore: 0,
      negativeScore: 0,
      coarseTagBonus: 0,
      matchedCoarseTags: const <String>[],
      matchedLocations: location.matchedLocations,
      bestPositiveSemantic: null,
      bestNegativeSemantic: null,
      explanation: explanation,
      isExactMatch: isExact,
    );
  }

  Map<int, SemanticSearchHit> _textFeatureFallbackHits({
    required String rawQuery,
    required List<PhotoEntity> candidates,
    required Set<int> exactIds,
    required Map<int, SemanticSearchHit> existingRelatedHits,
  }) {
    final hits = <int, SemanticSearchHit>{};
    for (final photo in candidates) {
      if (exactIds.contains(photo.id) ||
          existingRelatedHits.containsKey(photo.id)) {
        continue;
      }
      final match = _textFeatureMatch(photo, rawQuery);
      if (match.score < _textFeatureFallbackThreshold) {
        continue;
      }
      hits[photo.id] = SemanticSearchHit(
        photoId: photo.id,
        score: match.score,
        semanticScore: 0,
        qualifiedPositiveScore: 0,
        negativeScore: 0,
        coarseTagBonus: 0,
        matchedCoarseTags: const <String>[],
        matchedLocations: const <String>[],
        bestPositiveSemantic: null,
        bestNegativeSemantic: null,
        explanation: <String>[
          'text fallback: ${match.matchedTerms.join(' / ')}',
        ],
        isExactMatch: false,
      );
    }
    return hits;
  }

  @visibleForTesting
  double textFeatureScoreForTesting(PhotoEntity photo, String rawQuery) {
    return _textFeatureMatch(photo, rawQuery).score;
  }

  _TextFeatureMatch _textFeatureMatch(PhotoEntity photo, String rawQuery) {
    final normalizedQuery = _normalizeTextForSearch(rawQuery);
    if (normalizedQuery.length < 2) {
      return const _TextFeatureMatch.empty();
    }
    final terms = _textSearchTerms(rawQuery);
    if (terms.isEmpty) {
      return const _TextFeatureMatch.empty();
    }

    final caption = _normalizeTextForSearch(photo.aiCaption ?? '');
    final ocrText = _normalizeTextForSearch(
      OcrPolicy.effectiveText(photo.ocrText),
    );
    final ocrTags = OcrPolicy.effectiveTags(photo.ocrTags ?? const <String>[])
        .map(_normalizeTextForSearch)
        .where((item) => item.length >= 2)
        .toList(growable: false);
    final sources = <({String label, String text})>[
      if (caption.isNotEmpty) (label: 'caption', text: caption),
      if (ocrText.isNotEmpty) (label: 'ocr', text: ocrText),
      if (ocrTags.isNotEmpty) (label: 'ocr_tags', text: ocrTags.join(' ')),
    ];
    if (sources.isEmpty) {
      return const _TextFeatureMatch.empty();
    }

    var score = 0.0;
    final matchedTerms = <String>{};
    for (final source in sources) {
      if (source.text.contains(normalizedQuery)) {
        score += source.label == 'caption' ? 0.18 : 0.26;
        matchedTerms.add(source.label);
      }
      for (final term in terms) {
        if (source.text.contains(term)) {
          score += source.label == 'caption' ? 0.035 : 0.055;
          matchedTerms.add(term);
        }
      }
    }
    if (matchedTerms.isEmpty) {
      return const _TextFeatureMatch.empty();
    }
    return _TextFeatureMatch(
      score: score.clamp(0.0, _textFeatureMaxBonus),
      matchedTerms: matchedTerms.take(8).toList(growable: false),
    );
  }

  List<String> _textSearchTerms(String rawQuery) {
    final normalized = _normalizeTextForSearch(rawQuery);
    final terms = <String>{};
    final cjkPattern = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+');
    for (final match in cjkPattern.allMatches(normalized)) {
      final text = match.group(0) ?? '';
      if (text.length >= 2) {
        terms.add(text);
      }
      if (text.length > 4) {
        for (var i = 0; i <= text.length - 2; i++) {
          terms.add(text.substring(i, i + 2));
        }
      }
    }
    final asciiPattern = RegExp(r'[a-z0-9][a-z0-9._-]*');
    for (final match in asciiPattern.allMatches(normalized)) {
      final text = match.group(0) ?? '';
      if (text.length >= 2) {
        terms.add(text);
      }
    }
    const stopWords = <String>{
      '照片',
      '图片',
      '相册',
      '搜索',
      '查找',
      '里面',
      '附近',
      '一些',
      '全部',
      '白天',
      '晚上',
    };
    terms.removeWhere(stopWords.contains);
    return terms.toList(growable: false);
  }

  String _normalizeTextForSearch(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'''[，。！？、；：,.!?;:"'“”‘’（）()\[\]{}<>《》]'''), '');
  }

  double _bestLocationScore(
    PhotoEntity photo,
    List<SemanticSearchLocation> locations,
  ) {
    var best = 0.0;
    for (final location in locations) {
      final score = _metadataMatcher.scoreLocation(photo, location);
      if (score > best) {
        best = score;
      }
    }
    return best;
  }

  _SearchEmbeddingChoice? _readSearchEmbedding(
    PhotoEntity photo, {
    required String activeModelVersion,
  }) {
    final embedding = _photoEmbeddingIndexRepository.readEmbeddingForPhoto(
      photo,
      modelVersion: activeModelVersion,
    );
    if (embedding == null || embedding.isEmpty) {
      return null;
    }
    return _SearchEmbeddingChoice(embedding: embedding);
  }

  _PositiveSemanticAggregate _scorePositiveSemantics(
    List<double> imageEmbedding,
    List<_SemanticVector> positiveVectors,
  ) {
    var semanticScore = 0.0;
    var qualifiedWeightedScore = 0.0;
    var qualifiedWeight = 0.0;
    var bestSimilarity = 0.0;
    String? bestSemantic;

    for (final item in positiveVectors) {
      final similarity = _positiveSimilarity(imageEmbedding, item.vector);
      semanticScore += item.weight * similarity;
      if (similarity >= _positiveSemanticParticipationThreshold) {
        qualifiedWeightedScore += item.weight * similarity;
        qualifiedWeight += item.weight;
      }
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestSemantic = item.text;
      }
    }

    final qualifiedPositiveScore = qualifiedWeight > 0
        ? qualifiedWeightedScore / qualifiedWeight
        : 0.0;
    return _PositiveSemanticAggregate(
      semanticScore: semanticScore,
      qualifiedPositiveScore: qualifiedPositiveScore,
      bestPositiveSemantic: bestSemantic,
    );
  }

  _NegativeSemanticAggregate _scoreNegativeSemantics(
    List<double> imageEmbedding,
    List<_SemanticVector> negativeVectors,
  ) {
    var score = 0.0;
    var bestSimilarity = 0.0;
    String? bestSemantic;

    for (final item in negativeVectors) {
      final similarity = _positiveSimilarity(imageEmbedding, item.vector);
      score += item.weight * similarity;
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestSemantic = item.text;
      }
    }

    return _NegativeSemanticAggregate(
      negativeScore: score,
      bestNegativeSemantic: bestSemantic,
    );
  }

  double _positiveSimilarity(
    List<double> imageEmbedding,
    List<double> textVector,
  ) {
    if (imageEmbedding.length != textVector.length || imageEmbedding.isEmpty) {
      return 0.0;
    }
    final similarity = _semanticService.calculateSimilarity(
      imageEmbedding,
      textVector,
    );
    if (!similarity.isFinite) {
      return 0.0;
    }
    return similarity.clamp(0.0, 1.0);
  }

  List<PhotoEntity> _orderedPhotosForHits(
    List<PhotoEntity> candidates,
    List<SemanticSearchHit> hits,
  ) {
    final photoById = <int, PhotoEntity>{
      for (final photo in candidates) photo.id: photo,
    };
    return hits
        .map((hit) => photoById[hit.photoId])
        .whereType<PhotoEntity>()
        .toList(growable: false);
  }
}

class _ScoreCandidatesResult {
  const _ScoreCandidatesResult({required this.hits});

  final Map<int, SemanticSearchHit> hits;
}

class _SemanticVectorBundle {
  const _SemanticVectorBundle({
    required this.positiveVectors,
    required this.recallVectors,
    required this.negativeVectors,
  });

  final List<_SemanticVector> positiveVectors;
  final List<_SemanticVector> recallVectors;
  final List<_SemanticVector> negativeVectors;
}

class _SemanticVector {
  const _SemanticVector({
    required this.text,
    required this.weight,
    required this.vector,
  });

  final String text;
  final double weight;
  final List<double> vector;
}

class _PositiveSemanticAggregate {
  const _PositiveSemanticAggregate({
    required this.semanticScore,
    required this.qualifiedPositiveScore,
    required this.bestPositiveSemantic,
  });

  final double semanticScore;
  final double qualifiedPositiveScore;
  final String? bestPositiveSemantic;
}

class _NegativeSemanticAggregate {
  const _NegativeSemanticAggregate({
    required this.negativeScore,
    required this.bestNegativeSemantic,
  });

  final double negativeScore;
  final String? bestNegativeSemantic;
}

class _TextFeatureMatch {
  const _TextFeatureMatch({required this.score, required this.matchedTerms});

  const _TextFeatureMatch.empty() : score = 0, matchedTerms = const <String>[];

  final double score;
  final List<String> matchedTerms;
}

class _SearchEmbeddingChoice {
  const _SearchEmbeddingChoice({required this.embedding});

  final List<double> embedding;
}
