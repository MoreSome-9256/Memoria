import '../models/entity/place_resolve_cache_entity.dart';
import '../models/vo/semantic_search_models.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import 'amap_geo_service.dart';
import 'place_search_policy.dart';

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
    final cityHint = _cityHint(input);
    final lookup =
        '$normalized|${input.aliases.map(_normalize).join(',')}|${_normalize(cityHint ?? '')}';
    final query = box
        .query(PlaceResolveCacheEntity_.lookupKey.equals(lookup))
        .build();
    final cached = query.findFirst();
    query.close();
    if (cached != null) return _fromCache(input, cached);

    AmapPlaceResult? resolved;
    for (final keyword in <String>{input.text, ...input.aliases}) {
      resolved = await AmapGeoService.searchPlace(
        keywords: keyword,
        city: cityHint,
      );
      if (resolved != null) break;
    }
    if (resolved == null) return input;
    final radius = PlaceSearchPolicy.radiusFor(input.type);
    final cache = PlaceResolveCacheEntity()
      ..lookupKey = lookup
      ..normalizedText = normalized
      ..queryText = input.text
      ..cityHint = cityHint
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
      ..coreRadiusMeters = radius.coreMeters
      ..softRadiusMeters = radius.softMeters
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
    final radius = PlaceSearchPolicy.radiusFor(input.type);
    final aliases = PlaceSearchPolicy.searchAliases(
      type: input.type,
      primary: input.text,
      aliases: input.aliases,
      canonicalName: cache.canonicalName,
    );
    return SemanticSearchLocation(
      text: cache.canonicalName?.trim().isNotEmpty == true
          ? cache.canonicalName!
          : input.text,
      type: input.type,
      aliases: aliases,
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
      coreRadiusMeters: radius.coreMeters,
      softRadiusMeters: radius.softMeters,
    );
  }

  String? _cityHint(SemanticSearchLocation input) {
    if (input.type == 'city') return input.text;
    for (final value in <String>[input.text, ...input.aliases]) {
      final trimmed = value.trim();
      if (RegExp(r'[\u4e00-\u9fff]{2,}(市|自治州)$').hasMatch(trimmed)) {
        return trimmed;
      }
    }
    return null;
  }

  String _normalize(String value) => value.trim().toLowerCase().replaceAll(
    RegExp(r'[\s,，.。;；:：\-_/\\()（）]+'),
    '',
  );
}
