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
  static List<AssetEntity> _cachedAssets = <AssetEntity>[];
  static List<File> _cachedFiles = <File>[];
  static List<AndroidGrantedMediaReference> _cachedGrantedMedia =
      <AndroidGrantedMediaReference>[];
  static int _cachedTotalCount = -1;
  static String _cachedSelectionSignature = '';

  // ── 全量重建（clearCacheFirst 路径）────────────────────────────────
  Future<_PhotoRebuildPlan> prepareRebuild({int? maxAssets}) async {
    final totalBefore = _service._photoBox.count();
    final prepared = await _prepareScan(maxAssets: maxAssets);
    final filterProfile = await _resolveFilterProfile();

    final built = await _service._buildPhotoEntities(
      prepared.assets,
      skipExisting: false,
      filterProfile: filterProfile,
      resolveFile: true,
    );
    final fileResults = await Future.wait(
      prepared.files.map(
        (file) =>
            _service._buildSingleFilePhoto(file, filterProfile: filterProfile),
      ),
    );
    final grantedMediaResults = await Future.wait(
      prepared.grantedMedia.map(
        (media) => _service._buildSingleGrantedMediaPhoto(
          media,
          filterProfile: filterProfile,
        ),
      ),
    );
    final allPhotos = <PhotoEntity>[
      ...built.photos,
      ...fileResults.map((result) => result.photo).whereType<PhotoEntity>(),
      ...grantedMediaResults
          .map((result) => result.photo)
          .whereType<PhotoEntity>(),
    ];
    var fileStats = _ScanStats();
    for (final result in fileResults) {
      fileStats = fileStats.merge(result);
    }
    var grantedMediaStats = _ScanStats();
    for (final result in grantedMediaResults) {
      grantedMediaStats = grantedMediaStats.merge(result);
    }
    final mergedBuilt = _ScanBuildResult(
      photos: allPhotos,
      insertedCount: allPhotos.length,
      insertedNoGps:
          built.insertedNoGps +
          fileStats.insertedNoGps +
          grantedMediaStats.insertedNoGps,
      skippedInvalidTime:
          built.skippedInvalidTime +
          fileStats.skippedInvalidTime +
          grantedMediaStats.skippedInvalidTime,
      skippedNonCamera:
          built.skippedNonCamera +
          fileStats.skippedNonCamera +
          grantedMediaStats.skippedNonCamera,
      skippedScreenshot:
          built.skippedScreenshot +
          fileStats.skippedScreenshot +
          grantedMediaStats.skippedScreenshot,
    );
    if (mergedBuilt.photos.isEmpty) {
      throw const PhotoScanException(
        PhotoScanError.noEligiblePhoto,
        'No eligible photos were found. Please add photos or videos from system picker first.',
      );
    }

    debugPrint(
      maxAssets == null
          ? '全量重建完成: fetch=${prepared.fetchCount} 入库=${mergedBuilt.insertedCount}'
          : '部分重建完成: fetch=${prepared.fetchCount} 入库=${mergedBuilt.insertedCount}',
    );
    return _PhotoRebuildPlan(
      totalBefore: totalBefore,
      prepared: prepared,
      built: mergedBuilt,
    );
  }

  // ── 增量扫描：收集 [maxAssets] 张新照片后停止 ─────────────────────
  Future<_PhotoSyncPlan> prepareIncremental({
    int? maxAssets,
    int offsetFromNewest = 0,
    ValueChanged<BatchScanProgress>? onProgress,
  }) async {
    final totalBefore = _service._photoBox.count();

    final albumBundle = await _resolveAlbums(runCleanupOnce: totalBefore <= 0);
    if (albumBundle.isEmpty || _cachedTotalCount <= 0) {
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

    final filterProfile = PhotoScanFilterProfile.userSelectedAlbums;

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

    for (
      var cursor = 0;
      collectedPhotos.length < targetNew && cursor < albumBundle.totalLength;
      cursor += pageSize
    ) {
      final end = math.max(
        0,
        math.min(albumBundle.totalLength, cursor + pageSize),
      );
      final assets = albumBundle.assets.length > cursor
          ? albumBundle.assets.sublist(
              cursor,
              math.min(end, albumBundle.assets.length),
            )
          : const <AssetEntity>[];
      final fileStart = math.max(0, cursor - albumBundle.assets.length);
      final fileEnd = math.max(0, end - albumBundle.assets.length);
      final files = fileStart < albumBundle.files.length
          ? albumBundle.files.sublist(
              fileStart,
              math.min(fileEnd, albumBundle.files.length),
            )
          : const <File>[];
      final mediaStart = math.max(
        0,
        cursor - albumBundle.assets.length - albumBundle.files.length,
      );
      final mediaEnd = math.max(
        0,
        end - albumBundle.assets.length - albumBundle.files.length,
      );
      final grantedMedia = mediaStart < albumBundle.grantedMedia.length
          ? albumBundle.grantedMedia.sublist(
              mediaStart,
              math.min(mediaEnd, albumBundle.grantedMedia.length),
            )
          : const <AndroidGrantedMediaReference>[];
      if (assets.isEmpty && files.isEmpty && grantedMedia.isEmpty) break;
      totalScanned += assets.length + files.length + grantedMedia.length;

      // 批量过滤已存在
      final skipIds = _existingAssetIdSet(assets);
      final newAssets = <AssetEntity>[];
      for (final asset in assets) {
        if (!skipIds.contains(asset.id)) newAssets.add(asset);
      }
      final skipFileIds = _existingFileIdSet(files);
      final newFiles = <File>[];
      for (final file in files) {
        if (!skipFileIds.contains('file:${file.path}')) newFiles.add(file);
      }
      final skipGrantedMediaIds = _existingGrantedMediaIdSet(grantedMedia);
      final newGrantedMedia = <AndroidGrantedMediaReference>[];
      for (final media in grantedMedia) {
        if (!skipGrantedMediaIds.contains('document:${media.uri}')) {
          newGrantedMedia.add(media);
        }
      }
      if (newAssets.isEmpty && newFiles.isEmpty && newGrantedMedia.isEmpty) {
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

      var remainingSlots = targetNew - collectedPhotos.length;
      final buildAssets = newAssets.length > remainingSlots
          ? newAssets.take(remainingSlots).toList(growable: false)
          : newAssets;
      remainingSlots -= buildAssets.length;
      final buildFiles = newFiles.length > remainingSlots
          ? newFiles.take(remainingSlots).toList(growable: false)
          : newFiles;
      remainingSlots -= buildFiles.length;
      final buildGrantedMedia = newGrantedMedia.length > remainingSlots
          ? newGrantedMedia.take(remainingSlots).toList(growable: false)
          : newGrantedMedia;
      candidateCount +=
          buildAssets.length + buildFiles.length + buildGrantedMedia.length;
      onProgress?.call(
        BatchScanProgress(
          scannedCount: totalScanned,
          candidateCount: candidateCount,
          acceptedCount: collectedPhotos.length,
          totalCount: _cachedTotalCount,
          targetNew: targetNew,
        ),
      );

      // 并行构建（扫描阶段跳过 file 解析，GPS 从缓存读取）
      final results = await Future.wait(<Future<_SingleAssetBuildResult>>[
        ...buildAssets.map(
          (a) => _service._buildSingleAssetPhoto(
            a,
            filterProfile: filterProfile,
            resolveFile: false,
          ),
        ),
        ...buildFiles.map(
          (f) =>
              _service._buildSingleFilePhoto(f, filterProfile: filterProfile),
        ),
        ...buildGrantedMedia.map(
          (media) => _service._buildSingleGrantedMediaPhoto(
            media,
            filterProfile: filterProfile,
          ),
        ),
      ]);
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
        files: const [],
        grantedMedia: const [],
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
    final snapshot = await MediaAccessGrantService.instance.loadSnapshot();
    final selectionSignature = _signatureForSnapshot(snapshot);
    if (!forceRefresh &&
        (_cachedAssets.isNotEmpty ||
            _cachedFiles.isNotEmpty ||
            _cachedGrantedMedia.isNotEmpty) &&
        _cachedTotalCount >= 0 &&
        _cachedSelectionSignature == selectionSignature) {
      _cachedTotalCount =
          _cachedAssets.length +
          _cachedFiles.length +
          _cachedGrantedMedia.length;
      return _AlbumBundle(
        assets: _cachedAssets,
        files: _cachedFiles,
        grantedMedia: _cachedGrantedMedia,
        isUserSelection: true,
      );
    }

    if (snapshot.selectedAssetIds.isEmpty &&
        snapshot.selectedFilePaths.isEmpty &&
        snapshot.androidTreeUris.isEmpty) {
      return const _AlbumBundle(
        assets: <AssetEntity>[],
        files: <File>[],
        grantedMedia: <AndroidGrantedMediaReference>[],
        isUserSelection: true,
      );
    }

    // ★ BATCH 方式：用 getAssetListRange 批量获取照片，避免 N 次 ContentResolver 查询
    final assets = <AssetEntity>[];
    final selectedIds = snapshot.selectedAssetIds;
    if (selectedIds.isNotEmpty) {
      try {
        final albums = await PhotoManager.getAssetPathList(
          onlyAll: true,
          type: RequestType.common,
        );
        if (albums.isNotEmpty) {
          final allAlbum = albums.first;
          final total = await allAlbum.assetCountAsync;
          const batchPageSize = 1000;
          final idSet = selectedIds.toSet();
          for (var offset = 0; offset < total; offset += batchPageSize) {
            final end = offset + batchPageSize > total
                ? total
                : offset + batchPageSize;
            final page = await allAlbum.getAssetListRange(
              start: offset,
              end: end,
            );
            for (final asset in page) {
              if (idSet.contains(asset.id)) {
                assets.add(asset);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('批量解析失败，回退到逐张解析: $e');
        for (final assetId in selectedIds) {
          final asset = await AssetEntity.fromId(assetId);
          if (asset != null) assets.add(asset);
        }
      }
    }
    assets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    final files = <File>[];
    for (final path in snapshot.selectedFilePaths) {
      final file = File(path);
      if (await file.exists()) {
        files.add(file);
      }
    }
    final grantedMedia = await MediaAccessGrantService.instance
        .listAndroidGrantedMedia(snapshot: snapshot, limit: 2000);

    _cachedAssets = assets;
    _cachedFiles = files;
    _cachedGrantedMedia = grantedMedia;
    _cachedTotalCount = assets.length + files.length + grantedMedia.length;
    _cachedSelectionSignature = selectionSignature;

    if (runCleanupOnce) {
      // session 首次运行：清理一次已删除照片
      _service._removeUnavailablePhotos().ignore();
    }

    return _AlbumBundle(
      assets: assets,
      files: files,
      grantedMedia: grantedMedia,
      isUserSelection: true,
    );
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

  Set<String> _existingFileIdSet(List<File> files) {
    final ids = files
        .map((file) => 'file:${file.path}')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return {};

    final q = _service._photoBox.query(PhotoEntity_.assetId.oneOf(ids)).build();
    final existing = q.find().map((e) => e.assetId).toSet();
    q.close();
    return existing;
  }

  Set<String> _existingGrantedMediaIdSet(
    List<AndroidGrantedMediaReference> media,
  ) {
    final ids = media
        .map((item) => 'document:${item.uri}')
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
        files: const [],
        grantedMedia: const [],
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
    final remaining = math.max(0, fetchCount - assets.length);
    final files = albumBundle.files.length > remaining
        ? albumBundle.files.take(remaining).toList(growable: false)
        : albumBundle.files;
    final remainingAfterFiles = math.max(0, remaining - files.length);
    final grantedMedia = albumBundle.grantedMedia.length > remainingAfterFiles
        ? albumBundle.grantedMedia
              .take(remainingAfterFiles)
              .toList(growable: false)
        : albumBundle.grantedMedia;
    return _PreparedScanData(
      assets: assets,
      files: files,
      grantedMedia: grantedMedia,
      totalCount: count,
      fetchCount: assets.length + files.length + grantedMedia.length,
      startOffset: 0,
    );
  }

  Future<PhotoScanFilterProfile> _resolveFilterProfile() async {
    final prefs = await AlbumSelectionPreferenceService().loadScanPreferences();
    final accessSnapshot = await MediaAccessGrantService.instance
        .loadSnapshot();
    int? minTs;
    if (prefs['minYear'] != null) {
      final y = prefs['minYear']!;
      minTs = DateTime(y, 1, 1).millisecondsSinceEpoch;
    }
    final minW =
        prefs['minWidth'] ?? (accessSnapshot.excludeSmallMedia ? 512 : null);
    final minH =
        prefs['minHeight'] ?? (accessSnapshot.excludeSmallMedia ? 512 : null);
    const base = PhotoScanFilterProfile.userSelectedAlbums;
    return PhotoScanFilterProfile(
      requireValidDimensions: base.requireValidDimensions,
      minTimestampMs: minTs,
      minWidth: minW,
      minHeight: minH,
    );
  }

  String _signatureForSnapshot(MediaAccessGrantSnapshot snapshot) {
    final sortedAssetIds = snapshot.selectedAssetIds.toList()..sort();
    final sortedFilePaths = snapshot.selectedFilePaths.toList()..sort();
    final sortedTreeUris = snapshot.androidTreeUris.toList()..sort();
    final disabled = snapshot.disabledAutoSourceIds.toList()..sort();
    final withoutChildren = snapshot.sourcesWithoutChildren.toList()..sort();
    final mediaTypes = snapshot.excludedMediaTypes.toList()..sort();
    return 'assets:${sortedAssetIds.join(',')}'
        '|files:${sortedFilePaths.join(',')}'
        '|trees:${sortedTreeUris.join(',')}'
        '|included:${_encodePathRules(snapshot.includedSubpathsBySource)}'
        '|excluded:${_encodePathRules(snapshot.excludedSubpathsBySource)}'
        '|disabled:${disabled.join(',')}'
        '|flat:${withoutChildren.join(',')}'
        '|rules:${snapshot.excludeScreenshots},${snapshot.excludeScreenRecordings},${snapshot.excludeSmallMedia},${snapshot.excludeDuplicates},${mediaTypes.join(',')}';
  }

  String _encodePathRules(Map<String, List<String>> rules) {
    final sourceIds = rules.keys.toList()..sort();
    return sourceIds
        .map((sourceId) {
          final subpaths = (rules[sourceId] ?? const <String>[]).toList();
          subpaths.sort();
          return '$sourceId=${subpaths.join(';')}';
        })
        .join('|');
  }

  _PhotoSyncPlan _emptyPlan(int totalBefore) {
    return _PhotoSyncPlan(
      totalBefore: totalBefore,
      removedCount: 0,
      prepared: _PreparedScanData(
        assets: const [],
        files: const [],
        grantedMedia: const [],
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
    required this.assets,
    required this.files,
    required this.grantedMedia,
    required this.isUserSelection,
  });

  final List<AssetEntity> assets;
  final List<File> files;
  final List<AndroidGrantedMediaReference> grantedMedia;
  final bool isUserSelection;

  bool get isEmpty => assets.isEmpty && files.isEmpty && grantedMedia.isEmpty;
  int get totalLength => assets.length + files.length + grantedMedia.length;
}
