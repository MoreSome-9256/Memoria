part of 'photo_service.dart';

extension PhotoServiceScan on PhotoService {
  Future<PhotoScanSummary> rebuildAllCachedData({int? maxAssets}) async {
    final plan = await _PhotoScanCoordinator(
      this,
    ).prepareRebuild(maxAssets: maxAssets);

    await _isar.writeTxn(() async {
      await _isar.collection<DigitalAlbumBookEntity>().clear();
      await _isar.collection<CreateRecommendationEntity>().clear();
      await _isar.collection<StoryEntity>().clear();
      await _isar.collection<EventEntity>().clear();
      await _isar.collection<FaceEntity>().clear();
      await _isar.collection<PhotoEntity>().clear();
      await _isar.collection<PhotoEntity>().putAll(plan.built.photos);
    });
    _photoAccessCache.clear();
    _photoEmbeddingIndexRepository.deleteAll();
    _faceEmbeddingIndexRepository.deleteAll();

    debugPrint(
      "鉁?瀹夊叏閲嶅缓瀹屾垚: 娓呯┖鏃ф暟鎹?${plan.totalBefore} 鍏ュ簱=${plan.built.insertedCount} "
      "鏃燝PS=${plan.built.insertedNoGps} 璺宠繃[鏃犳椂闂?${plan.built.skippedInvalidTime} "
      "闈炵浉鏈?${plan.built.skippedNonCamera} 鎴浘=${plan.built.skippedScreenshot}]",
    );

    return PhotoScanSummary(
      totalBefore: plan.totalBefore,
      totalAfter: plan.built.insertedCount,
      removedCount: plan.totalBefore,
      insertedCount: plan.built.insertedCount,
      skippedInvalidTime: plan.built.skippedInvalidTime,
      insertedNoGps: plan.built.insertedNoGps,
      skippedNonCamera: plan.built.skippedNonCamera,
      skippedScreenshot: plan.built.skippedScreenshot,
    );
  }

  Future<PhotoScanSummary> scanAndSyncPhotos({int? maxAssets}) {
    return scanAndSyncPhotosWithOffset(maxAssets: maxAssets);
  }

  Future<PhotoScanSummary> scanAndSyncPhotosWithOffset({
    int? maxAssets,
    int offsetFromNewest = 0,
  }) async {
    final plan = await _PhotoScanCoordinator(this).prepareIncremental(
      maxAssets: maxAssets,
      offsetFromNewest: offsetFromNewest,
    );

    var insertedPhotoIds = const <int>[];
    if (plan.built.photos.isNotEmpty) {
      late final List<int> storedIds;
      await _isar.writeTxn(() async {
        storedIds = await _isar.collection<PhotoEntity>().putAll(
          plan.built.photos,
        );
      });
      insertedPhotoIds = storedIds
          .where((id) => id > 0)
          .toList(growable: false);
    }

    debugPrint(
      "鉁?鍩虹鏁版嵁鍚屾瀹屾垚: 鍒犻櫎=${plan.removedCount} 鍏ュ簱=${plan.built.insertedCount} "
      "鍏朵腑鏃燝PS鍏ュ簱=${plan.built.insertedNoGps} 璺宠繃[鏃犳椂闂?${plan.built.skippedInvalidTime} "
      "闈炵浉鏈?${plan.built.skippedNonCamera} 鎴浘=${plan.built.skippedScreenshot}]",
    );

    final totalAfter = await _isar.collection<PhotoEntity>().count();
    if (totalAfter == 0) {
      throw const PhotoScanException(
        PhotoScanError.noEligiblePhoto,
        '鏈壘鍒板彲鐢ㄧ収鐗囷細璇风‘璁ょ浉鍐屼腑瀛樺湪鍖呭惈鏈夋晥鏃堕棿鐨勫浘鐗囪祫婧愩€?',
      );
    }

    return PhotoScanSummary(
      totalBefore: plan.totalBefore,
      totalAfter: totalAfter,
      removedCount: plan.removedCount,
      insertedCount: plan.built.insertedCount,
      insertedPhotoIds: insertedPhotoIds,
      scanStartOffset: plan.prepared.startOffset,
      scannedCount: plan.prepared.fetchCount,
      skippedInvalidTime: plan.built.skippedInvalidTime,
      insertedNoGps: plan.built.insertedNoGps,
      skippedNonCamera: plan.built.skippedNonCamera,
      skippedScreenshot: plan.built.skippedScreenshot,
    );
  }
}
