import 'package:isar/isar.dart';
import 'package:flutter/foundation.dart';

import '../data/tag_taxonomy_v2.dart';
import '../models/entity/photo_entity.dart';
import '../models/vo/semantic_search_models.dart';
import '../utils/ocr_policy.dart';
import '../utils/tag_sanitizer.dart';
import 'photo_service.dart';
import 'semantic_matching_service.dart';
import 'semantic_query_parser_service.dart';

class SemanticPhotoSearchService {
  SemanticPhotoSearchService._internal();

  static final SemanticPhotoSearchService _instance =
      SemanticPhotoSearchService._internal();

  factory SemanticPhotoSearchService() => _instance;

  final SemanticMatchingService _semanticService = SemanticMatchingService();
  final SemanticQueryParserService _queryParser = SemanticQueryParserService();

  static const double _minSemanticScore = 0.08;
  static const double _negativePenaltyAlpha = 0.22;
  static const int _maxResults = 240;

  Set<String>? _cachedLocations;

  Future<SemanticSearchResult> search(String rawQuery) async {
    final photos = await _loadAnalyzedPhotos();
    final locationDictionary = _cachedLocations ?? const <String>{};
    final query = await _queryParser.parseQuery(
      rawQuery,
      locationDictionary: locationDictionary,
    );

    if (rawQuery.trim().isEmpty || photos.isEmpty) {
      return SemanticSearchResult(
        query: query,
        photos: const <PhotoEntity>[],
        hitPhotoIds: const <int>[],
        hits: const <int, SemanticSearchHit>{},
        totalAnalyzedPhotos: photos.length,
        filteredCandidateCount: 0,
        usedFallback: false,
      );
    }

    final resolvedTaxonomyLabel = _resolveTaxonomyLabel(query.semanticQuery);
    final candidates = photos.where(
      (photo) => _matchesStructuredFilters(
        photo,
        query,
        resolvedTaxonomyLabel: resolvedTaxonomyLabel,
      ),
    );
    final candidateList = candidates.toList(growable: false);
    if (candidateList.isEmpty) {
      return SemanticSearchResult(
        query: query,
        photos: const <PhotoEntity>[],
        hitPhotoIds: const <int>[],
        hits: const <int, SemanticSearchHit>{},
        totalAnalyzedPhotos: photos.length,
        filteredCandidateCount: 0,
        usedFallback: false,
      );
    }

    List<double>? positiveVector;
    List<double>? negativeVector;
    List<List<double>> includeTagVectors = const <List<double>>[];
    List<List<double>> excludeTagVectors = const <List<double>>[];
    try {
      if (query.hasSemanticQuery ||
          query.hasNegativeSemanticQuery ||
          query.includeTags.isNotEmpty ||
          query.excludeTags.isNotEmpty ||
          resolvedTaxonomyLabel != null) {
        await _semanticService.warmUp();
      }
      if (query.hasSemanticQuery) {
        positiveVector = await _semanticService.embedText(
          _resolveSemanticPrompt(query),
        );
      }
      if (query.hasNegativeSemanticQuery) {
        negativeVector = await _semanticService.embedText(
          _resolveNegativePrompt(query),
        );
      }
      final includeSemanticLabels = query.includeTags.isNotEmpty
          ? query.includeTags
          : resolvedTaxonomyLabel == null
          ? const <String>[]
          : <String>[resolvedTaxonomyLabel];
      includeTagVectors = await _buildPromptVectors(includeSemanticLabels);
      excludeTagVectors = await _buildPromptVectors(query.excludeTags);
    } catch (error) {
      debugPrint('⚠️ 语义搜索文本向量构建失败，回退到标签检索: $error');
    }

    final hitMap = <int, SemanticSearchHit>{};
    for (final photo in candidateList) {
      final hit = _scorePhoto(
        photo,
        query: query,
        positiveVector: positiveVector,
        negativeVector: negativeVector,
        includeTagVectors: includeTagVectors,
        excludeTagVectors: excludeTagVectors,
      );
      if (hit == null) {
        continue;
      }
      hitMap[photo.id] = hit;
    }

    final sortedHits = hitMap.values.toList(growable: false)
      ..sort((a, b) => b.score.compareTo(a.score));
    var usedFallback = false;
    var finalHits = sortedHits.where((hit) => _isAcceptedHit(hit, query)).toList(
      growable: false,
    );

    if (finalHits.isEmpty) {
      finalHits = _fallbackTagMatches(
        candidateList,
        query,
        resolvedTaxonomyLabel: resolvedTaxonomyLabel,
      );
      usedFallback = finalHits.isNotEmpty;
    }

    finalHits = finalHits.take(_maxResults).toList(growable: false);
    final orderedIds = finalHits.map((hit) => hit.photoId).toList(growable: false);
    final photoById = <int, PhotoEntity>{
      for (final photo in candidateList) photo.id: photo,
    };
    final orderedPhotos = orderedIds
        .map((id) => photoById[id])
        .whereType<PhotoEntity>()
        .toList(growable: false);

    return SemanticSearchResult(
      query: query,
      photos: orderedPhotos,
      hitPhotoIds: orderedIds,
      hits: hitMap,
      totalAnalyzedPhotos: photos.length,
      filteredCandidateCount: candidateList.length,
      usedFallback: usedFallback,
    );
  }

  Future<List<PhotoEntity>> _loadAnalyzedPhotos() async {
    final photos = await PhotoService()
        .isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .sortByTimestampDesc()
        .findAll();
    _cachedLocations = _buildLocationDictionary(photos);
    return photos;
  }

  Set<String> _buildLocationDictionary(List<PhotoEntity> photos) {
    final allLocations = <String>{};
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
        allLocations.add(normalized);
        final stripped = normalized
            .replaceAll(RegExp(r'[省市自治区县盟旗]'), '')
            .trim();
        if (stripped.length >= 2) {
          allLocations.add(stripped);
        }
      }
    }
    return allLocations;
  }

  bool _matchesStructuredFilters(
    PhotoEntity photo,
    SemanticSearchQuery query, {
    String? resolvedTaxonomyLabel,
  }) {
    if (!query.allowScreenshots && photo.isProbablyScreenshot) {
      return false;
    }
    if (query.startTimeMs != null && photo.timestamp < query.startTimeMs!) {
      return false;
    }
    if (query.endTimeMs != null && photo.timestamp > query.endTimeMs!) {
      return false;
    }

    final locationText = _photoLocationText(photo);
    if (query.includeLocations.isNotEmpty &&
        !query.includeLocations.any((locationText.contains))) {
      return false;
    }
    if (query.excludeLocations.any(locationText.contains)) {
      return false;
    }

    final tags = TagSanitizer.sanitizeVisualTags(photo.aiTags ?? const <String>[]);
    if (query.excludeTags.any(tags.contains)) {
      return false;
    }

    final ocrTerms = _photoOcrTerms(photo);
    if (query.includeOcrTerms.isNotEmpty &&
        !query.includeOcrTerms.any((term) => _containsKeyword(ocrTerms, term))) {
      return false;
    }
    if (query.excludeOcrTerms.any((term) => _containsKeyword(ocrTerms, term))) {
      return false;
    }
    return true;
  }

  SemanticSearchHit? _scorePhoto(
    PhotoEntity photo, {
    required SemanticSearchQuery query,
    required List<double>? positiveVector,
    required List<double>? negativeVector,
    required List<List<double>> includeTagVectors,
    required List<List<double>> excludeTagVectors,
  }) {
    final tags = TagSanitizer.sanitizeVisualTags(photo.aiTags ?? const <String>[]);
    final ocrTerms = _photoOcrTerms(photo);
    final matchedTags = query.includeTags.where(tags.contains).toList(growable: false);
    final matchedOcrTerms = query.includeOcrTerms
        .where((term) => _containsKeyword(ocrTerms, term))
        .toList(growable: false);

    final embedding = photo.imageEmbedding;
    var semanticScore = 0.0;
    var negativeScore = 0.0;
    var includeTagVectorScore = 0.0;
    var excludeTagVectorScore = 0.0;
    if (positiveVector != null &&
        embedding != null &&
        embedding.isNotEmpty &&
        embedding.length == positiveVector.length) {
      semanticScore = _semanticService.calculateSimilarity(positiveVector, embedding);
    }
    if (negativeVector != null &&
        embedding != null &&
        embedding.isNotEmpty &&
        embedding.length == negativeVector.length) {
      negativeScore = _semanticService
          .calculateSimilarity(negativeVector, embedding)
          .clamp(0.0, 1.0);
    }
    if (embedding != null && embedding.isNotEmpty) {
      includeTagVectorScore = _bestVectorSimilarity(embedding, includeTagVectors);
      excludeTagVectorScore = _bestVectorSimilarity(embedding, excludeTagVectors);
    }

    var tagScore = 0.0;
    if (query.includeTags.isNotEmpty) {
      tagScore += 0.12 * (matchedTags.length / query.includeTags.length);
    }
    if (includeTagVectorScore > 0) {
      tagScore += includeTagVectorScore * 0.42;
    }
    if (query.includeTags.isEmpty &&
        includeTagVectorScore <= 0 &&
        query.hasSemanticQuery) {
      final resolvedLabel = _resolveTaxonomyLabel(query.semanticQuery);
      if (resolvedLabel != null && tags.contains(resolvedLabel)) {
        tagScore += 0.10;
      }
    }

    var ocrScore = 0.0;
    if (query.includeOcrTerms.isNotEmpty) {
      ocrScore += 0.10 * (matchedOcrTerms.length / query.includeOcrTerms.length);
    }

    final textBoost = _buildTextBoost(photo, query);
    final recencyBoost = _buildRecencyBoost(photo);
    final hasOnlyStructuredFilter =
        !query.hasSemanticQuery &&
        query.includeTags.isEmpty &&
        query.includeOcrTerms.isEmpty;
    final score =
        semanticScore +
        tagScore +
        ocrScore +
        textBoost +
        recencyBoost -
        (_negativePenaltyAlpha * (negativeScore + excludeTagVectorScore));

    final hasStructuredSignal = matchedTags.isNotEmpty || matchedOcrTerms.isNotEmpty;
    if (!hasOnlyStructuredFilter &&
        !query.hasSemanticQuery &&
        !hasStructuredSignal &&
        textBoost <= 0) {
      return null;
    }

    return SemanticSearchHit(
      photoId: photo.id,
      score: score,
      semanticScore: semanticScore,
      negativeScore: negativeScore + excludeTagVectorScore,
      tagScore: tagScore + textBoost + recencyBoost,
      ocrScore: ocrScore,
      matchedTags: matchedTags,
      matchedOcrTerms: matchedOcrTerms,
    );
  }

  bool _isAcceptedHit(SemanticSearchHit hit, SemanticSearchQuery query) {
    if (hit.matchedTags.isNotEmpty || hit.matchedOcrTerms.isNotEmpty) {
      return true;
    }
    if (!query.hasSemanticQuery) {
      return hit.score > 0;
    }
    return hit.semanticScore >= _minSemanticScore || hit.score >= _minSemanticScore;
  }

  Future<List<List<double>>> _buildPromptVectors(List<String> labels) async {
    if (labels.isEmpty) {
      return const <List<double>>[];
    }
    return Future.wait(
      labels.map((label) {
        final prompt = memoriaMasterTaxonomy[label] ?? label;
        return _semanticService.embedText(prompt);
      }),
    );
  }

  double _bestVectorSimilarity(
    List<double> imageEmbedding,
    List<List<double>> vectors,
  ) {
    if (vectors.isEmpty) {
      return 0.0;
    }
    var best = 0.0;
    for (final vector in vectors) {
      if (vector.length != imageEmbedding.length || vector.isEmpty) {
        continue;
      }
      final score = _semanticService.calculateSimilarity(vector, imageEmbedding);
      if (score > best) {
        best = score;
      }
    }
    return best;
  }

  List<SemanticSearchHit> _fallbackTagMatches(
    List<PhotoEntity> candidates,
    SemanticSearchQuery query, {
    String? resolvedTaxonomyLabel,
  }) {
    final queryTokens = _buildQueryTokens(query, resolvedTaxonomyLabel);
    final fallback = <SemanticSearchHit>[];
    for (final photo in candidates) {
      final tags = TagSanitizer.sanitizeVisualTags(photo.aiTags ?? const <String>[]);
      final ocrTerms = _photoOcrTerms(photo);
      final caption = (photo.aiCaption ?? '').trim();
      final locationText = _photoLocationText(photo);
      final matchedTags = query.includeTags.where(tags.contains).toList(growable: false);
      final matchedOcrTerms = query.includeOcrTerms
          .where((term) => _containsKeyword(ocrTerms, term))
          .toList(growable: false);
      final matchedTextTokens = queryTokens
          .where(
            (token) =>
                _containsKeyword(tags, token) ||
                _containsKeyword(ocrTerms, token) ||
                caption.contains(token) ||
                locationText.contains(token),
          )
          .toList(growable: false);
      if (matchedTags.isEmpty &&
          matchedOcrTerms.isEmpty &&
          matchedTextTokens.isEmpty) {
        continue;
      }
      fallback.add(
        SemanticSearchHit(
          photoId: photo.id,
          score:
              matchedTags.length +
              (matchedOcrTerms.length * 0.6) +
              (matchedTextTokens.length * 0.35),
          semanticScore: 0,
          negativeScore: 0,
          tagScore: matchedTags.length.toDouble() + matchedTextTokens.length * 0.2,
          ocrScore: matchedOcrTerms.length.toDouble(),
          matchedTags: <String>[...matchedTags, ...matchedTextTokens]
              .take(3)
              .toList(growable: false),
          matchedOcrTerms: matchedOcrTerms,
        ),
      );
    }
    fallback.sort((a, b) => b.score.compareTo(a.score));
    return fallback;
  }

  String _resolveSemanticPrompt(SemanticSearchQuery query) {
    final trimmed = query.semanticQuery.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final mapped = memoriaMasterTaxonomy[trimmed];
    if (mapped != null && mapped.isNotEmpty) {
      return mapped;
    }
    for (final entry in memoriaMasterTaxonomy.entries) {
      if (trimmed.contains(entry.key) || entry.key.contains(trimmed)) {
        return entry.value;
      }
    }
    if (query.includeTags.isNotEmpty) {
      final first = query.includeTags.first;
      return memoriaMasterTaxonomy[first] ?? '$trimmed, $first';
    }
    return trimmed;
  }

  String _resolveNegativePrompt(SemanticSearchQuery query) {
    final trimmed = query.negativeSemanticQuery.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    if (query.excludeTags.isNotEmpty) {
      return query.excludeTags.join(', ');
    }
    return '';
  }

  String? _resolveTaxonomyLabel(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (memoriaMasterTaxonomy.containsKey(trimmed)) {
      return trimmed;
    }
    for (final label in memoriaMasterTaxonomy.keys) {
      if (trimmed.contains(label) || label.contains(trimmed)) {
        return label;
      }
    }
    return null;
  }

  double _buildTextBoost(PhotoEntity photo, SemanticSearchQuery query) {
    final caption = (photo.aiCaption ?? '').trim();
    final ocrText = (photo.ocrText ?? '').trim();
    final locationText = _photoLocationText(photo);
    final rawQuery = query.rawQuery.trim();
    var boost = 0.0;
    if (rawQuery.length >= 2 && caption.contains(rawQuery)) {
      boost += 0.08;
    }
    if (rawQuery.length >= 2 && locationText.contains(rawQuery)) {
      boost += 0.06;
    }
    if (query.includeOcrTerms.any(ocrText.contains)) {
      boost += 0.05;
    }
    return boost;
  }

  double _buildRecencyBoost(PhotoEntity photo) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ageDays = (now - photo.timestamp) / Duration.millisecondsPerDay;
    if (ageDays <= 30) {
      return 0.03;
    }
    if (ageDays <= 180) {
      return 0.015;
    }
    return 0.0;
  }

  String _photoLocationText(PhotoEntity photo) {
    return [
      photo.locationName,
      photo.district,
      photo.city,
      photo.province,
      photo.formattedAddress,
    ].whereType<String>().join(' ');
  }

  List<String> _photoOcrTerms(PhotoEntity photo) {
    final tags = OcrPolicy.effectiveTags(photo.ocrTags ?? const <String>[]);
    final text = (photo.ocrText ?? '').trim();
    final result = <String>[...tags];
    if (text.isNotEmpty) {
      result.add(text);
    }
    return result;
  }

  bool _containsKeyword(Iterable<String> values, String keyword) {
    final normalized = keyword.trim();
    if (normalized.isEmpty) {
      return false;
    }
    for (final value in values) {
      if (value.contains(normalized)) {
        return true;
      }
    }
    return false;
  }

  List<String> _buildQueryTokens(
    SemanticSearchQuery query,
    String? resolvedTaxonomyLabel,
  ) {
    final tokens = <String>[
      query.rawQuery.trim(),
      query.semanticQuery.trim(),
      ...?(resolvedTaxonomyLabel == null
          ? null
          : <String>[resolvedTaxonomyLabel]),
      ...query.includeTags,
      ...query.includeLocations,
      ...query.includeOcrTerms,
    ];
    final result = <String>[];
    for (final token in tokens) {
      final normalized = token.trim();
      if (normalized.length < 2 || result.contains(normalized)) {
        continue;
      }
      result.add(normalized);
    }
    return result;
  }
}
