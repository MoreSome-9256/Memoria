import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/travel_memory_detector.dart';

void main() {
  group('TravelMemoryDetector', () {
    test('detects a short trip away from the base city', () {
      final observations = <TravelDayObservation>[
        ..._range(
          start: const TravelDay(2026, 5, 1),
          count: 5,
          city: '济南市',
          photoCount: 4,
        ),
        ..._range(
          start: const TravelDay(2026, 5, 6),
          count: 3,
          city: '青岛市',
          photoCount: 2,
          eventIds: {1001},
          locationNames: const ['山大乐水居', '鳌山卫'],
        ),
        ..._range(
          start: const TravelDay(2026, 5, 9),
          count: 3,
          city: '济南市',
          photoCount: 4,
        ),
      ];

      final candidates = TravelMemoryDetector.detect(observations);

      expect(candidates, hasLength(1));
      final trip = candidates.single;
      expect(trip.baseCity, '济南市');
      expect(trip.city, '青岛市');
      expect(trip.startDay, const TravelDay(2026, 5, 6));
      expect(trip.endDay, const TravelDay(2026, 5, 8));
      expect(trip.photoCount, 6);
      expect(trip.eventIds, <int>[1001]);
      expect(trip.mainLocationNames, contains('山大乐水居'));
      expect(trip.hasBaseCityBefore, isTrue);
      expect(trip.hasBaseCityAfter, isTrue);
      expect(trip.score, greaterThan(0.7));
    });

    test('ignores non-base city spans longer than fourteen days', () {
      final observations = <TravelDayObservation>[
        ..._range(
          start: const TravelDay(2026, 4, 1),
          count: 8,
          city: '济南市',
          photoCount: 4,
        ),
        ..._range(
          start: const TravelDay(2026, 4, 9),
          count: 15,
          city: '青岛市',
          photoCount: 3,
          eventIds: {2001},
        ),
        ..._range(
          start: const TravelDay(2026, 4, 24),
          count: 8,
          city: '济南市',
          photoCount: 4,
        ),
      ];

      final candidates = TravelMemoryDetector.detect(observations);

      expect(candidates, isEmpty);
    });

    test('allows photo-only travel days when there are enough photos', () {
      final observations = <TravelDayObservation>[
        ..._range(
          start: const TravelDay(2026, 3, 1),
          count: 4,
          city: '济南市',
          photoCount: 4,
        ),
        TravelDayObservation(
          day: const TravelDay(2026, 3, 5),
          city: '南京市',
          photoCount: 3,
          eventIds: const <int>{},
          locationNames: const ['夫子庙'],
        ),
        ..._range(
          start: const TravelDay(2026, 3, 6),
          count: 4,
          city: '济南市',
          photoCount: 4,
        ),
      ];

      final candidates = TravelMemoryDetector.detect(observations);

      expect(candidates, hasLength(1));
      expect(candidates.single.city, '南京市');
      expect(candidates.single.photoCount, 3);
      expect(candidates.single.eventIds, isEmpty);
    });
  });
}

List<TravelDayObservation> _range({
  required TravelDay start,
  required int count,
  required String city,
  required int photoCount,
  Set<int> eventIds = const <int>{},
  List<String> locationNames = const <String>[],
}) {
  return List<TravelDayObservation>.generate(count, (index) {
    return TravelDayObservation(
      day: start.addDays(index),
      city: city,
      photoCount: photoCount,
      eventIds: eventIds,
      locationNames: locationNames,
    );
  });
}
