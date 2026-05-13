// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'face_entity.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetFaceEntityCollection on Isar {
  IsarCollection<FaceEntity> get faceEntitys => this.collection();
}

const FaceEntitySchema = CollectionSchema(
  name: r'FaceEntity',
  id: -8503213526589950055,
  properties: {
    r'area': PropertySchema(
      id: 0,
      name: r'area',
      type: IsarType.double,
    ),
    r'assetId': PropertySchema(
      id: 1,
      name: r'assetId',
      type: IsarType.string,
    ),
    r'bottom': PropertySchema(
      id: 2,
      name: r'bottom',
      type: IsarType.double,
    ),
    r'clusterId': PropertySchema(
      id: 3,
      name: r'clusterId',
      type: IsarType.long,
    ),
    r'createdAt': PropertySchema(
      id: 4,
      name: r'createdAt',
      type: IsarType.long,
    ),
    r'debugCropPath': PropertySchema(
      id: 5,
      name: r'debugCropPath',
      type: IsarType.string,
    ),
    r'embedding': PropertySchema(
      id: 6,
      name: r'embedding',
      type: IsarType.doubleList,
    ),
    r'embeddingModelVersion': PropertySchema(
      id: 7,
      name: r'embeddingModelVersion',
      type: IsarType.string,
    ),
    r'faceIndex': PropertySchema(
      id: 8,
      name: r'faceIndex',
      type: IsarType.long,
    ),
    r'height': PropertySchema(
      id: 9,
      name: r'height',
      type: IsarType.double,
    ),
    r'isPrimaryFace': PropertySchema(
      id: 10,
      name: r'isPrimaryFace',
      type: IsarType.bool,
    ),
    r'left': PropertySchema(
      id: 11,
      name: r'left',
      type: IsarType.double,
    ),
    r'leftEyeOpenProbability': PropertySchema(
      id: 12,
      name: r'leftEyeOpenProbability',
      type: IsarType.double,
    ),
    r'photoId': PropertySchema(
      id: 13,
      name: r'photoId',
      type: IsarType.long,
    ),
    r'qualityScore': PropertySchema(
      id: 14,
      name: r'qualityScore',
      type: IsarType.double,
    ),
    r'right': PropertySchema(
      id: 15,
      name: r'right',
      type: IsarType.double,
    ),
    r'rightEyeOpenProbability': PropertySchema(
      id: 16,
      name: r'rightEyeOpenProbability',
      type: IsarType.double,
    ),
    r'roll': PropertySchema(
      id: 17,
      name: r'roll',
      type: IsarType.double,
    ),
    r'smilingProbability': PropertySchema(
      id: 18,
      name: r'smilingProbability',
      type: IsarType.double,
    ),
    r'top': PropertySchema(
      id: 19,
      name: r'top',
      type: IsarType.double,
    ),
    r'updatedAt': PropertySchema(
      id: 20,
      name: r'updatedAt',
      type: IsarType.long,
    ),
    r'width': PropertySchema(
      id: 21,
      name: r'width',
      type: IsarType.double,
    ),
    r'yaw': PropertySchema(
      id: 22,
      name: r'yaw',
      type: IsarType.double,
    )
  },
  estimateSize: _faceEntityEstimateSize,
  serialize: _faceEntitySerialize,
  deserialize: _faceEntityDeserialize,
  deserializeProp: _faceEntityDeserializeProp,
  idName: r'id',
  indexes: {
    r'photoId': IndexSchema(
      id: -1877533456151046685,
      name: r'photoId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'photoId',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    ),
    r'assetId': IndexSchema(
      id: 174362542210192109,
      name: r'assetId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'assetId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    ),
    r'clusterId': IndexSchema(
      id: 1919966277605001711,
      name: r'clusterId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'clusterId',
          type: IndexType.value,
          caseSensitive: false,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _faceEntityGetId,
  getLinks: _faceEntityGetLinks,
  attach: _faceEntityAttach,
  version: '3.1.0+1',
);

int _faceEntityEstimateSize(
  FaceEntity object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.assetId.length * 3;
  {
    final value = object.debugCropPath;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.embedding;
    if (value != null) {
      bytesCount += 3 + value.length * 8;
    }
  }
  bytesCount += 3 + object.embeddingModelVersion.length * 3;
  return bytesCount;
}

void _faceEntitySerialize(
  FaceEntity object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeDouble(offsets[0], object.area);
  writer.writeString(offsets[1], object.assetId);
  writer.writeDouble(offsets[2], object.bottom);
  writer.writeLong(offsets[3], object.clusterId);
  writer.writeLong(offsets[4], object.createdAt);
  writer.writeString(offsets[5], object.debugCropPath);
  writer.writeDoubleList(offsets[6], object.embedding);
  writer.writeString(offsets[7], object.embeddingModelVersion);
  writer.writeLong(offsets[8], object.faceIndex);
  writer.writeDouble(offsets[9], object.height);
  writer.writeBool(offsets[10], object.isPrimaryFace);
  writer.writeDouble(offsets[11], object.left);
  writer.writeDouble(offsets[12], object.leftEyeOpenProbability);
  writer.writeLong(offsets[13], object.photoId);
  writer.writeDouble(offsets[14], object.qualityScore);
  writer.writeDouble(offsets[15], object.right);
  writer.writeDouble(offsets[16], object.rightEyeOpenProbability);
  writer.writeDouble(offsets[17], object.roll);
  writer.writeDouble(offsets[18], object.smilingProbability);
  writer.writeDouble(offsets[19], object.top);
  writer.writeLong(offsets[20], object.updatedAt);
  writer.writeDouble(offsets[21], object.width);
  writer.writeDouble(offsets[22], object.yaw);
}

FaceEntity _faceEntityDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = FaceEntity();
  object.assetId = reader.readString(offsets[1]);
  object.bottom = reader.readDouble(offsets[2]);
  object.clusterId = reader.readLongOrNull(offsets[3]);
  object.createdAt = reader.readLong(offsets[4]);
  object.debugCropPath = reader.readStringOrNull(offsets[5]);
  object.embedding = reader.readDoubleList(offsets[6]);
  object.embeddingModelVersion = reader.readString(offsets[7]);
  object.faceIndex = reader.readLong(offsets[8]);
  object.id = id;
  object.isPrimaryFace = reader.readBool(offsets[10]);
  object.left = reader.readDouble(offsets[11]);
  object.leftEyeOpenProbability = reader.readDoubleOrNull(offsets[12]);
  object.photoId = reader.readLong(offsets[13]);
  object.qualityScore = reader.readDoubleOrNull(offsets[14]);
  object.right = reader.readDouble(offsets[15]);
  object.rightEyeOpenProbability = reader.readDoubleOrNull(offsets[16]);
  object.roll = reader.readDoubleOrNull(offsets[17]);
  object.smilingProbability = reader.readDoubleOrNull(offsets[18]);
  object.top = reader.readDouble(offsets[19]);
  object.updatedAt = reader.readLong(offsets[20]);
  object.yaw = reader.readDoubleOrNull(offsets[22]);
  return object;
}

P _faceEntityDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readDouble(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readDouble(offset)) as P;
    case 3:
      return (reader.readLongOrNull(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readDoubleList(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readLong(offset)) as P;
    case 9:
      return (reader.readDouble(offset)) as P;
    case 10:
      return (reader.readBool(offset)) as P;
    case 11:
      return (reader.readDouble(offset)) as P;
    case 12:
      return (reader.readDoubleOrNull(offset)) as P;
    case 13:
      return (reader.readLong(offset)) as P;
    case 14:
      return (reader.readDoubleOrNull(offset)) as P;
    case 15:
      return (reader.readDouble(offset)) as P;
    case 16:
      return (reader.readDoubleOrNull(offset)) as P;
    case 17:
      return (reader.readDoubleOrNull(offset)) as P;
    case 18:
      return (reader.readDoubleOrNull(offset)) as P;
    case 19:
      return (reader.readDouble(offset)) as P;
    case 20:
      return (reader.readLong(offset)) as P;
    case 21:
      return (reader.readDouble(offset)) as P;
    case 22:
      return (reader.readDoubleOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _faceEntityGetId(FaceEntity object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _faceEntityGetLinks(FaceEntity object) {
  return [];
}

void _faceEntityAttach(IsarCollection<dynamic> col, Id id, FaceEntity object) {
  object.id = id;
}

extension FaceEntityQueryWhereSort
    on QueryBuilder<FaceEntity, FaceEntity, QWhere> {
  QueryBuilder<FaceEntity, FaceEntity, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhere> anyPhotoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'photoId'),
      );
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhere> anyClusterId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'clusterId'),
      );
    });
  }
}

extension FaceEntityQueryWhere
    on QueryBuilder<FaceEntity, FaceEntity, QWhereClause> {
  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> idNotEqualTo(Id id) {
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> idGreaterThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> idLessThan(Id id,
      {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> idBetween(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> photoIdEqualTo(
      int photoId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'photoId',
        value: [photoId],
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> photoIdNotEqualTo(
      int photoId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'photoId',
              lower: [],
              upper: [photoId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'photoId',
              lower: [photoId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'photoId',
              lower: [photoId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'photoId',
              lower: [],
              upper: [photoId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> photoIdGreaterThan(
    int photoId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'photoId',
        lower: [photoId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> photoIdLessThan(
    int photoId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'photoId',
        lower: [],
        upper: [photoId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> photoIdBetween(
    int lowerPhotoId,
    int upperPhotoId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'photoId',
        lower: [lowerPhotoId],
        includeLower: includeLower,
        upper: [upperPhotoId],
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> assetIdEqualTo(
      String assetId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'assetId',
        value: [assetId],
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> assetIdNotEqualTo(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> clusterIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'clusterId',
        value: [null],
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> clusterIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'clusterId',
        lower: [null],
        includeLower: false,
        upper: [],
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> clusterIdEqualTo(
      int? clusterId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'clusterId',
        value: [clusterId],
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> clusterIdNotEqualTo(
      int? clusterId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'clusterId',
              lower: [],
              upper: [clusterId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'clusterId',
              lower: [clusterId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'clusterId',
              lower: [clusterId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'clusterId',
              lower: [],
              upper: [clusterId],
              includeUpper: false,
            ));
      }
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> clusterIdGreaterThan(
    int? clusterId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'clusterId',
        lower: [clusterId],
        includeLower: include,
        upper: [],
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> clusterIdLessThan(
    int? clusterId, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'clusterId',
        lower: [],
        upper: [clusterId],
        includeUpper: include,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterWhereClause> clusterIdBetween(
    int? lowerClusterId,
    int? upperClusterId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.between(
        indexName: r'clusterId',
        lower: [lowerClusterId],
        includeLower: includeLower,
        upper: [upperClusterId],
        includeUpper: includeUpper,
      ));
    });
  }
}

extension FaceEntityQueryFilter
    on QueryBuilder<FaceEntity, FaceEntity, QFilterCondition> {
  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> areaEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'area',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> areaGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'area',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> areaLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'area',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> areaBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'area',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> assetIdEqualTo(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> assetIdLessThan(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> assetIdBetween(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> assetIdStartsWith(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> assetIdEndsWith(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> assetIdContains(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> assetIdMatches(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> assetIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'assetId',
        value: '',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      assetIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'assetId',
        value: '',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> bottomEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'bottom',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> bottomGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'bottom',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> bottomLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'bottom',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> bottomBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'bottom',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      clusterIdIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'clusterId',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      clusterIdIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'clusterId',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> clusterIdEqualTo(
      int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'clusterId',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      clusterIdGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'clusterId',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> clusterIdLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'clusterId',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> clusterIdBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'clusterId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> createdAtEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'createdAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> createdAtLessThan(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> createdAtBetween(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'debugCropPath',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'debugCropPath',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'debugCropPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'debugCropPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'debugCropPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'debugCropPath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'debugCropPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'debugCropPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'debugCropPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'debugCropPath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'debugCropPath',
        value: '',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      debugCropPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'debugCropPath',
        value: '',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'embedding',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'embedding',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingElementEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'embedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingElementGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'embedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingElementLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'embedding',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingElementBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'embedding',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        0,
        true,
        0,
        true,
      );
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingLengthLessThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingLengthGreaterThan(
    int length, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'embedding',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingModelVersionEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'embeddingModelVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingModelVersionGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'embeddingModelVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingModelVersionLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'embeddingModelVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingModelVersionBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'embeddingModelVersion',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingModelVersionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'embeddingModelVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingModelVersionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'embeddingModelVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingModelVersionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'embeddingModelVersion',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingModelVersionMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'embeddingModelVersion',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingModelVersionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'embeddingModelVersion',
        value: '',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      embeddingModelVersionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'embeddingModelVersion',
        value: '',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> faceIndexEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'faceIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      faceIndexGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'faceIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> faceIndexLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'faceIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> faceIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'faceIndex',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> heightEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'height',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> heightGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'height',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> heightLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'height',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> heightBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'height',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> idEqualTo(
      Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> idGreaterThan(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> idLessThan(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> idBetween(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      isPrimaryFaceEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isPrimaryFace',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> leftEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'left',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> leftGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'left',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> leftLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'left',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> leftBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'left',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      leftEyeOpenProbabilityIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'leftEyeOpenProbability',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      leftEyeOpenProbabilityIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'leftEyeOpenProbability',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      leftEyeOpenProbabilityEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'leftEyeOpenProbability',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      leftEyeOpenProbabilityGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'leftEyeOpenProbability',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      leftEyeOpenProbabilityLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'leftEyeOpenProbability',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      leftEyeOpenProbabilityBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'leftEyeOpenProbability',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> photoIdEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'photoId',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      photoIdGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'photoId',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> photoIdLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'photoId',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> photoIdBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'photoId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      qualityScoreIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'qualityScore',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      qualityScoreIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'qualityScore',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      qualityScoreEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'qualityScore',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      qualityScoreGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'qualityScore',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      qualityScoreLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'qualityScore',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      qualityScoreBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'qualityScore',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> rightEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'right',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> rightGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'right',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> rightLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'right',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> rightBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'right',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      rightEyeOpenProbabilityIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'rightEyeOpenProbability',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      rightEyeOpenProbabilityIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'rightEyeOpenProbability',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      rightEyeOpenProbabilityEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'rightEyeOpenProbability',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      rightEyeOpenProbabilityGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'rightEyeOpenProbability',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      rightEyeOpenProbabilityLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'rightEyeOpenProbability',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      rightEyeOpenProbabilityBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'rightEyeOpenProbability',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> rollIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'roll',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> rollIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'roll',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> rollEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'roll',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> rollGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'roll',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> rollLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'roll',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> rollBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'roll',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      smilingProbabilityIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'smilingProbability',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      smilingProbabilityIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'smilingProbability',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      smilingProbabilityEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'smilingProbability',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      smilingProbabilityGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'smilingProbability',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      smilingProbabilityLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'smilingProbability',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
      smilingProbabilityBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'smilingProbability',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> topEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'top',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> topGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'top',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> topLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'top',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> topBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'top',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> updatedAtEqualTo(
      int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition>
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> updatedAtLessThan(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> updatedAtBetween(
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

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> widthEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'width',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> widthGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'width',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> widthLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'width',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> widthBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'width',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> yawIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'yaw',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> yawIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'yaw',
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> yawEqualTo(
    double? value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'yaw',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> yawGreaterThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'yaw',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> yawLessThan(
    double? value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'yaw',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterFilterCondition> yawBetween(
    double? lower,
    double? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'yaw',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }
}

extension FaceEntityQueryObject
    on QueryBuilder<FaceEntity, FaceEntity, QFilterCondition> {}

extension FaceEntityQueryLinks
    on QueryBuilder<FaceEntity, FaceEntity, QFilterCondition> {}

extension FaceEntityQuerySortBy
    on QueryBuilder<FaceEntity, FaceEntity, QSortBy> {
  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByArea() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'area', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByAreaDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'area', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByAssetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetId', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByAssetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetId', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByBottom() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bottom', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByBottomDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bottom', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByClusterId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clusterId', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByClusterIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clusterId', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByDebugCropPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'debugCropPath', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByDebugCropPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'debugCropPath', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      sortByEmbeddingModelVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'embeddingModelVersion', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      sortByEmbeddingModelVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'embeddingModelVersion', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByFaceIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'faceIndex', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByFaceIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'faceIndex', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'height', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByHeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'height', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByIsPrimaryFace() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPrimaryFace', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByIsPrimaryFaceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPrimaryFace', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByLeft() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'left', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByLeftDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'left', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      sortByLeftEyeOpenProbability() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'leftEyeOpenProbability', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      sortByLeftEyeOpenProbabilityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'leftEyeOpenProbability', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByPhotoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoId', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByPhotoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoId', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByQualityScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'qualityScore', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByQualityScoreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'qualityScore', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByRight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'right', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByRightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'right', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      sortByRightEyeOpenProbability() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rightEyeOpenProbability', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      sortByRightEyeOpenProbabilityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rightEyeOpenProbability', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByRoll() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roll', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByRollDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roll', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      sortBySmilingProbability() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smilingProbability', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      sortBySmilingProbabilityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smilingProbability', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByTop() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'top', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByTopDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'top', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'width', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'width', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByYaw() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yaw', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> sortByYawDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yaw', Sort.desc);
    });
  }
}

extension FaceEntityQuerySortThenBy
    on QueryBuilder<FaceEntity, FaceEntity, QSortThenBy> {
  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByArea() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'area', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByAreaDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'area', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByAssetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetId', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByAssetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'assetId', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByBottom() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bottom', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByBottomDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'bottom', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByClusterId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clusterId', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByClusterIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clusterId', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByDebugCropPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'debugCropPath', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByDebugCropPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'debugCropPath', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      thenByEmbeddingModelVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'embeddingModelVersion', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      thenByEmbeddingModelVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'embeddingModelVersion', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByFaceIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'faceIndex', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByFaceIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'faceIndex', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'height', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByHeightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'height', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByIsPrimaryFace() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPrimaryFace', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByIsPrimaryFaceDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isPrimaryFace', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByLeft() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'left', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByLeftDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'left', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      thenByLeftEyeOpenProbability() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'leftEyeOpenProbability', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      thenByLeftEyeOpenProbabilityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'leftEyeOpenProbability', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByPhotoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoId', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByPhotoIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'photoId', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByQualityScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'qualityScore', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByQualityScoreDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'qualityScore', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByRight() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'right', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByRightDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'right', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      thenByRightEyeOpenProbability() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rightEyeOpenProbability', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      thenByRightEyeOpenProbabilityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'rightEyeOpenProbability', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByRoll() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roll', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByRollDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'roll', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      thenBySmilingProbability() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smilingProbability', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy>
      thenBySmilingProbabilityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'smilingProbability', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByTop() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'top', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByTopDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'top', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'width', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByWidthDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'width', Sort.desc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByYaw() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yaw', Sort.asc);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QAfterSortBy> thenByYawDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'yaw', Sort.desc);
    });
  }
}

extension FaceEntityQueryWhereDistinct
    on QueryBuilder<FaceEntity, FaceEntity, QDistinct> {
  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByArea() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'area');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByAssetId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'assetId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByBottom() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'bottom');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByClusterId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'clusterId');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByDebugCropPath(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'debugCropPath',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByEmbedding() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'embedding');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct>
      distinctByEmbeddingModelVersion({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'embeddingModelVersion',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByFaceIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'faceIndex');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByHeight() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'height');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByIsPrimaryFace() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isPrimaryFace');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByLeft() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'left');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct>
      distinctByLeftEyeOpenProbability() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'leftEyeOpenProbability');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByPhotoId() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'photoId');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByQualityScore() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'qualityScore');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByRight() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'right');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct>
      distinctByRightEyeOpenProbability() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'rightEyeOpenProbability');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByRoll() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'roll');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct>
      distinctBySmilingProbability() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'smilingProbability');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByTop() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'top');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByWidth() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'width');
    });
  }

  QueryBuilder<FaceEntity, FaceEntity, QDistinct> distinctByYaw() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'yaw');
    });
  }
}

extension FaceEntityQueryProperty
    on QueryBuilder<FaceEntity, FaceEntity, QQueryProperty> {
  QueryBuilder<FaceEntity, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<FaceEntity, double, QQueryOperations> areaProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'area');
    });
  }

  QueryBuilder<FaceEntity, String, QQueryOperations> assetIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'assetId');
    });
  }

  QueryBuilder<FaceEntity, double, QQueryOperations> bottomProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'bottom');
    });
  }

  QueryBuilder<FaceEntity, int?, QQueryOperations> clusterIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'clusterId');
    });
  }

  QueryBuilder<FaceEntity, int, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<FaceEntity, String?, QQueryOperations> debugCropPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'debugCropPath');
    });
  }

  QueryBuilder<FaceEntity, List<double>?, QQueryOperations>
      embeddingProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'embedding');
    });
  }

  QueryBuilder<FaceEntity, String, QQueryOperations>
      embeddingModelVersionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'embeddingModelVersion');
    });
  }

  QueryBuilder<FaceEntity, int, QQueryOperations> faceIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'faceIndex');
    });
  }

  QueryBuilder<FaceEntity, double, QQueryOperations> heightProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'height');
    });
  }

  QueryBuilder<FaceEntity, bool, QQueryOperations> isPrimaryFaceProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isPrimaryFace');
    });
  }

  QueryBuilder<FaceEntity, double, QQueryOperations> leftProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'left');
    });
  }

  QueryBuilder<FaceEntity, double?, QQueryOperations>
      leftEyeOpenProbabilityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'leftEyeOpenProbability');
    });
  }

  QueryBuilder<FaceEntity, int, QQueryOperations> photoIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'photoId');
    });
  }

  QueryBuilder<FaceEntity, double?, QQueryOperations> qualityScoreProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'qualityScore');
    });
  }

  QueryBuilder<FaceEntity, double, QQueryOperations> rightProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'right');
    });
  }

  QueryBuilder<FaceEntity, double?, QQueryOperations>
      rightEyeOpenProbabilityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'rightEyeOpenProbability');
    });
  }

  QueryBuilder<FaceEntity, double?, QQueryOperations> rollProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'roll');
    });
  }

  QueryBuilder<FaceEntity, double?, QQueryOperations>
      smilingProbabilityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'smilingProbability');
    });
  }

  QueryBuilder<FaceEntity, double, QQueryOperations> topProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'top');
    });
  }

  QueryBuilder<FaceEntity, int, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<FaceEntity, double, QQueryOperations> widthProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'width');
    });
  }

  QueryBuilder<FaceEntity, double?, QQueryOperations> yawProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'yaw');
    });
  }
}
