import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/utils/event_cluster_helper.dart';

PhotoEntity _photo({
  required int id,
  required DateTime time,
  double? lat,
  double? lon,
  String? city,
  String? province,
  String? adcode,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/p$id.jpg'
    ..timestamp = time.millisecondsSinceEpoch
    ..width = 1200
    ..height = 900
    ..latitude = lat
    ..longitude = lon
    ..city = city
    ..province = province
    ..adcode = adcode;
}

void main() {
  group('EventClusterHelper', () {
    test('photos without GPS still participate in clustering by time', () {
      final base = DateTime(2026, 2, 20, 9, 0);
      final photos = <PhotoEntity>[
        _photo(id: 1, time: base),
        _photo(id: 2, time: base.add(const Duration(minutes: 30))),
        _photo(id: 3, time: base.add(const Duration(hours: 4))),
      ];

      final result = EventClusterHelper.clusterPhotos(photos: photos);

      expect(result.clusters.length, 2);
      expect(result.clusters.first.length, 2);
      expect(result.clusters.last.length, 1);
    });

    test('same-day same-city travel clusters are merged', () {
      final day = DateTime(2026, 2, 20);
      final photos = <PhotoEntity>[
        _photo(
          id: 1,
          time: day.add(const Duration(hours: 9)),
          lat: 30.24,
          lon: 120.15,
          city: '杭州市',
          province: '浙江省',
          adcode: '330100',
        ),
        _photo(
          id: 2,
          time: day.add(const Duration(hours: 9, minutes: 10)),
          lat: 30.25,
          lon: 120.16,
          city: '杭州市',
          province: '浙江省',
          adcode: '330100',
        ),
        _photo(
          id: 3,
          time: day.add(const Duration(hours: 9, minutes: 20)),
          lat: 30.26,
          lon: 120.17,
          city: '杭州市',
          province: '浙江省',
          adcode: '330100',
        ),
        _photo(
          id: 4,
          time: day.add(const Duration(hours: 14)),
          lat: 30.70,
          lon: 120.60,
          city: '杭州市',
          province: '浙江省',
          adcode: '330100',
        ),
        _photo(
          id: 5,
          time: day.add(const Duration(hours: 14, minutes: 10)),
          lat: 30.71,
          lon: 120.61,
          city: '杭州市',
          province: '浙江省',
          adcode: '330100',
        ),
        _photo(
          id: 6,
          time: day.add(const Duration(hours: 14, minutes: 20)),
          lat: 30.72,
          lon: 120.62,
          city: '杭州市',
          province: '浙江省',
          adcode: '330100',
        ),
      ];

      final result = EventClusterHelper.clusterPhotos(
        photos: photos,
        config: const ClusterConfig(
          initialTimeThresholdHours: 3,
          sameDayMergeGapHours: 8,
          minPhotosPerClusterForMerge: 3,
          enableSameDayTravelMerge: true,
        ),
      );

      expect(result.initialClusterCount, 2);
      expect(result.mergedCount, 1);
      expect(result.clusters.length, 1);
      expect(result.clusters.first.length, 6);
    });

    test('cross-city clusters are not merged on same day', () {
      final day = DateTime(2026, 2, 20);
      final photos = <PhotoEntity>[
        _photo(
          id: 1,
          time: day.add(const Duration(hours: 9)),
          city: '杭州市',
          province: '浙江省',
          adcode: '330100',
        ),
        _photo(
          id: 2,
          time: day.add(const Duration(hours: 9, minutes: 10)),
          city: '杭州市',
          province: '浙江省',
          adcode: '330100',
        ),
        _photo(
          id: 3,
          time: day.add(const Duration(hours: 9, minutes: 20)),
          city: '杭州市',
          province: '浙江省',
          adcode: '330100',
        ),
        _photo(
          id: 4,
          time: day.add(const Duration(hours: 14)),
          city: '苏州市',
          province: '江苏省',
          adcode: '320500',
        ),
        _photo(
          id: 5,
          time: day.add(const Duration(hours: 14, minutes: 10)),
          city: '苏州市',
          province: '江苏省',
          adcode: '320500',
        ),
        _photo(
          id: 6,
          time: day.add(const Duration(hours: 14, minutes: 20)),
          city: '苏州市',
          province: '江苏省',
          adcode: '320500',
        ),
      ];

      final result = EventClusterHelper.clusterPhotos(photos: photos);

      expect(result.initialClusterCount, 2);
      expect(result.mergedCount, 0);
      expect(result.clusters.length, 2);
    });

    test('fallback same-city by GPS allows city threshold when city fields missing', () {
      final day = DateTime(2026, 2, 20);
      final photos = <PhotoEntity>[
        _photo(
          id: 1,
          time: day.add(const Duration(hours: 9)),
          lat: 22.5431,
          lon: 114.0579,
        ),
        _photo(
          id: 2,
          time: day.add(const Duration(hours: 13, minutes: 30)),
          lat: 22.6019,
          lon: 114.3162,
        ),
      ];

      final result = EventClusterHelper.clusterPhotos(
        photos: photos,
        config: const ClusterConfig(
          initialTimeThresholdHours: 3,
          sameCityTimeThresholdHours: 6,
          sameCityDistanceThresholdKm: 40,
          fallbackSameCityDistanceKm: 45,
        ),
      );

      expect(result.clusters.length, 1);
      expect(result.clusters.first.length, 2);
    });

    test('cross-day clusters can be merged when enabled and gap is within threshold', () {
      final day1 = DateTime(2026, 2, 20);
      final day2 = DateTime(2026, 2, 21);
      final photos = <PhotoEntity>[
        _photo(
          id: 1,
          time: day1.add(const Duration(hours: 19)),
          lat: 22.5431,
          lon: 114.0579,
        ),
        _photo(
          id: 2,
          time: day1.add(const Duration(hours: 19, minutes: 10)),
          lat: 22.5435,
          lon: 114.0583,
        ),
        _photo(
          id: 3,
          time: day1.add(const Duration(hours: 19, minutes: 20)),
          lat: 22.5440,
          lon: 114.0588,
        ),
        _photo(
          id: 4,
          time: day2.add(const Duration(hours: 8)),
          lat: 22.5460,
          lon: 114.0540,
        ),
        _photo(
          id: 5,
          time: day2.add(const Duration(hours: 8, minutes: 10)),
          lat: 22.5465,
          lon: 114.0546,
        ),
        _photo(
          id: 6,
          time: day2.add(const Duration(hours: 8, minutes: 20)),
          lat: 22.5470,
          lon: 114.0552,
        ),
      ];

      final result = EventClusterHelper.clusterPhotos(
        photos: photos,
        config: const ClusterConfig(
          initialTimeThresholdHours: 4,
          sameCityTimeThresholdHours: 6,
          sameCityDistanceThresholdKm: 20,
          fallbackSameCityDistanceKm: 45,
          sameDayMergeGapHours: 10,
          crossDayMergeGapHours: 18,
          minPhotosPerClusterForMerge: 3,
          enableSameDayTravelMerge: true,
          enableCrossDayTravelMerge: true,
        ),
      );

      expect(result.initialClusterCount, 2);
      expect(result.mergedCount, 1);
      expect(result.clusters.length, 1);
      expect(result.clusters.first.length, 6);
    });
  });
}
