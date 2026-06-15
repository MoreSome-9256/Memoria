import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/place_search_policy.dart';

void main() {
  test('uses recall-oriented radii without allowing cross-city distances', () {
    final poi = PlaceSearchPolicy.radiusFor('poi');
    final scenic = PlaceSearchPolicy.radiusFor('scenic_area');
    final district = PlaceSearchPolicy.radiusFor('district');

    expect(poi.coreMeters, greaterThanOrEqualTo(2000));
    expect(poi.softMeters, greaterThan(poi.coreMeters));
    expect(scenic.coreMeters, greaterThan(poi.coreMeters));
    expect(district.softMeters, lessThanOrEqualTo(30000));
  });

  test('administrative regions rely on names instead of a point radius', () {
    for (final type in <String>['city', 'province', 'country']) {
      final radius = PlaceSearchPolicy.radiusFor(type);
      expect(radius.coreMeters, 0);
      expect(radius.softMeters, 0);
    }
  });

  test('all non-administrative soft radii stay below cross-city scale', () {
    for (final type in <String>[
      'poi',
      'scenic_area',
      'campus',
      'business_area',
      'neighborhood',
      'township',
      'district',
      'development_zone',
    ]) {
      expect(
        PlaceSearchPolicy.radiusFor(type).softMeters,
        lessThanOrEqualTo(30000),
      );
    }
  });

  test('POI aliases exclude only unambiguous administrative names', () {
    final aliases = PlaceSearchPolicy.searchAliases(
      type: 'poi',
      primary: '目标地点',
      aliases: const <String>['示例市', '示例区', '示例市目标地点', 'Target Place'],
      canonicalName: '目标地点景区',
    );

    expect(aliases, isNot(contains('示例市')));
    expect(aliases, contains('示例区'));
    expect(aliases, contains('示例市目标地点'));
    expect(aliases, contains('Target Place'));
    expect(aliases, contains('目标地点景区'));
  });
}
