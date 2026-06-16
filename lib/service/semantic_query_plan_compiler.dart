import '../models/entity/photo_entity.dart';
import '../models/vo/semantic_search_models.dart';
import '../objectbox.g.dart';
import 'photo_search_index_service.dart';

class SemanticQueryPlanCompiler {
  const SemanticQueryPlanCompiler();

  Condition<PhotoEntity> compile(
    SemanticSearchQuery query, {
    bool relaxed = false,
  }) {
    Condition<PhotoEntity> condition = PhotoEntity_.isAiAnalyzed
        .equals(true)
        .and(PhotoEntity_.isAiAnalysisCandidate.equals(false))
        .and(
          PhotoEntity_.searchIndexVersion.equals(
            PhotoSearchIndexService.currentVersion,
          ),
        );

    final time = _compileTime(query, relaxed: relaxed);
    if (time != null) condition = condition.and(time);
    final geo = _compileGeo(query.locations, relaxed: relaxed);
    if (geo != null) condition = condition.and(geo);
    final attributes = _compileAttributes(query.attributes);
    if (attributes != null) condition = condition.and(attributes);
    return condition;
  }

  Condition<PhotoEntity>? _compileTime(
    SemanticSearchQuery query, {
    required bool relaxed,
  }) {
    final groups = <Condition<PhotoEntity>>[];
    final absolute = query.timeRanges.where((range) => range.hasDateBoundary);
    final absoluteConditions = <Condition<PhotoEntity>>[];
    for (final range in absolute) {
      final start = range.startTimeMs ?? 0;
      final end = range.endTimeMs ?? 0x7fffffffffffffff;
      final padding = relaxed ? const Duration(days: 3).inMilliseconds : 0;
      absoluteConditions.add(
        PhotoEntity_.capturedAtMillis.between(
          (start - padding).clamp(0, 0x7fffffffffffffff),
          (end + padding).clamp(0, 0x7fffffffffffffff),
        ),
      );
    }
    final absoluteGroup = _orAll(absoluteConditions);
    if (absoluteGroup != null) groups.add(absoluteGroup);

    final recurringConditions = <Condition<PhotoEntity>>[];
    for (final range in query.timeRanges.where(
      (range) => range.hasRecurringMonthRange,
    )) {
      final start = range.recurringStartMonth!;
      final end = range.recurringEndMonth!;
      recurringConditions.add(
        start <= end
            ? PhotoEntity_.capturedMonth.between(start, end)
            : PhotoEntity_.capturedMonth
                  .between(start, 12)
                  .or(PhotoEntity_.capturedMonth.between(1, end)),
      );
    }
    final recurringGroup = _orAll(recurringConditions);
    if (recurringGroup != null) groups.add(recurringGroup);

    final annualConditions = <Condition<PhotoEntity>>[];
    for (final range in query.timeRanges.where(
      (range) => range.hasAnnualDayRange,
    )) {
      final start = range.annualStartMonth!;
      final end = range.annualEndMonth!;
      annualConditions.add(
        start <= end
            ? PhotoEntity_.capturedMonth.between(start, end)
            : PhotoEntity_.capturedMonth
                  .between(start, 12)
                  .or(PhotoEntity_.capturedMonth.between(1, end)),
      );
    }
    final annualGroup = _orAll(annualConditions);
    if (annualGroup != null) groups.add(annualGroup);

    final minuteConditions = <Condition<PhotoEntity>>[];
    for (final range in query.timeRanges.where(
      (range) => range.hasLocalTimeWindow && range.utcOffsetMinutes == null,
    )) {
      final padding = relaxed ? 60 : 0;
      final start = (range.localStartMinute! - padding) % 1440;
      final end = (range.localEndMinute! + padding) % 1440;
      minuteConditions.add(
        start <= end
            ? PhotoEntity_.capturedMinuteOfDay.between(start, end)
            : PhotoEntity_.capturedMinuteOfDay
                  .between(start, 1439)
                  .or(PhotoEntity_.capturedMinuteOfDay.between(0, end)),
      );
    }
    final minuteGroup = _orAll(minuteConditions);
    if (minuteGroup != null) groups.add(minuteGroup);
    if (query.weekdays.isNotEmpty) {
      groups.add(PhotoEntity_.capturedWeekday.oneOf(query.weekdays));
    }
    return _andAll(groups);
  }

  Condition<PhotoEntity>? _compileGeo(
    List<SemanticSearchLocation> locations, {
    required bool relaxed,
  }) {
    final locationConditions = <Condition<PhotoEntity>>[];
    for (final location in locations) {
      if (location.type == 'region_concept' &&
          location.countryCandidates.isNotEmpty) {
        locationConditions.add(
          PhotoEntity_.country.oneOf(location.countryCandidates),
        );
        continue;
      }
      final terms = <String>{location.text, ...location.aliases}
          .map((term) => term.trim())
          .where((term) => term.length >= 2)
          .toList(growable: false);
      final termConditions = <Condition<PhotoEntity>>[];
      for (final term in terms) {
        termConditions.addAll(_geoTermConditions(term, location.type, relaxed));
      }
      if (location.amapPoiId?.isNotEmpty == true) {
        termConditions.add(
          PhotoEntity_.poiIdText.contains('|${location.amapPoiId}|'),
        );
      }
      if (location.amapAoiId?.isNotEmpty == true) {
        termConditions.add(
          PhotoEntity_.aoiIdText.contains('|${location.amapAoiId}|'),
        );
      }
      final radius = relaxed
          ? location.softRadiusMeters
          : location.coreRadiusMeters;
      final coordinateGroup = _coordinateBox(location, radius);
      if (coordinateGroup != null) {
        termConditions.add(coordinateGroup);
      }
      final locationGroup = _orAll(termConditions);
      if (locationGroup != null) locationConditions.add(locationGroup);
    }
    return _orAll(locationConditions);
  }

  Condition<PhotoEntity>? _coordinateBox(
    SemanticSearchLocation location,
    int radiusMeters,
  ) {
    final lat = location.centerLatAmapE6;
    final lon = location.centerLonAmapE6;
    if (lat == null || lon == null || radiusMeters <= 0) return null;
    final latDelta = (radiusMeters / 111320 * 1000000).ceil();
    final lonDelta = (radiusMeters / 90000 * 1000000).ceil();
    return PhotoEntity_.latAmapE6
        .between(lat - latDelta, lat + latDelta)
        .and(PhotoEntity_.lonAmapE6.between(lon - lonDelta, lon + lonDelta));
  }

  List<Condition<PhotoEntity>> _geoTermConditions(
    String term,
    String type,
    bool relaxed,
  ) {
    final broad = type == 'country' || type == 'province' || type == 'city';
    if (broad || relaxed) {
      return <Condition<PhotoEntity>>[
        PhotoEntity_.country.contains(term),
        PhotoEntity_.province.contains(term),
        PhotoEntity_.city.contains(term),
        PhotoEntity_.district.contains(term),
        PhotoEntity_.locationName.contains(term),
        PhotoEntity_.formattedAddress.contains(term),
        PhotoEntity_.adcode.equals(term),
        PhotoEntity_.township.contains(term),
        PhotoEntity_.businessAreaText.contains(term),
        PhotoEntity_.aoiNameText.contains(term),
        PhotoEntity_.poiNameText.contains(term),
        PhotoEntity_.geoTextTokens.contains(term),
      ];
    }
    if (type == 'district') {
      return <Condition<PhotoEntity>>[
        PhotoEntity_.district.contains(term),
        PhotoEntity_.township.contains(term),
        PhotoEntity_.formattedAddress.contains(term),
        PhotoEntity_.businessAreaText.contains(term),
        PhotoEntity_.aoiNameText.contains(term),
        PhotoEntity_.poiNameText.contains(term),
        PhotoEntity_.geoTextTokens.contains(term),
      ];
    }
    return <Condition<PhotoEntity>>[
      PhotoEntity_.locationName.contains(term),
      PhotoEntity_.formattedAddress.contains(term),
      PhotoEntity_.businessAreaText.contains(term),
      PhotoEntity_.aoiNameText.contains(term),
      PhotoEntity_.poiNameText.contains(term),
      PhotoEntity_.geoTextTokens.contains(term),
    ];
  }

  Condition<PhotoEntity>? _compileAttributes(SemanticSearchAttributes value) {
    final conditions = <Condition<PhotoEntity>>[];
    if (value.minFaceCount != null) {
      conditions.add(
        PhotoEntity_.faceCount.greaterOrEqual(value.minFaceCount!),
      );
    }
    if (value.maxFaceCount != null) {
      conditions.add(PhotoEntity_.faceCount.lessOrEqual(value.maxFaceCount!));
    }
    if (value.minSmileProbability != null) {
      conditions.add(
        PhotoEntity_.smileProb.greaterOrEqual(value.minSmileProbability!),
      );
    }
    if (value.minJoyScore != null) {
      conditions.add(PhotoEntity_.joyScore.greaterOrEqual(value.minJoyScore!));
    }
    if (value.mediaKinds.isNotEmpty) {
      conditions.add(PhotoEntity_.mediaKind.oneOf(value.mediaKinds));
    }
    return _andAll(conditions);
  }

  Condition<PhotoEntity>? _andAll(List<Condition<PhotoEntity>> values) {
    if (values.isEmpty) return null;
    return values.first.andAll(values.skip(1).toList(growable: false));
  }

  Condition<PhotoEntity>? _orAll(List<Condition<PhotoEntity>> values) {
    if (values.isEmpty) return null;
    return values.first.orAny(values.skip(1).toList(growable: false));
  }
}
