/// 照片访问辅助服务，封装对相册资源的读取和授权检查。

part of 'photo_service.dart';

extension PhotoServiceAccess on PhotoService {
  Future<int> removeUnavailablePhotosByAssetIds(
    Iterable<String> assetIds,
  ) async {
    final normalized = assetIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalized.isEmpty) {
      return 0;
    }

    final query = _photoBox
        .query(PhotoEntity_.assetId.oneOf(normalized))
        .build();
    final ids = query.findIds();
    query.close();
    return removeUnavailablePhotosByIds(ids);
  }

  Future<int> removeUnavailablePhotosByIds(Iterable<int> photoIds) async {
    final ids = photoIds.where((id) => id > 0).toSet().toList(growable: false);
    if (ids.isEmpty) {
      return 0;
    }

    final removedIds = <int>[];
    final repairedPhotos = <PhotoEntity>[];

    for (final id in ids) {
      final photo = _photoBox.get(id);
      if (photo == null) {
        continue;
      }

      if (photo.path.startsWith('content://')) {
        continue;
      }

      final currentFile = photo.path.trim().isEmpty ? null : File(photo.path);
      if (currentFile != null && await currentFile.exists()) {
        continue;
      }

      final asset = await AssetEntity.fromId(photo.assetId);
      if (asset == null) {
        removedIds.add(photo.id);
        continue;
      }

      final refreshedFile = await _resolveReadableFile(asset);
      if (refreshedFile != null && await refreshedFile.exists()) {
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

    if (repairedPhotos.isNotEmpty) {
      _photoBox.putMany(repairedPhotos);
      for (final photo in repairedPhotos) {
        _photoAccessCache.remove('id:${photo.id}');
        _photoAccessCache.remove('asset:${photo.assetId}');
      }
    }

    await _removePhotoRecordsByIds(removedIds);
    return removedIds.length;
  }

  Future<int> _removeUnavailablePhotos() async {
    final localPhotos = _photoBox.getAll();
    if (localPhotos.isEmpty) {
      return 0;
    }

    final removedIds = <int>[];
    final repairedPhotos = <PhotoEntity>[];
    for (final photo in localPhotos) {
      if (photo.path.startsWith('content://')) {
        continue;
      }
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

    if (removedIds.isEmpty && repairedPhotos.isEmpty) {
      return 0;
    }

    if (repairedPhotos.isNotEmpty) {
      _photoBox.putMany(repairedPhotos);
      for (final photo in repairedPhotos) {
        _photoAccessCache.remove('id:${photo.id}');
        _photoAccessCache.remove('asset:${photo.assetId}');
      }
    }
    await _removePhotoRecordsByIds(removedIds);

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
    for (final photo in candidates) {
      if (photo.path.startsWith('content://')) {
        _photoAccessCache[_photoAccessCacheKey(photo)] = _PhotoAccessCacheEntry(
          checkedAtMs: nowMs,
          resolvedPath: photo.path,
        );
        continue;
      }
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

    final repairedPhotos = repairedIds.isEmpty
        ? const <PhotoEntity>[]
        : candidates
              .where((photo) => repairedIds.contains(photo.id))
              .toList(growable: false);
    final removedPhotoIds = removedIds.toList(growable: false);

    if (repairedPhotos.isNotEmpty) {
      _photoBox.putMany(repairedPhotos);
    }
    await _removePhotoRecordsByIds(removedPhotoIds);
    for (final photo in repairedPhotos) {
      _photoAccessCache.remove('id:${photo.id}');
      _photoAccessCache.remove('asset:${photo.assetId}');
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

  Future<void> _removePhotoRecordsByIds(Iterable<int> photoIds) async {
    final ids = photoIds.where((id) => id > 0).toSet().toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final removedPhotos = _photoBox
        .getMany(ids)
        .whereType<PhotoEntity>()
        .toList(growable: false);
    final removedPhotoIdSet = ids.toSet();

    final staleFaceIds = <int>[];
    final faceQ = _faceBox.query(FaceEntity_.photoId.oneOf(ids)).build();
    try {
      staleFaceIds.addAll(faceQ.findIds());
    } finally {
      faceQ.close();
    }

    final eventsToRemove = <int>[];
    final eventsToUpdate = <EventEntity>[];
    final allEvents = _eventBox.getAll();
    for (final event in allEvents) {
      final originalCount = event.photoIds.length;
      if (originalCount == 0) {
        continue;
      }
      event.photoIds = event.photoIds
          .where((photoId) => !removedPhotoIdSet.contains(photoId))
          .toList(growable: false);
      if (event.photoIds.length == originalCount) {
        continue;
      }
      if (event.photoIds.isEmpty) {
        eventsToRemove.add(event.id);
        continue;
      }
      event.photoCount = event.photoIds.length;
      if (event.coverPhotoId == null ||
          removedPhotoIdSet.contains(event.coverPhotoId)) {
        event.coverPhotoId = event.photoIds.first;
      }
      eventsToUpdate.add(event);
    }

    _store.runInTransaction(TxMode.write, () {
      if (staleFaceIds.isNotEmpty) {
        _faceBox.removeMany(staleFaceIds);
      }
      if (eventsToRemove.isNotEmpty) {
        _eventBox.removeMany(eventsToRemove);
      }
      if (eventsToUpdate.isNotEmpty) {
        _eventBox.putMany(eventsToUpdate);
      }
      _photoBox.removeMany(ids);
    });

    _photoEmbeddingIndexRepository.deleteByPhotoIds(ids);
    _faceEmbeddingIndexRepository.deleteByPhotoIds(ids);
    for (final photo in removedPhotos) {
      _photoAccessCache.remove('id:${photo.id}');
      _photoAccessCache.remove('asset:${photo.assetId}');
    }

    debugPrint(
      '🧹 已移除不可访问照片记录: photos=${ids.length} '
      'faces=${staleFaceIds.length} eventsUpdated=${eventsToUpdate.length} '
      'eventsRemoved=${eventsToRemove.length}',
    );
  }

  String _photoAccessCacheKey(PhotoEntity photo) {
    if (photo.id > 0) {
      return 'id:${photo.id}';
    }
    return 'asset:${photo.assetId}';
  }

  Future<Map<String, int>> getPhotoStats() async {
    final total = _photoBox.count();
    final withGPS = _photoBox
        .query(PhotoEntity_.latitude.notNull())
        .build()
        .count();
    final aiAnalyzed = _photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(true))
        .build()
        .count();

    return {'total': total, 'withGPS': withGPS, 'aiAnalyzed': aiAnalyzed};
  }
}
