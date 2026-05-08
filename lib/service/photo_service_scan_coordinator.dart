/// 照片扫描协调器，调度扫描、增量更新和缓存同步任务。

part of 'photo_service.dart';

class _PhotoScanCoordinator {
  const _PhotoScanCoordinator(this._service);

  final PhotoService _service;

  Future<_PhotoRebuildPlan> prepareRebuild({int? maxAssets}) async {
    final totalBefore = await _service._isar.collection<PhotoEntity>().count();
    final prepared = await _prepareScan(maxAssets: maxAssets);

    debugPrint(
      maxAssets == null
          ? 'Starting safe album cache rebuild (all photos)...'
          : 'Starting safe album cache rebuild (${prepared.fetchCount} / ${prepared.totalCount})...',
    );

    final built = await _service._buildPhotoEntities(
      prepared.assets,
      skipExisting: false,
    );
    if (built.photos.isEmpty) {
      throw const PhotoScanException(
        PhotoScanError.noEligiblePhoto,
        'No eligible photos were found. Please check photo permission and local albums.',
      );
    }

    return _PhotoRebuildPlan(
      totalBefore: totalBefore,
      prepared: prepared,
      built: built,
    );
  }

  Future<_PhotoSyncPlan> prepareIncremental({
    int? maxAssets,
    int offsetFromNewest = 0,
  }) async {
    final totalBefore = await _service._isar.collection<PhotoEntity>().count();
    final prepared = await _prepareScan(
      maxAssets: maxAssets,
      offsetFromNewest: offsetFromNewest,
    );
    final removedCount = await _service._removeUnavailablePhotos();

    debugPrint(
      maxAssets == null
          ? 'Starting album scan (all photos)...'
          : 'Starting album scan (${prepared.fetchCount} / ${prepared.totalCount})...',
    );

    final built = await _service._buildPhotoEntities(
      prepared.assets,
      skipExisting: true,
    );

    return _PhotoSyncPlan(
      totalBefore: totalBefore,
      prepared: prepared,
      removedCount: removedCount,
      built: built,
    );
  }

  Future<_PreparedScanData> _prepareScan({
    int? maxAssets,
    int offsetFromNewest = 0,
  }) async {
    if (Platform.isAndroid) {
      final photosStatus = await Permission.photos.request();
      debugPrint('Android photos permission: $photosStatus');

      final locationStatus = await Permission.accessMediaLocation.request();
      debugPrint('Android media-location permission: $locationStatus');
    }

    final permissionState = await PhotoManager.requestPermissionExtend();
    final isLimited = permissionState == PermissionState.limited;
    debugPrint(
      'Photo permission: $permissionState isAuth=${permissionState.isAuth} hasAccess=${permissionState.hasAccess}',
    );
    if (!permissionState.isAuth && !permissionState.hasAccess) {
      throw const PhotoScanException(
        PhotoScanError.permissionDenied,
        'Photo access was not granted. Please allow photo access in system settings.',
      );
    }

    final safeFilter = FilterOptionGroup(
      orders: <OrderOption>[
        OrderOption(type: OrderOptionType.createDate, asc: false),
      ],
    );

    return _prepareScanViaAllPhotosOrGlobal(
      safeFilter: safeFilter,
      isLimited: isLimited,
      maxAssets: maxAssets,
      offsetFromNewest: offsetFromNewest,
    );
  }

  Future<_PreparedScanData> _prepareScanViaAllPhotosOrGlobal({
    required FilterOptionGroup safeFilter,
    required bool isLimited,
    required int? maxAssets,
    required int offsetFromNewest,
  }) async {
    final preferredAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: safeFilter,
    );

    AssetPathEntity? selectedAlbum;
    var selectedCount = -1;
    if (preferredAlbums.isNotEmpty) {
      final albumCountResults = await Future.wait(
        preferredAlbums.map((album) async {
          final count = await album.assetCountAsync;
          return MapEntry<AssetPathEntity, int>(album, count);
        }),
      );
      for (final entry in albumCountResults) {
        final album = entry.key;
        final count = entry.value;
        debugPrint('All-photos album [${album.name}] count=$count');
        if (count > selectedCount) {
          selectedAlbum = album;
          selectedCount = count;
        }
      }
    }

    if (selectedAlbum != null && selectedCount > 0) {
      final totalCount = selectedCount;
      final normalizedOffset = math.max(0, offsetFromNewest);
      final startOffset = maxAssets == null
          ? 0
          : math.min(normalizedOffset, totalCount);
      final remainingCount = math.max(0, totalCount - startOffset);
      final fetchCount = maxAssets == null
          ? totalCount
          : math.min(maxAssets, remainingCount);
      final endIndex = startOffset + fetchCount;
      final assets = await selectedAlbum.getAssetListRange(
        start: startOffset,
        end: endIndex,
      );
      assets.sort(
        (a, b) => b.createDateTime.millisecondsSinceEpoch.compareTo(
          a.createDateTime.millisecondsSinceEpoch,
        ),
      );

      return _PreparedScanData(
        assets: assets,
        totalCount: totalCount,
        fetchCount: fetchCount,
        startOffset: startOffset,
      );
    }

    final fallback = await _prepareGlobalScan(
      safeFilter: safeFilter,
      maxAssets: maxAssets,
      offsetFromNewest: offsetFromNewest,
    );
    if (fallback.assets.isNotEmpty) {
      return fallback;
    }

    if (isLimited) {
      throw const PhotoScanException(
        PhotoScanError.permissionDenied,
        'Photo access is limited and the authorized list is empty. Please allow all photos or select at least one photo in system settings.',
      );
    }

    throw const PhotoScanException(
      PhotoScanError.noAlbum,
      'No readable album was found. Please check photo permission and local albums.',
    );
  }

  Future<_PreparedScanData> _prepareGlobalScan({
    required FilterOptionGroup safeFilter,
    required int? maxAssets,
    required int offsetFromNewest,
  }) async {
    const pageSize = 200;
    final assets = <AssetEntity>[];
    var page = 0;
    final normalizedOffset = math.max(0, offsetFromNewest);
    final targetCount = maxAssets == null
        ? null
        : normalizedOffset + math.max(1, maxAssets);
    var reachedEnd = false;

    while (true) {
      final remaining = targetCount == null
          ? pageSize
          : targetCount - assets.length;
      if (remaining <= 0) {
        break;
      }

      final batch = await PhotoManager.getAssetListPaged(
        page: page,
        pageCount: remaining < pageSize ? remaining.toInt() : pageSize,
        type: RequestType.image,
        filterOption: safeFilter,
      );
      if (batch.isEmpty) {
        reachedEnd = true;
        break;
      }

      assets.addAll(batch);
      if (batch.length < pageSize) {
        reachedEnd = true;
        break;
      }
      page++;
    }

    assets.sort(
      (a, b) => b.createDateTime.millisecondsSinceEpoch.compareTo(
        a.createDateTime.millisecondsSinceEpoch,
      ),
    );

    final totalCount = reachedEnd
        ? assets.length
        : math.max(
            assets.length,
            normalizedOffset + (maxAssets ?? assets.length),
          );
    if (normalizedOffset >= assets.length) {
      return _PreparedScanData(
        assets: const <AssetEntity>[],
        totalCount: totalCount,
        fetchCount: 0,
        startOffset: normalizedOffset,
      );
    }

    final fetchEnd = maxAssets == null
        ? assets.length
        : math.min(normalizedOffset + maxAssets, assets.length);
    final slicedAssets = assets.sublist(normalizedOffset, fetchEnd);

    return _PreparedScanData(
      assets: slicedAssets,
      totalCount: totalCount,
      fetchCount: slicedAssets.length,
      startOffset: normalizedOffset,
    );
  }
}
