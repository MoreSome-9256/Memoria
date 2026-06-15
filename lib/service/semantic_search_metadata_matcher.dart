import '../models/entity/photo_entity.dart';
import '../models/vo/semantic_search_models.dart';
import '../utils/tag_sanitizer.dart';
import '../data/tag_taxonomy_v2.dart';
import 'geo_coordinate_service.dart';

class SemanticSearchMetadataMatcher {
  const SemanticSearchMetadataMatcher();

  static const double strictLocationThreshold = 0.62;
  static const double poiContextThreshold = 0.56;

  bool matchesTime(PhotoEntity photo, SemanticSearchQuery query) {
    final dateRanges = query.timeRanges
        .where((range) => range.hasDateBoundary)
        .toList(growable: false);
    final localTimeWindows = query.timeRanges
        .where((range) => range.hasLocalTimeWindow)
        .toList(growable: false);
    final recurringMonthRanges = query.timeRanges
        .where((range) => range.hasRecurringMonthRange)
        .toList(growable: false);
    final annualDayRanges = query.timeRanges
        .where((range) => range.hasAnnualDayRange)
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
    if (recurringMonthRanges.isNotEmpty &&
        !recurringMonthRanges.any(
          (range) => matchesRecurringMonth(photo, range),
        )) {
      return false;
    }
    if (annualDayRanges.isNotEmpty &&
        !annualDayRanges.any((range) => matchesAnnualDay(photo, range))) {
      return false;
    }
    if (query.weekdays.isNotEmpty) {
      final date = DateTime.fromMillisecondsSinceEpoch(
        normalizeTimestampMs(photo.timestamp),
      );
      if (!query.weekdays.contains(date.weekday)) return false;
    }
    return true;
  }

  bool matchesAnnualDay(PhotoEntity photo, SemanticSearchTimeRange range) {
    final start = range.annualStartDay;
    final end = range.annualEndDay;
    if (start == null || end == null) return true;
    final date = DateTime.fromMillisecondsSinceEpoch(
      normalizeTimestampMs(photo.timestamp),
    );
    final day = date.difference(DateTime(date.year)).inDays + 1;
    return start <= end
        ? day >= start && day <= end
        : day >= start || day <= end;
  }

  bool matchesRecurringMonth(PhotoEntity photo, SemanticSearchTimeRange range) {
    final start = range.recurringStartMonth;
    final end = range.recurringEndMonth;
    if (start == null || end == null) {
      return true;
    }
    final month = DateTime.fromMillisecondsSinceEpoch(
      normalizeTimestampMs(photo.timestamp),
    ).month;
    return start <= end
        ? month >= start && month <= end
        : month >= start || month <= end;
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

  double scoreLocation(PhotoEntity photo, SemanticSearchLocation location) {
    return _scoreLocation(photo, location);
  }

  double _scoreLocation(PhotoEntity photo, SemanticSearchLocation location) {
    if (location.type == 'region_concept' &&
        location.countryCandidates.any(
          (country) => photo.country?.contains(country) == true,
        )) {
      return 1.0;
    }
    final idMatched =
        (location.amapPoiId?.isNotEmpty == true &&
            photo.poiIdText?.contains('|${location.amapPoiId}|') == true) ||
        (location.amapAoiId?.isNotEmpty == true &&
            photo.aoiIdText?.contains('|${location.amapAoiId}|') == true);
    if (idMatched) return 1.0;
    final weightedParts = <_WeightedLocationPart>[
      _WeightedLocationPart(photo.locationName, 1.0, _LocationFieldScope.poi),
      _WeightedLocationPart(photo.poiNameText, 1.0, _LocationFieldScope.poi),
      _WeightedLocationPart(photo.aoiNameText, 0.98, _LocationFieldScope.poi),
      _WeightedLocationPart(
        photo.businessAreaText,
        0.88,
        _LocationFieldScope.address,
      ),
      _WeightedLocationPart(
        photo.geoTextTokens,
        0.95,
        _LocationFieldScope.address,
      ),
      _WeightedLocationPart(
        photo.formattedAddress,
        0.92,
        _LocationFieldScope.address,
      ),
      _WeightedLocationPart(photo.district, 0.82, _LocationFieldScope.district),
      _WeightedLocationPart(photo.city, 0.72, _LocationFieldScope.city),
      _WeightedLocationPart(photo.province, 0.58, _LocationFieldScope.province),
      _WeightedLocationPart(photo.country, 0.55, _LocationFieldScope.province),
      _WeightedLocationPart(photo.township, 0.76, _LocationFieldScope.district),
      _WeightedLocationPart(photo.adcode, 0.50, _LocationFieldScope.code),
    ];
    final primary = _normalizeLocationText(location.text);
    final terms = <_LocationTerm>[
      _LocationTerm(primary, isPrimary: true),
      for (final alias in location.aliases)
        _LocationTerm(_normalizeLocationText(alias), isPrimary: false),
    ].where((term) => term.value.isNotEmpty).toList(growable: false);
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
          part.scope,
          location.type,
          primary,
        );
        if (score > best) {
          best = score;
        }
      }
    }
    if ((location.strictness == 'nearby' || location.allowNearbySiblings) &&
        location.hasResolvedCenter &&
        photo.latAmapE6 != null &&
        photo.lonAmapE6 != null) {
      final distance = GeoCoordinateService.distanceMeters(
        photo.latAmapE6! / 1000000,
        photo.lonAmapE6! / 1000000,
        location.centerLatAmapE6! / 1000000,
        location.centerLonAmapE6! / 1000000,
      );
      if (distance <= location.coreRadiusMeters) return mathMin(0.82, 1.0);
    }
    if (location.hasResolvedCenter &&
        photo.latAmapE6 != null &&
        photo.lonAmapE6 != null) {
      final distance = GeoCoordinateService.distanceMeters(
        photo.latAmapE6! / 1000000,
        photo.lonAmapE6! / 1000000,
        location.centerLatAmapE6! / 1000000,
        location.centerLonAmapE6! / 1000000,
      );
      if (distance <= location.coreRadiusMeters) return mathMin(0.82, 1.0);
    }
    return best;
  }

  double _scoreNormalizedLocation(
    String part,
    _LocationTerm term,
    double fieldWeight,
    _LocationFieldScope fieldScope,
    String locationType,
    String primaryTerm,
  ) {
    final termValue = term.value;
    final scopeCap = _scopeCap(
      locationType: locationType,
      fieldScope: fieldScope,
      term: term,
      primaryTerm: primaryTerm,
    );
    if (part == termValue) {
      return mathMin(1.0 * fieldWeight, scopeCap);
    }
    final strippedPart = _stripLocationSuffix(part);
    final strippedTerm = _stripLocationSuffix(termValue);
    if (strippedPart.isNotEmpty && strippedPart == strippedTerm) {
      return mathMin(0.94 * fieldWeight, scopeCap);
    }
    if (part.contains(termValue) || termValue.contains(part)) {
      final ratio = _overlapRatio(part, termValue);
      final base = locationType == 'poi' || locationType == 'scenic_area'
          ? 0.74
          : 0.66;
      return mathMin((base + ratio * 0.22) * fieldWeight, scopeCap);
    }

    final partTokens = _locationTokens(part);
    final termTokens = _locationTokens(termValue);
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
    return mathMin(coverage * 0.70 * fieldWeight * strictTypePenalty, scopeCap);
  }

  double _scopeCap({
    required String locationType,
    required _LocationFieldScope fieldScope,
    required _LocationTerm term,
    required String primaryTerm,
  }) {
    final isPoiLike = locationType == 'poi' || locationType == 'scenic_area';
    if (!isPoiLike) {
      return 1.0;
    }
    if (fieldScope == _LocationFieldScope.poi ||
        fieldScope == _LocationFieldScope.address) {
      if (term.isPrimary || _isSpecificPoiAlias(term.value, primaryTerm)) {
        return 1.0;
      }
      return _looksLikeBroadContext(term.value) ? poiContextThreshold : 0.86;
    }
    return 0.48;
  }

  bool _isSpecificPoiAlias(String alias, String primaryTerm) {
    if (primaryTerm.isEmpty) {
      return false;
    }
    if (alias.contains(primaryTerm) || primaryTerm.contains(alias)) {
      return true;
    }
    if (_looksLikeBroadContext(alias)) {
      return false;
    }
    return alias.length <= primaryTerm.length + 2;
  }

  bool _looksLikeBroadContext(String value) {
    return RegExp('(景区|风景区|区域|片区|街道|社区|村|城区|市区|玄武湖|公园|湖)\$').hasMatch(value);
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

  double mathMin(double left, double right) => left < right ? left : right;
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
  const _WeightedLocationPart(this.value, this.weight, this.scope);

  final String? value;
  final double weight;
  final _LocationFieldScope scope;
}

class _LocationTerm {
  const _LocationTerm(this.value, {required this.isPrimary});

  final String value;
  final bool isPrimary;
}

enum _LocationFieldScope { poi, address, district, city, province, code }
