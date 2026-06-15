import '../models/entity/place_resolve_cache_entity.dart';
import '../models/vo/semantic_search_models.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import 'amap_geo_service.dart';

class PlaceResolverService {
  PlaceResolverService._();
  static final PlaceResolverService instance = PlaceResolverService._();

  Future<List<SemanticSearchLocation>> resolveAll(
    List<SemanticSearchLocation> locations,
  ) async {
    final results = <SemanticSearchLocation>[];
    for (final location in locations) {
      results.add(await resolve(location));
    }
    return results;
  }

  Future<SemanticSearchLocation> resolve(SemanticSearchLocation input) async {
    if (input.type == 'region_concept') return input;
    final box = ObjectBoxService().store.box<PlaceResolveCacheEntity>();
    final normalized = _normalize(input.text);
    final lookup = '$normalized|${input.aliases.map(_normalize).join(',')}';
    final query = box
        .query(PlaceResolveCacheEntity_.lookupKey.equals(lookup))
        .build();
    final cached = query.findFirst();
    query.close();
    if (cached != null) return _fromCache(input, cached);

    AmapPlaceResult? resolved;
    for (final keyword in <String>{input.text, ...input.aliases}) {
      resolved = await AmapGeoService.searchPlace(keywords: keyword);
      if (resolved != null) break;
    }
    if (resolved == null) return input;
    final nearby = input.strictness == 'nearby' || input.allowNearbySiblings;
    final cache = PlaceResolveCacheEntity()
      ..lookupKey = lookup
      ..normalizedText = normalized
      ..queryText = input.text
      ..resolvedKind = input.type
      ..canonicalName = resolved.name
      ..amapPoiId = resolved.poiId
      ..province = resolved.province
      ..city = resolved.city
      ..district = resolved.district
      ..adcode = resolved.adcode
      ..centerLatAmapE6 = resolved.latitude == null
          ? null
          : (resolved.latitude! * 1000000).round()
      ..centerLonAmapE6 = resolved.longitude == null
          ? null
          : (resolved.longitude! * 1000000).round()
      ..coreRadiusMeters = _coreRadius(input.type)
      ..softRadiusMeters = nearby ? 3000 : _softRadius(input.type)
      ..aliasesText = '|${<String>{input.text, ...input.aliases}.join('|')}|'
      ..confidence = 0.9
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    box.put(cache);
    return _fromCache(input, cache);
  }

  SemanticSearchLocation _fromCache(
    SemanticSearchLocation input,
    PlaceResolveCacheEntity cache,
  ) {
    return SemanticSearchLocation(
      text: cache.canonicalName?.trim().isNotEmpty == true
          ? cache.canonicalName!
          : input.text,
      type: input.type,
      aliases: <String>{
        input.text,
        ...input.aliases,
        if (cache.canonicalName != null) cache.canonicalName!,
        if (cache.province != null) cache.province!,
        if (cache.city != null) cache.city!,
        if (cache.district != null) cache.district!,
      }.toList(growable: false),
      timezone: input.timezone,
      utcOffsetMinutes: input.utcOffsetMinutes,
      strictness: input.strictness,
      allowDescendants: input.allowDescendants,
      allowNearbySiblings: input.allowNearbySiblings,
      countryCandidates: input.countryCandidates,
      amapPoiId: cache.amapPoiId,
      amapAoiId: cache.amapAoiId,
      adcode: cache.adcode,
      centerLatAmapE6: cache.centerLatAmapE6,
      centerLonAmapE6: cache.centerLonAmapE6,
      coreRadiusMeters: cache.coreRadiusMeters,
      softRadiusMeters: cache.softRadiusMeters,
    );
  }

  int _coreRadius(String type) => switch (type) {
    'city' || 'province' || 'country' => 0,
    'district' => 5000,
    'campus' || 'scenic_area' => 1000,
    _ => 350,
  };

  int _softRadius(String type) => switch (type) {
    'city' || 'province' || 'country' => 0,
    'district' => 10000,
    'campus' || 'scenic_area' => 2500,
    _ => 1000,
  };

  String _normalize(String value) => value.trim().toLowerCase().replaceAll(
    RegExp(r'[\s,，.。;；:：\-_/\\()（）]+'),
    '',
  );
}
