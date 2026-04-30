import 'package:flutter/foundation.dart';
import '../data/tag_taxonomy_v2.dart';
import '../models/entity/photo_entity.dart';
import '../models/vo/semantic_search_models.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../utils/tag_sanitizer.dart';
import 'mobileclip_embedding_service.dart';
import 'semantic_matching_service.dart';
import 'semantic_query_parser_service.dart';

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

  static const double _positiveSemanticParticipationThreshold = 0.20;
  static const double _exactPositiveThreshold = 0.24;
  static const double _relatedSemanticThreshold = 0.14;
  static const double _rescueSemanticThreshold = 0.10;
  static const double _negativePenaltyAlpha = 0.6;
  static const double _minimumFinalScore = 0.03;
  static const int _maxResultsPerBucket = 240;

  static const String _messageNoExactRelated =
      '\u672a\u627e\u5230\u60a8\u6240\u9700\u7684\u56fe\u7247\uff0c\u53ea\u627e\u5230\u4e00\u4e9b\u76f8\u5173\u56fe\u7247\u3002';
  static const String _messageRelaxTimeLocation =
      '\u6ca1\u6709\u627e\u5230\u4e25\u683c\u6ee1\u8db3\u65f6\u95f4\u6216\u5730\u70b9\u6761\u4ef6\u7684\u56fe\u7247\uff0c\u5df2\u81ea\u52a8\u653e\u5bbd\u65f6\u95f4\u5730\u70b9\u6761\u4ef6\u7ee7\u7eed\u641c\u7d22\u3002';
  static const String _messageRelaxTimeOnly =
      '\u6ca1\u6709\u627e\u5230\u540c\u65f6\u6ee1\u8db3\u65f6\u95f4\u548c\u5730\u70b9\u7684\u56fe\u7247\uff0c\u5df2\u4f18\u5148\u4fdd\u7559\u65f6\u95f4\u6761\u4ef6\u3002';
  static const String _messageRelaxLocationOnly =
      '\u6ca1\u6709\u627e\u5230\u540c\u65f6\u6ee1\u8db3\u65f6\u95f4\u548c\u5730\u70b9\u7684\u56fe\u7247\uff0c\u5df2\u4f18\u5148\u4fdd\u7559\u5730\u70b9\u6761\u4ef6\u3002';
  static const String _messageLocationNeedsGeocode =
      '\u5f53\u524d\u5730\u70b9\u8fc7\u6ee4\u4f9d\u8d56\u7167\u7247\u5df2\u5b8c\u6210\u9006\u5730\u7406\u7f16\u7801\u7684\u7701\u5e02\u533a\u6587\u672c\uff0c\u672a\u627e\u5230\u53ef\u76f4\u63a5\u5339\u914d\u7684\u5730\u70b9\u7ed3\u679c\u3002';
  static const String _messageRelaxTagOrRecall =
      '\u672a\u627e\u5230\u4e25\u683c\u5339\u914d\u7684\u56fe\u7247\uff0c\u5df2\u81ea\u52a8\u653e\u5bbd\u6807\u7b7e\u6216\u53ec\u56de\u8bed\u4e49\u3002';

  Set<String>? _cachedLocations;

  Future<SemanticSearchResult> search(String rawQuery) async {
    final allPhotos = await _loadAllPhotos();
    final query = await _queryParser.parseQuery(
      rawQuery,
      locationDictionary: _cachedLocations ?? const <String>{},
    );
    return _searchParsedQuery(
      rawQuery: rawQuery,
      query: query,
      allPhotos: allPhotos,
    );
  }

  Future<SemanticSearchResult> searchWithQuery(SemanticSearchQuery query) async {
    final allPhotos = await _loadAllPhotos();
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
    final photos = allPhotos
        .where((photo) => photo.isAiAnalyzed)
        .toList(growable: false);
    final activeModelVersion = await _mobileClipEmbeddingService
        .getSelectedModelVersion();

    if (rawQuery.trim().isEmpty || allPhotos.isEmpty) {
      return _emptyResult(query, photos.length);
    }

    final strictMetadataCandidates = _filterByMetadata(allPhotos, query);
    final metadataCandidateCount = strictMetadataCandidates.length;

    if (query.isMetadataOnly ||
        (!query.hasPositiveSemantics && !query.hasNegativeSemantics)) {
      final metadataOnlyResult = _resolveMetadataOnlyCandidates(
        allPhotos,
        strictMetadataCandidates,
        query,
      );
      if (metadataOnlyResult.photos.isEmpty) {
        return _emptyResult(
          query,
          photos.length,
          usedFallback: metadataOnlyResult.usedFallback,
          relaxationMessage: metadataOnlyResult.message,
        );
      }
      final metadataOnlyPhotos = metadataOnlyResult.photos.toList(growable: false)
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return SemanticSearchResult(
        query: query,
        exactPhotos: metadataOnlyPhotos,
        relatedPhotos: const <PhotoEntity>[],
        hits: const <int, SemanticSearchHit>{},
        totalAnalyzedPhotos: photos.length,
        filteredCandidateCount: metadataOnlyPhotos.length,
        usedFallback: metadataOnlyResult.usedFallback,
        relaxationMessage: metadataOnlyResult.message,
        metadataCandidateCount: metadataCandidateCount,
        tagCandidateCount: metadataOnlyPhotos.length,
        noExactMatchMessage: null,
      );
    }

    final semanticMetadataCandidates = _filterByMetadata(photos, query);
    final primaryMetadataCandidates = semanticMetadataCandidates.isNotEmpty
        ? semanticMetadataCandidates
        : photos;
    final vectors = await _buildSemanticVectors(query);
    final primaryTagCandidates = _applyTagStrategy(
      primaryMetadataCandidates,
      query,
      allowRelax: false,
    );
    final primaryTagCandidateCount = primaryTagCandidates.length;

    final primaryScores = _scoreCandidates(
      primaryTagCandidates,
      activeModelVersion: activeModelVersion,
      positiveVectors: vectors.positiveVectors,
      negativeVectors: vectors.negativeVectors,
      coarseTags: query.coarseTags,
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
    final primaryRelatedHits = primaryScores.hits.values
        .where((hit) => !hit.isExactMatch)
        .toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));
    for (final hit in primaryRelatedHits) {
      relatedHits[hit.photoId] = hit;
    }

    var usedFallback = false;
    String? relaxationMessage;
    var tagCandidateCount = primaryTagCandidateCount;

    if (_shouldBroadenSearch(
      exactCount: exactPhotos.length,
      relatedCount: relatedHits.length,
      query: query,
    )) {
      final fallback = _runFallbackSearch(
        photos: photos,
        strictMetadataCandidates: strictMetadataCandidates,
        query: query,
        vectors: vectors,
        activeModelVersion: activeModelVersion,
      );
      usedFallback = fallback.usedFallback;
      relaxationMessage = fallback.message;
      if (fallback.tagCandidateCount > tagCandidateCount) {
        tagCandidateCount = fallback.tagCandidateCount;
      }
      for (final entry in fallback.hits.entries) {
        final current = relatedHits[entry.key];
        if (current == null || entry.value.score > current.score) {
          relatedHits[entry.key] = entry.value;
        }
      }
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
      exactPhotos: exactPhotos.take(_maxResultsPerBucket).toList(growable: false),
      relatedPhotos:
          relatedPhotos.take(_maxResultsPerBucket).toList(growable: false),
      hits: hits,
      totalAnalyzedPhotos: photos.length,
      filteredCandidateCount: exactPhotos.length + relatedPhotos.length,
      usedFallback: usedFallback,
      relaxationMessage: relaxationMessage,
      metadataCandidateCount: metadataCandidateCount,
      tagCandidateCount: tagCandidateCount,
      noExactMatchMessage:
          exactPhotos.isEmpty && relatedPhotos.isNotEmpty ? _messageNoExactRelated : null,
    );
  }

  Future<List<PhotoEntity>> _loadAllPhotos() async {
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final q = photoBox.query()
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    final photos = q.find();
    q.close();
    _cachedLocations = _buildLocationDictionary(photos);
    return photos;
  }

  SemanticSearchResult _emptyResult(
    SemanticSearchQuery query,
    int totalAnalyzedPhotos, {
    bool usedFallback = false,
    String? relaxationMessage,
  }) {
    return SemanticSearchResult(
      query: query,
      exactPhotos: const <PhotoEntity>[],
      relatedPhotos: const <PhotoEntity>[],
      hits: const <int, SemanticSearchHit>{},
      totalAnalyzedPhotos: totalAnalyzedPhotos,
      filteredCandidateCount: 0,
      usedFallback: usedFallback,
      relaxationMessage: relaxationMessage,
      metadataCandidateCount: 0,
      tagCandidateCount: 0,
      noExactMatchMessage: null,
    );
  }

  Set<String> _buildLocationDictionary(List<PhotoEntity> photos) {
    final dictionary = <String>{};
    for (final photo in photos) {
      for (final value in <String?>[
        photo.locationName,
        photo.district,
        photo.city,
        photo.province,
      ]) {
        final normalized = value?.trim() ?? '';
        if (normalized.isEmpty) {
          continue;
        }
        dictionary.add(normalized);
        final stripped = _stripLocationSuffix(normalized);
        if (stripped.length >= 2) {
          dictionary.add(stripped);
        }
      }
    }
    return dictionary;
  }

  List<PhotoEntity> _filterByMetadata(
    List<PhotoEntity> photos,
    SemanticSearchQuery query,
  ) {
    return photos.where((photo) {
      if (query.hasTimeConstraints && !_matchesAnyTimeRange(photo, query)) {
        return false;
      }
      if (query.hasLocationConstraints &&
          !_matchesAnyLocation(photo, query.locations)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  bool _matchesAnyTimeRange(PhotoEntity photo, SemanticSearchQuery query) {
    for (final range in query.timeRanges) {
      final start = range.startTimeMs;
      final end = range.endTimeMs;
      if (start != null && photo.timestamp < start) {
        continue;
      }
      if (end != null && photo.timestamp > end) {
        continue;
      }
      return true;
    }
    return false;
  }

  bool _matchesAnyLocation(
    PhotoEntity photo,
    List<SemanticSearchLocation> locations,
  ) {
    final locationParts = _photoLocationParts(photo);
    if (locationParts.isEmpty) {
      return false;
    }

    final locationText = locationParts.join(' ');
    for (final location in locations) {
      final text = location.text.trim();
      if (text.isEmpty) {
        continue;
      }
      final stripped = _stripLocationSuffix(text);
      if (locationText.contains(text) ||
          (stripped.isNotEmpty && locationText.contains(stripped))) {
        return true;
      }
    }
    return false;
  }

  List<PhotoEntity> _applyTagStrategy(
    List<PhotoEntity> candidates,
    SemanticSearchQuery query, {
    required bool allowRelax,
  }) {
    if (!query.hasCoarseTags) {
      return candidates;
    }

    final filtered = _filterByCoarseTags(candidates, query.coarseTags);
    switch (query.tagStrictness) {
      case SemanticSearchTagStrictness.strict:
        return filtered;
      case SemanticSearchTagStrictness.prefer:
        if (!allowRelax) {
          return filtered.isNotEmpty ? filtered : candidates;
        }
        return filtered;
      case SemanticSearchTagStrictness.optional:
        return allowRelax && filtered.isNotEmpty ? filtered : candidates;
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
    return photos.where((photo) {
      final coarseIds = _photoCoarseIds(photo);
      return coarseIds.any(targetIds.contains);
    }).toList(growable: false);
  }

  Future<_SemanticVectorBundle> _buildSemanticVectors(
    SemanticSearchQuery query,
  ) async {
    try {
      await _semanticService.warmUp();
      final positiveVectors = await Future.wait(
        query.positiveSemantics.map((item) async {
          return _SemanticVector(
            text: item.text,
            weight: item.weight,
            vector: await _semanticService.embedText(item.text),
          );
        }),
      );
      final recallVectors = await Future.wait(
        query.recallSemantics.map((item) async {
          return _SemanticVector(
            text: item.text,
            weight: item.weight,
            vector: await _semanticService.embedText(item.text),
          );
        }),
      );
      final negativeVectors = await Future.wait(
        query.negativeSemantics.map((item) async {
          return _SemanticVector(
            text: item.text,
            weight: item.weight,
            vector: await _semanticService.embedText(item.text),
          );
        }),
      );
      return _SemanticVectorBundle(
        positiveVectors: positiveVectors,
        recallVectors: recallVectors,
        negativeVectors: negativeVectors,
      );
    } catch (error) {
      debugPrint('SemanticPhotoSearchService build vectors failed: $error');
      return const _SemanticVectorBundle(
        positiveVectors: <_SemanticVector>[],
        recallVectors: <_SemanticVector>[],
        negativeVectors: <_SemanticVector>[],
      );
    }
  }

  _ScoreCandidatesResult _scoreCandidates(
    List<PhotoEntity> candidates, {
    required String activeModelVersion,
    required List<_SemanticVector> positiveVectors,
    required List<_SemanticVector> negativeVectors,
    required List<SemanticSearchCoarseTag> coarseTags,
    required List<SemanticSearchLocation> locations,
    bool forceAllRelated = false,
    double semanticThreshold = _relatedSemanticThreshold,
  }) {
    final hits = <int, SemanticSearchHit>{};
    for (final photo in candidates) {
      final hit = _scorePhoto(
        photo,
        activeModelVersion: activeModelVersion,
        positiveVectors: positiveVectors,
        negativeVectors: negativeVectors,
        coarseTags: coarseTags,
        locations: locations,
        forceAllRelated: forceAllRelated,
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
    required List<_SemanticVector> positiveVectors,
    required List<_SemanticVector> negativeVectors,
    required List<SemanticSearchCoarseTag> coarseTags,
    required List<SemanticSearchLocation> locations,
    required bool forceAllRelated,
    required double semanticThreshold,
  }) {
    if (positiveVectors.isEmpty) {
      return null;
    }

    final imageEmbedding = _readSearchEmbedding(
      photo,
      activeModelVersion: activeModelVersion,
    );
    if (imageEmbedding == null || imageEmbedding.isEmpty) {
      return null;
    }

    final positive = _scorePositiveSemantics(imageEmbedding, positiveVectors);
    if (positive.semanticScore < semanticThreshold) {
      return null;
    }

    final negative = _scoreNegativeSemantics(imageEmbedding, negativeVectors);
    final finalScore = positive.qualifiedPositiveScore -
        (_negativePenaltyAlpha * negative.negativeScore);

    final isExact = !forceAllRelated &&
        positive.qualifiedPositiveScore >= _exactPositiveThreshold &&
        finalScore >= _minimumFinalScore;
    final isRelated =
        positive.semanticScore >= semanticThreshold && finalScore >= _minimumFinalScore;
    if (!isExact && !isRelated) {
      return null;
    }

    final matchedCoarseTags = <String>[];
    final photoCoarseIds = _photoCoarseIds(photo);
    for (final coarseTag in coarseTags) {
      if (photoCoarseIds.contains(coarseTag.id)) {
        matchedCoarseTags.add(coarseTag.labelZh);
      }
    }

    final matchedLocations = <String>[];
    for (final location in locations) {
      if (_matchesAnyLocation(photo, <SemanticSearchLocation>[location])) {
        matchedLocations.add(location.text);
      }
    }

    final explanation = <String>[];
    if (positive.bestPositiveSemantic != null) {
      explanation.add('semantic: ${positive.bestPositiveSemantic}');
    }
    if (matchedCoarseTags.isNotEmpty) {
      explanation.add('coarse tags: ${matchedCoarseTags.join(' / ')}');
    }
    if (matchedLocations.isNotEmpty) {
      explanation.add('location: ${matchedLocations.join(' / ')}');
    }
    if (negative.bestNegativeSemantic != null && negative.negativeScore >= 0.18) {
      explanation.add('negative: ${negative.bestNegativeSemantic}');
    }
    if (forceAllRelated) {
      explanation.add('fallback related result');
    }

    return SemanticSearchHit(
      photoId: photo.id,
      score: finalScore,
      semanticScore: positive.semanticScore,
      qualifiedPositiveScore: positive.qualifiedPositiveScore,
      negativeScore: negative.negativeScore,
      coarseTagBonus: 0.0,
      matchedCoarseTags: matchedCoarseTags,
      matchedLocations: matchedLocations,
      bestPositiveSemantic: positive.bestPositiveSemantic,
      bestNegativeSemantic: negative.bestNegativeSemantic,
      explanation: explanation,
      isExactMatch: isExact && !forceAllRelated,
    );
  }

  List<double>? _readSearchEmbedding(
    PhotoEntity photo, {
    required String activeModelVersion,
  }) {
    // The merged architecture stores vectors in ObjectBox, but many existing
    // photos still only have legacy Isar embeddings. Search should remain
    // usable while the index is warming up or after a partial migration.
    return _photoEmbeddingIndexRepository.readEmbeddingForPhoto(
      photo,
      modelVersion: activeModelVersion,
      allowLegacyFallback: true,
    );
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

  _FallbackSearchResult _runFallbackSearch({
    required List<PhotoEntity> photos,
    required List<PhotoEntity> strictMetadataCandidates,
    required SemanticSearchQuery query,
    required _SemanticVectorBundle vectors,
    required String activeModelVersion,
  }) {
    final hits = <int, SemanticSearchHit>{};
    var usedFallback = false;
    String? message;
    var tagCandidateCount = 0;

    final relaxedMetadata = _relaxMetadataConstraints(
      photos,
      strictMetadataCandidates,
      query,
    );
    if (relaxedMetadata.usedFallback) {
      usedFallback = true;
      message = relaxedMetadata.message;
    }

    final levelOneCandidates = _applyTagStrategy(
      relaxedMetadata.photos,
      query,
      allowRelax: true,
    );
    tagCandidateCount = levelOneCandidates.length;
    final levelOneScores = _scoreCandidates(
      levelOneCandidates,
      activeModelVersion: activeModelVersion,
      positiveVectors: vectors.positiveVectors,
      negativeVectors: vectors.negativeVectors,
      coarseTags: query.coarseTags,
      locations: query.locations,
      forceAllRelated: true,
    );
    hits.addAll(levelOneScores.hits);

    if (_shouldBroadenSearch(
          exactCount: 0,
          relatedCount: hits.length,
          query: query,
        ) &&
        query.tagStrictness != SemanticSearchTagStrictness.strict) {
      final levelTwoCandidates = relaxedMetadata.photos;
      if (levelTwoCandidates.length > tagCandidateCount) {
        tagCandidateCount = levelTwoCandidates.length;
      }
      final levelTwoScores = _scoreCandidates(
        levelTwoCandidates,
        activeModelVersion: activeModelVersion,
        positiveVectors: vectors.positiveVectors,
        negativeVectors: vectors.negativeVectors,
        coarseTags: const <SemanticSearchCoarseTag>[],
        locations: query.locations,
        forceAllRelated: true,
      );
      for (final entry in levelTwoScores.hits.entries) {
        final existing = hits[entry.key];
        if (existing == null || entry.value.score > existing.score) {
          hits[entry.key] = entry.value;
        }
      }
      if (levelTwoScores.hits.isNotEmpty) {
        usedFallback = true;
        message ??= _messageRelaxTagOrRecall;
      }
    }

    if (_shouldBroadenSearch(
          exactCount: 0,
          relatedCount: hits.length,
          query: query,
        ) &&
        vectors.recallVectors.isNotEmpty) {
      final recallCandidates = query.tagStrictness == SemanticSearchTagStrictness.strict
          ? levelOneCandidates
          : relaxedMetadata.photos;
      final recallScores = _scoreCandidates(
        recallCandidates,
        activeModelVersion: activeModelVersion,
        positiveVectors: vectors.recallVectors,
        negativeVectors: vectors.negativeVectors,
        coarseTags: const <SemanticSearchCoarseTag>[],
        locations: query.locations,
        forceAllRelated: true,
        semanticThreshold: _rescueSemanticThreshold,
      );
      for (final entry in recallScores.hits.entries) {
        final existing = hits[entry.key];
        if (existing == null || entry.value.score > existing.score) {
          hits[entry.key] = entry.value;
        }
      }
      if (recallScores.hits.isNotEmpty) {
        usedFallback = true;
        message = _messageNoExactRelated;
      }
    }

    return _FallbackSearchResult(
      hits: hits,
      usedFallback: usedFallback,
      message: message,
      tagCandidateCount: tagCandidateCount,
    );
  }

  _MetadataRelaxationResult _relaxMetadataConstraints(
    List<PhotoEntity> allPhotos,
    List<PhotoEntity> strictMetadataCandidates,
    SemanticSearchQuery query,
  ) {
    if (!query.hasTimeConstraints && !query.hasLocationConstraints) {
      return _MetadataRelaxationResult(
        photos: strictMetadataCandidates,
        usedFallback: false,
        message: null,
      );
    }

    if (strictMetadataCandidates.isNotEmpty) {
      return _MetadataRelaxationResult(
        photos: strictMetadataCandidates,
        usedFallback: false,
        message: null,
      );
    }

    if (query.hasTimeConstraints && query.hasLocationConstraints) {
      final timeOnly = allPhotos
          .where((photo) => _matchesAnyTimeRange(photo, query))
          .toList(growable: false);
      final locationOnly = allPhotos
          .where((photo) => _matchesAnyLocation(photo, query.locations))
          .toList(growable: false);

      if (timeOnly.isNotEmpty || locationOnly.isNotEmpty) {
        final preferTime = timeOnly.length >= locationOnly.length;
        return _MetadataRelaxationResult(
          photos: preferTime ? timeOnly : locationOnly,
          usedFallback: true,
          message: preferTime ? _messageRelaxTimeOnly : _messageRelaxLocationOnly,
        );
      }
    }

    if (query.hasTimeConstraints || query.hasLocationConstraints) {
      return _MetadataRelaxationResult(
        photos: allPhotos,
        usedFallback: true,
        message: _messageRelaxTimeLocation,
      );
    }

    return _MetadataRelaxationResult(
      photos: allPhotos,
      usedFallback: false,
      message: null,
    );
  }

  _MetadataRelaxationResult _resolveMetadataOnlyCandidates(
    List<PhotoEntity> allPhotos,
    List<PhotoEntity> strictMetadataCandidates,
    SemanticSearchQuery query,
  ) {
    if (strictMetadataCandidates.isNotEmpty) {
      return _MetadataRelaxationResult(
        photos: strictMetadataCandidates,
        usedFallback: false,
        message: null,
      );
    }

    if (query.hasTimeConstraints && query.hasLocationConstraints) {
      final timeOnly = allPhotos
          .where((photo) => _matchesAnyTimeRange(photo, query))
          .toList(growable: false);
      final locationOnly = allPhotos
          .where((photo) => _matchesAnyLocation(photo, query.locations))
          .toList(growable: false);
      if (timeOnly.isNotEmpty || locationOnly.isNotEmpty) {
        final preferTime = timeOnly.length >= locationOnly.length;
        return _MetadataRelaxationResult(
          photos: preferTime ? timeOnly : locationOnly,
          usedFallback: true,
          message: preferTime ? _messageRelaxTimeOnly : _messageRelaxLocationOnly,
        );
      }
    }

    return _MetadataRelaxationResult(
      photos: const <PhotoEntity>[],
      usedFallback: false,
      message: query.hasLocationConstraints ? _messageLocationNeedsGeocode : null,
    );
  }

  bool _shouldBroadenSearch({
    required int exactCount,
    required int relatedCount,
    required SemanticSearchQuery query,
  }) {
    final total = exactCount + relatedCount;
    if (total == 0) {
      return true;
    }
    final estimate = query.estimatedResultCount;
    if (!estimate.isMeaningful) {
      return total < 3;
    }
    final expectedFloor = estimate.min > 0 ? estimate.min : estimate.max ~/ 4;
    final threshold = expectedFloor <= 0 ? 3 : expectedFloor.clamp(3, 24);
    return total < threshold;
  }

  double _positiveSimilarity(
    List<double> imageEmbedding,
    List<double> textVector,
  ) {
    if (imageEmbedding.length != textVector.length || imageEmbedding.isEmpty) {
      return 0.0;
    }
    final similarity =
        _semanticService.calculateSimilarity(imageEmbedding, textVector);
    if (!similarity.isFinite) {
      return 0.0;
    }
    return similarity.clamp(0.0, 1.0);
  }

  Set<String> _photoCoarseIds(PhotoEntity photo) {
    final tags = TagSanitizer.sanitizeVisualTags(photo.aiTags ?? const <String>[]);
    final coarseIds = <String>{};
    for (final tag in tags) {
      final coarseId = memoriaAlbumTagLabelToCoarseId[tag];
      if (coarseId != null && coarseId != memoriaOtherCoarseId) {
        coarseIds.add(coarseId);
      }
    }
    return coarseIds;
  }

  List<String> _photoLocationParts(PhotoEntity photo) {
    return <String?>[
      photo.locationName,
      photo.district,
      photo.city,
      photo.province,
      photo.formattedAddress,
    ]
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _stripLocationSuffix(String value) {
    return value
        .replaceAll(
          RegExp(
            '(\u7701|\u5e02|\u533a|\u53bf|\u81ea\u6cbb\u5dde|\u81ea\u6cbb\u533a|\u7279\u522b\u884c\u653f\u533a)\$',
          ),
          '',
        )
        .trim();
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

class _MetadataRelaxationResult {
  const _MetadataRelaxationResult({
    required this.photos,
    required this.usedFallback,
    required this.message,
  });

  final List<PhotoEntity> photos;
  final bool usedFallback;
  final String? message;
}

class _FallbackSearchResult {
  const _FallbackSearchResult({
    required this.hits,
    required this.usedFallback,
    required this.message,
    required this.tagCandidateCount,
  });

  final Map<int, SemanticSearchHit> hits;
  final bool usedFallback;
  final String? message;
  final int tagCandidateCount;
}
