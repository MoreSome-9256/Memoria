// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_entity.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetPhotoEntityCollection on Isar {
  IsarCollection<PhotoEntity> get photoEntitys => this.collection();
}

const PhotoEntitySchema = CollectionSchema(
  name: r'PhotoEntity',
  id: 8245672414119462092,
  properties: {
    r'adcode': PropertySchema(
      id: 0,
      name: r'adcode',
      type: IsarType.string,
    ),
    r'aiCaption': PropertySchema(
      id: 1,
      name: r'aiCaption',
      type: IsarType.string,
    ),
    r'aiTags': PropertySchema(
      id: 2,
      name: r'aiTags',
      type: IsarType.stringList,
    ),
    r'aspectRatio': PropertySchema(
      id: 3,
      name: r'aspectRatio',
      type: IsarType.double,
    ),
    r'assetId': PropertySchema(
      id: 4,
      name: r'assetId',
      type: IsarType.string,
    ),
    r'city': PropertySchema(
      id: 5,
      name: r'city',
      type: IsarType.string,
    ),
    r'district': PropertySchema(
      id: 6,
      name: r'district',
      type: IsarType.string,
    ),
    r'eventId': PropertySchema(
      id: 7,
      name: r'eventId',
      type: IsarType.long,
    ),
    r'faceCount': PropertySchema(
      id: 8,
      name: r'faceCount',
      type: IsarType.long,
    ),
    r'formattedAddress': PropertySchema(
      id: 9,
      name: r'formattedAddress',
      type: IsarType.string,
    ),
    r'height': PropertySchema(
      id: 10,
      name: r'height',
      type: IsarType.long,
    ),
    r'imageEmbedding': PropertySchema(
      id: 11,
      name: r'imageEmbedding',
      type: IsarType.doubleList,
    ),
    r'isAiAnalyzed': PropertySchema(
      id: 12,
      name: r'isAiAnalyzed',
      type: IsarType.bool,
    ),
    r'isLocationProcessed': PropertySchema(
      id: 13,
      name: r'isLocationProcessed',
      type: IsarType.bool,
    ),
    r'isProbablyScreenshot': PropertySchema(
      id: 14,
      name: r'isProbablyScreenshot',
      type: IsarType.bool,
    ),
    r'joyScore': PropertySchema(
      id: 15,
      name: r'joyScore',
      type: IsarType.double,
    ),
    r'latitude': PropertySchema(
      id: 16,
      name: r'latitude',
      type: IsarType.double,
    ),
    r'locationName': PropertySchema(
      id: 17,
      name: r'locationName',
      type: IsarType.string,
    ),
    r'longitude': PropertySchema(
      id: 18,
      name: r'longitude',
      type: IsarType.double,
    ),
    r'ocrTags': PropertySchema(
      id: 19,
      name: r'ocrTags',
      type: IsarType.stringList,
    ),
    r'ocrText': PropertySchema(
      id: 20,
      name: r'ocrText',
      type: IsarType.string,
    ),
    r'path': PropertySchema(
      id: 21,
      name: r'path',
      type: IsarType.string,
    ),
    r'province': PropertySchema(
      id: 22,
      name: r'province',
      type: IsarType.string,
    ),
    r'smileProb': PropertySchema(
      id: 23,
      name: r'smileProb',
      type: IsarType.double,
    ),
    r'timestamp': PropertySchema(
      id: 24,
      name: r'timestamp',
      type: IsarType.long,
    ),
    r'width': PropertySchema(
      id: 25,
      name: r'width',
      type: IsarType.long,
    )
  },
  estimateSize: _photoEntityEstimateSize,
  serialize: _photoEntitySerialize,
  deserialize: _photoEntityDeserialize,
  deserializeProp: _photoEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'assetId': IndexSchema(
      id: 174362542210192109,
      name: r'assetId',
      unique: true,
      replace: true,
      properties: [
        IndexPropertySchema(
          name: r'assetId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'province': IndexSchema(
      id: -6035047385865569949,
      name: r'province',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'province',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'city': IndexSchema(
      id: 2121973393509345332,
      name: r'city',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'city',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'eventId': IndexSchema(
      id: -2707901133518603130,
      name: r'eventId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'eventId',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _photoEntityGetId,
  getLinks: _photoEntityGetLinks,
  attach: _photoEntityAttach,
  version: '3.1.0+1',
);

int _photoEntityEstimateSize(
  PhotoEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.adcode;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.aiCaption;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final list = object.aiTags;
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
  bytesCount += 3 + object.assetId.length * 3;
  {
    final value = object.city;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
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
  {
    final value = object.imageEmbedding;
    if (value != null) {
      bytesCount += 3 + value.length * 8;
    }
  }
  {
    final value = object.locationName;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final list = object.ocrTags;
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
    final value = object.ocrText;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.path.length * 3;
  {
    final value = object.province;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _photoEntitySerialize(
  PhotoEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.adcode);
  writer.writeString(offsets[1], object.aiCaption);
  writer.writeStringList(offsets[2], object.aiTags);
  writer.writeDouble(offsets[3], object.aspectRatio);
  writer.writeString(offsets[4], object.assetId);
  writer.writeString(offsets[5], object.city);
  writer.writeString(offsets[6], object.district);
  writer.writeLong(offsets[7], object.eventId);
  writer.writeLong(offsets[8], object.faceCount);
  writer.writeString(offsets[9], object.formattedAddress);
  writer.writeLong(offsets[10], object.height);
  writer.writeDoubleList(offsets[11], object.imageEmbedding);
  writer.writeBool(offsets[12], object.isAiAnalyzed);
  writer.writeBool(offsets[13], object.isLocationProcessed);
  writer.writeBool(offsets[14], object.isProbablyScreenshot);
  writer.writeDouble(offsets[15], object.joyScore);
  writer.writeDouble(offsets[16], object.latitude);
  writer.writeString(offsets[17], object.locationName);
  writer.writeDouble(offsets[18], object.longitude);
  writer.writeStringList(offsets[19], object.ocrTags);
  writer.writeString(offsets[20], object.ocrText);
  writer.writeString(offsets[21], object.path);
  writer.writeString(offsets[22], object.province);
  writer.writeDouble(offsets[23], object.smileProb);
  writer.writeLong(offsets[24], object.timestamp);
  writer.writeLong(offsets[25], object.width);
}

PhotoEntity _photoEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = PhotoEntity();
  object.adcode = reader.readStringOrNull(offsets[0]);
  object.aiCaption = reader.readStringOrNull(offsets[1]);
  object.aiTags = reader.readStringList(offsets[2]);
  object.assetId = reader.readString(offsets[4]);
  object.city = reader.readStringOrNull(offsets[5]);
  object.district = reader.readStringOrNull(offsets[6]);
  object.eventId = reader.readLongOrNull(offsets[7]);
  object.faceCount = reader.readLong(offsets[8]);
  object.formattedAddress = reader.readStringOrNull(offsets[9]);
  object.height = reader.readLong(offsets[10]);
  object.id = id;
  object.imageEmbedding = reader.readDoubleList(offsets[11]);
  object.isAiAnalyzed = reader.readBool(offsets[12]);
  object.isLocationProcessed = reader.readBool(offsets[13]);
  object.joyScore = reader.readDoubleOrNull(offsets[15]);
  object.latitude = reader.readDoubleOrNull(offsets[16]);
  object.locationName = reader.readStringOrNull(offsets[17]);
  object.longitude = reader.readDoubleOrNull(offsets[18]);
  object.ocrTags = reader.readStringList(offsets[19]);
  object.ocrText = reader.readStringOrNull(offsets[20]);
  object.path = reader.readString(offsets[21]);
  object.province = reader.readStringOrNull(offsets[22]);
  object.smileProb = reader.readDouble(offsets[23]);
  object.timestamp = reader.readLong(offsets[24]);
  object.width = reader.readLong(offsets[25]);
  return object;
}

P _photoEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readStringList(offset)) as P;
    case 3:
      return (reader.readDouble(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readLongOrNull(offset)) as P;
    case 8:
      return (reader.readLong(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readLong(offset)) as P;
    case 11:
      return (reader.readDoubleList(offset)) as P;
    case 12:
      return (reader.readBool(offset)) as P;
    case 13:
      return (reader.readBool(offset)) as P;
    case 14:
      return (reader.readBool(offset)) as P;
    case 15:
      return (reader.readDoubleOrNull(offset)) as P;
    case 16:
      return (reader.readDoubleOrNull(offset)) as P;
    case 17:
      return (reader.readStringOrNull(offset)) as P;
    case 18:
      return (reader.readDoubleOrNull(offset)) as P;
    case 19:
      return (reader.readStringList(offset)) as P;
    case 20:
      return (reader.readStringOrNull(offset)) as P;
    case 21:
      return (reader.readString(offset)) as P;
    case 22:
      return (reader.readStringOrNull(offset)) as P;
    case 23:
      return (reader.readDouble(offset)) as P;
    case 24:
      return (reader.readLong(offset)) as P;
    case 25:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _photoEntityGetId(PhotoEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _photoEntityGetLinks(PhotoEntity object) {
  return [];
}

void _photoEntityAttach(
    IsarCollection<dynamic> col, Id id, PhotoEntity object) {
  object.id = id;
}

extension PhotoEntityByIndex on IsarCollection<PhotoEntity> {
  Future<PhotoEntity?> getByAssetId(String assetId) {
    return getByIndex(r'assetId', [assetId]);
  }

  PhotoEntity? getByAssetIdSync(String assetId) {
    return getByIndexSync(r'assetId', [assetId]);
  }

  Future<bool> deleteByAssetId(String assetId) {
    return deleteByIndex(r'assetId', [assetId]);
  }

  bool deleteByAssetIdSync(String assetId) {
    return deleteByIndexSync(r'assetId', [assetId]);
  }

  Future<List<PhotoEntity?>> getAllByAssetId(List<String> assetIdValues) {
    final values = assetIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'assetId', values);
  }

  List<PhotoEntity?> getAllByAssetIdSync(List<String> assetIdValues) {
    final values = assetIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'assetId', values);
  }

  Future<int> deleteAllByAssetId(List<String> assetIdValues) {
    final values = assetIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'assetId', values);
  }

  int deleteAllByAssetIdSync(List<String> assetIdValues) {
    final values = assetIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'assetId', values);
  }

  Future<Id> putByAssetId(PhotoEntity object) {
    return putByIndex(r'assetId', object);
  }

  Id putByAssetIdSync(PhotoEntity object, {bool saveLinks = true}) {
    return putByIndexSync(r'assetId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByAssetId(List<PhotoEntity> objects) {
    return putAllByIndex(r'assetId', objects);
  }

  List<Id> putAllByAssetIdSync(List<PhotoEntity> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'assetId', objects, saveLinks: saveLinks);
  }
}

extension PhotoEntityQueryWhereSort
    on QueryBuilder<PhotoEntity, PhotoEntity, QWhere> {
  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhere> anyEventId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'eventId'),
      );
    });
  }
}

extension PhotoEntityQueryWhere
    on QueryBuilder<PhotoEntity, PhotoEntity, QWhereClause> {
  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> idNotEqualTo(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> idBetween(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> assetIdEqualTo(
      String assetId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'assetId',
        value: [assetId],
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> assetIdNotEqualTo(
      String assetId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'assetId',
              lower: [],
              upper: [assetId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'assetId',
              lower: [assetId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'assetId',
              lower: [assetId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'assetId',
              lower: [],
              upper: [assetId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> provinceIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'province',
        value: [null],
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause>
      provinceIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'province',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> provinceEqualTo(
      String? province) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'province',
        value: [province],
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> provinceNotEqualTo(
      String? province) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'province',
              lower: [],
              upper: [province],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'province',
              lower: [province],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'province',
              lower: [province],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'province',
              lower: [],
              upper: [province],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> cityIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'city',
        value: [null],
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> cityIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'city',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> cityEqualTo(
      String? city) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'city',
        value: [city],
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> cityNotEqualTo(
      String? city) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'city',
              lower: [],
              upper: [city],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'city',
              lower: [city],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'city',
              lower: [city],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'city',
              lower: [],
              upper: [city],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> eventIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'eventId',
        value: [null],
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> eventIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'eventId',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> eventIdEqualTo(
      int? eventId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'eventId',
        value: [eventId],
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> eventIdNotEqualTo(
      int? eventId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'eventId',
              lower: [],
              upper: [eventId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'eventId',
              lower: [eventId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'eventId',
              lower: [eventId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'eventId',
              lower: [],
              upper: [eventId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> eventIdGreaterThan(
    int? eventId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'eventId',
        lower: [eventId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> eventIdLessThan(
    int? eventId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'eventId',
        lower: [],
        upper: [eventId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterWhereClause> eventIdBetween(
    int? lowerEventId,
    int? upperEventId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'eventId',
        lower: [lowerEventId],
        includeLower: includeLower,
        upper: [upperEventId],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension PhotoEntityQueryFilter
    on QueryBuilder<PhotoEntity, PhotoEntity, QFilterCondition> {
  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> adcodeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'adcode',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      adcodeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'adcode',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> adcodeEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'adcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      adcodeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'adcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> adcodeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'adcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> adcodeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'adcode',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      adcodeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'adcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> adcodeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'adcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> adcodeContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'adcode',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> adcodeMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'adcode',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      adcodeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'adcode',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      adcodeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'adcode',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'aiCaption',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'aiCaption',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'aiCaption',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'aiCaption',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'aiCaption',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'aiCaption',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'aiCaption',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'aiCaption',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'aiCaption',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'aiCaption',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'aiCaption',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiCaptionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'aiCaption',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> aiTagsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'aiTags',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'aiTags',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'aiTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'aiTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'aiTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'aiTags',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'aiTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'aiTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'aiTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'aiTags',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'aiTags',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'aiTags',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiTags',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiTags',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiTags',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiTags',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiTags',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aiTagsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'aiTags',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aspectRatioEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'aspectRatio',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aspectRatioGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'aspectRatio',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aspectRatioLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'aspectRatio',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      aspectRatioBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'aspectRatio',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> assetIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'assetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      assetIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'assetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> assetIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'assetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> assetIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'assetId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      assetIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'assetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> assetIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'assetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> assetIdContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'assetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> assetIdMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'assetId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      assetIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'assetId',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      assetIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'assetId',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> cityIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'city',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      cityIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'city',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> cityEqualTo(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> cityGreaterThan(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> cityLessThan(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> cityBetween(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> cityStartsWith(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> cityEndsWith(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> cityContains(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> cityMatches(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> cityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'city',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      cityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'city',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      districtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'district',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      districtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'district',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> districtEqualTo(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> districtBetween(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      districtContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'district',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> districtMatches(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      districtIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'district',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      districtIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'district',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      eventIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'eventId',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      eventIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'eventId',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> eventIdEqualTo(
      int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'eventId',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      eventIdGreaterThan(
    int? value, {
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> eventIdLessThan(
    int? value, {
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> eventIdBetween(
    int? lower,
    int? upper, {
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      faceCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'faceCount',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      faceCountGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'faceCount',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      faceCountLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'faceCount',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      faceCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'faceCount',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      formattedAddressIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'formattedAddress',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      formattedAddressIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'formattedAddress',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      formattedAddressContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'formattedAddress',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      formattedAddressMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'formattedAddress',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      formattedAddressIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'formattedAddress',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      formattedAddressIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'formattedAddress',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> heightEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'height',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      heightGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'height',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> heightLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'height',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> heightBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'height',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> idBetween(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'imageEmbedding',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'imageEmbedding',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingElementEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'imageEmbedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingElementGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'imageEmbedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingElementLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'imageEmbedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingElementBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'imageEmbedding',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'imageEmbedding',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'imageEmbedding',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'imageEmbedding',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'imageEmbedding',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'imageEmbedding',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      imageEmbeddingLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'imageEmbedding',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      isAiAnalyzedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isAiAnalyzed',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      isLocationProcessedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isLocationProcessed',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      isProbablyScreenshotEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isProbablyScreenshot',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      joyScoreIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'joyScore',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      joyScoreIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'joyScore',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> joyScoreEqualTo(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> joyScoreBetween(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      latitudeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'latitude',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      latitudeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'latitude',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> latitudeEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      latitudeGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      latitudeLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'latitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> latitudeBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'latitude',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      locationNameIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'locationName',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      locationNameIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'locationName',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      locationNameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'locationName',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      locationNameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'locationName',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      locationNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'locationName',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      locationNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'locationName',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      longitudeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'longitude',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      longitudeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'longitude',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      longitudeEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      longitudeGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      longitudeLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'longitude',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      longitudeBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'longitude',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ocrTags',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ocrTags',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsElementEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ocrTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ocrTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ocrTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ocrTags',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsElementStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ocrTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsElementEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ocrTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ocrTags',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ocrTags',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ocrTags',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ocrTags',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ocrTags',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ocrTags',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ocrTags',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ocrTags',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ocrTags',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTagsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'ocrTags',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTextIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'ocrText',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTextIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'ocrText',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> ocrTextEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ocrText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTextGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ocrText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> ocrTextLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ocrText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> ocrTextBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ocrText',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTextStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ocrText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> ocrTextEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ocrText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> ocrTextContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ocrText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> ocrTextMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ocrText',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTextIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ocrText',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      ocrTextIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ocrText',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> pathEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'path',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> pathGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'path',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> pathLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'path',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> pathBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'path',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> pathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'path',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> pathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'path',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> pathContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'path',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> pathMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'path',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> pathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'path',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      pathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'path',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      provinceIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'province',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      provinceIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'province',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> provinceEqualTo(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> provinceBetween(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      provinceContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'province',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> provinceMatches(
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

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      provinceIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'province',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      provinceIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'province',
        value: '',
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      smileProbEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'smileProb',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      smileProbGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'smileProb',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      smileProbLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'smileProb',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      smileProbBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'smileProb',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      timestampEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      timestampGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      timestampLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      timestampBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'timestamp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> widthEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'width',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition>
      widthGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'width',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> widthLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'width',
        value: value,
      ));
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterFilterCondition> widthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'width',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension PhotoEntityQueryObject
    on QueryBuilder<PhotoEntity, PhotoEntity, QFilterCondition> {}

extension PhotoEntityQueryLinks
    on QueryBuilder<PhotoEntity, PhotoEntity, QFilterCondition> {}

extension PhotoEntityQuerySortBy
    on QueryBuilder<PhotoEntity, PhotoEntity, QSortBy> {
  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByAdcode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'adcode', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByAdcodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'adcode', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByAiCaption() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aiCaption', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByAiCaptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aiCaption', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByAspectRatio() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aspectRatio', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByAspectRatioDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aspectRatio', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByAssetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetId', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByAssetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetId', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByCity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByCityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByDistrict() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'district', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByDistrictDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'district', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByEventId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventId', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByEventIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventId', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByFaceCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'faceCount', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByFaceCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'faceCount', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      sortByFormattedAddress() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedAddress', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      sortByFormattedAddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedAddress', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'height', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByHeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'height', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByIsAiAnalyzed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isAiAnalyzed', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      sortByIsAiAnalyzedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isAiAnalyzed', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      sortByIsLocationProcessed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLocationProcessed', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      sortByIsLocationProcessedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLocationProcessed', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      sortByIsProbablyScreenshot() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isProbablyScreenshot', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      sortByIsProbablyScreenshotDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isProbablyScreenshot', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByJoyScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'joyScore', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByJoyScoreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'joyScore', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByLatitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByLocationName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationName', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      sortByLocationNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationName', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByLongitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByOcrText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ocrText', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByOcrTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ocrText', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'path', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'path', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByProvince() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'province', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByProvinceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'province', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortBySmileProb() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smileProb', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortBySmileProbDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smileProb', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'width', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> sortByWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'width', Sort.desc);
    });
  }
}

extension PhotoEntityQuerySortThenBy
    on QueryBuilder<PhotoEntity, PhotoEntity, QSortThenBy> {
  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByAdcode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'adcode', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByAdcodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'adcode', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByAiCaption() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aiCaption', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByAiCaptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aiCaption', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByAspectRatio() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aspectRatio', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByAspectRatioDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'aspectRatio', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByAssetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetId', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByAssetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetId', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByCity() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByCityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'city', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByDistrict() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'district', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByDistrictDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'district', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByEventId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventId', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByEventIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'eventId', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByFaceCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'faceCount', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByFaceCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'faceCount', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      thenByFormattedAddress() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedAddress', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      thenByFormattedAddressDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'formattedAddress', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'height', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByHeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'height', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByIsAiAnalyzed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isAiAnalyzed', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      thenByIsAiAnalyzedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isAiAnalyzed', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      thenByIsLocationProcessed() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLocationProcessed', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      thenByIsLocationProcessedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isLocationProcessed', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      thenByIsProbablyScreenshot() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isProbablyScreenshot', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      thenByIsProbablyScreenshotDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isProbablyScreenshot', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByJoyScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'joyScore', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByJoyScoreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'joyScore', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByLatitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'latitude', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByLocationName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationName', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy>
      thenByLocationNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'locationName', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByLongitudeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'longitude', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByOcrText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ocrText', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByOcrTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ocrText', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'path', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'path', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByProvince() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'province', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByProvinceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'province', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenBySmileProb() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smileProb', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenBySmileProbDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smileProb', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'width', Sort.asc);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QAfterSortBy> thenByWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'width', Sort.desc);
    });
  }
}

extension PhotoEntityQueryWhereDistinct
    on QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> {
  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByAdcode(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'adcode', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByAiCaption(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'aiCaption', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByAiTags() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'aiTags');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByAspectRatio() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'aspectRatio');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByAssetId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'assetId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByCity(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'city', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByDistrict(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'district', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByEventId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'eventId');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByFaceCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'faceCount');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByFormattedAddress(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'formattedAddress',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'height');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByImageEmbedding() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'imageEmbedding');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByIsAiAnalyzed() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isAiAnalyzed');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct>
      distinctByIsLocationProcessed() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isLocationProcessed');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct>
      distinctByIsProbablyScreenshot() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isProbablyScreenshot');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByJoyScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'joyScore');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByLatitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'latitude');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByLocationName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'locationName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByLongitude() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'longitude');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByOcrTags() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ocrTags');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByOcrText(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ocrText', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'path', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByProvince(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'province', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctBySmileProb() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'smileProb');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'timestamp');
    });
  }

  QueryBuilder<PhotoEntity, PhotoEntity, QDistinct> distinctByWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'width');
    });
  }
}

extension PhotoEntityQueryProperty
    on QueryBuilder<PhotoEntity, PhotoEntity, QQueryProperty> {
  QueryBuilder<PhotoEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<PhotoEntity, String?, QQueryOperations> adcodeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'adcode');
    });
  }

  QueryBuilder<PhotoEntity, String?, QQueryOperations> aiCaptionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'aiCaption');
    });
  }

  QueryBuilder<PhotoEntity, List<String>?, QQueryOperations> aiTagsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'aiTags');
    });
  }

  QueryBuilder<PhotoEntity, double, QQueryOperations> aspectRatioProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'aspectRatio');
    });
  }

  QueryBuilder<PhotoEntity, String, QQueryOperations> assetIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'assetId');
    });
  }

  QueryBuilder<PhotoEntity, String?, QQueryOperations> cityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'city');
    });
  }

  QueryBuilder<PhotoEntity, String?, QQueryOperations> districtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'district');
    });
  }

  QueryBuilder<PhotoEntity, int?, QQueryOperations> eventIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'eventId');
    });
  }

  QueryBuilder<PhotoEntity, int, QQueryOperations> faceCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'faceCount');
    });
  }

  QueryBuilder<PhotoEntity, String?, QQueryOperations>
      formattedAddressProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'formattedAddress');
    });
  }

  QueryBuilder<PhotoEntity, int, QQueryOperations> heightProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'height');
    });
  }

  QueryBuilder<PhotoEntity, List<double>?, QQueryOperations>
      imageEmbeddingProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'imageEmbedding');
    });
  }

  QueryBuilder<PhotoEntity, bool, QQueryOperations> isAiAnalyzedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isAiAnalyzed');
    });
  }

  QueryBuilder<PhotoEntity, bool, QQueryOperations>
      isLocationProcessedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isLocationProcessed');
    });
  }

  QueryBuilder<PhotoEntity, bool, QQueryOperations>
      isProbablyScreenshotProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isProbablyScreenshot');
    });
  }

  QueryBuilder<PhotoEntity, double?, QQueryOperations> joyScoreProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'joyScore');
    });
  }

  QueryBuilder<PhotoEntity, double?, QQueryOperations> latitudeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'latitude');
    });
  }

  QueryBuilder<PhotoEntity, String?, QQueryOperations> locationNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'locationName');
    });
  }

  QueryBuilder<PhotoEntity, double?, QQueryOperations> longitudeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'longitude');
    });
  }

  QueryBuilder<PhotoEntity, List<String>?, QQueryOperations> ocrTagsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ocrTags');
    });
  }

  QueryBuilder<PhotoEntity, String?, QQueryOperations> ocrTextProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ocrText');
    });
  }

  QueryBuilder<PhotoEntity, String, QQueryOperations> pathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'path');
    });
  }

  QueryBuilder<PhotoEntity, String?, QQueryOperations> provinceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'province');
    });
  }

  QueryBuilder<PhotoEntity, double, QQueryOperations> smileProbProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'smileProb');
    });
  }

  QueryBuilder<PhotoEntity, int, QQueryOperations> timestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'timestamp');
    });
  }

  QueryBuilder<PhotoEntity, int, QQueryOperations> widthProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'width');
    });
  }
}
