import 'dart:isolate';

import 'package:isar/isar.dart';

import '../models/entity/event_entity.dart';
import '../models/entity/photo_entity.dart';
import 'photo_service.dart';

class TravelMemoryService {
  TravelMemoryService({PhotoService? photoService})
    : _photoService = photoService ?? PhotoService();

  final PhotoService _photoService;

  Future<List<TravelMemoryCandidate>> detectRecentTravelMemories({
    int lookbackDays = 90,
  }) async {
    final safeLookbackDays = lookbackDays <= 0 ? 90 : lookbackDays;
    final isar = _photoService.isar;

    final latestEvent = await isar
        .collection<EventEntity>()
        .where()
        .sortByEndTimeDesc()
        .limit(1)
        .findFirst();
    final latestPhoto = await isar
        .collection<PhotoEntity>()
        .where()
        .sortByTimestampDesc()
        .limit(1)
        .findFirst();
    final latestTime = _latestTimestamp(
      latestEvent?.endTime,
      latestPhoto?.timestamp,
    );
    if (latestTime == null) {
      return const <TravelMemoryCandidate>[];
    }

    final windowStart = DateTime.fromMillisecondsSinceEpoch(
      latestTime,
    ).subtract(Duration(days: safeLookbackDays - 1)).millisecondsSinceEpoch;
    final events = await isar
        .collection<EventEntity>()
        .filter()
        .endTimeGreaterThan(windowStart, include: true)
        .findAll();
    final photos = await isar
        .collection<PhotoEntity>()
        .filter()
        .timestampGreaterThan(windowStart, include: true)
        .findAll();
    events.sort((a, b) => a.startTime.compareTo(b.startTime));
    photos.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final eventSnapshots = events
        .map(TravelEventSnapshot.fromEntity)
        .toList(growable: false);
    final photoSnapshots = photos
        .map(TravelPhotoSnapshot.fromEntity)
        .toList(growable: false);

    return Isolate.run(
      () => TravelMemoryDetector.detectFromSnapshots(
        events: eventSnapshots,
        photos: photoSnapshots,
        lookbackDays: safeLookbackDays,
      ),
    );
  }

  Future<String> buildDebugSummary({int lookbackDays = 90}) async {
    final candidates = await detectRecentTravelMemories(
      lookbackDays: lookbackDays,
    );
    if (candidates.isEmpty) {
      return 'TravelMemoryDetector: no travel candidates found';
    }
    final buffer = StringBuffer(
      'TravelMemoryDetector: ${candidates.length} candidate(s)',
    );
    for (final candidate in candidates.take(5)) {
      buffer.writeln();
      buffer.write(
        '- ${candidate.city} ${candidate.startDay}..${candidate.endDay} '
        'score=${candidate.score.toStringAsFixed(2)} '
        'photos=${candidate.photoCount} events=${candidate.eventIds.length} '
        'locations=${candidate.mainLocationNames.join('/')}',
      );
    }
    return buffer.toString();
  }

  int? _latestTimestamp(int? first, int? second) {
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    return first > second ? first : second;
  }
}

class TravelMemoryDetector {
  static const int minTripDays = 1;
  static const int maxTripDays = 14;
  static const int minPhotosForTrip = 3;

  static List<TravelDayObservation> buildObservations({
    required List<EventEntity> events,
    required List<PhotoEntity> photos,
  }) {
    return buildObservationsFromSnapshots(
      events: events.map(TravelEventSnapshot.fromEntity),
      photos: photos.map(TravelPhotoSnapshot.fromEntity),
    );
  }

  static List<TravelMemoryCandidate> detectFromSnapshots({
    required List<TravelEventSnapshot> events,
    required List<TravelPhotoSnapshot> photos,
    int lookbackDays = 90,
  }) {
    final observations = buildObservationsFromSnapshots(
      events: events,
      photos: photos,
    );
    return detect(observations, lookbackDays: lookbackDays);
  }

  static List<TravelDayObservation> buildObservationsFromSnapshots({
    required Iterable<TravelEventSnapshot> events,
    required Iterable<TravelPhotoSnapshot> photos,
  }) {
    final photosByEventId = <int, List<TravelPhotoSnapshot>>{};
    final ungroupedPhotos = <TravelPhotoSnapshot>[];
    for (final photo in photos) {
      final eventId = photo.eventId;
      if (eventId == null) {
        ungroupedPhotos.add(photo);
        continue;
      }
      photosByEventId
          .putIfAbsent(eventId, () => <TravelPhotoSnapshot>[])
          .add(photo);
    }

    final observations = <TravelDayObservation>[];
    for (final event in events) {
      final eventPhotos =
          photosByEventId[event.id] ?? const <TravelPhotoSnapshot>[];
      final city = _normalizeCity(
        event.city ??
            _mostFrequent(eventPhotos.map((photo) => photo.city)) ??
            event.district ??
            event.province,
      );
      if (city == null) {
        continue;
      }
      final adcode = _normalizeText(
        _mostFrequent(eventPhotos.map((photo) => photo.adcode)),
      );
      final locationNames = _topLocationNames(<String?>[
        event.locationName,
        ...eventPhotos.map((photo) => photo.locationName),
        event.district,
        ...eventPhotos.map((photo) => photo.district),
      ]);
      final startDay = TravelDay.fromMilliseconds(event.startTime);
      final endDay = TravelDay.fromMilliseconds(event.endTime);
      final days = _daysBetweenInclusive(startDay, endDay);
      final eventPhotoCount = event.photoCount > 0
          ? event.photoCount
          : eventPhotos.length;
      final photoCountPerDay = eventPhotoCount <= 0
          ? 1
          : (eventPhotoCount / days.length).ceil();

      for (final day in days) {
        observations.add(
          TravelDayObservation(
            day: day,
            city: city,
            district: _normalizeText(
              event.district ??
                  _mostFrequent(eventPhotos.map((photo) => photo.district)),
            ),
            adcode: adcode,
            photoCount: photoCountPerDay,
            eventIds: <int>{event.id},
            locationNames: locationNames,
          ),
        );
      }
    }

    final photosByDay = <TravelDay, List<TravelPhotoSnapshot>>{};
    for (final photo in ungroupedPhotos) {
      final city = _normalizeCity(
        photo.city ?? photo.district ?? photo.province,
      );
      if (city == null) {
        continue;
      }
      final day = TravelDay.fromMilliseconds(photo.timestamp);
      photosByDay.putIfAbsent(day, () => <TravelPhotoSnapshot>[]).add(photo);
    }

    for (final entry in photosByDay.entries) {
      final day = entry.key;
      final dayPhotos = entry.value;
      final city = _normalizeCity(
        _mostFrequent(
          dayPhotos.map(
            (photo) => photo.city ?? photo.district ?? photo.province,
          ),
        ),
      );
      if (city == null) {
        continue;
      }
      observations.add(
        TravelDayObservation(
          day: day,
          city: city,
          district: _normalizeText(
            _mostFrequent(dayPhotos.map((photo) => photo.district)),
          ),
          adcode: _normalizeText(
            _mostFrequent(dayPhotos.map((photo) => photo.adcode)),
          ),
          photoCount: dayPhotos.length,
          eventIds: const <int>{},
          locationNames: _topLocationNames(
            dayPhotos.map((photo) => photo.locationName),
          ),
        ),
      );
    }

    return _mergeSameDayCityObservations(observations);
  }

  static List<TravelMemoryCandidate> detect(
    List<TravelDayObservation> observations, {
    int lookbackDays = 90,
  }) {
    if (observations.isEmpty) {
      return const <TravelMemoryCandidate>[];
    }
    final ordered = observations.toList(growable: false)
      ..sort((a, b) => a.day.compareTo(b.day));
    final latestDay = ordered.last.day;
    final windowStart = latestDay.addDays(-(lookbackDays - 1));
    final windowed = ordered
        .where((observation) => observation.day.compareTo(windowStart) >= 0)
        .toList(growable: false);
    if (windowed.isEmpty) {
      return const <TravelMemoryCandidate>[];
    }

    final baseCity = _detectBaseCity(windowed, latestDay);
    if (baseCity == null) {
      return const <TravelMemoryCandidate>[];
    }

    final byDay = <TravelDay, List<TravelDayObservation>>{};
    for (final observation in windowed) {
      byDay
          .putIfAbsent(observation.day, () => <TravelDayObservation>[])
          .add(observation);
    }
    final days = byDay.keys.toList()..sort();
    final travelDays = <TravelDayObservation>[];
    for (final day in days) {
      final observationsForDay = byDay[day]!;
      final dominant = _dominantObservation(observationsForDay);
      if (dominant.city != baseCity) {
        travelDays.add(dominant);
      }
    }

    final segments = <List<TravelDayObservation>>[];
    var index = 0;
    while (index < travelDays.length) {
      final segment = <TravelDayObservation>[travelDays[index]];
      index += 1;
      while (index < travelDays.length &&
          travelDays[index].city == segment.last.city &&
          travelDays[index].day.daysSince(segment.last.day) <= 1) {
        segment.add(travelDays[index]);
        index += 1;
      }
      segments.add(segment);
    }

    final candidates = <TravelMemoryCandidate>[];
    for (final segment in segments) {
      if (segment.length < minTripDays || segment.length > maxTripDays) {
        continue;
      }
      final photoCount = segment.fold<int>(
        0,
        (sum, observation) => sum + observation.photoCount,
      );
      final eventIds = <int>{
        for (final observation in segment) ...observation.eventIds,
      };
      if (photoCount < minPhotosForTrip && eventIds.isEmpty) {
        continue;
      }
      final startDay = segment.first.day;
      final endDay = segment.last.day;
      final hasBaseBefore = windowed.any(
        (observation) =>
            observation.city == baseCity &&
            observation.day.compareTo(startDay) < 0 &&
            startDay.daysSince(observation.day) <= 14,
      );
      final hasBaseAfter = windowed.any(
        (observation) =>
            observation.city == baseCity &&
            observation.day.compareTo(endDay) > 0 &&
            observation.day.daysSince(endDay) <= 14,
      );
      final mainLocations = _topLocationNames(
        segment.expand((observation) => observation.locationNames),
      );
      candidates.add(
        TravelMemoryCandidate(
          score: _scoreSegment(
            dayCount: segment.length,
            photoCount: photoCount,
            eventCount: eventIds.length,
            hasBaseBefore: hasBaseBefore,
            hasBaseAfter: hasBaseAfter,
          ),
          baseCity: baseCity,
          city: segment.first.city,
          startDay: startDay,
          endDay: endDay,
          photoCount: photoCount,
          eventIds: eventIds.toList()..sort(),
          mainLocationNames: mainLocations,
          hasBaseCityBefore: hasBaseBefore,
          hasBaseCityAfter: hasBaseAfter,
        ),
      );
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  static List<TravelDayObservation> _mergeSameDayCityObservations(
    List<TravelDayObservation> observations,
  ) {
    final byKey = <String, List<TravelDayObservation>>{};
    for (final observation in observations) {
      byKey
          .putIfAbsent('${observation.day.key}|${observation.city}', () {
            return <TravelDayObservation>[];
          })
          .add(observation);
    }
    final merged = <TravelDayObservation>[];
    for (final group in byKey.values) {
      final first = group.first;
      merged.add(
        TravelDayObservation(
          day: first.day,
          city: first.city,
          district: first.district,
          adcode: first.adcode,
          photoCount: group.fold<int>(
            0,
            (sum, observation) => sum + observation.photoCount,
          ),
          eventIds: <int>{
            for (final observation in group) ...observation.eventIds,
          },
          locationNames: _topLocationNames(
            group.expand((observation) => observation.locationNames),
          ),
        ),
      );
    }
    return merged..sort((a, b) => a.day.compareTo(b.day));
  }

  static String? _detectBaseCity(
    List<TravelDayObservation> observations,
    TravelDay latestDay,
  ) {
    String? fromWindow(int days) {
      final start = latestDay.addDays(-(days - 1));
      final cityDays = <String, Set<TravelDay>>{};
      for (final observation in observations) {
        if (observation.day.compareTo(start) < 0) {
          continue;
        }
        cityDays
            .putIfAbsent(observation.city, () => <TravelDay>{})
            .add(observation.day);
      }
      if (cityDays.isEmpty) {
        return null;
      }
      final ranked = cityDays.entries.toList()
        ..sort((a, b) {
          final countCompare = b.value.length.compareTo(a.value.length);
          if (countCompare != 0) {
            return countCompare;
          }
          return a.key.compareTo(b.key);
        });
      return ranked.first.value.length >= 2 ? ranked.first.key : null;
    }

    return fromWindow(30) ?? fromWindow(90);
  }

  static TravelDayObservation _dominantObservation(
    List<TravelDayObservation> observations,
  ) {
    final sorted = observations.toList(growable: false)
      ..sort((a, b) {
        final photoCompare = b.photoCount.compareTo(a.photoCount);
        if (photoCompare != 0) {
          return photoCompare;
        }
        return b.eventIds.length.compareTo(a.eventIds.length);
      });
    return sorted.first;
  }

  static double _scoreSegment({
    required int dayCount,
    required int photoCount,
    required int eventCount,
    required bool hasBaseBefore,
    required bool hasBaseAfter,
  }) {
    var score = 0.42;
    score += dayCount.clamp(1, 7).toDouble() * 0.045;
    score += photoCount.clamp(0, 20).toDouble() * 0.012;
    score += eventCount.clamp(0, 5).toDouble() * 0.055;
    if (hasBaseBefore) {
      score += 0.12;
    }
    if (hasBaseAfter) {
      score += 0.14;
    }
    return score.clamp(0.0, 1.0).toDouble();
  }

  static List<TravelDay> _daysBetweenInclusive(TravelDay start, TravelDay end) {
    final days = <TravelDay>[];
    var current = start;
    while (current.compareTo(end) <= 0) {
      days.add(current);
      current = current.addDays(1);
    }
    return days;
  }

  static String? _mostFrequent(Iterable<String?> values) {
    final counts = <String, int>{};
    for (final value in values) {
      final normalized = _normalizeText(value);
      if (normalized == null) {
        continue;
      }
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      return null;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) {
          return countCompare;
        }
        return a.key.length.compareTo(b.key.length);
      });
    return ranked.first.key;
  }

  static List<String> _topLocationNames(Iterable<String?> values) {
    final counts = <String, int>{};
    for (final value in values) {
      final normalized = _normalizeText(value);
      if (normalized == null) {
        continue;
      }
      counts[normalized] = (counts[normalized] ?? 0) + 1;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) {
          return countCompare;
        }
        return a.key.length.compareTo(b.key.length);
      });
    return ranked.take(5).map((entry) => entry.key).toList(growable: false);
  }

  static String? _normalizeCity(String? value) {
    final normalized = _normalizeText(value);
    if (normalized == null) {
      return null;
    }
    if (normalized == '[]' || normalized == '[[]]') {
      return null;
    }
    return normalized;
  }

  static String? _normalizeText(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}

class TravelEventSnapshot {
  const TravelEventSnapshot({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.photoCount,
    this.city,
    this.province,
    this.district,
    this.locationName,
  });

  factory TravelEventSnapshot.fromEntity(EventEntity event) {
    return TravelEventSnapshot(
      id: event.id,
      startTime: event.startTime,
      endTime: event.endTime,
      photoCount: event.photoCount,
      city: event.city,
      province: event.province,
      district: event.district,
      locationName: event.locationName,
    );
  }

  final int id;
  final int startTime;
  final int endTime;
  final int photoCount;
  final String? city;
  final String? province;
  final String? district;
  final String? locationName;
}

class TravelPhotoSnapshot {
  const TravelPhotoSnapshot({
    required this.id,
    required this.timestamp,
    this.eventId,
    this.city,
    this.province,
    this.district,
    this.locationName,
    this.adcode,
  });

  factory TravelPhotoSnapshot.fromEntity(PhotoEntity photo) {
    return TravelPhotoSnapshot(
      id: photo.id,
      timestamp: photo.timestamp,
      eventId: photo.eventId,
      city: photo.city,
      province: photo.province,
      district: photo.district,
      locationName: photo.locationName,
      adcode: photo.adcode,
    );
  }

  final int id;
  final int timestamp;
  final int? eventId;
  final String? city;
  final String? province;
  final String? district;
  final String? locationName;
  final String? adcode;
}

class TravelDayObservation {
  const TravelDayObservation({
    required this.day,
    required this.city,
    required this.photoCount,
    required this.eventIds,
    this.district,
    this.adcode,
    this.locationNames = const <String>[],
  });

  final TravelDay day;
  final String city;
  final String? district;
  final String? adcode;
  final int photoCount;
  final Set<int> eventIds;
  final List<String> locationNames;
}

class TravelMemoryCandidate {
  const TravelMemoryCandidate({
    required this.score,
    required this.baseCity,
    required this.city,
    required this.startDay,
    required this.endDay,
    required this.photoCount,
    required this.eventIds,
    required this.mainLocationNames,
    required this.hasBaseCityBefore,
    required this.hasBaseCityAfter,
  });

  final double score;
  final String baseCity;
  final String city;
  final TravelDay startDay;
  final TravelDay endDay;
  final int photoCount;
  final List<int> eventIds;
  final List<String> mainLocationNames;
  final bool hasBaseCityBefore;
  final bool hasBaseCityAfter;
}

class TravelDay implements Comparable<TravelDay> {
  const TravelDay(this.year, this.month, this.day);

  factory TravelDay.fromMilliseconds(int millisecondsSinceEpoch) {
    final date = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    return TravelDay(date.year, date.month, date.day);
  }

  final int year;
  final int month;
  final int day;

  String get key {
    return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  TravelDay addDays(int days) {
    final date = DateTime(year, month, day).add(Duration(days: days));
    return TravelDay(date.year, date.month, date.day);
  }

  int daysSince(TravelDay other) {
    final current = DateTime(year, month, day);
    final previous = DateTime(other.year, other.month, other.day);
    return current.difference(previous).inDays;
  }

  @override
  int compareTo(TravelDay other) {
    final yearCompare = year.compareTo(other.year);
    if (yearCompare != 0) {
      return yearCompare;
    }
    final monthCompare = month.compareTo(other.month);
    if (monthCompare != 0) {
      return monthCompare;
    }
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) {
    return other is TravelDay &&
        other.year == year &&
        other.month == month &&
        other.day == day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => key;
}
