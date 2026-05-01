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
      '安全重建完成: 清空旧数据=${plan.totalBefore} 入库=${plan.built.insertedCount} '
      '无GPS=${plan.built.insertedNoGps} 无效时间=${plan.built.skippedInvalidTime} '
      '非相机=${plan.built.skippedNonCamera} 截图=${plan.built.skippedScreenshot}',
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
      '基础数据同步完成: 删除=${plan.removedCount} 入库=${plan.built.insertedCount} '
      '无GPS=${plan.built.insertedNoGps} 无效时间=${plan.built.skippedInvalidTime} '
      '非相机=${plan.built.skippedNonCamera} 截图=${plan.built.skippedScreenshot}',
    );

    final totalAfter = await _isar.collection<PhotoEntity>().count();
    if (totalAfter == 0) {
      throw const PhotoScanException(
        PhotoScanError.noEligiblePhoto,
        '没有找到可用照片。请检查相册权限和本地相册。',
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
