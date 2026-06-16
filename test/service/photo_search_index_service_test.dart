import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/service/amap_geo_service.dart';
import 'package:photo_album/service/photo_search_index_service.dart';

void main() {
  test('derives all mechanical time indexes from timestamp', () {
    final time = DateTime(2026, 6, 15, 19, 42);
    final photo = PhotoEntity()..timestamp = time.millisecondsSinceEpoch;

    expect(PhotoSearchIndexService.updateTimeFields(photo), isTrue);
    expect(photo.capturedAtMillis, time.millisecondsSinceEpoch);
    expect(photo.capturedYear, 2026);
    expect(photo.capturedMonth, 6);
    expect(photo.capturedDay, 15);
    expect(photo.capturedMinuteOfDay, 19 * 60 + 42);
    expect(photo.capturedWeekday, DateTime.monday);
    expect(photo.searchIndexVersion, PhotoSearchIndexService.currentVersion);
    expect(PhotoSearchIndexService.updateTimeFields(photo), isFalse);
  });

  test('normalizes legacy second timestamps', () {
    final time = DateTime(2025, 1, 2, 3, 4);
    final photo = PhotoEntity()
      ..timestamp = time.millisecondsSinceEpoch ~/ 1000;

    PhotoSearchIndexService.updateTimeFields(photo);

    expect(photo.capturedAtMillis, time.millisecondsSinceEpoch);
    expect(photo.capturedYear, 2025);
    expect(photo.capturedMinuteOfDay, 184);
  });

  test('builds compact geo tokens from lightweight Amap fields', () {
    const result = AmapGeoResult(
      country: '中国',
      province: '山东省',
      city: '济南市',
      district: '历下区',
      township: '舜华路街道',
      businessAreaText: '|齐鲁软件园|',
      aoiNameText: '|山东大学软件园校区|',
      poiNameText: '|山东大学软件园校区食堂|',
    );

    expect(result.geoTextTokens, contains('|山东大学软件园校区|'));
    expect(result.geoTextTokens, contains('|济南市|'));
  });

  test('derives Amap coordinates and tiered geo cells', () {
    final photo = PhotoEntity()
      ..latitude = 39.9087
      ..longitude = 116.3975;

    expect(PhotoSearchIndexService.updateCoordinateFields(photo), isTrue);
    expect(photo.latAmapE6, isNotNull);
    expect(photo.lonAmapE6, isNotNull);
    expect(photo.geoCellFine, isNotEmpty);
    expect(photo.geoCellMid, isNotEmpty);
    expect(photo.geoCellCoarse, isNotEmpty);
    expect(PhotoSearchIndexService.updateCoordinateFields(photo), isFalse);
  });
}
