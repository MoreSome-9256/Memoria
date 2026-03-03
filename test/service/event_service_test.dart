import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/event_service.dart';

void main() {
  group('EventService.shouldResolvePhotoLocation', () {
    test('returns false when event photo count is below display threshold', () {
      final shouldResolve = EventService.shouldResolvePhotoLocation(
        eventPhotoCount: EventService.minPhotosForDisplay - 1,
        isLocationProcessed: false,
        latitude: 22.5431,
        longitude: 114.0579,
      );

      expect(shouldResolve, isFalse);
    });

    test('returns false when location has already been processed', () {
      final shouldResolve = EventService.shouldResolvePhotoLocation(
        eventPhotoCount: EventService.minPhotosForDisplay,
        isLocationProcessed: true,
        latitude: 22.5431,
        longitude: 114.0579,
      );

      expect(shouldResolve, isFalse);
    });

    test('returns false when GPS data is incomplete', () {
      final withoutLat = EventService.shouldResolvePhotoLocation(
        eventPhotoCount: EventService.minPhotosForDisplay,
        isLocationProcessed: false,
        latitude: null,
        longitude: 114.0579,
      );
      final withoutLon = EventService.shouldResolvePhotoLocation(
        eventPhotoCount: EventService.minPhotosForDisplay,
        isLocationProcessed: false,
        latitude: 22.5431,
        longitude: null,
      );

      expect(withoutLat, isFalse);
      expect(withoutLon, isFalse);
    });

    test('returns true only when all requirements are satisfied', () {
      final shouldResolve = EventService.shouldResolvePhotoLocation(
        eventPhotoCount: EventService.minPhotosForDisplay,
        isLocationProcessed: false,
        latitude: 22.5431,
        longitude: 114.0579,
      );

      expect(shouldResolve, isTrue);
    });
  });
}
