/// 高德逆地理编码共享工具。
///
/// 可在主 isolate 与 foreground isolate 中通用，零 ObjectBox 依赖。
///
/// 用法：
/// ```dart
/// final addr = await AmapGeoService.reverseGeocode(lat, lng);
/// if (addr != null) {
///   print(addr.city); // "青岛市"
/// }
/// ```

import 'dart:convert';
import 'dart:io';

class AmapGeoResult {
  final String? province;
  final String? city;
  final String? district;
  final String? locationName;
  final String? formattedAddress;
  final String? adcode;

  const AmapGeoResult({
    this.province,
    this.city,
    this.district,
    this.locationName,
    this.formattedAddress,
    this.adcode,
  });

  @override
  String toString() =>
      'AmapGeoResult(province: $province, city: $city, district: $district, '
      'locationName: $locationName, formattedAddress: $formattedAddress, adcode: $adcode)';
}

class AmapGeoService {
  AmapGeoService._();

  static const String _amapWebKey = String.fromEnvironment(
    'AMAP_WEB_KEY',
    defaultValue: '7fe01f8a449b2aac28068feac9177316',
  );

  /// 调用高德逆地理编码，返回解析后的地址字段。
  ///
  /// 失败时返回 null，不会抛异常。
  static Future<AmapGeoResult?> reverseGeocode({
    required double latitude,
    required double longitude,
    String extensions = 'base',
  }) async {
    if (_amapWebKey.trim().isEmpty) return null;
    if (latitude == 0 && longitude == 0) return null;

    try {
      final raw = await _callApi(
        latitude: latitude,
        longitude: longitude,
        extensions: extensions,
      );
      return _parseRegeocode(raw);
    } catch (_) {
      return null;
    }
  }

  // ── 高德 API 调用 ──

  static Future<Map<String, dynamic>> _callApi({
    required double latitude,
    required double longitude,
    String extensions = 'base',
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.https(
        'restapi.amap.com',
        '/v3/geocode/regeo',
        <String, String>{
          'key': _amapWebKey,
          'location': '$longitude,$latitude',
          'extensions': extensions,
          'coordsys': 'gps',
        },
      );
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json['status'] != '1') {
        throw Exception('高德返回失败: ${json['info'] ?? '未知错误'}');
      }

      final regeocode = json['regeocode'];
      if (regeocode is! Map<String, dynamic>) {
        throw Exception('高德返回缺少regeocode');
      }
      return regeocode;
    } finally {
      client.close();
    }
  }

  // ── 地址字段提取 ──

  static AmapGeoResult _parseRegeocode(Map<String, dynamic> regeocode) {
    final addressComponent = regeocode['addressComponent'];
    if (addressComponent is! Map<String, dynamic>) {
      throw Exception('高德返回缺少addressComponent');
    }

    final province = _extractNonEmptyString(addressComponent, ['province']);
    final district = _extractNonEmptyString(addressComponent, ['district']);
    String? city = _extractNonEmptyString(addressComponent, ['city']);
    city ??= district;
    city ??= province;
    final adcode = _extractNonEmptyString(addressComponent, ['adcode']);
    final formattedAddress = _extractNonEmptyString(
      regeocode, ['formatted_address'],
    );
    final locationName = _extractLocationName(
      regeocode,
      addressComponent,
      city: city,
      district: district,
      formattedAddress: formattedAddress,
    );

    return AmapGeoResult(
      province: province,
      city: city,
      district: district,
      locationName: locationName,
      formattedAddress: formattedAddress,
      adcode: adcode,
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
      if (_isUsefulLocationName(neighborhoodName, city: city, district: district)) {
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
    }.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

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

  static bool _isUsefulLocationName(String? value, {String? city, String? district}) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return false;
    if (normalized == city || normalized == district) return false;
    const ignored = <String>{'[]', '[[]]'};
    if (ignored.contains(normalized)) return false;
    return true;
  }
}
