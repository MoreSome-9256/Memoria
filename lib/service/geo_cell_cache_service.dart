import '../models/entity/geo_cell_cache_entity.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import 'amap_geo_service.dart';
import 'geo_coordinate_service.dart';

class GeoCellCacheService {
  GeoCellCacheService._();
  static final GeoCellCacheService instance = GeoCellCacheService._();

  Future<AmapGeoResult?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    final amap = GeoCoordinateService.wgs84ToGcj02(latitude, longitude);
    final cell = GeoCoordinateService.cellKey(amap.latitude, amap.longitude, 3);
    final box = ObjectBoxService().store.box<GeoCellCacheEntity>();
    final query = box
        .query(GeoCellCacheEntity_.lookupKey.equals('3|$cell'))
        .build();
    final cached = query.findFirst();
    query.close();
    if (cached != null) return _fromCache(cached);

    final result = await AmapGeoService.reverseGeocode(
      latitude: latitude,
      longitude: longitude,
      extensions: 'all',
    );
    if (result == null) return null;
    box.put(
      GeoCellCacheEntity()
        ..lookupKey = '3|$cell'
        ..cellKey = cell
        ..level = 3
        ..centerLatAmapE6 = amap.latitudeE6
        ..centerLonAmapE6 = amap.longitudeE6
        ..country = result.country
        ..province = result.province
        ..city = result.city
        ..district = result.district
        ..adcode = result.adcode
        ..township = result.township
        ..locationName = result.locationName
        ..formattedAddress = result.formattedAddress
        ..businessAreaText = result.businessAreaText
        ..aoiIdText = result.aoiIdText
        ..aoiSummaryText = result.aoiNameText
        ..poiIdText = result.poiIdText
        ..poiSummaryText = result.poiNameText
        ..geoTextTokens = result.geoTextTokens
        ..updatedAt = DateTime.now().millisecondsSinceEpoch,
    );
    return result;
  }

  AmapGeoResult _fromCache(GeoCellCacheEntity value) => AmapGeoResult(
    country: value.country,
    province: value.province,
    city: value.city,
    district: value.district,
    adcode: value.adcode,
    township: value.township,
    locationName: value.locationName,
    formattedAddress: value.formattedAddress,
    businessAreaText: value.businessAreaText,
    aoiIdText: value.aoiIdText,
    aoiNameText: value.aoiSummaryText,
    poiIdText: value.poiIdText,
    poiNameText: value.poiSummaryText,
  );
}
