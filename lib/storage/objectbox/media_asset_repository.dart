import '../../objectbox.g.dart';
import 'entities/media_asset_entity.dart';
import 'objectbox_service.dart';

class MediaAssetRepository {
  MediaAssetRepository({ObjectBoxService? objectBoxService})
    : _objectBoxService = objectBoxService ?? ObjectBoxService();

  final ObjectBoxService _objectBoxService;

  Box<MediaAssetEntity>? get _box => _objectBoxService.tryBox<MediaAssetEntity>();

  bool get isReady => _box != null;

  bool get isEmpty {
    final box = _box;
    if (box == null) return true;
    return box.count() == 0;
  }

  int countPending() {
    final box = _box;
    if (box == null) return 0;
    final pending = MediaAssetEntity_.status.equals(MediaAssetStatus.pending.index);
    final dirty = MediaAssetEntity_.status.equals(MediaAssetStatus.dirty.index);
    final query = box.query(pending.or(dirty)).build();
    try {
      return query.count();
    } finally {
      query.close();
    }
  }

  List<MediaAssetEntity> getByAssetIds(Iterable<String> assetIds) {
    final box = _box;
    final keys = assetIds.toSet().toList(growable: false);
    if (box == null || keys.isEmpty) {
      return const <MediaAssetEntity>[];
    }

    final query = box.query(MediaAssetEntity_.assetId.oneOf(keys)).build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Map<String, MediaAssetEntity> getByAssetIdMap(Iterable<String> assetIds) {
    final entities = getByAssetIds(assetIds);
    return <String, MediaAssetEntity>{
      for (final entity in entities) entity.assetId: entity,
    };
  }

  List<String> loadAllAssetIds() {
    final box = _box;
    if (box == null) {
      return const <String>[];
    }
    final query = box.query().build();
    try {
      return query
          .find()
          .map((entity) => entity.assetId)
          .toList(growable: false);
    } finally {
      query.close();
    }
  }

  void putMany(List<MediaAssetEntity> entities) {
    if (entities.isEmpty) {
      return;
    }
    _box?.putMany(entities);
  }

  void removeByAssetIds(Iterable<String> assetIds) {
    final box = _box;
    final keys = assetIds.toSet().toList(growable: false);
    if (box == null || keys.isEmpty) {
      return;
    }

    final query = box.query(MediaAssetEntity_.assetId.oneOf(keys)).build();
    try {
      final ids = query.findIds();
      if (ids.isNotEmpty) {
        box.removeMany(ids);
      }
    } finally {
      query.close();
    }
  }

  List<MediaAssetEntity> loadPending({int limit = 200}) {
    final box = _box;
    if (box == null) {
      return const <MediaAssetEntity>[];
    }

    final pending = MediaAssetEntity_.status.equals(MediaAssetStatus.pending.index);
    final dirty = MediaAssetEntity_.status.equals(MediaAssetStatus.dirty.index);
    final query = box.query(pending.or(dirty)).build();
    try {
      final results = query.find();
      results.sort((a, b) => b.createTimeMs.compareTo(a.createTimeMs));
      if (results.length <= limit) {
        return results;
      }
      return results.take(limit).toList(growable: false);
    } finally {
      query.close();
    }
  }

  List<ObjectWithScore<MediaAssetEntity>> queryNearest(
    List<double> queryVector,
    int k,
  ) {
    final box = _box;
    if (box == null || queryVector.isEmpty || k <= 0) {
      return const <ObjectWithScore<MediaAssetEntity>>[];
    }

    final condition = MediaAssetEntity_.embedding
        .nearestNeighborsF32(queryVector, k)
        .and(MediaAssetEntity_.status.equals(MediaAssetStatus.ready.index));
    final query = box.query(condition).build();
    try {
      return query.findWithScores();
    } finally {
      query.close();
    }
  }

  void clearAll() {
    _box?.removeAll();
  }
}
