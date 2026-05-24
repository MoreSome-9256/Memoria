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
  static List<AssetPathEntity> _cachedAlbums = <AssetPathEntity>[];
  static int _cachedTotalCount = -1;
  static String _cachedSelectionSignature = '';
  static bool _permissionsReady = false;
  static bool _lastPermissionWasLimited = false;

  // ── 全量重建（clearCacheFirst 路径）────────────────────────────────
  Future<_PhotoRebuildPlan> prepareRebuild({int? maxAssets}) async {
    final totalBefore = _service._photoBox.count();
    final prepared = await _prepareScan(maxAssets: maxAssets);
    final filterProfile = await _resolveFilterProfile();

    final built = await _service._buildPhotoEntities(
      prepared.assets,
      skipExisting: false,
      filterProfile: filterProfile,
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
    ValueChanged<BatchScanProgress>? onProgress,
  }) async {
    final totalBefore = _service._photoBox.count();

    // 仅首次运行时请求权限+获取（并在首次执行一次旧照片清理）
    final albumBundle = await _resolveAlbums(
      runCleanupOnce: totalBefore <= 0,
    );
    if (albumBundle.albums.isEmpty || _cachedTotalCount <= 0) {
      onProgress?.call(
        const BatchScanProgress(
          scannedCount: 0,
          candidateCount: 0,
          acceptedCount: 0,
          totalCount: 0,
          targetNew: 0,
        ),
      );
      return _emptyPlan(totalBefore);
    }

    final filterProfile = albumBundle.isUserSelection
        ? PhotoScanFilterProfile.userSelectedAlbums
        : PhotoScanFilterProfile.strict;

    final targetNew = math.max(1, maxAssets ?? 50);
    const pageSize = 50;

    final collectedPhotos = <PhotoEntity>[];
    var totalScanned = 0;
    var candidateCount = 0;
    var stats = _ScanStats();

    onProgress?.call(
      BatchScanProgress(
        scannedCount: 0,
        candidateCount: 0,
        acceptedCount: 0,
        totalCount: _cachedTotalCount,
        targetNew: targetNew,
      ),
    );

    for (final album in albumBundle.albums) {
      if (collectedPhotos.length >= targetNew) break;
      final albumTotal = await album.assetCountAsync;
      var cursor = 0;

      while (collectedPhotos.length < targetNew && cursor < albumTotal) {
        final end = math.max(0, math.min(albumTotal, cursor + pageSize));
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
        if (newAssets.isEmpty) {
          onProgress?.call(
            BatchScanProgress(
              scannedCount: totalScanned,
              candidateCount: candidateCount,
              acceptedCount: collectedPhotos.length,
              totalCount: _cachedTotalCount,
              targetNew: targetNew,
            ),
          );
          continue;
        }

        final remainingSlots = targetNew - collectedPhotos.length;
        final buildAssets = newAssets.length > remainingSlots
            ? newAssets.take(remainingSlots).toList(growable: false)
            : newAssets;
        candidateCount += buildAssets.length;
        onProgress?.call(
          BatchScanProgress(
            scannedCount: totalScanned,
            candidateCount: candidateCount,
            acceptedCount: collectedPhotos.length,
            totalCount: _cachedTotalCount,
            targetNew: targetNew,
          ),
        );

        // 并行构建
        final results = await Future.wait(
          buildAssets.map(
            (a) => _service._buildSingleAssetPhoto(
              a,
              filterProfile: filterProfile,
            ),
          ),
        );
        for (final r in results) {
          if (r.photo != null) {
            collectedPhotos.add(r.photo!);
          }
          stats = stats.merge(r);
        }
        onProgress?.call(
          BatchScanProgress(
            scannedCount: totalScanned,
            candidateCount: candidateCount,
            acceptedCount: collectedPhotos.length,
            totalCount: _cachedTotalCount,
            targetNew: targetNew,
          ),
        );
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
  Future<_AlbumBundle> _resolveAlbums({
    bool runCleanupOnce = false,
    bool forceRefresh = false,
  }) async {
    final selection = await AlbumSelectionPreferenceService().loadSelection();
    final selectionSignature = _signatureForSelection(selection);
    if (!forceRefresh &&
        _cachedAlbums.isNotEmpty &&
        _cachedTotalCount >= 0 &&
        _cachedSelectionSignature == selectionSignature) {
      _cachedTotalCount = 0;
      for (final album in _cachedAlbums) {
        _cachedTotalCount += await album.assetCountAsync;
      }
      return _AlbumBundle(
        albums: _cachedAlbums,
        isUserSelection: !selection.useAllAlbums,
      );
    }

    await _ensurePermissions();

    // 降序排列确保 position 0 = 最新照片
    final filter = FilterOptionGroup(
      orders: [OrderOption(type: OrderOptionType.createDate, asc: false)],
    );
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: selection.useAllAlbums,
      filterOption: filter,
    );
    if (albums.isEmpty) {
      if (_lastPermissionWasLimited) {
        throw const PhotoScanException(
          PhotoScanError.permissionDenied,
          '照片访问权限为受限模式，且当前授权列表为空。',
        );
      }
      return const _AlbumBundle(albums: <AssetPathEntity>[], isUserSelection: false);
    }

    List<AssetPathEntity> selectedAlbums = albums;
    if (!selection.useAllAlbums) {
      final selectedIdSet = selection.selectedAlbumIds.toSet();
      selectedAlbums = albums
          .where((album) => selectedIdSet.contains(album.id))
          .toList(growable: false);
    }
    if (selectedAlbums.isEmpty) {
      return const _AlbumBundle(albums: <AssetPathEntity>[], isUserSelection: false);
    }

    var totalCount = 0;
    for (final album in selectedAlbums) {
      totalCount += await album.assetCountAsync;
    }

    _cachedAlbums = selectedAlbums;
    _cachedTotalCount = totalCount;
    _cachedSelectionSignature = selectionSignature;

    if (runCleanupOnce) {
      // session 首次运行：清理一次已删除照片
      _service._removeUnavailablePhotos().ignore();
    }

    return _AlbumBundle(
      albums: selectedAlbums,
      isUserSelection: !selection.useAllAlbums,
    );
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
    final albumBundle = await _resolveAlbums(runCleanupOnce: true, forceRefresh: true);
    if (albumBundle.albums.isEmpty || _cachedTotalCount <= 0) {
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
    final assets = await _collectAssetsFromAlbums(
      albumBundle.albums,
      maxAssets: fetchCount,
    );
    return _PreparedScanData(
      assets: assets,
      totalCount: count,
      fetchCount: assets.length,
      startOffset: 0,
    );
  }

  Future<List<AssetEntity>> _collectAssetsFromAlbums(
    List<AssetPathEntity> albums, {
    required int maxAssets,
  }) async {
    final collected = <AssetEntity>[];
    if (maxAssets <= 0 || albums.isEmpty) {
      return collected;
    }

    for (final album in albums) {
      if (collected.length >= maxAssets) break;
      final total = await album.assetCountAsync;
      var cursor = 0;
      while (cursor < total && collected.length < maxAssets) {
        final end = math.min(total, cursor + 200);
        final assets = await album.getAssetListRange(start: cursor, end: end);
        if (assets.isEmpty) break;
        collected.addAll(assets);
        cursor = end;
      }
    }
    if (collected.length > maxAssets) {
      return collected.sublist(0, maxAssets);
    }
    return collected;
  }

  Future<PhotoScanFilterProfile> _resolveFilterProfile() async {
    final selection = await AlbumSelectionPreferenceService().loadSelection();
    final prefs = await AlbumSelectionPreferenceService().loadScanPreferences();
    int? minTs;
    if (prefs['minYear'] != null) {
      final y = prefs['minYear']!;
      minTs = DateTime(y, 1, 1).millisecondsSinceEpoch;
    }
    final minW = prefs['minWidth'];
    final minH = prefs['minHeight'];
    final base = selection.useAllAlbums
        ? PhotoScanFilterProfile.strict
        : PhotoScanFilterProfile.userSelectedAlbums;
    return PhotoScanFilterProfile(
      requireValidDimensions: base.requireValidDimensions,
      minTimestampMs: minTs,
      minWidth: minW,
      minHeight: minH,
    );
  }

  String _signatureForSelection(AlbumSelectionSnapshot selection) {
    if (selection.useAllAlbums) {
      return 'all';
    }
    final sortedIds = selection.selectedAlbumIds.toList()..sort();
    return 'custom:${sortedIds.join(',')}';
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

class _AlbumBundle {
  const _AlbumBundle({
    required this.albums,
    required this.isUserSelection,
  });

  final List<AssetPathEntity> albums;
  final bool isUserSelection;
}
