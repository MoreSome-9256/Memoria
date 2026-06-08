import '../models/entity/photo_entity.dart';
import '../models/vo/semantic_search_models.dart';
import '../utils/tag_sanitizer.dart';
import '../data/tag_taxonomy_v2.dart';

class SemanticSearchMetadataMatcher {
  const SemanticSearchMetadataMatcher();

  static const double strictLocationThreshold = 0.62;

  bool matchesTime(PhotoEntity photo, SemanticSearchQuery query) {
    final dateRanges = query.timeRanges
        .where((range) => range.hasDateBoundary)
        .toList(growable: false);
    final localTimeWindows = query.timeRanges
        .where((range) => range.hasLocalTimeWindow)
        .toList(growable: false);

    if (dateRanges.isNotEmpty &&
        !dateRanges.any((range) => matchesDateRange(photo, range))) {
      return false;
    }
    if (localTimeWindows.isNotEmpty &&
        !localTimeWindows.any(
          (range) => matchesLocalTimeWindow(
            photo,
            range,
            fallbackUtcOffsetMinutes: _fallbackOffsetFromQuery(query),
          ),
        )) {
      return false;
    }
    return true;
  }

  bool matchesDateRange(PhotoEntity photo, SemanticSearchTimeRange range) {
    final timestamp = normalizeTimestampMs(photo.timestamp);
    final start = range.startTimeMs;
    final end = range.endTimeMs;
    if (start != null && timestamp < start) {
      return false;
    }
    if (end != null && timestamp > end) {
      return false;
    }
    return true;
  }

  bool matchesLocalTimeWindow(
    PhotoEntity photo,
    SemanticSearchTimeRange range, {
    int? fallbackUtcOffsetMinutes,
  }) {
    final localStart = range.localStartMinute;
    final localEnd = range.localEndMinute;
    if (localStart == null || localEnd == null) {
      return true;
    }

    final offset = range.utcOffsetMinutes ?? fallbackUtcOffsetMinutes;
    final localTime = offset == null
        ? DateTime.fromMillisecondsSinceEpoch(
            normalizeTimestampMs(photo.timestamp),
          )
        : DateTime.fromMillisecondsSinceEpoch(
            normalizeTimestampMs(photo.timestamp),
            isUtc: true,
          ).add(Duration(minutes: offset));
    final minuteOfDay = localTime.hour * 60 + localTime.minute;
    if (localStart <= localEnd) {
      return minuteOfDay >= localStart && minuteOfDay <= localEnd;
    }
    return minuteOfDay >= localStart || minuteOfDay <= localEnd;
  }

  LocationMatchResult matchLocation(
    PhotoEntity photo,
    List<SemanticSearchLocation> locations,
  ) {
    if (locations.isEmpty) {
      return LocationMatchResult.none;
    }

    var bestScore = 0.0;
    final matched = <String>[];
    for (final location in locations) {
      final score = _scoreLocation(photo, location);
      if (score >= strictLocationThreshold) {
        matched.add(location.text);
      }
      if (score > bestScore) {
        bestScore = score;
      }
    }
    return LocationMatchResult(
      score: bestScore.clamp(0.0, 1.0).toDouble(),
      matchedLocations: matched,
      isStrictMatch: bestScore >= strictLocationThreshold,
    );
  }

  bool matchesLocation(
    PhotoEntity photo,
    List<SemanticSearchLocation> locations,
  ) {
    return matchLocation(photo, locations).isStrictMatch;
  }

  CoarseTagMatchResult matchCoarseTags(
    PhotoEntity photo,
    List<SemanticSearchCoarseTag> coarseTags,
  ) {
    if (coarseTags.isEmpty) {
      return CoarseTagMatchResult.empty;
    }
    final coarseIds = photoCoarseIds(photo);
    final matched = <String>[];
    var confidence = 0.0;
    for (final coarseTag in coarseTags) {
      if (coarseIds.contains(coarseTag.id)) {
        matched.add(coarseTag.labelZh);
        if (coarseTag.confidence > confidence) {
          confidence = coarseTag.confidence;
        }
      }
    }
    return CoarseTagMatchResult(
      matchedLabels: matched,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
    );
  }

  Set<String> photoCoarseIds(PhotoEntity photo) {
    final tags = TagSanitizer.sanitizeVisualTags(
      photo.aiTags ?? const <String>[],
    );
    final coarseIds = <String>{};
    for (final tag in tags) {
      final coarseId = memoriaAlbumTagLabelToCoarseId[tag];
      if (coarseId != null && coarseId != memoriaOtherCoarseId) {
        coarseIds.add(coarseId);
      }
    }
    return coarseIds;
  }

  int normalizeTimestampMs(int timestamp) {
    if (timestamp > 0 && timestamp < 10000000000) {
      return timestamp * 1000;
    }
    return timestamp;
  }

  int? _fallbackOffsetFromQuery(SemanticSearchQuery query) {
    for (final location in query.locations) {
      final offset = location.utcOffsetMinutes;
      if (offset != null) {
        return offset;
      }
    }
    return null;
  }

  double _scoreLocation(PhotoEntity photo, SemanticSearchLocation location) {
    final weightedParts = <_WeightedLocationPart>[
      _WeightedLocationPart(photo.locationName, 1.0),
      _WeightedLocationPart(photo.formattedAddress, 0.92),
      _WeightedLocationPart(photo.district, 0.82),
      _WeightedLocationPart(photo.city, 0.72),
      _WeightedLocationPart(photo.province, 0.58),
      _WeightedLocationPart(photo.adcode, 0.50),
    ];
    final terms = <String>{
      location.text,
      ...location.aliases,
    }.map(_normalizeLocationText).where((item) => item.isNotEmpty).toList();
    if (terms.isEmpty) {
      return 0.0;
    }

    var best = 0.0;
    for (final part in weightedParts) {
      final normalizedPart = _normalizeLocationText(part.value);
      if (normalizedPart.isEmpty) {
        continue;
      }
      for (final term in terms) {
        final score = _scoreNormalizedLocation(
          normalizedPart,
          term,
          part.weight,
          location.type,
        );
        if (score > best) {
          best = score;
        }
      }
    }
    return best;
  }

  double _scoreNormalizedLocation(
    String part,
    String term,
    double fieldWeight,
    String locationType,
  ) {
    if (part == term) {
      return 1.0 * fieldWeight;
    }
    final strippedPart = _stripLocationSuffix(part);
    final strippedTerm = _stripLocationSuffix(term);
    if (strippedPart.isNotEmpty && strippedPart == strippedTerm) {
      return 0.94 * fieldWeight;
    }
    if (part.contains(term) || term.contains(part)) {
      final ratio = _overlapRatio(part, term);
      final base = locationType == 'poi' || locationType == 'scenic_area'
          ? 0.74
          : 0.66;
      return (base + ratio * 0.22) * fieldWeight;
    }

    final partTokens = _locationTokens(part);
    final termTokens = _locationTokens(term);
    if (partTokens.isEmpty || termTokens.isEmpty) {
      return 0.0;
    }
    final hitCount = termTokens.where(partTokens.contains).length;
    if (hitCount == 0) {
      return 0.0;
    }
    final coverage = hitCount / termTokens.length;
    final strictTypePenalty = locationType == 'poi' && coverage < 1.0
        ? 0.82
        : 1.0;
    return coverage * 0.70 * fieldWeight * strictTypePenalty;
  }

  String _normalizeLocationText(String? value) {
    final text = value?.trim().toLowerCase() ?? '';
    if (text.isEmpty) {
      return '';
    }
    return text
        .replaceAll(RegExp(r'[\s,，.。;；:：\-_/\\()（）\[\]【】]+'), '')
        .replaceAll(RegExp(r'(中华人民共和国|中国)'), '');
  }

  String _stripLocationSuffix(String value) {
    return value
        .replaceAll(RegExp('(省|市|区|县|自治州|自治区|特别行政区|风景区|景区|公园|街道)\$'), '')
        .trim();
  }

  Set<String> _locationTokens(String value) {
    final ascii = RegExp(r'[a-z0-9]+')
        .allMatches(value)
        .map((match) => match.group(0)!)
        .where((token) => token.length >= 2)
        .toSet();
    final chinese = RegExp(
      r'[\u4e00-\u9fa5]{2,}',
    ).allMatches(value).map((match) => match.group(0)!).toSet();
    return <String>{...ascii, ...chinese};
  }

  double _overlapRatio(String left, String right) {
    final shorter = left.length < right.length ? left.length : right.length;
    final longer = left.length > right.length ? left.length : right.length;
    if (longer <= 0) {
      return 0.0;
    }
    return shorter / longer;
  }
}

class LocationMatchResult {
  const LocationMatchResult({
    required this.score,
    required this.matchedLocations,
    required this.isStrictMatch,
  });

  static const LocationMatchResult none = LocationMatchResult(
    score: 0.0,
    matchedLocations: <String>[],
    isStrictMatch: false,
  );

  final double score;
  final List<String> matchedLocations;
  final bool isStrictMatch;
}

class CoarseTagMatchResult {
  const CoarseTagMatchResult({
    required this.matchedLabels,
    required this.confidence,
  });

  static const CoarseTagMatchResult empty = CoarseTagMatchResult(
    matchedLabels: <String>[],
    confidence: 0.0,
  );

  final List<String> matchedLabels;
  final double confidence;
}

class _WeightedLocationPart {
  const _WeightedLocationPart(this.value, this.weight);

  final String? value;
  final double weight;
}
