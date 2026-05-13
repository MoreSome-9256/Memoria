// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_entity.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetEventEntityCollection on Isar {
  IsarCollection<EventEntity> get eventEntitys => this.collection();
}

const EventEntitySchema = CollectionSchema(
  name: r'EventEntity',
  id: -1764225715171335918,
  properties: {
    r'aiThemes': PropertySchema(
      id: 0,
      name: r'aiThemes',
      type: IsarType.stringList,
    ),
    r'analyzedPhotoCount': PropertySchema(
      id: 1,
      name: r'analyzedPhotoCount',
      type: IsarType.long,
    ),
    r'avgLatitude': PropertySchema(
      id: 2,
      name: r'avgLatitude',
      type: IsarType.double,
    ),
    r'avgLongitude': PropertySchema(
      id: 3,
      name: r'avgLongitude',
      type: IsarType.double,
    ),
    r'city': PropertySchema(
      id: 4,
      name: r'city',
      type: IsarType.string,
    ),
    r'coverPhotoId': PropertySchema(
      id: 5,
      name: r'coverPhotoId',
      type: IsarType.long,
    ),
    r'dateRangeText': PropertySchema(
      id: 6,
      name: r'dateRangeText',
      type: IsarType.string,
    ),
    r'district': PropertySchema(
      id: 7,
      name: r'district',
      type: IsarType.string,
    ),
    r'endTime': PropertySchema(
      id: 8,
      name: r'endTime',
      type: IsarType.long,
    ),
    r'formattedAddress': PropertySchema(
      id: 9,
      name: r'formattedAddress',
      type: IsarType.string,
    ),
    r'isLlmGenerated': PropertySchema(
      id: 10,
      name: r'isLlmGenerated',
      type: IsarType.bool,
    ),
    r'joyScore': PropertySchema(
      id: 11,
      name: r'joyScore',
      type: IsarType.double,
    ),
    r'location': PropertySchema(
      id: 12,
      name: r'location',
      type: IsarType.string,
    ),
    r'locationName': PropertySchema(
      id: 13,
      name: r'locationName',
      type: IsarType.string,
    ),
    r'photoCount': PropertySchema(
      id: 14,
      name: r'photoCount',
      type: IsarType.long,
    ),
    r'photoIds': PropertySchema(
      id: 15,
      name: r'photoIds',
      type: IsarType.longList,
    ),
    r'province': PropertySchema(
      id: 16,
      name: r'province',
      type: IsarType.string,
    ),
    r'season': PropertySchema(
      id: 17,
      name: r'season',
      type: IsarType.string,
    ),
    r'startTime': PropertySchema(
      id: 18,
      name: r'startTime',
      type: IsarType.long,
    ),
    r'tags': PropertySchema(
      id: 19,
      name: r'tags',
      type: IsarType.stringList,
    ),
    r'title': PropertySchema(
      id: 20,
      name: r'title',
      type: IsarType.string,
    ),
    r'year': PropertySchema(
      id: 21,
      name: r'year',
      type: IsarType.long,
    )
  },
  estimateSize: _eventEntityEstimateSize,
  serialize: _eventEntitySerialize,
  deserialize: _eventEntityDeserialize,
  deserializeProp: _eventEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _eventEntityGetId,
  getLinks: _eventEntityGetLinks,
  attach: _eventEntityAttach,
  version: '3.1.0+1',
);

int _eventEntityEstimateSize(
  EventEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final list = object.aiThemes;
    if (list != null) {
      bytesCount += 3 + list.length * 3;
      {
        for (var i = 0; i < list.length; i++) {
          final value = list[i];
          bytesCount += value.length * 3;
        }
      }
    }
  }
  {
    final value = object.city;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.dateRangeText.length * 3;
  {
    final value = object.district;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.formattedAddress;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.location.length * 3;
  {
    final value = object.locationName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.photoIds.length * 8;
  {
    final value = object.province;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.season.length * 3;
  bytesCount += 3 + object.tags.length * 3;
  {
    for (var i = 0; i < object.tags.length; i++) {
      final value = object.tags[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.title.length * 3;
  return bytesCount;
}

void _eventEntitySerialize(
  EventEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeStringList(offsets[0], object.aiThemes);
  writer.writeLong(offsets[1], object.analyzedPhotoCount);
  writer.writeDouble(offsets[2], object.avgLatitude);
  writer.writeDouble(offsets[3], object.avgLongitude);
  writer.writeString(offsets[4], object.city);
  writer.writeLong(offsets[5], object.coverPhotoId);
  writer.writeString(offsets[6], object.dateRangeText);
  writer.writeString(offsets[7], object.district);
  writer.writeLong(offsets[8], object.endTime);
  writer.writeString(offsets[9], object.formattedAddress);
  writer.writeBool(offsets[10], object.isLlmGenerated);
  writer.writeDouble(offsets[11], object.joyScore);
  writer.writeString(offsets[12], object.location);
  writer.writeString(offsets[13], object.locationName);
  writer.writeLong(offsets[14], object.photoCount);
  writer.writeLongList(offsets[15], object.photoIds);
  writer.writeString(offsets[16], object.province);
  writer.writeString(offsets[17], object.season);
  writer.writeLong(offsets[18], object.startTime);
  writer.writeStringList(offsets[19], object.tags);
  writer.writeString(offsets[20], object.title);
  writer.writeLong(offsets[21], object.year);
}

EventEntity _eventEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = EventEntity();
  object.aiThemes = reader.readStringList(offsets[0]);
  object.analyzedPhotoCount = reader.readLong(offsets[1]);
  object.avgLatitude = reader.readDoubleOrNull(offsets[2]);
  object.avgLongitude = reader.readDoubleOrNull(offsets[3]);
  object.city = reader.readStringOrNull(offsets[4]);
  object.coverPhotoId = reader.readLongOrNull(offsets[5]);
  object.district = reader.readStringOrNull(offsets[7]);
  object.endTime = reader.readLong(offsets[8]);
  object.formattedAddress = reader.readStringOrNull(offsets[9]);
  object.id = id;
  object.isLlmGenerated = reader.readBool(offsets[10]);
  object.joyScore = reader.readDoubleOrNull(offsets[11]);
  object.locationName = reader.readStringOrNull(offsets[13]);
  object.photoCount = reader.readLong(offsets[14]);
  object.photoIds = reader.readLongList(offsets[15]) ?? [];
  object.province = reader.readStringOrNull(offsets[16]);
  object.startTime = reader.readLong(offsets[18]);
  object.tags = reader.readStringList(offsets[19]) ?? [];
  object.title = reader.readString(offsets[20]);
  return object;
}

P _eventEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringList(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readDoubleOrNull(offset)) as P;
    case 3:
      return (reader.readDoubleOrNull(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readLongOrNull(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readLong(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readBool(offset)) as P;
    case 11:
      return (reader.readDoubleOrNull(offset)) as P;
    case 12:
      return (reader.readString(offset)) as P;
    case 13:
      return (reader.readStringOrNull(offset)) as P;
    case 14:
      return (reader.readLong(offset)) as P;
    case 15:
      return (reader.readLongList(offset) ?? []) as P;
    case 16:
      return (reader.readStringOrNull(offset)) as P;
    case 17:
      return (reader.readString(offset)) as P;
    case 18:
      return (reader.readLong(offset)) as P;
    case 19:
      return (reader.readStringList(offset) ?? []) as P;
    case 20:
      return (reader.readString(offset)) as P;
    case 21:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _eventEntityGetId(EventEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _eventEntityGetLinks(EventEntity object) {
  return [];
}

void _eventEntityAttach(
    IsarCollection<dynamic> col, Id id, EventEntity object) {
  object.id = id;
}

extension EventEntityQueryWhereSort
    on QueryBuilder<EventEntity, EventEntity, QWhere> {
  QueryBuilder<EventEntity, EventEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension EventEntityQueryWhere
    on QueryBuilder<EventEntity, EventEntity, QWhereClause> {
  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> idNotEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension EventEntityQueryFilter
    on QueryBuilder<EventEntity, EventEntity, QFilterCondition> {
  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'aiThemes',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'aiThemes',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'aiThemes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'aiThemes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'aiThemes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'aiThemes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'aiThemes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'aiThemes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'aiThemes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'aiThemes',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'aiThemes',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'aiThemes',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiThemes',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiThemes',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiThemes',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiThemes',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiThemes',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      aiThemesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiThemes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      analyzedPhotoCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'analyzedPhotoCount',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      analyzedPhotoCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'analyzedPhotoCount',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      analyzedPhotoCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'analyzedPhotoCount',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      analyzedPhotoCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'analyzedPhotoCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLatitudeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'avgLatitude',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLatitudeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'avgLatitude',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLatitudeEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'avgLatitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLatitudeGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'avgLatitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLatitudeLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'avgLatitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLatitudeBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'avgLatitude',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLongitudeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'avgLongitude',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLongitudeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'avgLongitude',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLongitudeEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'avgLongitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLongitudeGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'avgLongitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLongitudeLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'avgLongitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      avgLongitudeBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'avgLongitude',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> cityIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'city',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      cityIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'city',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> cityEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> cityGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> cityLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> cityBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'city',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> cityStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> cityEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> cityContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'city',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> cityMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'city',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> cityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'city',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      cityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'city',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      coverPhotoIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'coverPhotoId',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      coverPhotoIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'coverPhotoId',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      coverPhotoIdEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'coverPhotoId',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      coverPhotoIdGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'coverPhotoId',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      coverPhotoIdLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'coverPhotoId',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      coverPhotoIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'coverPhotoId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      dateRangeTextEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dateRangeText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      dateRangeTextGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'dateRangeText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      dateRangeTextLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'dateRangeText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      dateRangeTextBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'dateRangeText',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      dateRangeTextStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'dateRangeText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      dateRangeTextEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'dateRangeText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      dateRangeTextContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'dateRangeText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      dateRangeTextMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'dateRangeText',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      dateRangeTextIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dateRangeText',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      dateRangeTextIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'dateRangeText',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      districtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'district',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      districtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'district',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> districtEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'district',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      districtGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'district',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      districtLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'district',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> districtBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'district',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      districtStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'district',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      districtEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'district',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      districtContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'district',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> districtMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'district',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      districtIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'district',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      districtIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'district',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endTimeEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endTime',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      endTimeGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'endTime',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endTimeLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'endTime',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> endTimeBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'endTime',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'formattedAddress',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'formattedAddress',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'formattedAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'formattedAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'formattedAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'formattedAddress',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'formattedAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'formattedAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'formattedAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'formattedAddress',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'formattedAddress',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      formattedAddressIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'formattedAddress',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      isLlmGeneratedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isLlmGenerated',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      joyScoreIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'joyScore',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      joyScoreIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'joyScore',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> joyScoreEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'joyScore',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      joyScoreGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'joyScore',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      joyScoreLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'joyScore',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> joyScoreBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'joyScore',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> locationEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> locationBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'location',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'location',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> locationMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'location',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'location',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'location',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'locationName',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'locationName',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'locationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'locationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'locationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'locationName',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'locationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'locationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'locationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'locationName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'locationName',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      locationNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'locationName',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'photoCount',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'photoCount',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'photoCount',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'photoCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoIdsElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'photoIds',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoIdsElementGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'photoIds',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoIdsElementLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'photoIds',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoIdsElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'photoIds',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoIdsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'photoIds',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoIdsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'photoIds',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoIdsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'photoIds',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoIdsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'photoIds',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoIdsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'photoIds',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      photoIdsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'photoIds',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      provinceIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'province',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      provinceIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'province',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> provinceEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'province',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      provinceGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'province',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      provinceLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'province',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> provinceBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'province',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      provinceStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'province',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      provinceEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'province',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      provinceContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'province',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> provinceMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'province',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      provinceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'province',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      provinceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'province',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> seasonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'season',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      seasonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'season',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> seasonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'season',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> seasonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'season',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      seasonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'season',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> seasonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'season',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> seasonContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'season',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> seasonMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'season',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      seasonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'season',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      seasonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'season',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'startTime',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'startTime',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'startTime',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      startTimeBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'startTime',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'tags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'tags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'tags',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'tags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'tags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'tags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'tags',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tags',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'tags',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'tags',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> tagsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'tags',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'tags',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'tags',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'tags',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      tagsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'tags',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      titleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'title',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'title',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition>
      titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> yearEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'year',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> yearGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'year',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> yearLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'year',
        value: value,
      ));
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterFilterCondition> yearBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'year',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension EventEntityQueryObject
    on QueryBuilder<EventEntity, EventEntity, QFilterCondition> {}

extension EventEntityQueryLinks
    on QueryBuilder<EventEntity, EventEntity, QFilterCondition> {}

extension EventEntityQuerySortBy
    on QueryBuilder<EventEntity, EventEntity, QSortBy> {
  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByAnalyzedPhotoCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'analyzedPhotoCount', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByAnalyzedPhotoCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'analyzedPhotoCount', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByAvgLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avgLatitude', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByAvgLatitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avgLatitude', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByAvgLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avgLongitude', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByAvgLongitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avgLongitude', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByCity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByCityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByCoverPhotoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coverPhotoId', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByCoverPhotoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coverPhotoId', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByDateRangeText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dateRangeText', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByDateRangeTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dateRangeText', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByDistrict() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'district', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByDistrictDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'district', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByEndTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByEndTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByFormattedAddress() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedAddress', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByFormattedAddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedAddress', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByIsLlmGenerated() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLlmGenerated', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByIsLlmGeneratedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLlmGenerated', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByJoyScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'joyScore', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByJoyScoreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'joyScore', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByLocation() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByLocationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByLocationName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationName', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      sortByLocationNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationName', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByPhotoCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoCount', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByPhotoCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoCount', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByProvince() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'province', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByProvinceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'province', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortBySeason() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'season', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortBySeasonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'season', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByStartTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByStartTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByYear() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'year', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> sortByYearDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'year', Sort.desc);
    });
  }
}

extension EventEntityQuerySortThenBy
    on QueryBuilder<EventEntity, EventEntity, QSortThenBy> {
  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByAnalyzedPhotoCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'analyzedPhotoCount', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByAnalyzedPhotoCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'analyzedPhotoCount', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByAvgLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avgLatitude', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByAvgLatitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avgLatitude', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByAvgLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avgLongitude', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByAvgLongitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avgLongitude', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByCity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByCityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByCoverPhotoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coverPhotoId', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByCoverPhotoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'coverPhotoId', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByDateRangeText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dateRangeText', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByDateRangeTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dateRangeText', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByDistrict() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'district', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByDistrictDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'district', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByEndTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByEndTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endTime', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByFormattedAddress() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedAddress', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByFormattedAddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedAddress', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByIsLlmGenerated() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLlmGenerated', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByIsLlmGeneratedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLlmGenerated', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByJoyScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'joyScore', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByJoyScoreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'joyScore', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByLocation() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByLocationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'location', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByLocationName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationName', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy>
      thenByLocationNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationName', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByPhotoCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoCount', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByPhotoCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoCount', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByProvince() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'province', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByProvinceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'province', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenBySeason() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'season', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenBySeasonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'season', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByStartTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByStartTimeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'startTime', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByYear() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'year', Sort.asc);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QAfterSortBy> thenByYearDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'year', Sort.desc);
    });
  }
}

extension EventEntityQueryWhereDistinct
    on QueryBuilder<EventEntity, EventEntity, QDistinct> {
  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByAiThemes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'aiThemes');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct>
      distinctByAnalyzedPhotoCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'analyzedPhotoCount');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByAvgLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'avgLatitude');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByAvgLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'avgLongitude');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByCity(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'city', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByCoverPhotoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'coverPhotoId');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByDateRangeText(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dateRangeText',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByDistrict(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'district', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByEndTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endTime');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByFormattedAddress(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'formattedAddress',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByIsLlmGenerated() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isLlmGenerated');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByJoyScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'joyScore');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByLocation(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'location', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByLocationName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'locationName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByPhotoCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'photoCount');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByPhotoIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'photoIds');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByProvince(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'province', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctBySeason(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'season', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByStartTime() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'startTime');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByTags() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'tags');
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EventEntity, EventEntity, QDistinct> distinctByYear() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'year');
    });
  }
}

extension EventEntityQueryProperty
    on QueryBuilder<EventEntity, EventEntity, QQueryProperty> {
  QueryBuilder<EventEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<EventEntity, List<String>?, QQueryOperations>
      aiThemesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'aiThemes');
    });
  }

  QueryBuilder<EventEntity, int, QQueryOperations>
      analyzedPhotoCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'analyzedPhotoCount');
    });
  }

  QueryBuilder<EventEntity, double?, QQueryOperations> avgLatitudeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'avgLatitude');
    });
  }

  QueryBuilder<EventEntity, double?, QQueryOperations> avgLongitudeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'avgLongitude');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> cityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'city');
    });
  }

  QueryBuilder<EventEntity, int?, QQueryOperations> coverPhotoIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'coverPhotoId');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> dateRangeTextProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dateRangeText');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> districtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'district');
    });
  }

  QueryBuilder<EventEntity, int, QQueryOperations> endTimeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endTime');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations>
      formattedAddressProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'formattedAddress');
    });
  }

  QueryBuilder<EventEntity, bool, QQueryOperations> isLlmGeneratedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isLlmGenerated');
    });
  }

  QueryBuilder<EventEntity, double?, QQueryOperations> joyScoreProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'joyScore');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> locationProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'location');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> locationNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'locationName');
    });
  }

  QueryBuilder<EventEntity, int, QQueryOperations> photoCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'photoCount');
    });
  }

  QueryBuilder<EventEntity, List<int>, QQueryOperations> photoIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'photoIds');
    });
  }

  QueryBuilder<EventEntity, String?, QQueryOperations> provinceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'province');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> seasonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'season');
    });
  }

  QueryBuilder<EventEntity, int, QQueryOperations> startTimeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'startTime');
    });
  }

  QueryBuilder<EventEntity, List<String>, QQueryOperations> tagsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'tags');
    });
  }

  QueryBuilder<EventEntity, String, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<EventEntity, int, QQueryOperations> yearProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'year');
    });
  }
}
