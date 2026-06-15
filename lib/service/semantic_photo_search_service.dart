// 语义照片搜索服务，串联查询解析、向量检索和结果排序。

import 'package:flutter/foundation.dart';
import '../models/entity/photo_entity.dart';
import '../models/vo/semantic_search_models.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import 'mobileclip_embedding_service.dart';
import 'semantic_matching_service.dart';
import 'semantic_search_metadata_matcher.dart';
import 'semantic_query_parser_service.dart';
import 'photo_service.dart';
import 'searchable_photo_policy.dart';

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

  static const double _positiveSemanticParticipationThreshold = 0.17;
  static const double _exactPositiveThreshold = 0.23;
  static const double _relatedSemanticThreshold = 0.17;
  static const double _negativePenaltyAlpha = 0.72;
  static const double _coarseTagBonus = 0.055;
  static const double _minimumFinalScore = 0.15;
  static const int _maxResultsPerBucket = 240;

  static const String _messageNoExactRelated = '未找到您所需的图片，只找到一些相关图片。';

  Future<SemanticSearchResult> search(String rawQuery) async {
    final allPhotos = await _loadSearchablePhotos();
    final query = await _queryParser.parseQuery(rawQuery);
    return _searchParsedQuery(
      rawQuery: rawQuery,
      query: query,
      allPhotos: allPhotos,
    );
  }

  Future<SemanticSearchResult> searchWithQuery(
    SemanticSearchQuery query,
  ) async {
    final allPhotos = await _loadSearchablePhotos();
    return _searchParsedQuery(
      rawQuery: query.rawQuery,
      query: query,
      allPhotos: allPhotos,
    );
  }

  Future<SemanticSearchResult> _searchParsedQuery({
    required String rawQuery,
    required SemanticSearchQuery query,
    required List<PhotoEntity> allPhotos,
  }) async {
    final photos = SearchablePhotoPolicy.filter(allPhotos);
    final activeModelVersion = await _mobileClipEmbeddingService
        .getSelectedModelVersion();

    if (rawQuery.trim().isEmpty || allPhotos.isEmpty) {
      return _emptyResult(query, photos.length);
    }

    final strictMetadataCandidates = _filterByMetadata(photos, query);
    final metadataCandidateCount = strictMetadataCandidates.length;

    if (query.isMetadataOnly ||
        (!query.hasPositiveSemantics && !query.hasNegativeSemantics)) {
      if (strictMetadataCandidates.isEmpty) {
        return _emptyResult(query, photos.length);
      }
      final metadataOnlyPhotos = _sortMetadataOnlyPhotos(
        strictMetadataCandidates,
        query,
      );
      return SemanticSearchResult(
        query: query,
        exactPhotos: metadataOnlyPhotos,
        relatedPhotos: const <PhotoEntity>[],
        hits: const <int, SemanticSearchHit>{},
        totalAnalyzedPhotos: photos.length,
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
    );

    final exactPhotos = _orderedPhotosForHits(
      primaryTagCandidates,
      primaryScores.hits.values
          .where((hit) => hit.isExactMatch)
          .toList(growable: false)
        ..sort((a, b) => b.score.compareTo(a.score)),
    );

    final relatedHits = <int, SemanticSearchHit>{};
    final primaryRelatedHits =
        primaryScores.hits.values
            .where((hit) => !hit.isExactMatch)
            .toList(growable: false)
          ..sort((a, b) => b.score.compareTo(a.score));
    for (final hit in primaryRelatedHits) {
      relatedHits[hit.photoId] = hit;
    }

    for (final photo in exactPhotos) {
      relatedHits.remove(photo.id);
    }

    final relatedPhotos = _orderedPhotosForHits(
      photos,
      relatedHits.values.toList(growable: false)
        ..sort((a, b) => b.score.compareTo(a.score)),
    );

    final hits = <int, SemanticSearchHit>{
      ...primaryScores.hits,
      ...relatedHits,
    };

    return SemanticSearchResult(
      query: query,
      exactPhotos: exactPhotos
          .take(_maxResultsPerBucket)
          .toList(growable: false),
      relatedPhotos: relatedPhotos
          .take(_maxResultsPerBucket)
          .toList(growable: false),
      hits: hits,
      totalAnalyzedPhotos: photos.length,
      filteredCandidateCount: exactPhotos.length + relatedPhotos.length,
      metadataCandidateCount: metadataCandidateCount,
      tagCandidateCount: primaryTagCandidateCount,
      noExactMatchMessage: exactPhotos.isEmpty && relatedPhotos.isNotEmpty
          ? _messageNoExactRelated
          : null,
    );
  }

  Future<List<PhotoEntity>> _loadSearchablePhotos() async {
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final q = photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(true))
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    final photos = q.find();
    q.close();
    return PhotoService().reconcileAccessiblePhotos(
      SearchablePhotoPolicy.filter(photos),
    );
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
    double semanticThreshold = _relatedSemanticThreshold,
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
        semanticThreshold: semanticThreshold,
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
    required double semanticThreshold,
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
        (_negativePenaltyAlpha * negative.negativeScore);
    final coarseTagRequiredForExact =
        coarseTags.isNotEmpty &&
        tagStrictness != SemanticSearchTagStrictness.optional &&
        coarseTagMatch.matchedLabels.isEmpty;
    final coarseTagRequiredForRelated =
        coarseTags.isNotEmpty &&
        tagStrictness != SemanticSearchTagStrictness.optional &&
        coarseTagMatch.matchedLabels.isEmpty;

    final isExact =
        primary.qualifiedPositiveScore >= _exactPositiveThreshold &&
        !coarseTagRequiredForExact &&
        finalScore >= _minimumFinalScore;
    final isRelated =
        !isExact &&
        recall.qualifiedPositiveScore >= _relatedSemanticThreshold &&
        !coarseTagRequiredForRelated &&
        finalScore >= _minimumFinalScore;
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
      return right.timestamp.compareTo(left.timestamp);
    });
    return sorted;
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

class _SearchEmbeddingChoice {
  const _SearchEmbeddingChoice({required this.embedding});

  final List<double> embedding;
}
