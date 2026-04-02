import '../../models/entity/face_entity.dart';
import '../../objectbox.g.dart';
import '../objectbox/entities/face_embedding_index_entity.dart';
import '../objectbox/objectbox_service.dart';
import 'vector_index_constants.dart';

class FaceEmbeddingIndexRepository {
  FaceEmbeddingIndexRepository({ObjectBoxService? objectBoxService})
    : _objectBoxService = objectBoxService ?? ObjectBoxService();

  final ObjectBoxService _objectBoxService;

  Box<FaceEmbeddingIndexEntity>? get _boxOrNull =>
      _objectBoxService.tryBox<FaceEmbeddingIndexEntity>();

  bool get isReady => _boxOrNull != null;

  List<double>? readEmbeddingForFace(
    FaceEntity face, {
    bool allowLegacyFallback = true,
  }) {
    final indexed = readEmbeddingsForFaces(<FaceEntity>[
      face,
    ], allowLegacyFallback: false)[face.id];
    return indexed ??
        (allowLegacyFallback ? _normalizedVector(face.embedding) : null);
  }

  Map<int, List<double>> readEmbeddingsForFaces(
    Iterable<FaceEntity> faces, {
    bool allowLegacyFallback = true,
  }) {
    final faceList = faces.where((face) => face.id > 0).toList(growable: false);
    if (faceList.isEmpty) {
      return const <int, List<double>>{};
    }

    final lookupByFaceId = <int, String>{
      for (final face in faceList)
        if (face.embeddingModelVersion.trim().isNotEmpty)
          face.id: FaceEmbeddingIndexEntity.buildLookupKey(
            face.id,
            face.embeddingModelVersion,
          ),
    };
    final indexedByLookupKey = _readRecordsByLookupKeys(lookupByFaceId.values);
    final result = <int, List<double>>{};

    for (final face in faceList) {
      final indexedVector = _normalizedVector(
        indexedByLookupKey[lookupByFaceId[face.id]]?.vector,
      );
      if (indexedVector != null) {
        result[face.id] = indexedVector;
        continue;
      }

      if (!allowLegacyFallback) {
        continue;
      }
      final legacy = _normalizedVector(face.embedding);
      if (legacy != null) {
        result[face.id] = legacy;
      }
    }

    return result;
  }

  void replaceForPhoto({
    required int photoId,
    required Iterable<FaceEntity> faces,
  }) {
    final box = _boxOrNull;
    if (box == null || photoId <= 0) {
      return;
    }

    final faceList = faces.where((face) => face.id > 0).toList(growable: false);
    final store = _objectBoxService.store;
    store.runInTransaction(TxMode.write, () {
      final existingQuery = box
          .query(FaceEmbeddingIndexEntity_.photoId.equals(photoId))
          .build();
      try {
        final existingIds = existingQuery.findIds();
        if (existingIds.isNotEmpty) {
          box.removeMany(existingIds);
        }
      } finally {
        existingQuery.close();
      }

      final entities = faceList
          .map(_toEntityOrNull)
          .whereType<FaceEmbeddingIndexEntity>()
          .toList(growable: false);
      if (entities.isNotEmpty) {
        box.putMany(entities);
      }
    });
  }

  void upsertFromFace(FaceEntity face, {bool isStale = false}) {
    final box = _boxOrNull;
    final entity = _toEntityOrNull(face, isStale: isStale);
    if (box == null || entity == null) {
      return;
    }
    box.put(entity);
  }

  void deleteByPhotoIds(Iterable<int> photoIds) {
    final box = _boxOrNull;
    final ids = photoIds.where((id) => id > 0).toSet().toList(growable: false);
    if (box == null || ids.isEmpty) {
      return;
    }

    final query = box
        .query(FaceEmbeddingIndexEntity_.photoId.oneOf(ids))
        .build();
    try {
      final entityIds = query.findIds();
      if (entityIds.isNotEmpty) {
        box.removeMany(entityIds);
      }
    } finally {
      query.close();
    }
  }

  void deleteAll() {
    _boxOrNull?.removeAll();
  }

  Map<String, FaceEmbeddingIndexEntity> _readRecordsByLookupKeys(
    Iterable<String> lookupKeys,
  ) {
    final box = _boxOrNull;
    final keys = lookupKeys
        .where((lookupKey) => lookupKey.trim().isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (box == null || keys.isEmpty) {
      return const <String, FaceEmbeddingIndexEntity>{};
    }

    final query = box
        .query(FaceEmbeddingIndexEntity_.lookupKey.oneOf(keys))
        .build();
    try {
      final grouped = <String, FaceEmbeddingIndexEntity>{};
      final entities = query.find();
      for (final entity in entities) {
        if (entity.isStale || _normalizedVector(entity.vector) == null) {
          continue;
        }
        grouped[entity.lookupKey] = entity;
      }
      return grouped;
    } finally {
      query.close();
    }
  }

  FaceEmbeddingIndexEntity? _toEntityOrNull(
    FaceEntity face, {
    bool isStale = false,
  }) {
    final vector = _normalizedVector(face.embedding);
    if (face.id <= 0 || face.photoId <= 0 || vector == null) {
      return null;
    }

    return FaceEmbeddingIndexEntity(
      lookupKey: FaceEmbeddingIndexEntity.buildLookupKey(
        face.id,
        face.embeddingModelVersion,
      ),
      faceId: face.id,
      photoId: face.photoId,
      modelVersion: face.embeddingModelVersion,
      updatedAtMillis: face.updatedAt,
      isStale: isStale,
      qualityScore: face.qualityScore,
      vector: vector,
    );
  }

  List<double>? _normalizedVector(List<double>? vector) {
    if (vector == null || vector.length != kFaceEmbeddingVectorDimensions) {
      return null;
    }
    return List<double>.unmodifiable(vector);
  }
}
