// 高德逆地理编码共享工具。
//
// 可在主 isolate 与 foreground isolate 中通用，零 ObjectBox 依赖。

import 'api_proxy_service.dart';
import 'package:flutter/foundation.dart';

class AmapGeoResult {
  final String? country;
  final String? province;
  final String? city;
  final String? district;
  final String? locationName;
  final String? formattedAddress;
  final String? adcode;
  final String? township;
  final String? businessAreaText;
  final String? aoiNameText;
  final String? poiNameText;
  final String? aoiIdText;
  final String? poiIdText;

  const AmapGeoResult({
    this.country,
    this.province,
    this.city,
    this.district,
    this.locationName,
    this.formattedAddress,
    this.adcode,
    this.township,
    this.businessAreaText,
    this.aoiNameText,
    this.poiNameText,
    this.aoiIdText,
    this.poiIdText,
  });

  String get geoTextTokens =>
      <String?>[
            country,
            province,
            city,
            district,
            township,
            businessAreaText,
            aoiNameText,
            poiNameText,
            aoiIdText,
            poiIdText,
            locationName,
            formattedAddress,
            adcode,
          ]
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .map((value) => '|${value.trim()}|')
          .join();

  @override
  String toString() =>
      'AmapGeoResult(country: $country, province: $province, city: $city, district: $district, '
      'locationName: $locationName, formattedAddress: $formattedAddress, adcode: $adcode)';
}

class AmapGeoService {
  AmapGeoService._();

  /// 调用高德逆地理编码，返回解析后的地址字段。
  ///
  /// 失败时返回 null，不会抛异常。
  static Future<AmapGeoResult?> reverseGeocode({
    required double latitude,
    required double longitude,
    String extensions = 'base',
  }) async {
    if (latitude == 0 && longitude == 0) return null;

    try {
      final raw = await _callApi(
        latitude: latitude,
        longitude: longitude,
        extensions: extensions,
      );
      return _parseRegeocode(raw);
    } catch (error) {
      debugPrint(
        '[amap] reverse geocode failed lat=${latitude.toStringAsFixed(5)} '
        'lon=${longitude.toStringAsFixed(5)} error=$error',
      );
      return null;
    }
  }

  static Future<AmapPlaceResult?> searchPlace({
    required String keywords,
    String? city,
  }) async {
    if (keywords.trim().isEmpty) return null;
    try {
      final json = await _getJson(
        '/v1/amap/place/text',
        queryParameters: <String, String>{
          'keywords': keywords.trim(),
          if (city?.trim().isNotEmpty == true) 'city': city!.trim(),
          'citylimit': city?.trim().isNotEmpty == true ? 'true' : 'false',
          'offset': '5',
          'page': '1',
          'extensions': 'base',
        },
      );
      if (json is! Map || json['status'] != '1') return null;
      final pois = json['pois'];
      if (pois is! List || pois.isEmpty || pois.first is! Map) return null;
      return AmapPlaceResult.fromJson(
        (pois.first as Map).cast<String, dynamic>(),
      );
    } catch (error) {
      debugPrint('[amap] place search failed keywords=$keywords error=$error');
      return null;
    }
  }

  // ── 高德 API 调用 ──

  static Future<Map<String, dynamic>> _callApi({
    required double latitude,
    required double longitude,
    String extensions = 'base',
  }) async {
    final json =
        await _getJson(
              '/v1/amap/regeo',
              queryParameters: <String, String>{
                'location': '$longitude,$latitude',
                'extensions': extensions,
                'coordsys': 'gps',
              },
            )
            as Map<String, dynamic>;

    if (json['status'] != '1') {
      throw Exception('高德返回失败: ${json['info'] ?? '未知错误'}');
    }

    final regeocode = json['regeocode'];
    if (regeocode is! Map<String, dynamic>) {
      throw Exception('高德返回缺少regeocode');
    }
    return regeocode;
  }

  static Future<dynamic> _getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await ApiProxyService.instance.get<dynamic>(
      path,
      queryParameters: queryParameters,
    );
    return response.data;
  }

  // ── 地址字段提取 ──

  static AmapGeoResult _parseRegeocode(Map<String, dynamic> regeocode) {
    final addressComponent = regeocode['addressComponent'];
    if (addressComponent is! Map<String, dynamic>) {
      throw Exception('高德返回缺少addressComponent');
    }

    final country = _extractNonEmptyString(addressComponent, ['country']);
    final province = _extractNonEmptyString(addressComponent, ['province']);
    final district = _extractNonEmptyString(addressComponent, ['district']);
    String? city = _extractNonEmptyString(addressComponent, ['city']);
    city ??= district;
    city ??= province;
    final adcode = _extractNonEmptyString(addressComponent, ['adcode']);
    final township = _extractNonEmptyString(addressComponent, ['township']);
    final businessAreaText = _extractNamesText(
      addressComponent['businessAreas'],
    );
    final aoiNameText = _extractNamesText(regeocode['aois']);
    final poiNameText = _extractNamesText(regeocode['pois']);
    final aoiIdText = _extractValuesText(regeocode['aois'], 'id');
    final poiIdText = _extractValuesText(regeocode['pois'], 'id');
    final formattedAddress = _extractNonEmptyString(regeocode, [
      'formatted_address',
    ]);
    final locationName = _extractLocationName(
      regeocode,
      addressComponent,
      city: city,
      district: district,
      formattedAddress: formattedAddress,
    );

    return AmapGeoResult(
      country: country,
      province: province,
      city: city,
      district: district,
      locationName: locationName,
      formattedAddress: formattedAddress,
      adcode: adcode,
      township: township,
      businessAreaText: businessAreaText,
      aoiNameText: aoiNameText,
      poiNameText: poiNameText,
      aoiIdText: aoiIdText,
      poiIdText: poiIdText,
    );
  }

  // ── 提取帮助函数（从 event_service 迁移） ──

  static String? _extractNonEmptyString(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is String && first.trim().isNotEmpty) {
          return first.trim();
        }
      }
    }
    return null;
  }

  static String? _extractNamesText(dynamic value) {
    if (value is! List) return null;
    final names = value
        .whereType<Map>()
        .map(
          (item) =>
              _extractNonEmptyString(item.cast<String, dynamic>(), ['name']),
        )
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return names.isEmpty ? null : names.map((name) => '|$name|').join();
  }

  static String? _extractValuesText(dynamic value, String key) {
    if (value is! List) return null;
    final values = value
        .whereType<Map>()
        .map((item) => item[key]?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    return values.isEmpty ? null : values.map((item) => '|$item|').join();
  }

  static String? _extractLocationName(
    Map<String, dynamic> regeocode,
    Map<String, dynamic> addressComponent, {
    String? city,
    String? district,
    String? formattedAddress,
  }) {
    final poi = regeocode['pois'];
    if (poi is List && poi.isNotEmpty) {
      final firstPoi = poi.first;
      if (firstPoi is Map<String, dynamic>) {
        final poiName = _extractNonEmptyString(firstPoi, ['name']);
        if (_isUsefulLocationName(poiName, city: city, district: district)) {
          return poiName;
        }
      }
    }

    final aois = regeocode['aois'];
    if (aois is List && aois.isNotEmpty) {
      final firstAoi = aois.first;
      if (firstAoi is Map<String, dynamic>) {
        final aoiName = _extractNonEmptyString(firstAoi, ['name']);
        if (_isUsefulLocationName(aoiName, city: city, district: district)) {
          return aoiName;
        }
      }
    }

    final building = addressComponent['building'];
    if (building is Map<String, dynamic>) {
      final buildingName = _extractNonEmptyString(building, ['name']);
      if (_isUsefulLocationName(buildingName, city: city, district: district)) {
        return buildingName;
      }
    }

    final neighborhood = addressComponent['neighborhood'];
    if (neighborhood is Map<String, dynamic>) {
      final neighborhoodName = _extractNonEmptyString(neighborhood, ['name']);
      if (_isUsefulLocationName(
        neighborhoodName,
        city: city,
        district: district,
      )) {
        return neighborhoodName;
      }
    }

    final formattedAddressName = _extractLocationNameFromFormattedAddress(
      formattedAddress,
      addressComponent,
      city: city,
      district: district,
    );
    if (_isUsefulLocationName(
      formattedAddressName,
      city: city,
      district: district,
    )) {
      return formattedAddressName;
    }

    final township = _extractNonEmptyString(addressComponent, ['township']);
    if (_isUsefulLocationName(township, city: city, district: district)) {
      return township;
    }

    return district ?? city;
  }

  static String? _extractLocationNameFromFormattedAddress(
    String? formattedAddress,
    Map<String, dynamic> addressComponent, {
    String? city,
    String? district,
  }) {
    if (formattedAddress == null) return null;

    var candidate = formattedAddress.trim();
    if (candidate.isEmpty) return null;

    final province = _extractNonEmptyString(addressComponent, ['province']);
    final township = _extractNonEmptyString(addressComponent, ['township']);
    final streetName = _extractStreetName(addressComponent);
    final prefixes = <String>{
      if (province != null && province.isNotEmpty) province,
      if (city != null && city.isNotEmpty) city,
      if (district != null && district.isNotEmpty) district,
      if (township != null && township.isNotEmpty) township,
      if (streetName != null && streetName.isNotEmpty) streetName,
    }.toList()..sort((a, b) => b.length.compareTo(a.length));

    var changed = true;
    while (changed && candidate.isNotEmpty) {
      changed = false;
      for (final prefix in prefixes) {
        if (candidate.startsWith(prefix)) {
          candidate = candidate.substring(prefix.length).trim();
          changed = true;
        }
      }
      candidate = candidate.replaceFirst(RegExp(r'^[,，\s]+'), '').trim();
    }

    if (_isUsefulLocationName(candidate, city: city, district: district)) {
      return candidate;
    }

    return null;
  }

  static String? _extractStreetName(Map<String, dynamic> addressComponent) {
    final streetName = _extractNonEmptyString(addressComponent, ['street']);
    if (streetName != null && streetName.isNotEmpty) {
      return streetName;
    }

    final streetNumber = addressComponent['streetNumber'];
    if (streetNumber is Map<String, dynamic>) {
      return _extractNonEmptyString(streetNumber, ['street', 'name']);
    }

    return null;
  }

  static bool _isUsefulLocationName(
    String? value, {
    String? city,
    String? district,
  }) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return false;
    if (normalized == city || normalized == district) return false;
    const ignored = <String>{'[]', '[[]]'};
    if (ignored.contains(normalized)) return false;
    return true;
  }
}

class AmapPlaceResult {
  const AmapPlaceResult({
    required this.name,
    this.poiId,
    this.type,
    this.province,
    this.city,
    this.district,
    this.adcode,
    this.latitude,
    this.longitude,
  });

  factory AmapPlaceResult.fromJson(Map<String, dynamic> json) {
    final location =
        json['location']?.toString().split(',') ?? const <String>[];
    return AmapPlaceResult(
      name: json['name']?.toString().trim() ?? '',
      poiId: json['id']?.toString().trim(),
      type: json['type']?.toString().trim(),
      province: _value(json['pname']),
      city: _value(json['cityname']),
      district: _value(json['adname']),
      adcode: _value(json['adcode']),
      longitude: location.isNotEmpty ? double.tryParse(location[0]) : null,
      latitude: location.length > 1 ? double.tryParse(location[1]) : null,
    );
  }

  final String name;
  final String? poiId;
  final String? type;
  final String? province;
  final String? city;
  final String? district;
  final String? adcode;
  final double? latitude;
  final double? longitude;

  static String? _value(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is List && value.isNotEmpty) return _value(value.first);
    return null;
  }
}
