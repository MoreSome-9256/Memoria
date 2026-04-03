part of 'photo_service.dart';

class _PhotoAssetBuilder {
  const _PhotoAssetBuilder(this._service);

  final PhotoService _service;

  Future<_ScanBuildResult> buildPhotoEntities(
    List<AssetEntity> assets, {
    required bool skipExisting,
  }) async {
    final existingAssetIds = <String>{};
    final buildResults = <_SingleAssetBuildResult>[];

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

    final timestamp = asset.createDateTime.millisecondsSinceEpoch;
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
