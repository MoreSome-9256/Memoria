part of 'photo_service.dart';

extension PhotoServiceAccess on PhotoService {
  Future<int> _removeUnavailablePhotos() async {
    final localPhotos = await _isar.collection<PhotoEntity>().where().findAll();
    if (localPhotos.isEmpty) {
      return 0;
    }

    final removedIds = <int>[];
    final repairedPhotos = <PhotoEntity>[];
    var cursor = 0;
    final workerCount = math.min(
      PhotoService._assetExistenceWorkerCount,
      localPhotos.length,
    );
    final workers = List<Future<void>>.generate(workerCount, (_) async {
      while (true) {
        final index = cursor;
        cursor++;
        if (index >= localPhotos.length) {
          break;
        }

        final photo = localPhotos[index];
        final asset = await AssetEntity.fromId(photo.assetId);
        if (asset == null) {
          removedIds.add(photo.id);
          continue;
        }

        final currentFile = photo.path.trim().isEmpty ? null : File(photo.path);
        if (currentFile != null && currentFile.existsSync()) {
          continue;
        }

        final refreshedFile = await _resolveReadableFile(asset);
        if (refreshedFile != null && refreshedFile.existsSync()) {
          photo.path = refreshedFile.path;
          final refreshedTimestamp = _resolveBestTimestampMs(
            asset,
            refreshedFile,
          );
          if (PhotoFilterHelper.hasValidTimestamp(refreshedTimestamp)) {
            photo.timestamp = refreshedTimestamp;
          }
          repairedPhotos.add(photo);
        } else {
          removedIds.add(photo.id);
        }
      }
    });

    await Future.wait(workers);

    if (removedIds.isEmpty && repairedPhotos.isEmpty) {
      return 0;
    }

    await _isar.writeTxn(() async {
      if (removedIds.isNotEmpty) {
        await _isar.collection<PhotoEntity>().deleteAll(removedIds);
      }
      if (repairedPhotos.isNotEmpty) {
        await _isar.collection<PhotoEntity>().putAll(repairedPhotos);
      }
    });
    _photoEmbeddingIndexRepository.deleteByPhotoIds(removedIds);
    _faceEmbeddingIndexRepository.deleteByPhotoIds(removedIds);

    if (repairedPhotos.isNotEmpty) {
      debugPrint("🩹 已修复 ${repairedPhotos.length} 条失效照片路径");
    }

    debugPrint("🧹 已清理系统相册中删除/不可访问的照片: ${removedIds.length} 张");
    return removedIds.length;
  }

  Future<List<PhotoEntity>> reconcileAccessiblePhotos(
    Iterable<PhotoEntity> photos,
  ) async {
    final candidates = photos.toList(growable: false);
    if (candidates.isEmpty) {
      return const <PhotoEntity>[];
    }

    final stopwatch = Stopwatch()..start();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final removedIds = <int>{};
    final repairedIds = <int>{};
    var cacheHits = 0;
    var removedCount = 0;
    var repairedCount = 0;
    var cursor = 0;
    final workerCount = math.min(
      PhotoService._assetExistenceWorkerCount,
      candidates.length,
    );
    final workers = List<Future<void>>.generate(workerCount, (_) async {
      while (true) {
        final index = cursor;
        cursor++;
        if (index >= candidates.length) {
          break;
        }

        final photo = candidates[index];
        final cacheKey = _photoAccessCacheKey(photo);
        final cacheEntry = _photoAccessCache[cacheKey];
        if (cacheEntry != null &&
            nowMs - cacheEntry.checkedAtMs <=
                PhotoService._photoAccessCacheTtl.inMilliseconds) {
          cacheHits++;
          if (cacheEntry.isRemoved) {
            if (photo.id > 0) {
              removedIds.add(photo.id);
            }
            removedCount++;
            continue;
          }
          final resolvedPath = cacheEntry.resolvedPath;
          if (resolvedPath != null && resolvedPath.isNotEmpty) {
            photo.path = resolvedPath;
            continue;
          }
        }

        final currentFile = photo.path.trim().isEmpty ? null : File(photo.path);
        if (currentFile != null && currentFile.existsSync()) {
          _photoAccessCache[cacheKey] = _PhotoAccessCacheEntry(
            checkedAtMs: nowMs,
            resolvedPath: photo.path,
          );
          continue;
        }

        final asset = await AssetEntity.fromId(photo.assetId);
        if (asset == null) {
          if (photo.id > 0) {
            removedIds.add(photo.id);
          }
          _photoAccessCache[cacheKey] = _PhotoAccessCacheEntry(
            checkedAtMs: nowMs,
            isRemoved: true,
          );
          removedCount++;
          continue;
        }

        final refreshedFile = await _resolveReadableFile(asset);
        if (refreshedFile != null && refreshedFile.existsSync()) {
          if (photo.path != refreshedFile.path) {
            photo.path = refreshedFile.path;
            if (photo.id > 0) {
              repairedIds.add(photo.id);
            }
            repairedCount++;
          }
          _photoAccessCache[cacheKey] = _PhotoAccessCacheEntry(
            checkedAtMs: nowMs,
            resolvedPath: refreshedFile.path,
          );
        } else if (photo.id > 0) {
          removedIds.add(photo.id);
          _photoAccessCache[cacheKey] = _PhotoAccessCacheEntry(
            checkedAtMs: nowMs,
            isRemoved: true,
          );
          removedCount++;
        }
      }
    });

    await Future.wait(workers);

    final repairedPhotos = repairedIds.isEmpty
        ? const <PhotoEntity>[]
        : candidates
              .where((photo) => repairedIds.contains(photo.id))
              .toList(growable: false);
    final removedPhotoIds = removedIds.toList(growable: false);

    final staleFaces = removedPhotoIds.isEmpty
        ? const <FaceEntity>[]
        : await _isar
              .collection<FaceEntity>()
              .filter()
              .anyOf(
                removedPhotoIds,
                (query, photoId) => query.photoIdEqualTo(photoId),
              )
              .findAll();

    if (removedPhotoIds.isNotEmpty || repairedPhotos.isNotEmpty) {
      await _isar.writeTxn(() async {
        if (staleFaces.isNotEmpty) {
          await _isar.collection<FaceEntity>().deleteAll(
            staleFaces.map((item) => item.id).toList(growable: false),
          );
        }
        if (removedPhotoIds.isNotEmpty) {
          await _isar.collection<PhotoEntity>().deleteAll(removedPhotoIds);
        }
        if (repairedPhotos.isNotEmpty) {
          await _isar.collection<PhotoEntity>().putAll(repairedPhotos);
        }
      });
    }

    if (removedPhotoIds.isNotEmpty) {
      _photoEmbeddingIndexRepository.deleteByPhotoIds(removedPhotoIds);
      _faceEmbeddingIndexRepository.deleteByPhotoIds(removedPhotoIds);
    }

    final result = candidates
        .where((photo) => !removedIds.contains(photo.id))
        .toList(growable: false);
    stopwatch.stop();
    if (kDebugMode &&
        (candidates.length >= 12 ||
            repairedIds.isNotEmpty ||
            removedIds.isNotEmpty ||
            cacheHits > 0)) {
      debugPrint(
        '🧹 [photo-reconcile] total=${candidates.length} '
        'result=${result.length} cacheHits=$cacheHits '
        'repaired=$repairedCount removed=$removedCount '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
    }
    return result;
  }

  String _photoAccessCacheKey(PhotoEntity photo) {
    if (photo.id > 0) {
      return 'id:${photo.id}';
    }
    return 'asset:${photo.assetId}';
  }

  Future<Map<String, int>> getPhotoStats() async {
    final total = await _isar.collection<PhotoEntity>().count();
    final withGPS = await _isar
        .collection<PhotoEntity>()
        .filter()
        .latitudeIsNotNull()
        .count();
    final aiAnalyzed = await _isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .count();

    return {'total': total, 'withGPS': withGPS, 'aiAnalyzed': aiAnalyzed};
  }
}
