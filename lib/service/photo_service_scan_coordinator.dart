/// 照片扫描协调器 — 高效批量发现系统相册中的新照片。
///
/// 核心策略：
///   1. 缓存系统相册引用，session 内只获取一次
///   2. 小批量分页（50张/页），从最新开始遍历
///   3. 每页查询 ObjectBox 批量过滤已存在的 assetId
///   4. 对真正新增的照片并行构建实体
///   5. 收集到目标数量后立即停止（stop-early）
///   6. 增量路径跳过 `_removeUnavailablePhotos`（全量旧照片校验）
///
/// 消除的问题：
/// - 不再全量扫描系统相册
/// - 不再每次请求权限
/// - 不再重复查询 album/assetCountAsync
/// - 不再 in-Dart 排序（系统已按时间返回）

part of 'photo_service.dart';

class _PhotoScanCoordinator {
  const _PhotoScanCoordinator(this._service);

  final PhotoService _service;

  // ── session 级缓存 ────────────────────────────────────────────────
  static AssetPathEntity? _cachedAlbum;
  static int _cachedTotalCount = -1;
  static bool _permissionsReady = false;
  static bool _lastPermissionWasLimited = false;

  // ── 全量重建（clearCacheFirst 路径）────────────────────────────────
  Future<_PhotoRebuildPlan> prepareRebuild({int? maxAssets}) async {
    final totalBefore = _service._photoBox.count();
    final prepared = await _prepareScan(maxAssets: maxAssets);

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

    debugPrint(
      maxAssets == null
          ? '全量重建完成: fetch=${prepared.fetchCount} 入库=${built.insertedCount}'
          : '部分重建完成: fetch=${prepared.fetchCount} 入库=${built.insertedCount}',
    );
    return _PhotoRebuildPlan(
      totalBefore: totalBefore,
      prepared: prepared,
      built: built,
    );
  }

  // ── 增量扫描：收集 [maxAssets] 张新照片后停止 ─────────────────────
  Future<_PhotoSyncPlan> prepareIncremental({
    int? maxAssets,
    int offsetFromNewest = 0,
  }) async {
    final totalBefore = _service._photoBox.count();

    // 仅首次运行时请求权限+获取（并在首次执行一次旧照片清理）
    final album = await _resolveAlbum(
      runCleanupOnce: totalBefore <= 0,
    );
    if (album == null || _cachedTotalCount <= 0) {
      return _emptyPlan(totalBefore);
    }

    final targetNew = math.max(1, math.min(500, maxAssets ?? 50));
    const pageSize = 50;

    var cursor = 0;
    final collectedPhotos = <PhotoEntity>[];
    var totalScanned = 0;
    var stats = _ScanStats();

    while (collectedPhotos.length < targetNew && cursor < _cachedTotalCount) {
      final end = math.max(0, math.min(_cachedTotalCount, cursor + pageSize));
      final assets = await album.getAssetListRange(start: cursor, end: end);
      if (assets.isEmpty) break;
      totalScanned += assets.length;
      cursor = end;

      // 批量过滤已存在
      final skipIds = _existingAssetIdSet(assets);
      final newAssets = <AssetEntity>[];
      for (final asset in assets) {
        if (!skipIds.contains(asset.id)) newAssets.add(asset);
      }
      if (newAssets.isEmpty) continue;

      // 并行构建
      final results = await Future.wait(
        newAssets.map((a) => _service._buildSingleAssetPhoto(a)),
      );
      for (final r in results) {
        if (r.photo != null) {
          collectedPhotos.add(r.photo!);
        }
        stats = stats.merge(r);
      }
    }

    final built = _ScanBuildResult(
      photos: collectedPhotos,
      insertedCount: collectedPhotos.length,
      insertedNoGps: stats.insertedNoGps,
      skippedInvalidTime: stats.skippedInvalidTime,
      skippedNonCamera: stats.skippedNonCamera,
      skippedScreenshot: stats.skippedScreenshot,
    );

    debugPrint(
      '增量扫描: scan=$totalScanned new=${collectedPhotos.length} '
      'noGps=${stats.insertedNoGps} badTime=${stats.skippedInvalidTime} '
      'nonCam=${stats.skippedNonCamera} ss=${stats.skippedScreenshot}',
    );

    return _PhotoSyncPlan(
      totalBefore: totalBefore,
      removedCount: 0,
      prepared: _PreparedScanData(
        assets: const [],
        totalCount: _cachedTotalCount,
        fetchCount: totalScanned,
        startOffset: offsetFromNewest,
      ),
      built: built,
    );
  }

  // ── 获取并缓存系统相册引用 ───────────────────────────────────────
  Future<AssetPathEntity?> _resolveAlbum({
    bool runCleanupOnce = false,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedAlbum != null && _cachedTotalCount >= 0) {
      _cachedTotalCount = await _cachedAlbum!.assetCountAsync;
      return _cachedAlbum;
    }

    await _ensurePermissions();

    // 降序排列确保 position 0 = 最新照片
    final filter = FilterOptionGroup(
      orders: [OrderOption(type: OrderOptionType.createDate, asc: false)],
    );
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: filter,
    );
    if (albums.isEmpty) {
      if (_lastPermissionWasLimited) {
        throw const PhotoScanException(
          PhotoScanError.permissionDenied,
          '照片访问权限为受限模式，且当前授权列表为空。',
        );
      }
      return null;
    }

    // 找照片最多的相册
    var best = albums.first;
    var bestCount = await best.assetCountAsync;
    for (final album in albums.skip(1)) {
      final c = await album.assetCountAsync;
      if (c > bestCount) {
        best = album;
        bestCount = c;
      }
    }

    _cachedAlbum = best;
    _cachedTotalCount = bestCount;

    if (runCleanupOnce) {
      // session 首次运行：清理一次已删除照片
      _service._removeUnavailablePhotos().ignore();
    }

    return best;
  }

  Future<void> _ensurePermissions() async {
    if (_permissionsReady) return;
    if (Platform.isAndroid) {
      await Permission.photos.request();
      await Permission.accessMediaLocation.request();
    }
    final permissionState = await PhotoManager.requestPermissionExtend();
    _lastPermissionWasLimited = permissionState == PermissionState.limited;
    debugPrint(
      'Photo permission: $permissionState '
      'isAuth=${permissionState.isAuth} hasAccess=${permissionState.hasAccess}',
    );
    if (!permissionState.isAuth && !permissionState.hasAccess) {
      throw const PhotoScanException(
        PhotoScanError.permissionDenied,
        '没有获得照片访问权限。',
      );
    }
    _permissionsReady = true;
  }

  // ── 批量查 ObjectBox，返回已存在的 assetId 集合 ──────────────────
  Set<String> _existingAssetIdSet(List<AssetEntity> assets) {
    final ids = assets
        .map((a) => a.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return {};

    final q = _service._photoBox
        .query(PhotoEntity_.assetId.oneOf(ids))
        .build();
    final existing = q.find().map((e) => e.assetId).toSet();
    q.close();
    return existing;
  }

  // ── 全量重建用：兼容原 _prepareScan（简化版）─────────────────────
  Future<_PreparedScanData> _prepareScan({int? maxAssets}) async {
    // 全量重建每次强制刷新缓存（因为可能要扫全部照片）
    final album = await _resolveAlbum(runCleanupOnce: true, forceRefresh: true);
    if (album == null || _cachedTotalCount <= 0) {
      return _PreparedScanData(
        assets: const [],
        totalCount: 0,
        fetchCount: 0,
        startOffset: 0,
      );
    }

    final count = _cachedTotalCount;
    final fetchCount = maxAssets == null
        ? count
        : math.max(1, math.min(count, maxAssets));
    final assets = await album.getAssetListRange(start: 0, end: fetchCount);
    return _PreparedScanData(
      assets: assets,
      totalCount: count,
      fetchCount: assets.length,
      startOffset: 0,
    );
  }

  _PhotoSyncPlan _emptyPlan(int totalBefore) {
    return _PhotoSyncPlan(
      totalBefore: totalBefore,
      removedCount: 0,
      prepared: _PreparedScanData(
        assets: const [],
        totalCount: 0,
        fetchCount: 0,
        startOffset: 0,
      ),
      built: _ScanBuildResult(
        photos: const [],
        insertedCount: 0,
        insertedNoGps: 0,
        skippedInvalidTime: 0,
        skippedNonCamera: 0,
        skippedScreenshot: 0,
      ),
    );
  }
}

/// 累加统计辅助类（替代 fold 遍历）
class _ScanStats {
  const _ScanStats({
    this.insertedNoGps = 0,
    this.skippedInvalidTime = 0,
    this.skippedNonCamera = 0,
    this.skippedScreenshot = 0,
  });

  final int insertedNoGps;
  final int skippedInvalidTime;
  final int skippedNonCamera;
  final int skippedScreenshot;

  _ScanStats merge(_SingleAssetBuildResult r) => _ScanStats(
    insertedNoGps: insertedNoGps + r.insertedNoGps,
    skippedInvalidTime: skippedInvalidTime + r.skippedInvalidTime,
    skippedNonCamera: skippedNonCamera + r.skippedNonCamera,
    skippedScreenshot: skippedScreenshot + r.skippedScreenshot,
  );
}
