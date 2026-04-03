part of 'photo_service.dart';

class _PhotoScanCoordinator {
  const _PhotoScanCoordinator(this._service);

  final PhotoService _service;

  Future<_PhotoRebuildPlan> prepareRebuild({int? maxAssets}) async {
    final totalBefore = await _service._isar.collection<PhotoEntity>().count();
    final prepared = await _prepareScan(maxAssets: maxAssets);

    debugPrint(
      maxAssets == null
          ? "馃П 寮€濮嬪畨鍏ㄩ噸寤虹浉鍐岀紦瀛橈紙鍏ㄩ噺锛?.."
          : "馃П 寮€濮嬪畨鍏ㄩ噸寤虹浉鍐岀紦瀛橈紙鏈€杩?${prepared.fetchCount} / ${prepared.totalCount} 寮狅級...",
    );

    final built = await _service._buildPhotoEntities(
      prepared.assets,
      skipExisting: false,
    );
    if (built.photos.isEmpty) {
      throw const PhotoScanException(
        PhotoScanError.noEligiblePhoto,
        '鏈壘鍒板彲鐢ㄧ収鐗囷細璇风‘璁ょ浉鍐屼腑瀛樺湪鍖呭惈鏈夋晥鏃堕棿鐨勭浉鏈哄浘鐗囪祫婧愩€?',
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
          ? "馃殌 寮€濮嬫壂鎻忕浉鍐岋紙鍏ㄩ噺锛?.."
          : "馃殌 寮€濮嬫壂鎻忕浉鍐岋紙鏈€杩?${prepared.fetchCount} / ${prepared.totalCount} 寮狅級...",
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
      debugPrint('馃摳 Android photos 鏉冮檺璇锋眰缁撴灉: $photosStatus');

      final locationStatus = await Permission.accessMediaLocation.request();
      if (locationStatus.isGranted) {
        debugPrint("鉁?鎴愬姛鑾峰緱璇诲彇鐓х墖鐪熷疄 GPS 鐨勭壒鏉?");
      } else {
        debugPrint("鈿狅笍 鐢ㄦ埛鎷掔粷浜嗕綅缃壒鏉冿紝鐓х墖缁忕含搴﹀皢琚郴缁熸姽闄や负 null");
      }
    }

    final permissionState = await PhotoManager.requestPermissionExtend();
    final isLimited = permissionState == PermissionState.limited;
    debugPrint(
      '馃摳 鐩稿唽鏉冮檺鐘舵€? $permissionState isAuth=${permissionState.isAuth} hasAccess=${permissionState.hasAccess}',
    );
    if (!permissionState.isAuth && !permissionState.hasAccess) {
      throw const PhotoScanException(
        PhotoScanError.permissionDenied,
        '鏈幏寰楃浉鍐岃闂潈闄愶紝璇峰湪绯荤粺璁剧疆涓厑璁歌闂収鐗囥€?',
      );
    }

    final safeFilter = FilterOptionGroup(
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
    );

    final preferredAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: safeFilter,
    );
    var albums = preferredAlbums;
    if (albums.isEmpty) {
      albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: false,
        filterOption: safeFilter,
      );
    }

    AssetPathEntity? selectedAlbum;
    var selectedCount = -1;
    final albumCountResults = await Future.wait(
      albums.map((album) async {
        final count = await album.assetCountAsync;
        return MapEntry<AssetPathEntity, int>(album, count);
      }),
    );
    for (final entry in albumCountResults) {
      final album = entry.key;
      final count = entry.value;
      debugPrint('馃搨 鐩稿唽 [${album.name}] 鍐呮湁 $count 寮犲浘鐗?');
      if (count > selectedCount) {
        selectedAlbum = album;
        selectedCount = count;
      }
    }

    if ((selectedAlbum == null || selectedCount <= 0) &&
        preferredAlbums.isNotEmpty) {
      final fallbackAlbums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: false,
        filterOption: safeFilter,
      );
      final fallbackCountResults = await Future.wait(
        fallbackAlbums.map((album) async {
          final count = await album.assetCountAsync;
          return MapEntry<AssetPathEntity, int>(album, count);
        }),
      );
      for (final entry in fallbackCountResults) {
        final album = entry.key;
        final count = entry.value;
        debugPrint('馃搨 鍏滃簳鐩稿唽 [${album.name}] 鍐呮湁 $count 寮犲浘鐗?');
        if (count > selectedCount) {
          selectedAlbum = album;
          selectedCount = count;
        }
      }
    }

    if (albums.isEmpty || selectedAlbum == null || selectedCount <= 0) {
      debugPrint('鈿狅笍 鐩稿唽鍒楄〃涓虹┖鎴栧叏閮ㄤ负绌哄３锛屽垏鎹㈠埌鍏ㄥ眬濯掍綋搴撴壂鎻忓厹搴?');
      final fallback = await _prepareGlobalScan(maxAssets: maxAssets);
      if (fallback.assets.isNotEmpty) {
        return fallback;
      }

      if (isLimited) {
        throw const PhotoScanException(
          PhotoScanError.permissionDenied,
          '褰撳墠绯荤粺浠呮巿浜堜簡鈥滈儴鍒嗙収鐗団€濇潈闄愶紝涓斿凡鎺堟潈鍒楄〃涓虹┖銆傝鍒扮郴缁熻缃皢鐓х墖鏉冮檺鏀逛负銆屽厑璁告墍鏈夌収鐗囥€嶏紝鎴栧厛鍦ㄧ郴缁熸潈闄愰潰鏉夸腑鍕鹃€夎嚦灏戜竴寮犵収鐗囧悗閲嶈瘯銆?',
        );
      }

      throw const PhotoScanException(
        PhotoScanError.noAlbum,
        '鏈壘鍒板彲璇诲彇鐨勭浉鍐屻€傝纭绯荤粺鐓х墖鏉冮檺宸叉巿浜堬紝骞舵鏌ョ郴缁熺浉鍐屼腑鏄惁瀛樺湪鍥剧墖銆?',
      );
    }

    debugPrint('鉁?鏈鎵弿閫変腑鐩稿唽: ${selectedAlbum.name} ($selectedCount 寮?');
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

  Future<_PreparedScanData> _prepareGlobalScan({int? maxAssets}) async {
    const pageSize = 200;
    final assets = <AssetEntity>[];
    var page = 0;

    final safeFilter = FilterOptionGroup(
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
    );

    while (true) {
      final remaining = maxAssets == null
          ? pageSize
          : maxAssets - assets.length;
      if (remaining <= 0) {
        break;
      }

      final batch = await PhotoManager.getAssetListPaged(
        page: page,
        pageCount: remaining < pageSize ? remaining : pageSize,
        type: RequestType.image,
        filterOption: safeFilter,
      );
      debugPrint('馃О 鍏ㄥ眬濯掍綋搴撶 ${page + 1} 椤佃繑鍥?${batch.length} 寮犲浘鐗?');

      if (batch.isEmpty) {
        break;
      }

      assets.addAll(batch);
      if (batch.length < pageSize) {
        break;
      }
      page++;
    }

    assets.sort(
      (a, b) => b.createDateTime.millisecondsSinceEpoch.compareTo(
        a.createDateTime.millisecondsSinceEpoch,
      ),
    );
    if (maxAssets != null && assets.length > maxAssets) {
      assets.removeRange(maxAssets, assets.length);
    }

    debugPrint('鉁?鍏ㄥ眬濯掍綋搴撳厹搴曞叡鎷垮埌 ${assets.length} 寮犲浘鐗?');
    return _PreparedScanData(
      assets: assets,
      totalCount: assets.length,
      fetchCount: assets.length,
      startOffset: 0,
    );
  }
}
