// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'story_entity.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetStoryEntityCollection on Isar {
  IsarCollection<StoryEntity> get storyEntitys => this.collection();
}

const StoryEntitySchema = CollectionSchema(
  name: r'StoryEntity',
  id: -2239914619125153475,
  properties: {
    r'content': PropertySchema(
      id: 0,
      name: r'content',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.long,
    ),
    r'createdAtText': PropertySchema(
      id: 2,
      name: r'createdAtText',
      type: IsarType.string,
    ),
    r'eventId': PropertySchema(
      id: 3,
      name: r'eventId',
      type: IsarType.long,
    ),
    r'isHorizontal': PropertySchema(
      id: 4,
      name: r'isHorizontal',
      type: IsarType.bool,
    ),
    r'isLlmGenerated': PropertySchema(
      id: 5,
      name: r'isLlmGenerated',
      type: IsarType.bool,
    ),
    r'photoCount': PropertySchema(
      id: 6,
      name: r'photoCount',
      type: IsarType.long,
    ),
    r'photoIds': PropertySchema(
      id: 7,
      name: r'photoIds',
      type: IsarType.longList,
    ),
    r'subtitle': PropertySchema(
      id: 8,
      name: r'subtitle',
      type: IsarType.string,
    ),
    r'targetPlatform': PropertySchema(
      id: 9,
      name: r'targetPlatform',
      type: IsarType.string,
    ),
    r'title': PropertySchema(
      id: 10,
      name: r'title',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 11,
      name: r'updatedAt',
      type: IsarType.long,
    )
  },
  estimateSize: _storyEntityEstimateSize,
  serialize: _storyEntitySerialize,
  deserialize: _storyEntityDeserialize,
  deserializeProp: _storyEntityDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _storyEntityGetId,
  getLinks: _storyEntityGetLinks,
  attach: _storyEntityAttach,
  version: '3.1.0+1',
);

int _storyEntityEstimateSize(
  StoryEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.content.length * 3;
  bytesCount += 3 + object.createdAtText.length * 3;
  bytesCount += 3 + object.photoIds.length * 8;
  bytesCount += 3 + object.subtitle.length * 3;
  {
    final value = object.targetPlatform;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.title.length * 3;
  return bytesCount;
}

void _storyEntitySerialize(
  StoryEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.content);
  writer.writeLong(offsets[1], object.createdAt);
  writer.writeString(offsets[2], object.createdAtText);
  writer.writeLong(offsets[3], object.eventId);
  writer.writeBool(offsets[4], object.isHorizontal);
  writer.writeBool(offsets[5], object.isLlmGenerated);
  writer.writeLong(offsets[6], object.photoCount);
  writer.writeLongList(offsets[7], object.photoIds);
  writer.writeString(offsets[8], object.subtitle);
  writer.writeString(offsets[9], object.targetPlatform);
  writer.writeString(offsets[10], object.title);
  writer.writeLong(offsets[11], object.updatedAt);
}

StoryEntity _storyEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = StoryEntity();
  object.content = reader.readString(offsets[0]);
  object.createdAt = reader.readLong(offsets[1]);
  object.eventId = reader.readLong(offsets[3]);
  object.id = id;
  object.isHorizontal = reader.readBool(offsets[4]);
  object.isLlmGenerated = reader.readBool(offsets[5]);
  object.photoCount = reader.readLong(offsets[6]);
  object.photoIds = reader.readLongList(offsets[7]) ?? [];
  object.subtitle = reader.readString(offsets[8]);
  object.targetPlatform = reader.readStringOrNull(offsets[9]);
  object.title = reader.readString(offsets[10]);
  object.updatedAt = reader.readLong(offsets[11]);
  return object;
}

P _storyEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readBool(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    case 7:
      return (reader.readLongList(offset) ?? []) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _storyEntityGetId(StoryEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _storyEntityGetLinks(StoryEntity object) {
  return [];
}

void _storyEntityAttach(
    IsarCollection<dynamic> col, Id id, StoryEntity object) {
  object.id = id;
}

extension StoryEntityQueryWhereSort
    on QueryBuilder<StoryEntity, StoryEntity, QWhere> {
  QueryBuilder<StoryEntity, StoryEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension StoryEntityQueryWhere
    on QueryBuilder<StoryEntity, StoryEntity, QWhereClause> {
  QueryBuilder<StoryEntity, StoryEntity, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterWhereClause> idNotEqualTo(
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterWhereClause> idBetween(
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

extension StoryEntityQueryFilter
    on QueryBuilder<StoryEntity, StoryEntity, QFilterCondition> {
  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> contentEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      contentGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> contentLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> contentBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'content',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      contentStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> contentEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> contentContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'content',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> contentMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'content',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      contentIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'content',
        value: '',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      contentIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'content',
        value: '',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtTextEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAtText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtTextGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'createdAtText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtTextLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'createdAtText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtTextBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'createdAtText',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtTextStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'createdAtText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtTextEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'createdAtText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtTextContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'createdAtText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtTextMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'createdAtText',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtTextIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAtText',
        value: '',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      createdAtTextIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'createdAtText',
        value: '',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> eventIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'eventId',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      eventIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'eventId',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> eventIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'eventId',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> eventIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'eventId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> idBetween(
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      isHorizontalEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isHorizontal',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      isLlmGeneratedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isLlmGenerated',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      photoCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'photoCount',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      photoIdsElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'photoIds',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> subtitleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'subtitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      subtitleGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'subtitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      subtitleLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'subtitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> subtitleBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'subtitle',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      subtitleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'subtitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      subtitleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'subtitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      subtitleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'subtitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> subtitleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'subtitle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      subtitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'subtitle',
        value: '',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      subtitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'subtitle',
        value: '',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'targetPlatform',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'targetPlatform',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'targetPlatform',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'targetPlatform',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'targetPlatform',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'targetPlatform',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'targetPlatform',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'targetPlatform',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'targetPlatform',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'targetPlatform',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'targetPlatform',
        value: '',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      targetPlatformIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'targetPlatform',
        value: '',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> titleEqualTo(
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> titleLessThan(
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> titleBetween(
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> titleStartsWith(
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> titleEndsWith(
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> titleContains(
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> titleMatches(
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

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      updatedAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      updatedAtGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      updatedAtLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterFilterCondition>
      updatedAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension StoryEntityQueryObject
    on QueryBuilder<StoryEntity, StoryEntity, QFilterCondition> {}

extension StoryEntityQueryLinks
    on QueryBuilder<StoryEntity, StoryEntity, QFilterCondition> {}

extension StoryEntityQuerySortBy
    on QueryBuilder<StoryEntity, StoryEntity, QSortBy> {
  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByCreatedAtText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtText', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy>
      sortByCreatedAtTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtText', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByEventId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventId', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByEventIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventId', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByIsHorizontal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isHorizontal', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy>
      sortByIsHorizontalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isHorizontal', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByIsLlmGenerated() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLlmGenerated', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy>
      sortByIsLlmGeneratedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLlmGenerated', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByPhotoCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoCount', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByPhotoCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoCount', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortBySubtitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortBySubtitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByTargetPlatform() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetPlatform', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy>
      sortByTargetPlatformDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetPlatform', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension StoryEntityQuerySortThenBy
    on QueryBuilder<StoryEntity, StoryEntity, QSortThenBy> {
  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByContent() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByContentDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'content', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByCreatedAtText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtText', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy>
      thenByCreatedAtTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAtText', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByEventId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventId', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByEventIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventId', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByIsHorizontal() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isHorizontal', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy>
      thenByIsHorizontalDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isHorizontal', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByIsLlmGenerated() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLlmGenerated', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy>
      thenByIsLlmGeneratedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLlmGenerated', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByPhotoCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoCount', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByPhotoCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoCount', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenBySubtitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenBySubtitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByTargetPlatform() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetPlatform', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy>
      thenByTargetPlatformDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'targetPlatform', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension StoryEntityQueryWhereDistinct
    on QueryBuilder<StoryEntity, StoryEntity, QDistinct> {
  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctByContent(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'content', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctByCreatedAtText(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAtText',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctByEventId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'eventId');
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctByIsHorizontal() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isHorizontal');
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctByIsLlmGenerated() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isLlmGenerated');
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctByPhotoCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'photoCount');
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctByPhotoIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'photoIds');
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctBySubtitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'subtitle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctByTargetPlatform(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'targetPlatform',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctByTitle(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<StoryEntity, StoryEntity, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension StoryEntityQueryProperty
    on QueryBuilder<StoryEntity, StoryEntity, QQueryProperty> {
  QueryBuilder<StoryEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<StoryEntity, String, QQueryOperations> contentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'content');
    });
  }

  QueryBuilder<StoryEntity, int, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<StoryEntity, String, QQueryOperations> createdAtTextProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAtText');
    });
  }

  QueryBuilder<StoryEntity, int, QQueryOperations> eventIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'eventId');
    });
  }

  QueryBuilder<StoryEntity, bool, QQueryOperations> isHorizontalProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isHorizontal');
    });
  }

  QueryBuilder<StoryEntity, bool, QQueryOperations> isLlmGeneratedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isLlmGenerated');
    });
  }

  QueryBuilder<StoryEntity, int, QQueryOperations> photoCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'photoCount');
    });
  }

  QueryBuilder<StoryEntity, List<int>, QQueryOperations> photoIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'photoIds');
    });
  }

  QueryBuilder<StoryEntity, String, QQueryOperations> subtitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'subtitle');
    });
  }

  QueryBuilder<StoryEntity, String?, QQueryOperations>
      targetPlatformProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'targetPlatform');
    });
  }

  QueryBuilder<StoryEntity, String, QQueryOperations> titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<StoryEntity, int, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
