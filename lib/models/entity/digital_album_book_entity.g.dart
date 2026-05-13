// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'digital_album_book_entity.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetDigitalAlbumBookEntityCollection on Isar {
  IsarCollection<DigitalAlbumBookEntity> get digitalAlbumBookEntitys =>
      this.collection();
}

const DigitalAlbumBookEntitySchema = CollectionSchema(
  name: r'DigitalAlbumBookEntity',
  id: 369885899802443400,
  properties: {
    r'contentJson': PropertySchema(
      id: 0,
      name: r'contentJson',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 1,
      name: r'createdAt',
      type: IsarType.long,
    ),
    r'layoutSource': PropertySchema(
      id: 2,
      name: r'layoutSource',
      type: IsarType.string,
    ),
    r'pageHeight': PropertySchema(
      id: 3,
      name: r'pageHeight',
      type: IsarType.double,
    ),
    r'pageWidth': PropertySchema(
      id: 4,
      name: r'pageWidth',
      type: IsarType.double,
    ),
    r'spreadCount': PropertySchema(
      id: 5,
      name: r'spreadCount',
      type: IsarType.long,
    ),
    r'storyId': PropertySchema(
      id: 6,
      name: r'storyId',
      type: IsarType.long,
    ),
    r'subtitle': PropertySchema(
      id: 7,
      name: r'subtitle',
      type: IsarType.string,
    ),
    r'theme': PropertySchema(
      id: 8,
      name: r'theme',
      type: IsarType.string,
    ),
    r'title': PropertySchema(
      id: 9,
      name: r'title',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 10,
      name: r'updatedAt',
      type: IsarType.long,
    )
  },
  estimateSize: _digitalAlbumBookEntityEstimateSize,
  serialize: _digitalAlbumBookEntitySerialize,
  deserialize: _digitalAlbumBookEntityDeserialize,
  deserializeProp: _digitalAlbumBookEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'storyId': IndexSchema(
      id: -7904996416186759579,
      name: r'storyId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'storyId',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _digitalAlbumBookEntityGetId,
  getLinks: _digitalAlbumBookEntityGetLinks,
  attach: _digitalAlbumBookEntityAttach,
  version: '3.1.0+1',
);

int _digitalAlbumBookEntityEstimateSize(
  DigitalAlbumBookEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.contentJson.length * 3;
  bytesCount += 3 + object.layoutSource.length * 3;
  bytesCount += 3 + object.subtitle.length * 3;
  bytesCount += 3 + object.theme.length * 3;
  bytesCount += 3 + object.title.length * 3;
  return bytesCount;
}

void _digitalAlbumBookEntitySerialize(
  DigitalAlbumBookEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.contentJson);
  writer.writeLong(offsets[1], object.createdAt);
  writer.writeString(offsets[2], object.layoutSource);
  writer.writeDouble(offsets[3], object.pageHeight);
  writer.writeDouble(offsets[4], object.pageWidth);
  writer.writeLong(offsets[5], object.spreadCount);
  writer.writeLong(offsets[6], object.storyId);
  writer.writeString(offsets[7], object.subtitle);
  writer.writeString(offsets[8], object.theme);
  writer.writeString(offsets[9], object.title);
  writer.writeLong(offsets[10], object.updatedAt);
}

DigitalAlbumBookEntity _digitalAlbumBookEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = DigitalAlbumBookEntity();
  object.contentJson = reader.readString(offsets[0]);
  object.createdAt = reader.readLong(offsets[1]);
  object.id = id;
  object.layoutSource = reader.readString(offsets[2]);
  object.pageHeight = reader.readDouble(offsets[3]);
  object.pageWidth = reader.readDouble(offsets[4]);
  object.spreadCount = reader.readLong(offsets[5]);
  object.storyId = reader.readLong(offsets[6]);
  object.subtitle = reader.readString(offsets[7]);
  object.theme = reader.readString(offsets[8]);
  object.title = reader.readString(offsets[9]);
  object.updatedAt = reader.readLong(offsets[10]);
  return object;
}

P _digitalAlbumBookEntityDeserializeProp<P>(
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
      return (reader.readDouble(offset)) as P;
    case 4:
      return (reader.readDouble(offset)) as P;
    case 5:
      return (reader.readLong(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _digitalAlbumBookEntityGetId(DigitalAlbumBookEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _digitalAlbumBookEntityGetLinks(
    DigitalAlbumBookEntity object) {
  return [];
}

void _digitalAlbumBookEntityAttach(
    IsarCollection<dynamic> col, Id id, DigitalAlbumBookEntity object) {
  object.id = id;
}

extension DigitalAlbumBookEntityByIndex
    on IsarCollection<DigitalAlbumBookEntity> {
  Future<DigitalAlbumBookEntity?> getByStoryId(int storyId) {
    return getByIndex(r'storyId', [storyId]);
  }

  DigitalAlbumBookEntity? getByStoryIdSync(int storyId) {
    return getByIndexSync(r'storyId', [storyId]);
  }

  Future<bool> deleteByStoryId(int storyId) {
    return deleteByIndex(r'storyId', [storyId]);
  }

  bool deleteByStoryIdSync(int storyId) {
    return deleteByIndexSync(r'storyId', [storyId]);
  }

  Future<List<DigitalAlbumBookEntity?>> getAllByStoryId(
      List<int> storyIdValues) {
    final values = storyIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'storyId', values);
  }

  List<DigitalAlbumBookEntity?> getAllByStoryIdSync(List<int> storyIdValues) {
    final values = storyIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'storyId', values);
  }

  Future<int> deleteAllByStoryId(List<int> storyIdValues) {
    final values = storyIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'storyId', values);
  }

  int deleteAllByStoryIdSync(List<int> storyIdValues) {
    final values = storyIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'storyId', values);
  }

  Future<Id> putByStoryId(DigitalAlbumBookEntity object) {
    return putByIndex(r'storyId', object);
  }

  Id putByStoryIdSync(DigitalAlbumBookEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'storyId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByStoryId(List<DigitalAlbumBookEntity> objects) {
    return putAllByIndex(r'storyId', objects);
  }

  List<Id> putAllByStoryIdSync(List<DigitalAlbumBookEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'storyId', objects, saveLinks: saveLinks);
  }
}

extension DigitalAlbumBookEntityQueryWhereSort
    on QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QWhere> {
  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterWhere>
      anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterWhere>
      anyStoryId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'storyId'),
      );
    });
  }
}

extension DigitalAlbumBookEntityQueryWhere on QueryBuilder<
    DigitalAlbumBookEntity, DigitalAlbumBookEntity, QWhereClause> {
  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterWhereClause> idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterWhereClause> idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterWhereClause> storyIdEqualTo(int storyId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'storyId',
        value: [storyId],
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterWhereClause> storyIdNotEqualTo(int storyId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'storyId',
              lower: [],
              upper: [storyId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'storyId',
              lower: [storyId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'storyId',
              lower: [storyId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'storyId',
              lower: [],
              upper: [storyId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterWhereClause> storyIdGreaterThan(
    int storyId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'storyId',
        lower: [storyId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterWhereClause> storyIdLessThan(
    int storyId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'storyId',
        lower: [],
        upper: [storyId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterWhereClause> storyIdBetween(
    int lowerStoryId,
    int upperStoryId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'storyId',
        lower: [lowerStoryId],
        includeLower: includeLower,
        upper: [upperStoryId],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension DigitalAlbumBookEntityQueryFilter on QueryBuilder<
    DigitalAlbumBookEntity, DigitalAlbumBookEntity, QFilterCondition> {
  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> contentJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contentJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> contentJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'contentJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> contentJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'contentJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> contentJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'contentJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> contentJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'contentJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> contentJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'contentJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
          QAfterFilterCondition>
      contentJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'contentJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
          QAfterFilterCondition>
      contentJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'contentJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> contentJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contentJson',
        value: '',
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> contentJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'contentJson',
        value: '',
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> createdAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> layoutSourceEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'layoutSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> layoutSourceGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'layoutSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> layoutSourceLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'layoutSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> layoutSourceBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'layoutSource',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> layoutSourceStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'layoutSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> layoutSourceEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'layoutSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
          QAfterFilterCondition>
      layoutSourceContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'layoutSource',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
          QAfterFilterCondition>
      layoutSourceMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'layoutSource',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> layoutSourceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'layoutSource',
        value: '',
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> layoutSourceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'layoutSource',
        value: '',
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> pageHeightEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'pageHeight',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> pageHeightGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'pageHeight',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> pageHeightLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'pageHeight',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> pageHeightBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'pageHeight',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> pageWidthEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'pageWidth',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> pageWidthGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'pageWidth',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> pageWidthLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'pageWidth',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> pageWidthBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'pageWidth',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> spreadCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'spreadCount',
        value: value,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> spreadCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'spreadCount',
        value: value,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> spreadCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'spreadCount',
        value: value,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> spreadCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'spreadCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> storyIdEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'storyId',
        value: value,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> storyIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'storyId',
        value: value,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> storyIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'storyId',
        value: value,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> storyIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'storyId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> subtitleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'subtitle',
        value: '',
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> subtitleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'subtitle',
        value: '',
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> themeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> themeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> themeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> themeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'theme',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> themeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> themeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
          QAfterFilterCondition>
      themeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'theme',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
          QAfterFilterCondition>
      themeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'theme',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> themeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'theme',
        value: '',
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> themeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'theme',
        value: '',
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> titleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> titleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'title',
        value: '',
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
      QAfterFilterCondition> updatedAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity,
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

extension DigitalAlbumBookEntityQueryObject on QueryBuilder<
    DigitalAlbumBookEntity, DigitalAlbumBookEntity, QFilterCondition> {}

extension DigitalAlbumBookEntityQueryLinks on QueryBuilder<
    DigitalAlbumBookEntity, DigitalAlbumBookEntity, QFilterCondition> {}

extension DigitalAlbumBookEntityQuerySortBy
    on QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QSortBy> {
  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByContentJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentJson', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByContentJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentJson', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByLayoutSource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'layoutSource', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByLayoutSourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'layoutSource', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByPageHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageHeight', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByPageHeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageHeight', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByPageWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageWidth', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByPageWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageWidth', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortBySpreadCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'spreadCount', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortBySpreadCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'spreadCount', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByStoryId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storyId', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByStoryIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storyId', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortBySubtitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortBySubtitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByTheme() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByThemeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension DigitalAlbumBookEntityQuerySortThenBy on QueryBuilder<
    DigitalAlbumBookEntity, DigitalAlbumBookEntity, QSortThenBy> {
  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByContentJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentJson', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByContentJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contentJson', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByLayoutSource() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'layoutSource', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByLayoutSourceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'layoutSource', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByPageHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageHeight', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByPageHeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageHeight', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByPageWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageWidth', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByPageWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'pageWidth', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenBySpreadCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'spreadCount', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenBySpreadCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'spreadCount', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByStoryId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storyId', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByStoryIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'storyId', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenBySubtitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenBySubtitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'subtitle', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByTheme() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByThemeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByTitle() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByTitleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'title', Sort.desc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension DigitalAlbumBookEntityQueryWhereDistinct
    on QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct> {
  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct>
      distinctByContentJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contentJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct>
      distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct>
      distinctByLayoutSource({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'layoutSource', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct>
      distinctByPageHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pageHeight');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct>
      distinctByPageWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'pageWidth');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct>
      distinctBySpreadCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'spreadCount');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct>
      distinctByStoryId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'storyId');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct>
      distinctBySubtitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'subtitle', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct>
      distinctByTheme({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'theme', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct>
      distinctByTitle({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'title', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, DigitalAlbumBookEntity, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension DigitalAlbumBookEntityQueryProperty on QueryBuilder<
    DigitalAlbumBookEntity, DigitalAlbumBookEntity, QQueryProperty> {
  QueryBuilder<DigitalAlbumBookEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, String, QQueryOperations>
      contentJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contentJson');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, int, QQueryOperations>
      createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, String, QQueryOperations>
      layoutSourceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'layoutSource');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, double, QQueryOperations>
      pageHeightProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pageHeight');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, double, QQueryOperations>
      pageWidthProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'pageWidth');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, int, QQueryOperations>
      spreadCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'spreadCount');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, int, QQueryOperations>
      storyIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'storyId');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, String, QQueryOperations>
      subtitleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'subtitle');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, String, QQueryOperations>
      themeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'theme');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, String, QQueryOperations>
      titleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'title');
    });
  }

  QueryBuilder<DigitalAlbumBookEntity, int, QQueryOperations>
      updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}
