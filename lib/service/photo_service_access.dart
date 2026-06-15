/// 照片访问辅助服务，封装对相册资源的读取和授权检查。

part of 'photo_service.dart';

class PhotoOriginalAccessException implements Exception {
  const PhotoOriginalAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension PhotoServiceAccess on PhotoService {
  Future<AssetEntity> openOriginalMediaAsset(
    PhotoEntity photo, {
    String purpose = 'media access',
  }) async {
    final assetId = photo.assetId.trim();
    if (assetId.isEmpty) {
      await _removePhotoRecordsByIds(<int>[photo.id]);
      throw PhotoOriginalAccessException(
        '照片缺少 assetId，已移除本地记录 photoId=${photo.id} purpose=$purpose',
      );
    }

    final asset = await AssetEntity.fromId(assetId);
    if (asset == null) {
      final canDelete =
          await MediaPermissionService.canDeleteUnavailableMedia();
      if (canDelete) {
        await _removePhotoRecordsByIds(<int>[photo.id]);
      }
      throw PhotoOriginalAccessException(
        canDelete
            ? '系统相册资源不可访问，已移除本地记录 photoId=${photo.id} assetId=$assetId purpose=$purpose'
            : '当前授权不包含该资源，或系统暂时无法确认资源状态。请检查照片访问范围。',
      );
    }

    final thumbnail = await asset.thumbnailDataWithSize(
      const ThumbnailSize.square(32),
      quality: 30,
    );
    if (thumbnail == null || thumbnail.isEmpty) {
      throw PhotoOriginalAccessException(
        '无法通过系统相册 API 读取媒体 photoId=${photo.id} assetId=$assetId purpose=$purpose',
      );
    }

    var changed = false;
    final timestamp = _bestAssetTimestampMs(asset);
    if (PhotoFilterHelper.hasValidTimestamp(timestamp) &&
        photo.timestamp != timestamp) {
      photo.timestamp = timestamp;
      changed = true;
    }
    if (PhotoSearchIndexService.updateTimeFields(photo)) {
      changed = true;
    }
    if (asset.width > 0 && photo.width != asset.width) {
      photo.width = asset.width;
      changed = true;
    }
    if (asset.height > 0 && photo.height != asset.height) {
      photo.height = asset.height;
      changed = true;
    }
    final mediaKind = MediaTypeHelper.toStorageValue(
      asset.type == AssetType.video
          ? MemoriaMediaKind.video
          : asset.isLivePhoto
          ? MemoriaMediaKind.dynamicImage
          : MemoriaMediaKind.image,
    );
    if (photo.mediaKind != mediaKind) {
      photo.mediaKind = mediaKind;
      changed = true;
    }
    final mimeType = asset.mimeType;
    if (photo.mimeType != mimeType) {
      photo.mimeType = mimeType;
      changed = true;
    }
    if (photo.isLivePhoto != asset.isLivePhoto) {
      photo.isLivePhoto = asset.isLivePhoto;
      changed = true;
    }
    if (changed && photo.id > 0) {
      _photoBox.put(photo);
      _photoAccessCache.remove('id:${photo.id}');
      _photoAccessCache.remove('asset:${photo.assetId}');
    }
    return asset;
  }

  Future<Uint8List> readOriginalMediaBytes(
    PhotoEntity photo, {
    String purpose = 'media bytes',
  }) async {
    final asset = await openOriginalMediaAsset(photo, purpose: purpose);
    final bytes = await asset.thumbnailDataWithOption(
      const ThumbnailOption(
        size: ThumbnailSize.square(1024),
        format: ThumbnailFormat.jpeg,
        quality: 92,
      ),
    );
    if (bytes == null || bytes.isEmpty) {
      throw PhotoOriginalAccessException(
        '读取系统相册媒体失败 photoId=${photo.id} assetId=${photo.assetId} purpose=$purpose',
      );
    }
    return bytes;
  }

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
    if (!await MediaPermissionService.canDeleteUnavailableMedia()) {
      return 0;
    }

    final removedIds = <int>[];
    final repairedPhotos = <PhotoEntity>[];

    for (final id in ids) {
      final photo = _photoBox.get(id);
      if (photo == null) {
        continue;
      }

      final asset = await AssetEntity.fromId(photo.assetId);
      if (asset == null) {
        removedIds.add(photo.id);
        continue;
      }
      if (_refreshPhotoFromAssetMetadata(photo, asset)) {
        repairedPhotos.add(photo);
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
    if (!await MediaPermissionService.canDeleteUnavailableMedia()) {
      return 0;
    }
    final localPhotos = _photoBox.getAll();
    if (localPhotos.isEmpty) {
      return 0;
    }

    final removedIds = <int>[];
    final repairedPhotos = <PhotoEntity>[];
    for (final photo in localPhotos) {
      final asset = await AssetEntity.fromId(photo.assetId);
      if (asset == null) {
        removedIds.add(photo.id);
        continue;
      }
      if (_refreshPhotoFromAssetMetadata(photo, asset)) {
        repairedPhotos.add(photo);
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
    final canDeleteUnavailable =
        await MediaPermissionService.canDeleteUnavailableMedia();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final removedIds = <int>{};
    final repairedIds = <int>{};
    var cacheHits = 0;
    var removedCount = 0;
    var repairedCount = 0;
    for (final photo in candidates) {
      final cacheKey = _photoAccessCacheKey(photo);
      final cacheEntry = _photoAccessCache[cacheKey];
      if (cacheEntry != null &&
          nowMs - cacheEntry.checkedAtMs <=
              PhotoService._photoAccessCacheTtl.inMilliseconds) {
        cacheHits++;
        if (cacheEntry.isRemoved) {
          if (canDeleteUnavailable && photo.id > 0) {
            removedIds.add(photo.id);
          }
          removedCount++;
          continue;
        }
        continue;
      }

      final asset = await AssetEntity.fromId(photo.assetId);
      if (asset == null) {
        if (canDeleteUnavailable && photo.id > 0) {
          removedIds.add(photo.id);
        }
        _photoAccessCache[cacheKey] = _PhotoAccessCacheEntry(
          checkedAtMs: nowMs,
          isRemoved: true,
        );
        removedCount++;
        continue;
      }

      var needsUpdate = false;

      if (_refreshPhotoFromAssetMetadata(photo, asset)) {
        needsUpdate = true;
      }

      if (photo.thumbnailBytes == null || photo.thumbnailBytes!.isEmpty) {
        final thumbnailBytes = await MediaThumbnailCacheService.instance
            .generateCompressedBytes(asset);
        if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
          photo.thumbnailBytes = thumbnailBytes;
          needsUpdate = true;
        }
      }

      if (needsUpdate) {
        if (photo.id > 0) {
          repairedIds.add(photo.id);
        }
        repairedCount++;
      }

      _photoAccessCache[cacheKey] = _PhotoAccessCacheEntry(checkedAtMs: nowMs);
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
    if (canDeleteUnavailable) {
      await _removePhotoRecordsByIds(removedPhotoIds);
    }
    for (final photo in repairedPhotos) {
      _photoAccessCache.remove('id:${photo.id}');
      _photoAccessCache.remove('asset:${photo.assetId}');
    }

    final inaccessibleIds = <int>{
      for (final photo in candidates)
        if (_photoAccessCache[_photoAccessCacheKey(photo)]?.isRemoved ?? false)
          photo.id,
    };
    final result = candidates
        .where((photo) => !inaccessibleIds.contains(photo.id))
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

  int _bestAssetTimestampMs(AssetEntity asset) {
    final candidates = <int>[];
    final createMs = asset.createDateTime.millisecondsSinceEpoch;
    if (PhotoFilterHelper.hasValidTimestamp(createMs)) candidates.add(createMs);
    final modifiedMs = asset.modifiedDateTime.millisecondsSinceEpoch;
    if (PhotoFilterHelper.hasValidTimestamp(modifiedMs)) {
      candidates.add(modifiedMs);
    }
    return candidates.isEmpty ? 0 : candidates.reduce(math.min);
  }

  bool _refreshPhotoFromAssetMetadata(PhotoEntity photo, AssetEntity asset) {
    var changed = false;
    final timestamp = _bestAssetTimestampMs(asset);
    if (PhotoFilterHelper.hasValidTimestamp(timestamp) &&
        photo.timestamp != timestamp) {
      photo.timestamp = timestamp;
      changed = true;
    }
    if (PhotoSearchIndexService.updateTimeFields(photo)) {
      changed = true;
    }
    if (asset.width > 0 && photo.width != asset.width) {
      photo.width = asset.width;
      changed = true;
    }
    if (asset.height > 0 && photo.height != asset.height) {
      photo.height = asset.height;
      changed = true;
    }
    final mediaKind = MediaTypeHelper.toStorageValue(
      asset.type == AssetType.video
          ? MemoriaMediaKind.video
          : asset.isLivePhoto
          ? MemoriaMediaKind.dynamicImage
          : MemoriaMediaKind.image,
    );
    if (photo.mediaKind != mediaKind) {
      photo.mediaKind = mediaKind;
      changed = true;
    }
    final mimeType = asset.mimeType;
    if (photo.mimeType != mimeType) {
      photo.mimeType = mimeType;
      changed = true;
    }
    if (photo.isLivePhoto != asset.isLivePhoto) {
      photo.isLivePhoto = asset.isLivePhoto;
      changed = true;
    }
    return changed;
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
