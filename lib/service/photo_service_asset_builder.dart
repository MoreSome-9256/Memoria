/// 照片资产构建服务 — 将系统相册的 AssetEntity 转换为 PhotoEntity。
///
/// 优化点：
/// - `resolveReadableFile` 与 `latlngAsync` 并行发起（减少串行等待）
/// - `resolveBestTimestampMs` 简化为最小值聚合（O(n) 代替 O(n log n)）

part of 'photo_service.dart';

class _PhotoAssetBuilder {
  const _PhotoAssetBuilder(this._service);

  final PhotoService _service;

  // ── 批量构建 ─────────────────────────────────────────────────────
  Future<_ScanBuildResult> buildPhotoEntities(
    List<AssetEntity> assets, {
    required bool skipExisting,
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
    final workerCount = math.min(PhotoService._assetBuildWorkerCount, assets.length);
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

        buildResults.add(await buildSingleAssetPhoto(asset));
      }
    });
    await Future.wait(workers);

    if (refreshedExisting.isNotEmpty) {
      _service._store.runInTransaction(
        TxMode.write,
        () => _service._photoBox.putMany(refreshedExisting),
      );
    }

    final photos = buildResults.map((r) => r.photo).whereType<PhotoEntity>().toList(growable: false);
    var stats = _ScanStats();
    for (final r in buildResults) { stats = stats.merge(r); }

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
  Future<_SingleAssetBuildResult> buildSingleAssetPhoto(AssetEntity asset) async {
    final width = asset.width;
    final height = asset.height;
    if (width <= 0 || height <= 0) {
      return const _SingleAssetBuildResult(skippedNonCamera: 1);
    }

    final isScreenshotByRatio = PhotoFilterHelper.isLikelyScreenshotByRatio(width, height);

    // 并行发起 file 解析 与 (条件性的) GPS 查询
    final fileFuture = resolveReadableFile(asset);
    final latlngFuture = (!isScreenshotByRatio)
        ? asset.latlngAsync()
        : Future<LatLng?>.value(null);

    final results = await (fileFuture, latlngFuture).wait;
    final file = results.$1;
    final latLong = results.$2;

    if (file == null) {
      return const _SingleAssetBuildResult(skippedNonCamera: 1);
    }

    final isCamera = PhotoFilterHelper.isLikelyCameraPhoto(file.path);
    if (!isCamera) {
      return _SingleAssetBuildResult(skippedNonCamera: 1, skippedScreenshot: isScreenshotByRatio ? 1 : 0);
    }

    final timestamp = resolveBestTimestampMs(asset, file);
    if (!PhotoFilterHelper.hasValidTimestamp(timestamp)) {
      return _SingleAssetBuildResult(
        skippedInvalidTime: 1,
        skippedNonCamera: 0,
        skippedScreenshot: isScreenshotByRatio ? 1 : 0,
      );
    }

    final hasGps = PhotoFilterHelper.hasValidGps(latLong?.latitude, latLong?.longitude);
    final photo = PhotoEntity()
      ..assetId = asset.id
      ..timestamp = timestamp
      ..path = file.path
      ..width = width
      ..height = height
      ..latitude = hasGps ? latLong!.latitude : null
      ..longitude = hasGps ? latLong!.longitude : null
      ..isLocationProcessed = false;

    return _SingleAssetBuildResult(
      photo: photo,
      insertedNoGps: hasGps ? 0 : 1,
      skippedScreenshot: isScreenshotByRatio ? 1 : 0,
    );
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
    final fileNameMs = PhotoFilterHelper.extractTimestampFromFileName(file.path);
    if (fileNameMs != null && PhotoFilterHelper.hasValidTimestamp(fileNameMs)) {
      candidates.add(fileNameMs);
    }
    final createMs = asset.createDateTime.millisecondsSinceEpoch;
    if (PhotoFilterHelper.hasValidTimestamp(createMs)) candidates.add(createMs);
    final modifiedMs = asset.modifiedDateTime.millisecondsSinceEpoch;
    if (PhotoFilterHelper.hasValidTimestamp(modifiedMs)) candidates.add(modifiedMs);
    return candidates.isEmpty ? 0 : candidates.reduce(math.min);
  }

  // ── 仅当字段变化时刷新 ──────────────────────────────────────────
  Future<PhotoEntity?> _refreshIfChanged(PhotoEntity existing, AssetEntity asset) async {
    final file = await resolveReadableFile(asset);
    if (file == null) return null;

    var changed = false;
    final ts = resolveBestTimestampMs(asset, file);
    if (PhotoFilterHelper.hasValidTimestamp(ts) && existing.timestamp != ts) {
      existing.timestamp = ts; changed = true;
    }
    if (file.path.isNotEmpty && existing.path != file.path) {
      existing.path = file.path; changed = true;
    }
    if (asset.width > 0 && existing.width != asset.width) {
      existing.width = asset.width; changed = true;
    }
    if (asset.height > 0 && existing.height != asset.height) {
      existing.height = asset.height; changed = true;
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
