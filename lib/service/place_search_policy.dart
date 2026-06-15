class PlaceSearchRadius {
  const PlaceSearchRadius({required this.coreMeters, required this.softMeters});

  final int coreMeters;
  final int softMeters;
}

class PlaceSearchPolicy {
  const PlaceSearchPolicy._();

  static PlaceSearchRadius radiusFor(String type) => switch (type) {
    'country' ||
    'province' ||
    'city' => const PlaceSearchRadius(coreMeters: 0, softMeters: 0),
    'district' || 'development_zone' => const PlaceSearchRadius(
      coreMeters: 15000,
      softMeters: 30000,
    ),
    'campus' || 'scenic_area' => const PlaceSearchRadius(
      coreMeters: 5000,
      softMeters: 15000,
    ),
    'business_area' ||
    'neighborhood' ||
    'township' => const PlaceSearchRadius(coreMeters: 4000, softMeters: 12000),
    _ => const PlaceSearchRadius(coreMeters: 2500, softMeters: 8000),
  };

  static List<String> searchAliases({
    required String type,
    required String primary,
    required Iterable<String> aliases,
    String? canonicalName,
  }) {
    final candidates = <String>{primary, ...aliases};
    if (canonicalName?.trim().isNotEmpty == true) {
      candidates.add(canonicalName!.trim());
    }
    if (!_isPoiLike(type)) return candidates.toList(growable: false);
    return candidates
        .where((value) => !_isStandaloneAdministrativeName(value))
        .toList(growable: false);
  }

  static bool _isPoiLike(String type) => switch (type) {
    'poi' ||
    'scenic_area' ||
    'campus' ||
    'business_area' ||
    'neighborhood' => true,
    _ => false,
  };

  static bool _isStandaloneAdministrativeName(String value) {
    final trimmed = value.trim();
    return RegExp(
      r'^[\u4e00-\u9fff]{2,}(省|市|县|自治州|自治区|特别行政区)$',
    ).hasMatch(trimmed);
  }
}
