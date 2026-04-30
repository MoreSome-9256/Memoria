// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_recommendation_entity.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetCreateRecommendationEntityCollection on Isar {
  IsarCollection<CreateRecommendationEntity> get createRecommendationEntitys =>
      this.collection();
}

const CreateRecommendationEntitySchema = CollectionSchema(
  name: r'CreateRecommendationEntity',
  id: -502805306209220599,
  properties: {
    r'coverPhotoIds': PropertySchema(
      id: 0,
      name: r'coverPhotoIds',
      type: IsarType.longList,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.long,
    ),
    r'group': PropertySchema(
      id: 2,
      name: r'group',
      type: IsarType.string,
    ),
    r'isActive': PropertySchema(
      id: 3,
      name: r'isActive',
      type: IsarType.bool,
    ),
    r'label': PropertySchema(
      id: 4,
      name: r'label',
      type: IsarType.string,
    ),
    r'lastCheckedAt': PropertySchema(
      id: 5,
      name: r'lastCheckedAt',
      type: IsarType.long,
    ),
    r'lastRecommendedAt': PropertySchema(
      id: 6,
      name: r'lastRecommendedAt',
      type: IsarType.long,
    ),
    r'matchedCount': PropertySchema(
      id: 7,
      name: r'matchedCount',
      type: IsarType.long,
    ),
    r'nextCheckAt': PropertySchema(
      id: 8,
      name: r'nextCheckAt',
      type: IsarType.long,
    ),
    r'photoIds': PropertySchema(
      id: 9,
      name: r'photoIds',
      type: IsarType.longList,
    ),
    r'presetId': PropertySchema(
      id: 10,
      name: r'presetId',
      type: IsarType.string,
    ),
    r'priority': PropertySchema(
      id: 11,
      name: r'priority',
      type: IsarType.long,
    ),
    r'query': PropertySchema(
      id: 12,
      name: r'query',
      type: IsarType.string,
    ),
    r'recommendationKey': PropertySchema(
      id: 13,
      name: r'recommendationKey',
      type: IsarType.string,
    ),
    r'resultFingerprint': PropertySchema(
      id: 14,
      name: r'resultFingerprint',
      type: IsarType.string,
    ),
    r'status': PropertySchema(
      id: 15,
      name: r'status',
      type: IsarType.string,
    ),
    r'subtitle': PropertySchema(
      id: 16,
      name: r'subtitle',
      type: IsarType.string,
    ),
    r'title': PropertySchema(
      id: 17,
      name: r'title',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 18,
      name: r'updatedAt',
      type: IsarType.long,
    )
  },
  estimateSize: _createRecommendationEntityEstimateSize,
  serialize: _createRecommendationEntitySerialize,
  deserialize: _createRecommendationEntityDeserialize,
  deserializeProp: _createRecommendationEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'recommendationKey': IndexSchema(
      id: -5559656872123513518,
      name: r'recommendationKey',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'recommendationKey',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'presetId': IndexSchema(
      id: -2454531593692408596,
      name: r'presetId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'presetId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'status': IndexSchema(
      id: -107785170620420283,
      name: r'status',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'status',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _createRecommendationEntityGetId,
  getLinks: _createRecommendationEntityGetLinks,
  attach: _createRecommendationEntityAttach,
  version: '3.1.0+1',
);

int _createRecommendationEntityEstimateSize(
  CreateRecommendationEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.coverPhotoIds.length * 8;
  bytesCount += 3 + object.group.length * 3;
  bytesCount += 3 + object.label.length * 3;
  bytesCount += 3 + object.photoIds.length * 8;
  bytesCount += 3 + object.presetId.length * 3;
  bytesCount += 3 + object.query.length * 3;
  bytesCount += 3 + object.recommendationKey.length * 3;
  {
    final value = object.resultFingerprint;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.status.length * 3;
  bytesCount += 3 + object.subtitle.length * 3;
  bytesCount += 3 + object.title.length * 3;
  return bytesCount;
}

void _createRecommendationEntitySerialize(
  CreateRecommendationEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLongList(offsets[0], object.coverPhotoIds);
  writer.writeLong(offsets[1], object.createdAt);
  writer.writeString(offsets[2], object.group);
  writer.writeBool(offsets[3], object.isActive);
  writer.writeString(offsets[4], object.label);
  writer.writeLong(offsets[5], object.lastCheckedAt);
  writer.writeLong(offsets[6], object.lastRecommendedAt);
  writer.writeLong(offsets[7], object.matchedCount);
  writer.writeLong(offsets[8], object.nextCheckAt);
  writer.writeLongList(offsets[9], object.photoIds);
  writer.writeString(offsets[10], object.presetId);
  writer.writeLong(offsets[11], object.priority);
  writer.writeString(offsets[12], object.query);
  writer.writeString(offsets[13], object.recommendationKey);
  writer.writeString(offsets[14], object.resultFingerprint);
  writer.writeString(offsets[15], object.status);
  writer.writeString(offsets[16], object.subtitle);
  writer.writeString(offsets[17], object.title);
  writer.writeLong(offsets[18], object.updatedAt);
}

CreateRecommendationEntity _createRecommendationEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = CreateRecommendationEntity();
  object.coverPhotoIds = reader.readLongList(offsets[0]) ?? [];
  object.createdAt = reader.readLong(offsets[1]);
  object.group = reader.readString(offsets[2]);
  object.id = id;
  object.label = reader.readString(offsets[4]);
  object.lastCheckedAt = reader.readLongOrNull(offsets[5]);
  object.lastRecommendedAt = reader.readLongOrNull(offsets[6]);
  object.matchedCount = reader.readLong(offsets[7]);
  object.nextCheckAt = reader.readLongOrNull(offsets[8]);
  object.photoIds = reader.readLongList(offsets[9]) ?? [];
  object.presetId = reader.readString(offsets[10]);
  object.priority = reader.readLong(offsets[11]);
  object.query = reader.readString(offsets[12]);
  object.recommendationKey = reader.readString(offsets[13]);
  object.resultFingerprint = reader.readStringOrNull(offsets[14]);
  object.status = reader.readString(offsets[15]);
  object.subtitle = reader.readString(offsets[16]);
  object.title = reader.readString(offsets[17]);
  object.updatedAt = reader.readLong(offsets[18]);
  return object;
}

P _createRecommendationEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLongList(offset) ?? []) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readBool(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readLongOrNull(offset)) as P;
    case 6:
      return (reader.readLongOrNull(offset)) as P;
    case 7:
      return (reader.readLong(offset)) as P;
    case 8:
      return (reader.readLongOrNull(offset)) as P;
    case 9:
      return (reader.readLongList(offset) ?? []) as P;
    case 10:
      return (reader.readString(offset)) as P;
    case 11:
      return (reader.readLong(offset)) as P;
    case 12:
      return (reader.readString(offset)) as P;
    case 13:
      return (reader.readString(offset)) as P;
    case 14:
      return (reader.readStringOrNull(offset)) as P;
    case 15:
      return (reader.readString(offset)) as P;
    case 16:
      return (reader.readString(offset)) as P;
    case 17:
      return (reader.readString(offset)) as P;
    case 18:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _createRecommendationEntityGetId(CreateRecommendationEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _createRecommendationEntityGetLinks(
    CreateRecommendationEntity object) {
  return [];
}

void _createRecommendationEntityAttach(
    IsarCollection<dynamic> col, Id id, CreateRecommendationEntity object) {
  object.id = id;
}

extension CreateRecommendationEntityByIndex
    on IsarCollection<CreateRecommendationEntity> {
  Future<CreateRecommendationEntity?> getByRecommendationKey(
      String recommendationKey) {
    return getByIndex(r'recommendationKey', [recommendationKey]);
  }

  CreateRecommendationEntity? getByRecommendationKeySync(
      String recommendationKey) {
    return getByIndexSync(r'recommendationKey', [recommendationKey]);
  }

  Future<bool> deleteByRecommendationKey(String recommendationKey) {
    return deleteByIndex(r'recommendationKey', [recommendationKey]);
  }

  bool deleteByRecommendationKeySync(String recommendationKey) {
    return deleteByIndexSync(r'recommendationKey', [recommendationKey]);
  }

  Future<List<CreateRecommendationEntity?>> getAllByRecommendationKey(
      List<String> recommendationKeyValues) {
    final values = recommendationKeyValues.map((e) => [e]).toList();
    return getAllByIndex(r'recommendationKey', values);
  }

  List<CreateRecommendationEntity?> getAllByRecommendationKeySync(
      List<String> recommendationKeyValues) {
    final values = recommendationKeyValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'recommendationKey', values);
  }

  Future<int> deleteAllByRecommendationKey(
      List<String> recommendationKeyValues) {
    final values = recommendationKeyValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'recommendationKey', values);
  }

  int deleteAllByRecommendationKeySync(List<String> recommendationKeyValues) {
    final values = recommendationKeyValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'recommendationKey', values);
  }

  Future<Id> putByRecommendationKey(CreateRecommendationEntity object) {
    return putByIndex(r'recommendationKey', object);
  }

  Id putByRecommendationKeySync(CreateRecommendationEntity object,
      {bool saveLinks = true}) {
    return putByIndexSync(r'recommendationKey', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByRecommendationKey(
      List<CreateRecommendationEntity> objects) {
    return putAllByIndex(r'recommendationKey', objects);
  }

  List<Id> putAllByRecommendationKeySync(
      List<CreateRecommendationEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'recommendationKey', objects,
        saveLinks: saveLinks);
  }
}

extension CreateRecommendationEntityQueryWhereSort on QueryBuilder<
    CreateRecommendationEntity, CreateRecommendationEntity, QWhere> {
  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension CreateRecommendationEntityQueryWhere on QueryBuilder<
    CreateRecommendationEntity, CreateRecommendationEntity, QWhereClause> {
  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhereClause> idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhereClause> idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhereClause> idBetween(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhereClause> recommendationKeyEqualTo(String recommendationKey) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'recommendationKey',
        value: [recommendationKey],
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhereClause> recommendationKeyNotEqualTo(String recommendationKey) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'recommendationKey',
              lower: [],
              upper: [recommendationKey],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'recommendationKey',
              lower: [recommendationKey],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'recommendationKey',
              lower: [recommendationKey],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'recommendationKey',
              lower: [],
              upper: [recommendationKey],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhereClause> presetIdEqualTo(String presetId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'presetId',
        value: [presetId],
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhereClause> presetIdNotEqualTo(String presetId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'presetId',
              lower: [],
              upper: [presetId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'presetId',
              lower: [presetId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'presetId',
              lower: [presetId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'presetId',
              lower: [],
              upper: [presetId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhereClause> statusEqualTo(String status) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'status',
        value: [status],
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterWhereClause> statusNotEqualTo(String status) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'status',
              lower: [],
              upper: [status],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'status',
              lower: [status],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'status',
              lower: [status],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'status',
              lower: [],
              upper: [status],
              includeUpper: false,
            ));
      }
    });
  }
}

extension CreateRecommendationEntityQueryFilter on QueryBuilder<
    CreateRecommendationEntity, CreateRecommendationEntity, QFilterCondition> {
  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> coverPhotoIdsElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'coverPhotoIds',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> coverPhotoIdsElementGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'coverPhotoIds',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> coverPhotoIdsElementLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'coverPhotoIds',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> coverPhotoIdsElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'coverPhotoIds',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> coverPhotoIdsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'coverPhotoIds',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> coverPhotoIdsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'coverPhotoIds',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> coverPhotoIdsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'coverPhotoIds',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> coverPhotoIdsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'coverPhotoIds',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> coverPhotoIdsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'coverPhotoIds',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> coverPhotoIdsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'coverPhotoIds',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> createdAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> createdAtGreaterThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> createdAtLessThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> createdAtBetween(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> groupEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'group',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> groupGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'group',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> groupLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'group',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> groupBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'group',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> groupStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'group',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> groupEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'group',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      groupContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'group',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      groupMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'group',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> groupIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'group',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> groupIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'group',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> idLessThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> idBetween(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> isActiveEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isActive',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> labelEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'label',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> labelGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'label',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> labelLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'label',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> labelBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'label',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> labelStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'label',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> labelEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'label',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      labelContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'label',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      labelMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'label',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> labelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'label',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> labelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'label',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastCheckedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastCheckedAt',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastCheckedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastCheckedAt',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastCheckedAtEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastCheckedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastCheckedAtGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastCheckedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastCheckedAtLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastCheckedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastCheckedAtBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastCheckedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastRecommendedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'lastRecommendedAt',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastRecommendedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'lastRecommendedAt',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastRecommendedAtEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'lastRecommendedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastRecommendedAtGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'lastRecommendedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastRecommendedAtLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'lastRecommendedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> lastRecommendedAtBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'lastRecommendedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> matchedCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'matchedCount',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> matchedCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'matchedCount',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> matchedCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'matchedCount',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> matchedCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'matchedCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> nextCheckAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'nextCheckAt',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> nextCheckAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'nextCheckAt',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> nextCheckAtEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'nextCheckAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> nextCheckAtGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'nextCheckAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> nextCheckAtLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'nextCheckAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> nextCheckAtBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'nextCheckAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> photoIdsElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'photoIds',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> photoIdsElementGreaterThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> photoIdsElementLessThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> photoIdsElementBetween(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> photoIdsLengthEqualTo(int length) {
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> photoIdsIsEmpty() {
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> photoIdsIsNotEmpty() {
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> photoIdsLengthLessThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> photoIdsLengthGreaterThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> photoIdsLengthBetween(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> presetIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> presetIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> presetIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> presetIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'presetId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> presetIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> presetIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      presetIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      presetIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'presetId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> presetIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'presetId',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> presetIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'presetId',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> priorityEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'priority',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> priorityGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'priority',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> priorityLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'priority',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> priorityBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'priority',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> queryEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'query',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> queryGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'query',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> queryLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'query',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> queryBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'query',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> queryStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'query',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> queryEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'query',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      queryContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'query',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      queryMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'query',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> queryIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'query',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> queryIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'query',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> recommendationKeyEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'recommendationKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> recommendationKeyGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'recommendationKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> recommendationKeyLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'recommendationKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> recommendationKeyBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'recommendationKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> recommendationKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'recommendationKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> recommendationKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'recommendationKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      recommendationKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'recommendationKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      recommendationKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'recommendationKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> recommendationKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'recommendationKey',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> recommendationKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'recommendationKey',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> resultFingerprintIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'resultFingerprint',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> resultFingerprintIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'resultFingerprint',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> resultFingerprintEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'resultFingerprint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> resultFingerprintGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'resultFingerprint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> resultFingerprintLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'resultFingerprint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> resultFingerprintBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'resultFingerprint',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> resultFingerprintStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'resultFingerprint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> resultFingerprintEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'resultFingerprint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      resultFingerprintContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'resultFingerprint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      resultFingerprintMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'resultFingerprint',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> resultFingerprintIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'resultFingerprint',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> resultFingerprintIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'resultFingerprint',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> statusEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> statusGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> statusLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> statusBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'status',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> statusStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> statusEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      statusContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'status',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      statusMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'status',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> statusIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'status',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> statusIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'status',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> subtitleEqualTo(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> subtitleGreaterThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> subtitleLessThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> subtitleBetween(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> subtitleStartsWith(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> subtitleEndsWith(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      subtitleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'subtitle',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      subtitleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'subtitle',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> subtitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'subtitle',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> subtitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'subtitle',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> titleEqualTo(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> titleGreaterThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> titleLessThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> titleBetween(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> titleStartsWith(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> titleEndsWith(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      titleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'title',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
          QAfterFilterCondition>
      titleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'title',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> updatedAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> updatedAtGreaterThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> updatedAtLessThan(
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

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterFilterCondition> updatedAtBetween(
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

extension CreateRecommendationEntityQueryObject on QueryBuilder<
    CreateRecommendationEntity, CreateRecommendationEntity, QFilterCondition> {}

extension CreateRecommendationEntityQueryLinks on QueryBuilder<
    CreateRecommendationEntity, CreateRecommendationEntity, QFilterCondition> {}

extension CreateRecommendationEntityQuerySortBy on QueryBuilder<
    CreateRecommendationEntity, CreateRecommendationEntity, QSortBy> {
  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByGroup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'group', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByGroupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'group', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByIsActive() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByIsActiveDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'label', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'label', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByLastCheckedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastCheckedAt', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByLastCheckedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastCheckedAt', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByLastRecommendedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRecommendedAt', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByLastRecommendedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRecommendedAt', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByMatchedCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchedCount', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByMatchedCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchedCount', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByNextCheckAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nextCheckAt', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByNextCheckAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nextCheckAt', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByPresetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'presetId', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByPresetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'presetId', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priority', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priority', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByQuery() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'query', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByQueryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'query', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByRecommendationKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recommendationKey', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByRecommendationKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recommendationKey', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByResultFingerprint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultFingerprint', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByResultFingerprintDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultFingerprint', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortBySubtitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortBySubtitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension CreateRecommendationEntityQuerySortThenBy on QueryBuilder<
    CreateRecommendationEntity, CreateRecommendationEntity, QSortThenBy> {
  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByGroup() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'group', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByGroupDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'group', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByIsActive() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByIsActiveDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isActive', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByLabel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'label', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByLabelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'label', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByLastCheckedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastCheckedAt', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByLastCheckedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastCheckedAt', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByLastRecommendedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRecommendedAt', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByLastRecommendedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastRecommendedAt', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByMatchedCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchedCount', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByMatchedCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'matchedCount', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByNextCheckAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nextCheckAt', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByNextCheckAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'nextCheckAt', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByPresetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'presetId', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByPresetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'presetId', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priority', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByPriorityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'priority', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByQuery() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'query', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByQueryDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'query', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByRecommendationKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recommendationKey', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByRecommendationKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'recommendationKey', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByResultFingerprint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultFingerprint', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByResultFingerprintDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultFingerprint', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByStatus() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByStatusDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'status', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenBySubtitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenBySubtitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension CreateRecommendationEntityQueryWhereDistinct on QueryBuilder<
    CreateRecommendationEntity, CreateRecommendationEntity, QDistinct> {
  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByCoverPhotoIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'coverPhotoIds');
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByGroup({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'group', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByIsActive() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isActive');
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByLabel({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'label', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByLastCheckedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastCheckedAt');
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByLastRecommendedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastRecommendedAt');
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByMatchedCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'matchedCount');
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByNextCheckAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'nextCheckAt');
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByPhotoIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'photoIds');
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByPresetId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'presetId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByPriority() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'priority');
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByQuery({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'query', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByRecommendationKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'recommendationKey',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByResultFingerprint({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'resultFingerprint',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByStatus({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'status', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctBySubtitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'subtitle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CreateRecommendationEntity, CreateRecommendationEntity,
      QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension CreateRecommendationEntityQueryProperty on QueryBuilder<
    CreateRecommendationEntity, CreateRecommendationEntity, QQueryProperty> {
  QueryBuilder<CreateRecommendationEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<CreateRecommendationEntity, List<int>, QQueryOperations>
      coverPhotoIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'coverPhotoIds');
    });
  }

  QueryBuilder<CreateRecommendationEntity, int, QQueryOperations>
      createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<CreateRecommendationEntity, String, QQueryOperations>
      groupProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'group');
    });
  }

  QueryBuilder<CreateRecommendationEntity, bool, QQueryOperations>
      isActiveProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isActive');
    });
  }

  QueryBuilder<CreateRecommendationEntity, String, QQueryOperations>
      labelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'label');
    });
  }

  QueryBuilder<CreateRecommendationEntity, int?, QQueryOperations>
      lastCheckedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastCheckedAt');
    });
  }

  QueryBuilder<CreateRecommendationEntity, int?, QQueryOperations>
      lastRecommendedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastRecommendedAt');
    });
  }

  QueryBuilder<CreateRecommendationEntity, int, QQueryOperations>
      matchedCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'matchedCount');
    });
  }

  QueryBuilder<CreateRecommendationEntity, int?, QQueryOperations>
      nextCheckAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'nextCheckAt');
    });
  }

  QueryBuilder<CreateRecommendationEntity, List<int>, QQueryOperations>
      photoIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'photoIds');
    });
  }

  QueryBuilder<CreateRecommendationEntity, String, QQueryOperations>
      presetIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'presetId');
    });
  }

  QueryBuilder<CreateRecommendationEntity, int, QQueryOperations>
      priorityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'priority');
    });
  }

  QueryBuilder<CreateRecommendationEntity, String, QQueryOperations>
      queryProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'query');
    });
  }

  QueryBuilder<CreateRecommendationEntity, String, QQueryOperations>
      recommendationKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'recommendationKey');
    });
  }

  QueryBuilder<CreateRecommendationEntity, String?, QQueryOperations>
      resultFingerprintProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'resultFingerprint');
    });
  }

  QueryBuilder<CreateRecommendationEntity, String, QQueryOperations>
      statusProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'status');
    });
  }

  QueryBuilder<CreateRecommendationEntity, String, QQueryOperations>
      subtitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'subtitle');
    });
  }

  QueryBuilder<CreateRecommendationEntity, String, QQueryOperations>
      titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<CreateRecommendationEntity, int, QQueryOperations>
      updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
