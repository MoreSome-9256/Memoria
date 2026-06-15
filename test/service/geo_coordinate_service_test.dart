import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/geo_coordinate_service.dart';

void main() {
  test('keeps coordinates outside China unchanged', () {
    final result = GeoCoordinateService.wgs84ToGcj02(21.3069, -157.8583);

    expect(result.latitude, closeTo(21.3069, 0.000001));
    expect(result.longitude, closeTo(-157.8583, 0.000001));
  });

  test('converts Chinese WGS84 coordinates and builds tiered cells', () {
    final result = GeoCoordinateService.wgs84ToGcj02(39.9087, 116.3975);

    expect(result.latitude, isNot(closeTo(39.9087, 0.000001)));
    expect(result.longitude, isNot(closeTo(116.3975, 0.000001)));
    expect(
      GeoCoordinateService.cellKey(result.latitude, result.longitude, 3),
      matches(RegExp(r'^\d+\.\d{3},\d+\.\d{3}$')),
    );
    expect(
      GeoCoordinateService.cellKey(result.latitude, result.longitude, 1),
      matches(RegExp(r'^\d+\.\d,\d+\.\d$')),
    );
  });

  test('calculates useful nearby distances', () {
    final distance = GeoCoordinateService.distanceMeters(
      39.9087,
      116.3975,
      39.9097,
      116.3975,
    );

    expect(distance, inInclusiveRange(105, 118));
  });
}
