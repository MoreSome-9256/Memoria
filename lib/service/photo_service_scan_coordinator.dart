/// 照片扫描协调器 — 高效批量发现系统相册中的新照片。
///
/// 核心策略：
///   1. 缓存系统相册清单，session 内只获取一次
///   2. 小批量分页（50张/页），从最新开始遍历
///   3. 每页查询 ObjectBox 批量过滤已存在的 assetId
///   4. 对真正新增的照片并行构建实体
///   5. 增量路径完整更新本地缓存，再从数据库筛选交给 AI 的项目
///   6. 增量路径跳过 `_removeUnavailablePhotos`（全量旧照片校验）
///
/// 消除的问题：
/// - 增量构建只处理未入库的新资源
/// - 不再每次请求权限
/// - 不再重复查询 album/assetCountAsync
/// - 不再 in-Dart 排序（系统已按时间返回）

part of 'photo_service.dart';

class _PhotoScanCoordinator {
  const _PhotoScanCoordinator(this._service);

  final PhotoService _service;

  // ── session 级缓存 ────────────────────────────────────────────────
  static List<AssetEntity> _cachedAssets = <AssetEntity>[];
  static int _cachedTotalCount = -1;
  static String _cachedSelectionSignature = '';

  static void invalidateSessionCache() {
    _cachedAssets = const <AssetEntity>[];
    _cachedTotalCount = -1;
    _cachedSelectionSignature = '';
  }

  // ── 全量重建（clearCacheFirst 路径）────────────────────────────────
  Future<_PhotoRebuildPlan> prepareRebuild({int? maxAssets}) async {
    invalidateSessionCache();
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
        '没有找到符合条件的照片。',
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

  // ── 增量扫描：完整预扫描授权相册并更新本地缓存 ─────────────────
  Future<_PhotoSyncPlan> prepareIncremental({
    int? maxAssets,
    int offsetFromNewest = 0,
    ValueChanged<BatchScanProgress>? onProgress,
  }) async {
    final totalBefore = _service._photoBox.count();

    final scanSource = await _resolveIncrementalScanSource(
      runCleanupOnce: totalBefore <= 0,
    );
    if (scanSource.isEmpty) {
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

    final filterProfile = await _resolveFilterProfile();

    const pageSize = 50;

    final insertedPhotoIds = <int>[];
    var totalScanned = 0;
    var candidateCount = 0;
    var stats = _ScanStats();
    final startedAt = DateTime.now();

    onProgress?.call(
      BatchScanProgress(
        scannedCount: 0,
        candidateCount: 0,
        acceptedCount: 0,
        totalCount: scanSource.totalCount,
        targetNew: scanSource.totalCount,
      ),
    );

    await for (final assets in _incrementalAssetPages(
      scanSource,
      pageSize: pageSize,
      offsetFromNewest: offsetFromNewest,
    )) {
      if (assets.isEmpty) break;

      final existingByAssetId = _existingAssetMap(assets);
      final newAssets = <AssetEntity>[];
      for (final asset in assets) {
        totalScanned++;
        final existing = existingByAssetId[asset.id];
        if (existing == null) {
          newAssets.add(asset);
        } else {
          await _refreshExistingThumbnailIfNeeded(existing, asset);
        }
      }
      if (newAssets.isEmpty) {
        if (totalScanned % 20 == 0) {
          onProgress?.call(
            BatchScanProgress(
              scannedCount: totalScanned,
              candidateCount: candidateCount,
              acceptedCount: insertedPhotoIds.length,
              totalCount: scanSource.totalCount,
              targetNew: scanSource.totalCount,
            ),
          );
        }
        continue;
      }

      final buildAssets = newAssets;
      candidateCount += buildAssets.length;

      final batchPhotos = <PhotoEntity>[];
      for (final asset in buildAssets) {
        final r = await _service._buildSingleAssetPhoto(
          asset,
          filterProfile: filterProfile,
        );
        if (r.photo != null) {
          batchPhotos.add(r.photo!);
          stats = stats.merge(r);
        } else {
          stats = stats.merge(r);
        }
      }

      if (batchPhotos.isNotEmpty) {
        final storedIds = _service._store.runInTransaction(
          TxMode.write,
          () => _service._photoBox.putMany(batchPhotos),
        );
        insertedPhotoIds.addAll(storedIds.where((id) => id > 0));
      }

      if (totalScanned % 20 == 0 || batchPhotos.isNotEmpty) {
        onProgress?.call(
          BatchScanProgress(
            scannedCount: totalScanned,
            candidateCount: candidateCount,
            acceptedCount: insertedPhotoIds.length,
            totalCount: scanSource.totalCount,
            targetNew: scanSource.totalCount,
          ),
        );
      }
    }

    final built = _ScanBuildResult(
      photos: const <PhotoEntity>[],
      insertedCount: insertedPhotoIds.length,
      insertedNoGps: stats.insertedNoGps,
      skippedInvalidTime: stats.skippedInvalidTime,
      skippedNonCamera: stats.skippedNonCamera,
      skippedScreenshot: stats.skippedScreenshot,
    );

    debugPrint(
      '增量扫描: scan=$totalScanned new=${insertedPhotoIds.length} '
      'noGps=${stats.insertedNoGps} badTime=${stats.skippedInvalidTime} '
      'nonCam=${stats.skippedNonCamera} ss=${stats.skippedScreenshot} '
      'small=${stats.skippedSmallResolution} '
      'elapsed=${DateTime.now().difference(startedAt).inMilliseconds}ms',
    );

    return _PhotoSyncPlan(
      totalBefore: totalBefore,
      removedCount: 0,
      prepared: _PreparedScanData(
        assets: const [],
        totalCount: scanSource.totalCount,
        fetchCount: totalScanned,
        startOffset: offsetFromNewest,
      ),
      built: built,
      insertedPhotoIds: insertedPhotoIds,
    );
  }

  Future<_IncrementalScanSource> _resolveIncrementalScanSource({
    bool runCleanupOnce = false,
  }) async {
    final settings = await AppAiSettingsService.instance.load();
    final requestType = settings.includeVideos
        ? RequestType.common
        : RequestType.image;
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: requestType,
          mediaLocation: false,
        ),
      ),
    );
    if (!state.hasAccess) {
      throw const PhotoScanException(
        PhotoScanError.permissionDenied,
        '没有相册权限，无法扫描系统相册。',
      );
    }

    final albSel = await AlbumSelectionPreferenceService().loadSelection();
    final selectedIds = albSel.selectedAlbumIds.toSet();
    final albumStates = <_IncrementalAlbumState>[];

    if (selectedIds.isEmpty) {
      final albums = await PhotoManager.getAssetPathList(
        onlyAll: true,
        type: requestType,
        filterOption: _createDateDescFilter(),
      );
      if (albums.isEmpty) {
        return const _IncrementalScanSource(albums: <_IncrementalAlbumState>[]);
      }
      final allAlbum = albums.first;
      final count = await allAlbum.assetCountAsync;
      albumStates.add(
        _IncrementalAlbumState(album: allAlbum, totalCount: count),
      );
    } else {
      final allAlbums = await PhotoManager.getAssetPathList(
        type: requestType,
        filterOption: _createDateDescFilter(),
      );
      final targetAlbums = allAlbums
          .where((album) => _isSelectedAlbum(album, selectedIds))
          .toList(growable: false);
      for (final album in targetAlbums) {
        final count = await album.assetCountAsync;
        if (count > 0) {
          albumStates.add(
            _IncrementalAlbumState(album: album, totalCount: count),
          );
        }
      }
    }

    if (runCleanupOnce) {
      _service._removeUnavailablePhotos().ignore();
    }

    return _IncrementalScanSource(albums: albumStates);
  }

  Stream<List<AssetEntity>> _incrementalAssetPages(
    _IncrementalScanSource source, {
    required int pageSize,
    required int offsetFromNewest,
  }) async* {
    if (source.albums.isEmpty) return;

    if (source.albums.length == 1) {
      final state = source.albums.first;
      final startOffset = math.max(0, offsetFromNewest);
      for (
        var pageIndex = startOffset ~/ pageSize;
        pageIndex * pageSize < state.totalCount;
        pageIndex += 1
      ) {
        var page = await state.album.getAssetListPaged(
          page: pageIndex,
          size: pageSize,
        );
        if (pageIndex == startOffset ~/ pageSize) {
          final skipWithinPage = startOffset % pageSize;
          if (skipWithinPage > 0 && skipWithinPage < page.length) {
            page = page.sublist(skipWithinPage);
          } else if (skipWithinPage >= page.length) {
            page = const <AssetEntity>[];
          }
        }
        if (page.isEmpty) break;
        yield page;
      }
      return;
    }

    var skipped = 0;
    while (source.albums.any((state) => !state.exhausted)) {
      final pageAssets = <AssetEntity>[];
      for (final state in source.albums) {
        if (state.exhausted) continue;
        final page = await state.album.getAssetListPaged(
          page: state.offset ~/ pageSize,
          size: pageSize,
        );
        state.offset += pageSize;
        if (page.isEmpty || state.offset >= state.totalCount) {
          state.exhausted = true;
        }
        pageAssets.addAll(page);
      }
      if (pageAssets.isEmpty) break;

      final seen = <String>{};
      final unique = <AssetEntity>[];
      for (final asset in pageAssets) {
        if (seen.add(asset.id)) {
          unique.add(asset);
        }
      }
      unique.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

      final offset = math.max(0, offsetFromNewest);
      if (skipped < offset) {
        final remainingSkip = offset - skipped;
        if (remainingSkip >= unique.length) {
          skipped += unique.length;
          continue;
        }
        yield unique.sublist(remainingSkip);
        skipped = offset;
      } else {
        yield unique;
      }
    }
  }

  // ── 获取并缓存系统相册引用 ───────────────────────────────────────
  Future<_AlbumBundle> _resolveAlbums({
    bool runCleanupOnce = false,
    bool forceRefresh = false,
  }) async {
    final settings = await AppAiSettingsService.instance.load();
    final requestType = settings.includeVideos
        ? RequestType.common
        : RequestType.image;
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: requestType,
          mediaLocation: false,
        ),
      ),
    );
    if (!state.hasAccess) {
      throw const PhotoScanException(
        PhotoScanError.permissionDenied,
        '没有相册权限，无法扫描系统相册。',
      );
    }

    final albSel = await AlbumSelectionPreferenceService().loadSelection();
    final selectedIds = albSel.selectedAlbumIds.toSet();

    // 没有选中的相册 → 用 onlyAll 路径获取全部
    if (selectedIds.isEmpty) {
      return _resolveAllAlbums(requestType, runCleanupOnce, forceRefresh);
    }

    // 按选定相册分别加载
    final allAlbums = await PhotoManager.getAssetPathList(
      type: requestType,
      filterOption: _createDateDescFilter(),
    );
    final targetAlbums = allAlbums
        .where((album) => _isSelectedAlbum(album, selectedIds))
        .toList(growable: false);

    if (targetAlbums.isEmpty) {
      _cachedAssets = const <AssetEntity>[];
      _cachedTotalCount = 0;
      _cachedSelectionSignature = 'custom:empty';
      return const _AlbumBundle(assets: <AssetEntity>[]);
    }

    final targetAlbumIds = targetAlbums.map((album) => album.id).toList()
      ..sort();
    final signature = 'custom:${targetAlbumIds.join(',')}';
    if (!forceRefresh &&
        _cachedTotalCount >= 0 &&
        _cachedSelectionSignature == signature) {
      return _AlbumBundle(assets: _cachedAssets);
    }

    // 分批加载每个选中相册的照片
    final allAssets = <AssetEntity>[];
    for (final album in targetAlbums) {
      final count = await album.assetCountAsync;
      const pageSize = 1000;
      for (var pageIndex = 0; pageIndex * pageSize < count; pageIndex += 1) {
        final page = await album.getAssetListPaged(
          page: pageIndex,
          size: pageSize,
        );
        allAssets.addAll(page);
      }
    }

    // 按 assetId 去重（同一张照片可能属于多个相册）
    final seen = <String>{};
    final unique = <AssetEntity>[];
    for (final a in allAssets) {
      if (!seen.contains(a.id)) {
        seen.add(a.id);
        unique.add(a);
      }
    }
    unique.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

    _cachedAssets = unique;
    _cachedTotalCount = unique.length;
    _cachedSelectionSignature = signature;

    if (runCleanupOnce) {
      _service._removeUnavailablePhotos().ignore();
    }

    return _AlbumBundle(assets: unique);
  }

  bool _isSelectedAlbum(AssetPathEntity album, Set<String> selectedIds) {
    if (selectedIds.contains(album.id)) return true;
    if (selectedIds.contains(album.name)) return true;
    return selectedIds.contains(album.name.toLowerCase());
  }

  FilterOptionGroup _createDateDescFilter() {
    return FilterOptionGroup(
      orders: <OrderOption>[
        OrderOption(type: OrderOptionType.createDate, asc: false),
      ],
    );
  }

  /// 回退路径：加载系统全部照片（用户未选择特定相册时）。
  Future<_AlbumBundle> _resolveAllAlbums(
    RequestType requestType,
    bool runCleanupOnce,
    bool forceRefresh,
  ) async {
    final albums = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: requestType,
      filterOption: _createDateDescFilter(),
    );
    if (albums.isEmpty) {
      _cachedAssets = const <AssetEntity>[];
      _cachedTotalCount = 0;
      _cachedSelectionSignature = 'system-album:${requestType.value}:empty';
      return const _AlbumBundle(assets: <AssetEntity>[]);
    }

    final allAlbum = albums.first;
    final total = await allAlbum.assetCountAsync;
    final selectionSignature = 'system-album:${requestType.value}:$total';
    if (!forceRefresh &&
        _cachedTotalCount >= 0 &&
        _cachedSelectionSignature == selectionSignature) {
      return _AlbumBundle(assets: _cachedAssets);
    }

    final assets = <AssetEntity>[];
    const batchPageSize = 1000;
    for (var pageIndex = 0; pageIndex * batchPageSize < total; pageIndex += 1) {
      final page = await allAlbum.getAssetListPaged(
        page: pageIndex,
        size: batchPageSize,
      );
      assets.addAll(page);
    }
    assets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

    _cachedAssets = assets;
    _cachedTotalCount = assets.length;
    _cachedSelectionSignature = selectionSignature;

    if (runCleanupOnce) {
      _service._removeUnavailablePhotos().ignore();
    }

    return _AlbumBundle(assets: assets);
  }

  // ── 批量查 ObjectBox，返回已存在的 assetId 映射 ─────────────────
  Map<String, PhotoEntity> _existingAssetMap(List<AssetEntity> assets) {
    final ids = assets
        .map((a) => a.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return const <String, PhotoEntity>{};

    final q = _service._photoBox.query(PhotoEntity_.assetId.oneOf(ids)).build();
    try {
      return <String, PhotoEntity>{
        for (final photo in q.find())
          if (photo.assetId.isNotEmpty) photo.assetId: photo,
      };
    } finally {
      q.close();
    }
  }

  Future<void> _refreshExistingThumbnailIfNeeded(
    PhotoEntity existing,
    AssetEntity asset,
  ) async {
    if (existing.thumbnailBytes != null &&
        existing.thumbnailBytes!.isNotEmpty) {
      return;
    }
    final thumbnailBytes = await MediaThumbnailCacheService.instance
        .generateCompressedBytes(asset);
    if (thumbnailBytes == null || thumbnailBytes.isEmpty) {
      return;
    }
    existing.thumbnailBytes = thumbnailBytes;
    _service._photoBox.put(existing);
  }

  // ── 全量重建用：兼容原 _prepareScan（简化版）─────────────────────
  Future<_PreparedScanData> _prepareScan({int? maxAssets}) async {
    // 全量重建每次强制刷新缓存（因为可能要扫全部照片）
    final albumBundle = await _resolveAlbums(
      runCleanupOnce: true,
      forceRefresh: true,
    );
    if (albumBundle.isEmpty || _cachedTotalCount <= 0) {
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
    final assets = albumBundle.assets.length > fetchCount
        ? albumBundle.assets.take(fetchCount).toList(growable: false)
        : albumBundle.assets;
    return _PreparedScanData(
      assets: assets,
      totalCount: count,
      fetchCount: assets.length,
      startOffset: 0,
    );
  }

  Future<PhotoScanFilterProfile> _resolveFilterProfile() async {
    final prefs = await AlbumSelectionPreferenceService().loadScanPreferences();
    int? minTs;
    if (prefs.minYear != null) {
      final y = prefs.minYear!;
      minTs = DateTime(y, 1, 1).millisecondsSinceEpoch;
    }
    const base = PhotoScanFilterProfile.userSelectedAlbums;
    return PhotoScanFilterProfile(
      requireValidDimensions: base.requireValidDimensions,
      minTimestampMs: minTs,
      minWidth: prefs.minWidth,
      minHeight: prefs.minHeight,
      minPixels: prefs.minPixels,
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
    this.skippedSmallResolution = 0,
  });

  final int insertedNoGps;
  final int skippedInvalidTime;
  final int skippedNonCamera;
  final int skippedScreenshot;
  final int skippedSmallResolution;

  _ScanStats merge(_SingleAssetBuildResult r) => _ScanStats(
    insertedNoGps: insertedNoGps + r.insertedNoGps,
    skippedInvalidTime: skippedInvalidTime + r.skippedInvalidTime,
    skippedNonCamera: skippedNonCamera + r.skippedNonCamera,
    skippedScreenshot: skippedScreenshot + r.skippedScreenshot,
    skippedSmallResolution: skippedSmallResolution + r.skippedSmallResolution,
  );
}

class _AlbumBundle {
  const _AlbumBundle({required this.assets});

  final List<AssetEntity> assets;

  bool get isEmpty => assets.isEmpty;
  int get totalLength => assets.length;
}

class _IncrementalScanSource {
  const _IncrementalScanSource({required this.albums});

  final List<_IncrementalAlbumState> albums;

  bool get isEmpty => albums.isEmpty || totalCount <= 0;

  int get totalCount {
    var total = 0;
    for (final album in albums) {
      total += album.totalCount;
    }
    return total;
  }
}

class _IncrementalAlbumState {
  _IncrementalAlbumState({required this.album, required this.totalCount});

  final AssetPathEntity album;
  final int totalCount;
  int offset = 0;
  bool exhausted = false;
}
