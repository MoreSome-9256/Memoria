import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/event_entity.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/service/event_service.dart';
import 'package:photo_album/service/junk_photo_filter_service.dart';

PhotoEntity _photo({required int id, bool confirmedJunk = false}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = ''
    ..timestamp = DateTime(2026, 1, id).millisecondsSinceEpoch
    ..width = 1000
    ..height = 800
    ..aiTags = confirmedJunk
        ? const <String>[JunkPhotoFilterService.junkCandidateTag]
        : const <String>['旅行'];
}

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

  group('EventEntity moments projection', () {
    test(
      'preview model excludes confirmed junk photos from covers and count',
      () async {
        final event = EventEntity()
          ..id = 1
          ..title = '1月时刻'
          ..startTime = DateTime(2026, 1, 1).millisecondsSinceEpoch
          ..endTime = DateTime(2026, 1, 3).millisecondsSinceEpoch
          ..photoIds = <int>[1, 2, 3]
          ..photoCount = 3
          ..tags = const <String>['旅行'];
        final photos = <int, PhotoEntity>{
          1: _photo(id: 1),
          2: _photo(id: 2, confirmedJunk: true),
          3: _photo(id: 3),
        };

        final preview = await event.toPreviewModel(
          loadPhotoEntities: (ids) async => ids
              .map((id) => photos[id])
              .whereType<PhotoEntity>()
              .toList(growable: false),
        );

        expect(preview.photoCount, 2);
        expect(preview.coverPhotos.map((photo) => photo.id), <String>[
          'asset_1',
          'asset_3',
        ]);
      },
    );
  });
}
