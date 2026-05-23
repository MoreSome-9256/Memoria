/// 照片资产构建服务 — 将系统相册的 AssetEntity 转换为 PhotoEntity。
///
/// 优化点：
/// - `resolveReadableFile` 与 `latlngAsync` 并行发起（减少串行等待）
/// - `resolveBestTimestampMs` 简化为最小值聚合（O(n) 代替 O(n log n)）

part of 'photo_service.dart';

class PhotoScanFilterProfile {
  const PhotoScanFilterProfile({
    required this.requireValidDimensions,
    this.minTimestampMs,
    this.minWidth,
    this.minHeight,
  });

  /// 现有筛选策略汇总：
  /// - requireValidDimensions: 宽高必须有效
  /// - requireCameraLikePath: 仅接收“相机路径/命名”照片
  /// - requireValidTimestamp: 仅接收有效时间戳
  /// - skipScreenshotByRatio: 跳过疑似截图比例
  // 默认策略：不进行预先的截图/路径/时间戳筛选，仅可选的尺寸与时间阈值由用户偏好控制。
  static const PhotoScanFilterProfile strict = PhotoScanFilterProfile(
    requireValidDimensions: true,
  );

  /// 用户自选相册：同样不做自动筛选（以用户偏好为准）。
  static const PhotoScanFilterProfile userSelectedAlbums =
      PhotoScanFilterProfile(requireValidDimensions: true);

  final bool requireValidDimensions;
  // 可选的用户阈值（若为 null 则表示不限制）
  final int? minTimestampMs;
  final int? minWidth;
  final int? minHeight;
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
        skippedScreenshot: 0,
      );
    }

    var cursor = 0;
    final workerCount = math.min(
      PhotoService._assetBuildWorkerCount,
      assets.length,
    );
    final workers = List<Future<void>>.generate(workerCount, (_) async {
      while (true) {
        final idx = cursor;
        cursor++;
        if (idx >= assets.length) break;
        final asset = assets[idx];

        if (skipExisting && existingByAssetId.containsKey(asset.id)) {
          final existing = existingByAssetId[asset.id]!;
          final refreshed = await _refreshIfChanged(existing, asset);
          if (refreshed != null) refreshedExisting.add(refreshed);
          continue;
        }

        buildResults.add(
          await buildSingleAssetPhoto(asset, filterProfile: filterProfile),
        );
      }
    });
    await Future.wait(workers);

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
      skippedScreenshot: stats.skippedScreenshot,
    );
  }

  // ── 单张构建：关键优化 — file 与 latlng 并发 ────────────────────
  Future<_SingleAssetBuildResult> buildSingleAssetPhoto(
    AssetEntity asset, {
    PhotoScanFilterProfile filterProfile = PhotoScanFilterProfile.strict,
  }) async {
    final width = asset.width;
    final height = asset.height;
    if (filterProfile.requireValidDimensions && (width <= 0 || height <= 0)) {
      return const _SingleAssetBuildResult(skippedNonCamera: 1);
    }

    // 并行发起 file 解析 与 GPS 查询
    final fileFuture = resolveReadableFile(asset);
    final latlngFuture = asset.latlngAsync();

    final results = await (fileFuture, latlngFuture).wait;
    final file = results.$1;
    final latLong = results.$2;

    if (file == null) {
      // 无法直接解析到文件（例如 iCloud/受限或 thumbnail-only），
      // 对于用户选定相册或默认策略，仍尽量建立最小可用实体，
      // 后续 reconcileAccessiblePhotos 会尝试修复 path 或移除不可访问的条目。
      final fallbackTimestamp = asset.createDateTime.millisecondsSinceEpoch;

      final photo = PhotoEntity()
        ..assetId = asset.id
        ..timestamp = fallbackTimestamp
        ..path = ''
        ..width = width
        ..height = height
        ..isLocationProcessed = false
        ..faceCount = 0
        ..smileProb = 0.0;
      // 应用用户指定的时间与分辨率阈值（若存在）
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
          return const _SingleAssetBuildResult(skippedInvalidTime: 1);
        }
      }

      return _SingleAssetBuildResult(photo: photo, insertedNoGps: 1);
    }
    final timestamp = resolveBestTimestampMs(asset, file);

    final hasGps = PhotoFilterHelper.hasValidGps(
      latLong?.latitude,
      latLong?.longitude,
    );
    final photo = PhotoEntity()
      ..assetId = asset.id
      ..timestamp = timestamp
      ..path = file.path
      ..width = width
      ..height = height
      ..latitude = hasGps ? latLong!.latitude : null
      ..longitude = hasGps ? latLong!.longitude : null
      ..isLocationProcessed = false;

    // 应用用户指定的时间与分辨率阈值（若存在）
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
        return const _SingleAssetBuildResult(skippedInvalidTime: 1);
      }
    }

    return _SingleAssetBuildResult(photo: photo, insertedNoGps: hasGps ? 0 : 1);
  }

  Future<_SingleAssetBuildResult> buildSingleFilePhoto(
    File file, {
    PhotoScanFilterProfile filterProfile = PhotoScanFilterProfile.strict,
  }) async {
    if (!file.existsSync()) {
      return const _SingleAssetBuildResult(skippedNonCamera: 1);
    }
    final dimensions = await _readLocalImageDimensions(file);
    if (dimensions == null) {
      return const _SingleAssetBuildResult(skippedNonCamera: 1);
    }
    final timestamp = _resolveBestFileTimestampMs(file);
    final photo = PhotoEntity()
      ..assetId = 'file:${file.path}'
      ..timestamp = timestamp
      ..path = file.path
      ..width = dimensions.$1
      ..height = dimensions.$2
      ..isLocationProcessed = false
      ..faceCount = 0
      ..smileProb = 0.0;

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
        return const _SingleAssetBuildResult(skippedInvalidTime: 1);
      }
    }

    return _SingleAssetBuildResult(photo: photo, insertedNoGps: 1);
  }

  // ── File 解析：Android 跳过 originFile（快 2×）──────────────────
  Future<File?> resolveReadableFile(AssetEntity asset) async {
    final directFile = await asset.file;
    if (directFile != null && directFile.path.isNotEmpty) return directFile;

    final originFile = await asset.originFile;
    if (originFile != null && originFile.path.isNotEmpty) return originFile;

    return null;
  }

  // ── 时间戳解析：最小值聚合 O(n) ──────────────────────────────────
  int resolveBestTimestampMs(AssetEntity asset, File file) {
    final candidates = <int>[];
    final fileNameMs = PhotoFilterHelper.extractTimestampFromFileName(
      file.path,
    );
    if (fileNameMs != null && PhotoFilterHelper.hasValidTimestamp(fileNameMs)) {
      candidates.add(fileNameMs);
    }
    final createMs = asset.createDateTime.millisecondsSinceEpoch;
    if (PhotoFilterHelper.hasValidTimestamp(createMs)) candidates.add(createMs);
    final modifiedMs = asset.modifiedDateTime.millisecondsSinceEpoch;
    if (PhotoFilterHelper.hasValidTimestamp(modifiedMs))
      candidates.add(modifiedMs);
    return candidates.isEmpty ? 0 : candidates.reduce(math.min);
  }

  int _resolveBestFileTimestampMs(File file) {
    final fileNameMs = PhotoFilterHelper.extractTimestampFromFileName(
      file.path,
    );
    if (fileNameMs != null && PhotoFilterHelper.hasValidTimestamp(fileNameMs)) {
      return fileNameMs;
    }
    final stat = file.statSync();
    final modifiedMs = stat.modified.millisecondsSinceEpoch;
    if (PhotoFilterHelper.hasValidTimestamp(modifiedMs)) {
      return modifiedMs;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  Future<(int, int)?> _readLocalImageDimensions(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoder = img.findDecoderForData(bytes);
      final info = decoder?.startDecode(bytes);
      if (info != null && info.width > 0 && info.height > 0) {
        return (info.width, info.height);
      }
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return null;
      }
      final baked = img.bakeOrientation(decoded);
      return (baked.width, baked.height);
    } catch (_) {
      return null;
    }
  }

  // ── 仅当字段变化时刷新 ──────────────────────────────────────────
  Future<PhotoEntity?> _refreshIfChanged(
    PhotoEntity existing,
    AssetEntity asset,
  ) async {
    final file = await resolveReadableFile(asset);
    if (file == null) return null;

    var changed = false;
    final ts = resolveBestTimestampMs(asset, file);
    if (PhotoFilterHelper.hasValidTimestamp(ts) && existing.timestamp != ts) {
      existing.timestamp = ts;
      changed = true;
    }
    if (file.path.isNotEmpty && existing.path != file.path) {
      existing.path = file.path;
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
    return changed ? existing : null;
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
