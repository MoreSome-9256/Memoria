/// 照片资产构建服务 — 将系统相册的 AssetEntity 转换为 PhotoEntity。
///
/// 优化点：
/// - 只使用 AssetEntity 元数据和缩略图 API，不读取源文件路径。

part of 'photo_service.dart';

class PhotoScanFilterProfile {
  const PhotoScanFilterProfile({
    required this.requireValidDimensions,
    this.minTimestampMs,
    this.minWidth,
    this.minHeight,
    this.minPixels,
  });

  static const PhotoScanFilterProfile strict = PhotoScanFilterProfile(
    requireValidDimensions: true,
  );

  static const PhotoScanFilterProfile userSelectedAlbums =
      PhotoScanFilterProfile(requireValidDimensions: true);

  final bool requireValidDimensions;
  final int? minTimestampMs;
  final int? minWidth;
  final int? minHeight;
  final int? minPixels;
}

class _PhotoAssetBuilder {
  const _PhotoAssetBuilder(this._service);

  final PhotoService _service;

  // ── 批量构建 ─────────────────────────────────────────────────────
  Future<_ScanBuildResult> buildPhotoEntities(
    List<AssetEntity> assets, {
    required bool skipExisting,
    PhotoScanFilterProfile filterProfile = PhotoScanFilterProfile.strict,
  }) async {
    final existingByAssetId = <String, PhotoEntity>{};
    final refreshedExisting = <PhotoEntity>[];
    final buildResults = <_SingleAssetBuildResult>[];

    if (skipExisting && assets.isNotEmpty) {
      final ids = assets
          .map((a) => a.id)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (ids.isNotEmpty) {
        final q = _service._photoBox
            .query(PhotoEntity_.assetId.oneOf(ids))
            .build();
        for (final p in q.find()) {
          if (p.assetId.isNotEmpty) existingByAssetId[p.assetId] = p;
        }
        q.close();
      }
    }

    if (assets.isEmpty) {
      return _ScanBuildResult(
        photos: const [],
        insertedCount: 0,
        insertedNoGps: 0,
        skippedInvalidTime: 0,
        skippedNonCamera: 0,
      );
    }

    for (final asset in assets) {
      if (skipExisting && existingByAssetId.containsKey(asset.id)) {
        continue;
      }

      buildResults.add(
        await buildSingleAssetPhoto(asset, filterProfile: filterProfile),
      );
    }

    if (refreshedExisting.isNotEmpty) {
      _service._store.runInTransaction(
        TxMode.write,
        () => _service._photoBox.putMany(refreshedExisting),
      );
    }

    final photos = buildResults
        .map((r) => r.photo)
        .whereType<PhotoEntity>()
        .toList(growable: false);
    var stats = _ScanStats();
    for (final r in buildResults) {
      stats = stats.merge(r);
    }

    return _ScanBuildResult(
      photos: photos,
      insertedCount: photos.length,
      insertedNoGps: stats.insertedNoGps,
      skippedInvalidTime: stats.skippedInvalidTime,
      skippedNonCamera: stats.skippedNonCamera,
    );
  }

  // ── 单张构建：GPS 直接从 AssetEntity 读取（已在批量查询中加载），
  //     file 解析延迟到后台（减少 N 次 ContentResolver 查询）
  Future<_SingleAssetBuildResult> buildSingleAssetPhoto(
    AssetEntity asset, {
    PhotoScanFilterProfile filterProfile = PhotoScanFilterProfile.strict,
  }) async {
    final width = asset.width;
    final height = asset.height;
    if (filterProfile.requireValidDimensions && (width <= 0 || height <= 0)) {
      return const _SingleAssetBuildResult(skippedNonCamera: 1);
    }
    if (filterProfile.minPixels != null &&
        width > 0 &&
        height > 0 &&
        width * height < filterProfile.minPixels!) {
      return const _SingleAssetBuildResult(skippedSmallResolution: 1);
    }
    final latLong = await _resolveAssetLatLng(asset);
    final mimeType = asset.mimeType;
    final isLivePhoto = asset.isLivePhoto;
    final timestamp = _resolveBestAssetTimestampMs(asset);
    final mediaKind = _resolveMediaKind(
      asset: asset,
      path: '',
      mimeType: mimeType,
      isLivePhoto: isLivePhoto,
    );
    final thumbnailBytes = await MediaThumbnailCacheService.instance
        .generateCompressedBytes(asset);

    final hasGps = PhotoFilterHelper.hasValidGps(
      latLong?.latitude,
      latLong?.longitude,
    );
    final photo = PhotoEntity()
      ..assetId = asset.id
      ..timestamp = timestamp
      ..path = ''
      ..width = width
      ..height = height
      ..mediaKind = MediaTypeHelper.toStorageValue(mediaKind)
      ..mimeType = mimeType
      ..isLivePhoto = isLivePhoto
      ..thumbnailBytes = thumbnailBytes
      ..latitude = hasGps ? latLong!.latitude : null
      ..longitude = hasGps ? latLong!.longitude : null
      ..isLocationProcessed = false;
    PhotoSearchIndexService.updateTimeFields(photo);
    PhotoSearchIndexService.updateCoordinateFields(photo);

    if (filterProfile.minTimestampMs != null &&
        photo.timestamp < filterProfile.minTimestampMs!) {
      return const _SingleAssetBuildResult(skippedInvalidTime: 1);
    }
    if (filterProfile.minWidth != null && filterProfile.minHeight != null) {
      final selMax = math.max(
        filterProfile.minWidth!,
        filterProfile.minHeight!,
      );
      final selMin = math.min(
        filterProfile.minWidth!,
        filterProfile.minHeight!,
      );
      final pMax = math.max(photo.width, photo.height);
      final pMin = math.min(photo.width, photo.height);
      if (pMax < selMax || pMin < selMin) {
        return const _SingleAssetBuildResult(skippedSmallResolution: 1);
      }
    }

    return _SingleAssetBuildResult(photo: photo, insertedNoGps: hasGps ? 0 : 1);
  }

  int _resolveBestAssetTimestampMs(AssetEntity asset) {
    final candidates = <int>[];
    final createMs = asset.createDateTime.millisecondsSinceEpoch;
    if (PhotoFilterHelper.hasValidTimestamp(createMs)) candidates.add(createMs);
    final modifiedMs = asset.modifiedDateTime.millisecondsSinceEpoch;
    if (PhotoFilterHelper.hasValidTimestamp(modifiedMs)) {
      candidates.add(modifiedMs);
    }
    return candidates.isEmpty ? 0 : candidates.reduce(math.min);
  }

  // ── 仅当字段变化时刷新 ──────────────────────────────────────────
  Future<PhotoEntity?> _refreshIfChanged(
    PhotoEntity existing,
    AssetEntity asset, {
    bool refreshThumbnail = true,
  }) async {
    var changed = false;
    final ts = _resolveBestAssetTimestampMs(asset);
    if (PhotoFilterHelper.hasValidTimestamp(ts) && existing.timestamp != ts) {
      existing.timestamp = ts;
      changed = true;
    }
    if (PhotoSearchIndexService.updateTimeFields(existing)) {
      changed = true;
    }
    if (existing.path.isNotEmpty) {
      existing.path = '';
      changed = true;
    }
    if (asset.width > 0 && existing.width != asset.width) {
      existing.width = asset.width;
      changed = true;
    }
    if (asset.height > 0 && existing.height != asset.height) {
      existing.height = asset.height;
      changed = true;
    }
    final mimeType = asset.mimeType;
    final isLivePhoto = asset.isLivePhoto;
    final mediaKind = MediaTypeHelper.toStorageValue(
      _resolveMediaKind(
        asset: asset,
        path: '',
        mimeType: mimeType,
        isLivePhoto: isLivePhoto,
      ),
    );
    if (existing.mediaKind != mediaKind) {
      existing.mediaKind = mediaKind;
      changed = true;
    }
    if (existing.mimeType != mimeType) {
      existing.mimeType = mimeType;
      changed = true;
    }
    if (existing.isLivePhoto != isLivePhoto) {
      existing.isLivePhoto = isLivePhoto;
      changed = true;
    }
    final latLong = await _resolveAssetLatLng(asset);
    final hasGps = PhotoFilterHelper.hasValidGps(
      latLong?.latitude,
      latLong?.longitude,
    );
    if (hasGps &&
        (existing.latitude != latLong!.latitude ||
            existing.longitude != latLong.longitude)) {
      existing
        ..latitude = latLong.latitude
        ..longitude = latLong.longitude
        ..isLocationProcessed = false
        ..geoIndexVersion = 0;
      PhotoSearchIndexService.updateCoordinateFields(existing);
      changed = true;
    }
    if (refreshThumbnail) {
      final thumbnailBytes = await MediaThumbnailCacheService.instance
          .generateCompressedBytes(asset);
      if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
        existing.thumbnailBytes = thumbnailBytes;
        changed = true;
      }
    }
    return changed ? existing : null;
  }

  Future<LatLng?> _resolveAssetLatLng(AssetEntity asset) async {
    final cached = asset.latLng;
    if (PhotoFilterHelper.hasValidGps(cached?.latitude, cached?.longitude)) {
      return cached;
    }
    try {
      final loaded = await asset.latlngAsync();
      return PhotoFilterHelper.hasValidGps(loaded?.latitude, loaded?.longitude)
          ? loaded
          : null;
    } catch (error) {
      debugPrint('[asset-builder] GPS 读取失败 assetId=${asset.id}: $error');
      return null;
    }
  }

  MemoriaMediaKind _resolveMediaKind({
    required AssetEntity asset,
    required String path,
    required String? mimeType,
    required bool isLivePhoto,
  }) {
    if (asset.type == AssetType.video ||
        mimeType?.toLowerCase().startsWith('video/') == true ||
        MediaTypeHelper.isVideoPath(path)) {
      return MemoriaMediaKind.video;
    }
    final normalizedMime = mimeType?.toLowerCase() ?? '';
    if (isLivePhoto ||
        normalizedMime == 'image/gif' ||
        normalizedMime == 'image/webp' ||
        MediaTypeHelper.isDynamicImagePath(path)) {
      return MemoriaMediaKind.dynamicImage;
    }
    return MemoriaMediaKind.image;
  }

  void logAssetExtInfo({
    required AssetEntity asset,
    required String? filePath,
    required LatLng? latLong,
  }) {
    debugPrint(
      '[EXTINFO] id=${asset.id} file=${filePath ?? "null"} '
      'time=${asset.createDateTime.toIso8601String()} '
      'size=${asset.width}x${asset.height} '
      'lat=${latLong?.latitude.toStringAsFixed(6) ?? "null"} '
      'lon=${latLong?.longitude.toStringAsFixed(6) ?? "null"}',
    );
  }
}
