/// 照片向量索引仓库，负责存取和查询照片嵌入数据。

import '../../models/entity/photo_entity.dart';
import '../../objectbox.g.dart';
import '../objectbox/entities/photo_embedding_index_entity.dart';
import '../objectbox/objectbox_service.dart';
import 'vector_index_constants.dart';

class PhotoEmbeddingIndexRepository {
  PhotoEmbeddingIndexRepository({ObjectBoxService? objectBoxService})
    : _objectBoxService = objectBoxService ?? ObjectBoxService();

  final ObjectBoxService _objectBoxService;

  bool get isReady => _boxOrNull != null;

  Box<PhotoEmbeddingIndexEntity>? get _boxOrNull =>
      _objectBoxService.tryBox<PhotoEmbeddingIndexEntity>();

  List<double>? readEmbeddingForPhoto(
    PhotoEntity photo, {
    required String modelVersion,
  }) {
    final indexed = readIndexedEmbeddingsByPhotoIds(<int>[
      photo.id,
    ], modelVersion: modelVersion)[photo.id];
    return indexed;
  }

  Map<int, List<double>> readEmbeddingsForPhotos(
    Iterable<PhotoEntity> photos, {
    required String modelVersion,
  }) {
    final photoList = photos
        .where((photo) => photo.id > 0)
        .toList(growable: false);
    if (photoList.isEmpty) {
      return const <int, List<double>>{};
    }

    final indexedByPhotoId = readIndexedEmbeddingsByPhotoIds(
      photoList.map((photo) => photo.id),
      modelVersion: modelVersion,
    );
    final result = <int, List<double>>{};

    for (final photo in photoList) {
      final indexedVector = indexedByPhotoId[photo.id];
      if (indexedVector != null) {
        result[photo.id] = indexedVector;
        continue;
      }
    }

    return result;
  }

  Map<int, List<double>> readIndexedEmbeddingsByPhotoIds(
    Iterable<int> photoIds, {
    required String modelVersion,
  }) {
    final box = _boxOrNull;
    final ids = photoIds.where((id) => id > 0).toSet().toList(growable: false);
    if (box == null || ids.isEmpty) {
      return const <int, List<double>>{};
    }

    final lookupKeys = ids
        .map(
          (photoId) =>
              PhotoEmbeddingIndexEntity.buildLookupKey(photoId, modelVersion),
        )
        .toList(growable: false);
    final query = box
        .query(PhotoEmbeddingIndexEntity_.lookupKey.oneOf(lookupKeys))
        .build();
    try {
      final result = <int, List<double>>{};
      for (final entity in query.find()) {
        final vector = _normalizedVector(entity.vector);
        if (vector == null || entity.isStale) {
          continue;
        }
        result[entity.photoId] = vector;
      }
      return result;
    } finally {
      query.close();
    }
  }

  void upsertEmbedding({
    required int photoId,
    required List<double> vector,
    required String modelVersion,
    bool isStale = false,
    int? updatedAtMillis,
  }) {
    final box = _boxOrNull;
    final normalized = _normalizedVector(vector);
    if (box == null || photoId <= 0 || normalized == null) {
      return;
    }

    final entity = PhotoEmbeddingIndexEntity(
      lookupKey: PhotoEmbeddingIndexEntity.buildLookupKey(
        photoId,
        modelVersion,
      ),
      photoId: photoId,
      modelVersion: modelVersion,
      updatedAtMillis: updatedAtMillis ?? DateTime.now().millisecondsSinceEpoch,
      isStale: isStale,
      vector: normalized,
    );
    box.put(entity);
  }

  void deleteByPhotoIds(Iterable<int> photoIds) {
    final box = _boxOrNull;
    final ids = photoIds.where((id) => id > 0).toSet().toList(growable: false);
    if (box == null || ids.isEmpty) {
      return;
    }

    final query = box
        .query(PhotoEmbeddingIndexEntity_.photoId.oneOf(ids))
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

  List<ObjectWithScore<PhotoEmbeddingIndexEntity>> queryNearest(
    List<double> vector, {
    int topK = 24,
    required String modelVersion,
    bool includeStale = false,
  }) {
    final box = _boxOrNull;
    final normalized = _normalizedVector(vector);
    if (box == null || normalized == null || topK <= 0) {
      return const <ObjectWithScore<PhotoEmbeddingIndexEntity>>[];
    }

    Condition<PhotoEmbeddingIndexEntity> condition = PhotoEmbeddingIndexEntity_
        .vector
        .nearestNeighborsF32(normalized, topK);
    condition = condition.and(
      PhotoEmbeddingIndexEntity_.modelVersion.equals(modelVersion),
    );
    if (!includeStale) {
      condition = condition.and(
        PhotoEmbeddingIndexEntity_.isStale.equals(false),
      );
    }

    final query = box.query(condition).build();
    try {
      return query.findWithScores();
    } finally {
      query.close();
    }
  }

  List<double>? _normalizedVector(List<double>? vector) {
    if (vector == null || vector.length != kPhotoEmbeddingVectorDimensions) {
      return null;
    }
    return List<double>.unmodifiable(vector);
  }
}
