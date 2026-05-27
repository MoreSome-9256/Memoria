/// 照片扫描协调器 — 高效批量发现系统相册中的新照片。
///
/// 核心策略：
///   1. 缓存系统相册清单，session 内只获取一次
///   2. 小批量分页（50张/页），从最新开始遍历
///   3. 每页查询 ObjectBox 批量过滤已存在的 assetId
///   4. 对真正新增的照片并行构建实体
///   5. 收集到目标数量后立即停止（stop-early）
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
      resolveFile: true,
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

  // ── 增量扫描：收集 [maxAssets] 张新照片后停止 ─────────────────────
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

    final targetNew = maxAssets == null ? null : math.max(1, maxAssets);
    final progressTarget = targetNew ?? scanSource.totalCount;
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
        totalCount: scanSource.totalCount,
        targetNew: progressTarget,
      ),
    );

    await for (final assets in _incrementalAssetPages(
      scanSource,
      pageSize: pageSize,
      offsetFromNewest: offsetFromNewest,
    )) {
      if (targetNew != null && collectedPhotos.length >= targetNew) break;
      if (assets.isEmpty) break;
      totalScanned += assets.length;

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
            totalCount: scanSource.totalCount,
            targetNew: progressTarget,
          ),
        );
        continue;
      }

      final buildAssets = newAssets;
      candidateCount += buildAssets.length;
      onProgress?.call(
        BatchScanProgress(
          scannedCount: totalScanned,
          candidateCount: candidateCount,
          acceptedCount: collectedPhotos.length,
          totalCount: scanSource.totalCount,
          targetNew: progressTarget,
        ),
      );

      // 并行构建（扫描阶段跳过 file 解析，GPS 从缓存读取）
      final results = await Future.wait(
        buildAssets.map(
          (a) => _service._buildSingleAssetPhoto(
            a,
            filterProfile: filterProfile,
            resolveFile: false,
          ),
        ),
      );
      for (final r in results) {
        if (r.photo != null) {
          if (targetNew == null || collectedPhotos.length < targetNew) {
            collectedPhotos.add(r.photo!);
            stats = stats.merge(r);
          }
          continue;
        } else {
          stats = stats.merge(r);
        }
      }
      onProgress?.call(
        BatchScanProgress(
          scannedCount: totalScanned,
          candidateCount: candidateCount,
          acceptedCount: collectedPhotos.length,
          totalCount: scanSource.totalCount,
          targetNew: progressTarget,
        ),
      );
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
      'nonCam=${stats.skippedNonCamera} ss=${stats.skippedScreenshot} '
      'small=${stats.skippedSmallResolution} '
      'wide=${stats.skippedExtremeAspectRatio}',
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
      final allAlbums = await PhotoManager.getAssetPathList(type: requestType);
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
      for (
        var offset = math.max(0, offsetFromNewest);
        offset < state.totalCount;
        offset += pageSize
      ) {
        final end = math.min(state.totalCount, offset + pageSize);
        final page = await state.album.getAssetListRange(
          start: offset,
          end: end,
        );
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
        final end = math.min(state.totalCount, state.offset + pageSize);
        final page = await state.album.getAssetListRange(
          start: state.offset,
          end: end,
        );
        state.offset = end;
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
    final allAlbums = await PhotoManager.getAssetPathList(type: requestType);
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
      for (var offset = 0; offset < count; offset += pageSize) {
        final end = math.min(count, offset + pageSize);
        final page = await album.getAssetListRange(start: offset, end: end);
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

  /// 回退路径：加载系统全部照片（用户未选择特定相册时）。
  Future<_AlbumBundle> _resolveAllAlbums(
    RequestType requestType,
    bool runCleanupOnce,
    bool forceRefresh,
  ) async {
    final albums = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: requestType,
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
    for (var offset = 0; offset < total; offset += batchPageSize) {
      final end = math.min(total, offset + batchPageSize);
      final page = await allAlbum.getAssetListRange(start: offset, end: end);
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

  // ── 批量查 ObjectBox，返回已存在的 assetId 集合 ──────────────────
  Set<String> _existingAssetIdSet(List<AssetEntity> assets) {
    final ids = assets
        .map((a) => a.id)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return {};

    final q = _service._photoBox.query(PhotoEntity_.assetId.oneOf(ids)).build();
    final existing = q.find().map((e) => e.assetId).toSet();
    q.close();
    return existing;
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
      excludeExtremeAspectRatios: prefs.excludeExtremeAspectRatios,
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
    this.skippedExtremeAspectRatio = 0,
  });

  final int insertedNoGps;
  final int skippedInvalidTime;
  final int skippedNonCamera;
  final int skippedScreenshot;
  final int skippedSmallResolution;
  final int skippedExtremeAspectRatio;

  _ScanStats merge(_SingleAssetBuildResult r) => _ScanStats(
    insertedNoGps: insertedNoGps + r.insertedNoGps,
    skippedInvalidTime: skippedInvalidTime + r.skippedInvalidTime,
    skippedNonCamera: skippedNonCamera + r.skippedNonCamera,
    skippedScreenshot: skippedScreenshot + r.skippedScreenshot,
    skippedSmallResolution: skippedSmallResolution + r.skippedSmallResolution,
    skippedExtremeAspectRatio:
        skippedExtremeAspectRatio + r.skippedExtremeAspectRatio,
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
