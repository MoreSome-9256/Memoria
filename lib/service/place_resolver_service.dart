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
    input = _withInferredAdministrativeType(input);
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
    final resolvedType =
        _inferAdministrativeType(<String?>{
          resolved.name,
          input.text,
          ...input.aliases,
        }) ??
        input.type;
    final radius = PlaceSearchPolicy.radiusFor(resolvedType);
    final cache = PlaceResolveCacheEntity()
      ..lookupKey = lookup
      ..normalizedText = normalized
      ..queryText = input.text
      ..cityHint = cityHint
      ..resolvedKind = resolvedType
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
    final resolvedType =
        _inferAdministrativeType(<String?>{
          cache.canonicalName,
          input.text,
          ...input.aliases,
        }) ??
        (cache.resolvedKind.trim().isNotEmpty
            ? cache.resolvedKind
            : input.type);
    final radius = PlaceSearchPolicy.radiusFor(resolvedType);
    final aliases = PlaceSearchPolicy.searchAliases(
      type: resolvedType,
      primary: input.text,
      aliases: input.aliases,
      canonicalName: cache.canonicalName,
    );
    return SemanticSearchLocation(
      text: cache.canonicalName?.trim().isNotEmpty == true
          ? cache.canonicalName!
          : input.text,
      type: resolvedType,
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

  SemanticSearchLocation _withInferredAdministrativeType(
    SemanticSearchLocation input,
  ) {
    final inferred = _inferAdministrativeType(<String?>{
      input.text,
      ...input.aliases,
    });
    if (inferred == null || inferred == input.type) {
      return input;
    }
    if (input.type != 'poi') {
      return input;
    }
    return input.copyWithType(inferred);
  }

  String? _inferAdministrativeType(Iterable<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) {
        continue;
      }
      if (RegExp(r'^[\u4e00-\u9fff]{2,}(省|自治区|特别行政区)$').hasMatch(trimmed)) {
        return 'province';
      }
      if (RegExp(r'^[\u4e00-\u9fff]{2,}(市|自治州)$').hasMatch(trimmed)) {
        return 'city';
      }
      if (RegExp(r'^[\u4e00-\u9fff]{2,}(县|旗|自治县)$').hasMatch(trimmed)) {
        return 'district';
      }
    }
    return null;
  }
}
