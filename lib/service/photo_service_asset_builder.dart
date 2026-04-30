part of 'photo_service.dart';

class _PhotoAssetBuilder {
  const _PhotoAssetBuilder(this._service);

  final PhotoService _service;

  Future<_ScanBuildResult> buildPhotoEntities(
    List<AssetEntity> assets, {
    required bool skipExisting,
  }) async {
    final existingAssetIds = <String>{};
    final existingPhotosByAssetId = <String, PhotoEntity>{};
    final buildResults = <_SingleAssetBuildResult>[];
    final refreshedExistingPhotos = <PhotoEntity>[];

    if (skipExisting && assets.isNotEmpty) {
      final assetIdsToCheck = assets
          .map((asset) => asset.id)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (assetIdsToCheck.isNotEmpty) {
        final existingPhotos = await _service._isar
            .collection<PhotoEntity>()
            .filter()
            .anyOf(
              assetIdsToCheck,
              (query, assetId) => query.assetIdEqualTo(assetId),
            )
            .findAll();
        existingAssetIds.addAll(
          existingPhotos
              .map((photo) => photo.assetId)
              .where((id) => id.isNotEmpty),
        );
        for (final photo in existingPhotos) {
          if (photo.assetId.isNotEmpty) {
            existingPhotosByAssetId[photo.assetId] = photo;
          }
        }
      }
    }

    if (assets.isNotEmpty) {
      var cursor = 0;
      final workerCount = math.min(
        PhotoService._assetBuildWorkerCount,
        assets.length,
      );
      final workers = List<Future<void>>.generate(workerCount, (_) async {
        while (true) {
          final index = cursor;
          cursor++;
          if (index >= assets.length) {
            break;
          }

          final asset = assets[index];
          if (skipExisting && existingAssetIds.contains(asset.id)) {
            final existingPhoto = existingPhotosByAssetId[asset.id];
            if (existingPhoto != null) {
              final refreshed = await refreshExistingPhotoFromAsset(
                existingPhoto,
                asset,
              );
              if (refreshed != null) {
                refreshedExistingPhotos.add(refreshed);
              }
            }
            continue;
          }

          final result = await buildSingleAssetPhoto(asset);
          buildResults.add(result);
        }
      });

      await Future.wait(workers);
    }

    final photos = buildResults
        .map((item) => item.photo)
        .whereType<PhotoEntity>()
        .toList(growable: false);
    final insertedNoGps = buildResults.fold<int>(
      0,
      (sum, item) => sum + item.insertedNoGps,
    );
    final skippedInvalidTime = buildResults.fold<int>(
      0,
      (sum, item) => sum + item.skippedInvalidTime,
    );
    final skippedNonCamera = buildResults.fold<int>(
      0,
      (sum, item) => sum + item.skippedNonCamera,
    );
    final skippedScreenshot = buildResults.fold<int>(
      0,
      (sum, item) => sum + item.skippedScreenshot,
    );

    if (refreshedExistingPhotos.isNotEmpty) {
      await _service._isar.writeTxn(() async {
        await _service._isar.collection<PhotoEntity>().putAll(
          refreshedExistingPhotos,
        );
      });
    }

    return _ScanBuildResult(
      photos: photos,
      insertedCount: photos.length,
      insertedNoGps: insertedNoGps,
      skippedInvalidTime: skippedInvalidTime,
      skippedNonCamera: skippedNonCamera,
      skippedScreenshot: skippedScreenshot,
    );
  }

  Future<_SingleAssetBuildResult> buildSingleAssetPhoto(
    AssetEntity asset,
  ) async {
    final file = await resolveReadableFile(asset);
    if (file == null) {
      debugPrint(
        '鈿狅笍 璧勬簮鏃犳硶瑙ｆ瀽涓烘湰鍦版枃浠? assetId=${asset.id} title=${asset.title}',
      );
      return const _SingleAssetBuildResult(skippedNonCamera: 1);
    }

    final width = asset.width;
    final height = asset.height;
    if (width <= 0 || height <= 0) {
      return const _SingleAssetBuildResult(skippedNonCamera: 1);
    }

    final screenshotByRatio = PhotoFilterHelper.isLikelyScreenshotByRatio(
      width,
      height,
    );
    final likelyCameraPhoto = PhotoFilterHelper.isLikelyCameraPhoto(file.path);

    var skippedScreenshot = 0;
    var skippedNonCamera = 0;
    if (screenshotByRatio) {
      skippedScreenshot = 1;
    }
    if (!likelyCameraPhoto) {
      skippedNonCamera = 1;
    }

    final shouldResolveGps = !screenshotByRatio && likelyCameraPhoto;
    final latLong = shouldResolveGps ? await asset.latlngAsync() : null;
    if (PhotoService._verboseAssetLogging) {
      logAssetExtInfo(asset: asset, filePath: file.path, latLong: latLong);
    }

    final timestamp = resolveBestTimestampMs(asset, file);
    if (!PhotoFilterHelper.hasValidTimestamp(timestamp)) {
      return _SingleAssetBuildResult(
        skippedInvalidTime: 1,
        skippedNonCamera: skippedNonCamera,
        skippedScreenshot: skippedScreenshot,
      );
    }

    final hasGps = PhotoFilterHelper.hasValidGps(
      latLong?.latitude,
      latLong?.longitude,
    );
    final newPhoto = PhotoEntity()
      ..assetId = asset.id
      ..timestamp = timestamp
      ..path = file.path
      ..width = width
      ..height = height
      ..latitude = hasGps ? latLong!.latitude : null
      ..longitude = hasGps ? latLong!.longitude : null
      ..isLocationProcessed = false;

    return _SingleAssetBuildResult(
      photo: newPhoto,
      insertedNoGps: hasGps ? 0 : 1,
      skippedNonCamera: skippedNonCamera,
      skippedScreenshot: skippedScreenshot,
    );
  }

  Future<File?> resolveReadableFile(AssetEntity asset) async {
    final directFile = await asset.file;
    if (directFile != null && directFile.path.isNotEmpty) {
      return directFile;
    }

    final originFile = await asset.originFile;
    if (originFile != null && originFile.path.isNotEmpty) {
      debugPrint(
        '鈩癸笍 璧勬簮浣跨敤 originFile 鍏滃簳: assetId=${asset.id} path=${originFile.path}',
      );
      return originFile;
    }

    return null;
  }

  Future<PhotoEntity?> refreshExistingPhotoFromAsset(
    PhotoEntity existingPhoto,
    AssetEntity asset,
  ) async {
    final file = await resolveReadableFile(asset);
    if (file == null) {
      return null;
    }

    final refreshedTimestamp = resolveBestTimestampMs(asset, file);
    final refreshedWidth = asset.width;
    final refreshedHeight = asset.height;

    var changed = false;
    if (PhotoFilterHelper.hasValidTimestamp(refreshedTimestamp) &&
        existingPhoto.timestamp != refreshedTimestamp) {
      existingPhoto.timestamp = refreshedTimestamp;
      changed = true;
    }
    if (file.path.isNotEmpty && existingPhoto.path != file.path) {
      existingPhoto.path = file.path;
      changed = true;
    }
    if (refreshedWidth > 0 && existingPhoto.width != refreshedWidth) {
      existingPhoto.width = refreshedWidth;
      changed = true;
    }
    if (refreshedHeight > 0 && existingPhoto.height != refreshedHeight) {
      existingPhoto.height = refreshedHeight;
      changed = true;
    }

    if (!changed) {
      return null;
    }
    return existingPhoto;
  }

  int resolveBestTimestampMs(AssetEntity asset, File file) {
    final createMs = asset.createDateTime.millisecondsSinceEpoch;
    final modifiedMs = asset.modifiedDateTime.millisecondsSinceEpoch;
    final fileNameMs = PhotoFilterHelper.extractTimestampFromFileName(
      file.path,
    );

    final candidates = <int>[
      if (fileNameMs != null && PhotoFilterHelper.hasValidTimestamp(fileNameMs))
        fileNameMs,
      if (PhotoFilterHelper.hasValidTimestamp(createMs)) createMs,
      if (PhotoFilterHelper.hasValidTimestamp(modifiedMs)) modifiedMs,
    ]..sort();

    if (candidates.isEmpty) {
      return 0;
    }

    final resolved = candidates.first;
    if (PhotoService._verboseAssetLogging) {
      final createIso = asset.createDateTime.toIso8601String();
      final modifiedIso = asset.modifiedDateTime.toIso8601String();
      final resolvedIso = DateTime.fromMillisecondsSinceEpoch(
        resolved,
      ).toIso8601String();
      debugPrint(
        'Resolved photo time assetId=${asset.id} resolved=$resolvedIso create=$createIso modified=$modifiedIso file=${file.path}',
      );
    }
    return resolved;
  }

  void logAssetExtInfo({
    required AssetEntity asset,
    required String? filePath,
    required LatLng? latLong,
  }) {
    final timestamp = asset.createDateTime.millisecondsSinceEpoch;
    final modified = asset.modifiedDateTime;
    final hasValidTime = PhotoFilterHelper.hasValidTimestamp(timestamp);
    final hasValidGps = PhotoFilterHelper.hasValidGps(
      latLong?.latitude,
      latLong?.longitude,
    );

    debugPrint(
      '馃Ь [EXTINFO] id=${asset.id} file=${filePath ?? 'null'} '
      'time=${asset.createDateTime.toIso8601String()} modified=${modified.toIso8601String()} '
      'size=${asset.width}x${asset.height} '
      'lat=${latLong?.latitude.toStringAsFixed(6) ?? 'null'} '
      'lon=${latLong?.longitude.toStringAsFixed(6) ?? 'null'} '
      'validTime=$hasValidTime validGps=$hasValidGps',
    );
  }
}
