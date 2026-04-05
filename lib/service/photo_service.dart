import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/entity/face_entity.dart';
import '../models/entity/digital_album_book_entity.dart';
import '../models/entity/photo_entity.dart';
import '../models/entity/event_entity.dart';
import '../models/entity/story_entity.dart';
import '../storage/vector_index/face_embedding_index_repository.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../data/tag_taxonomy_v2.dart';
import '../service/junk_photo_filter_service.dart';
import '../utils/photo_filter_helper.dart';

class _PreparedScanData {
  const _PreparedScanData({
    required this.assets,
    required this.totalCount,
    required this.fetchCount,
    required this.startOffset,
  });

  final List<AssetEntity> assets;
  final int totalCount;
  final int fetchCount;
  final int startOffset;
}

class _ScanBuildResult {
  const _ScanBuildResult({
    required this.photos,
    required this.insertedCount,
    required this.insertedNoGps,
    required this.skippedInvalidTime,
    required this.skippedNonCamera,
    required this.skippedScreenshot,
  });

  final List<PhotoEntity> photos;
  final int insertedCount;
  final int insertedNoGps;
  final int skippedInvalidTime;
  final int skippedNonCamera;
  final int skippedScreenshot;
}

class _SingleAssetBuildResult {
  const _SingleAssetBuildResult({
    this.photo,
    this.insertedNoGps = 0,
    this.skippedInvalidTime = 0,
    this.skippedNonCamera = 0,
    this.skippedScreenshot = 0,
  });

  final PhotoEntity? photo;
  final int insertedNoGps;
  final int skippedInvalidTime;
  final int skippedNonCamera;
  final int skippedScreenshot;
}

class _PhotoAccessCacheEntry {
  const _PhotoAccessCacheEntry({
    required this.checkedAtMs,
    this.resolvedPath,
    this.isRemoved = false,
  });

  final int checkedAtMs;
  final String? resolvedPath;
  final bool isRemoved;
}

class PhotoService {
  late Isar _isar;
  bool _isInitialized = false;
  static const bool _verboseAssetLogging = false;
  static const int _assetExistenceWorkerCount = 12;
  static const int _assetBuildWorkerCount = 8;
  static const Duration _photoAccessCacheTtl = Duration(seconds: 20);

  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  // 私有构造函数
  PhotoService._internal();
  final PhotoEmbeddingIndexRepository _photoEmbeddingIndexRepository =
      PhotoEmbeddingIndexRepository();
  final FaceEmbeddingIndexRepository _faceEmbeddingIndexRepository =
      FaceEmbeddingIndexRepository();
  final Map<String, _PhotoAccessCacheEntry> _photoAccessCache =
      <String, _PhotoAccessCacheEntry>{};

  // 暴露 isar 实例供其他服务使用
  Isar get isar => _isar;

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [
        PhotoEntitySchema,
        FaceEntitySchema,
        EventEntitySchema,
        StoryEntitySchema,
        DigitalAlbumBookEntitySchema,
      ], // 注册所有实体
      directory: dir.path,
    );
    _isInitialized = true;
  }

  Future<void> clearAllCachedData() async {
    await _isar.writeTxn(() async {
      await _isar.collection<DigitalAlbumBookEntity>().clear();
      await _isar.collection<StoryEntity>().clear();
      await _isar.collection<EventEntity>().clear();
      await _isar.collection<FaceEntity>().clear();
      await _isar.collection<PhotoEntity>().clear();
    });
    _photoAccessCache.clear();
    _photoEmbeddingIndexRepository.deleteAll();
    _faceEmbeddingIndexRepository.deleteAll();

    print("🗑️ 已清空 Isar 缓存数据（照片/事件/故事）");
  }

  Future<PhotoScanSummary> rebuildAllCachedData({int? maxAssets}) async {
    final totalBefore = await _isar.collection<PhotoEntity>().count();
    final prepared = await _prepareScan(maxAssets: maxAssets);

    print(
      maxAssets == null
          ? "🧱 开始安全重建相册缓存（全量）..."
          : "🧱 开始安全重建相册缓存（最近 ${prepared.fetchCount} / ${prepared.totalCount} 张）...",
    );

    final built = await _buildPhotoEntities(
      prepared.assets,
      skipExisting: false,
    );

    if (built.photos.isEmpty) {
      throw const PhotoScanException(
        PhotoScanError.noEligiblePhoto,
        '未找到可用照片：请确认相册中存在包含有效时间的相机图片资源。',
      );
    }

    await _isar.writeTxn(() async {
      await _isar.collection<DigitalAlbumBookEntity>().clear();
      await _isar.collection<StoryEntity>().clear();
      await _isar.collection<EventEntity>().clear();
      await _isar.collection<FaceEntity>().clear();
      await _isar.collection<PhotoEntity>().clear();
      await _isar.collection<PhotoEntity>().putAll(built.photos);
    });
    _photoAccessCache.clear();
    _photoEmbeddingIndexRepository.deleteAll();
    _faceEmbeddingIndexRepository.deleteAll();

    print(
      "✅ 安全重建完成: 清空旧数据=$totalBefore 入库=${built.insertedCount} 无GPS=${built.insertedNoGps} 跳过[无时间=${built.skippedInvalidTime} 非相机=${built.skippedNonCamera} 截图=${built.skippedScreenshot}]",
    );

    return PhotoScanSummary(
      totalBefore: totalBefore,
      totalAfter: built.insertedCount,
      removedCount: totalBefore,
      insertedCount: built.insertedCount,
      skippedInvalidTime: built.skippedInvalidTime,
      insertedNoGps: built.insertedNoGps,
      skippedNonCamera: built.skippedNonCamera,
      skippedScreenshot: built.skippedScreenshot,
    );
  }

  // 1️⃣ 扫描相册 (快速入库，带截图过滤)
  Future<PhotoScanSummary> scanAndSyncPhotos({int? maxAssets}) async {
    return scanAndSyncPhotosWithOffset(maxAssets: maxAssets);
  }

  Future<PhotoScanSummary> scanAndSyncPhotosWithOffset({
    int? maxAssets,
    int offsetFromNewest = 0,
  }) async {
    final totalBefore = await _isar.collection<PhotoEntity>().count();
    final prepared = await _prepareScan(
      maxAssets: maxAssets,
      offsetFromNewest: offsetFromNewest,
    );

    // 先做反向同步：清理系统相册已删除/已不可访问的照片
    final removedCount = await _removeUnavailablePhotos();

    print(
      maxAssets == null
          ? "🚀 开始扫描相册（全量）..."
          : "🚀 开始扫描相册（最近 ${prepared.fetchCount} / ${prepared.totalCount} 张）...",
    );
    final built = await _buildPhotoEntities(
      prepared.assets,
      skipExisting: true,
    );

    var insertedPhotoIds = const <int>[];
    if (built.photos.isNotEmpty) {
      late final List<int> storedIds;
      await _isar.writeTxn(() async {
        storedIds = await _isar.collection<PhotoEntity>().putAll(built.photos);
      });
      insertedPhotoIds = storedIds.where((id) => id > 0).toList(growable: false);
    }

    print(
      "✅ 基础数据同步完成: 删除=$removedCount 入库=${built.insertedCount} 其中无GPS入库=${built.insertedNoGps} 跳过[无时间=${built.skippedInvalidTime} 非相机=${built.skippedNonCamera} 截图=${built.skippedScreenshot}]",
    );

    final totalAfter = await _isar.collection<PhotoEntity>().count();
    if (totalAfter == 0) {
      throw const PhotoScanException(
        PhotoScanError.noEligiblePhoto,
        '未找到可用照片：请确认相册中存在包含有效时间的图片资源。',
      );
    }

    // AI 分析由上层流程在聚类后触发，确保 eventId 已建立
    return PhotoScanSummary(
      totalBefore: totalBefore,
      totalAfter: totalAfter,
      removedCount: removedCount,
      insertedCount: built.insertedCount,
      insertedPhotoIds: insertedPhotoIds,
      scanStartOffset: prepared.startOffset,
      scannedCount: prepared.fetchCount,
      skippedInvalidTime: built.skippedInvalidTime,
      insertedNoGps: built.insertedNoGps,
      skippedNonCamera: built.skippedNonCamera,
      skippedScreenshot: built.skippedScreenshot,
    );
  }

  Future<_PreparedScanData> _prepareScan({
    int? maxAssets,
    int offsetFromNewest = 0,
  }) async {
    if (Platform.isAndroid) {
      final photosStatus = await Permission.photos.request();
      print('📸 Android photos 权限请求结果: $photosStatus');

      final locationStatus = await Permission.accessMediaLocation.request();
      if (locationStatus.isGranted) {
        print("✅ 成功获得读取照片真实 GPS 的特权");
      } else {
        print("⚠️ 用户拒绝了位置特权，照片经纬度将被系统抹除为 null");
      }
    }

    final permissionState = await PhotoManager.requestPermissionExtend();
    final isLimited = permissionState == PermissionState.limited;
    print(
      '📸 相册权限状态: $permissionState isAuth=${permissionState.isAuth} hasAccess=${permissionState.hasAccess}',
    );
    if (!permissionState.isAuth && !permissionState.hasAccess) {
      throw const PhotoScanException(
        PhotoScanError.permissionDenied,
        '未获得相册访问权限，请在系统设置中允许访问照片。',
      );
    }
    // ==========================================
    // 🌟 核心修复：创建一个带有明确排序规则的过滤器
    // ==========================================
    final FilterOptionGroup safeFilter = FilterOptionGroup(
      orders: [
        const OrderOption(
          type: OrderOptionType.createDate,
          asc: false, // 强制按照创建时间倒序（最新的在前面）
        ),
      ],
    );

    return _prepareScanViaAllPhotosOrGlobal(
      safeFilter: safeFilter,
      isLimited: isLimited,
      maxAssets: maxAssets,
      offsetFromNewest: offsetFromNewest,
    );

    /* final preferredAlbums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: safeFilter,
    );
    var albums = preferredAlbums;
    // onlyAll=true 在部分 ROM / 授权模式下可能返回空或空壳相册，降级到全量列表取图片最多的相册
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
      print('📂 相册 [${album.name}] 内有 $count 张图片');
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
        print('📂 兜底相册 [${album.name}] 内有 $count 张图片');
        if (count > selectedCount) {
          selectedAlbum = album;
          selectedCount = count;
        }
      }
    }

    if (albums.isEmpty || selectedAlbum == null || selectedCount <= 0) {
      print('⚠️ 相册列表为空或全部为空壳，切换到全局媒体库扫描兜底');
      final fallback = await _prepareGlobalScan(maxAssets: maxAssets);
      if (fallback.assets.isNotEmpty) {
        return fallback;
      }

      if (isLimited) {
        throw const PhotoScanException(
          PhotoScanError.permissionDenied,
          '当前系统仅授予了“部分照片”权限，且已授权列表为空。请到系统设置将照片权限改为「允许所有照片」，或先在系统权限面板中勾选至少一张照片后重试。',
        );
      }

      throw const PhotoScanException(
        PhotoScanError.noAlbum,
        '未找到可读取的相册。请确认系统照片权限已授予，并检查系统相册中是否存在图片。',
      );
    }

    print('✅ 本次扫描选中相册: ${selectedAlbum.name} ($selectedCount 张)');
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
    ); */
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
        print('All-photos album [${album.name}] count=$count');
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
      maxAssets: maxAssets,
      offsetFromNewest: offsetFromNewest,
      safeFilter: safeFilter,
    );
    if (fallback.assets.isNotEmpty) {
      return fallback;
    }

    if (isLimited) {
      throw const PhotoScanException(
        PhotoScanError.permissionDenied,
        '当前系统仅授予了“部分照片”权限，且授权列表为空。请到系统设置将照片权限改为“允许所有照片”，或先在系统权限面板中勾选至少一张照片后重试。',
      );
    }

    throw const PhotoScanException(
      PhotoScanError.noAlbum,
      '未找到可读取的相册。请确认系统照片权限已授予，并检查系统相册中是否存在图片。',
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

  // ignore: unused_element
  Future<_PreparedScanData> _prepareGlobalScanLegacy({int? maxAssets}) async {
    const pageSize = 200;
    final assets = <AssetEntity>[];
    var page = 0;

    // ==========================================
    // 🌟 核心修复：定义明确的排序规则，填补 SQL 语句的空白
    // ==========================================
    final FilterOptionGroup safeFilter = FilterOptionGroup(
      orders: [
        const OrderOption(
          type: OrderOptionType.createDate,
          asc: false, // 强制按照创建时间倒序（最新的在前面）
        ),
      ],
    );

    while (true) {
      final remaining = maxAssets == null
          ? pageSize
          : maxAssets - assets.length;
      if (remaining <= 0) {
        break;
      }

      // 🌟 修复点：强制传入 filterOption
      final batch = await PhotoManager.getAssetListPaged(
        page: page,
        pageCount: remaining < pageSize ? remaining : pageSize,
        type: RequestType.image,
        filterOption: safeFilter, // 👈 补丁打在这里！
      );
      print('🧰 全局媒体库第 ${page + 1} 页返回 ${batch.length} 张图片');

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

    print('✅ 全局媒体库兜底共拿到 ${assets.length} 张图片');
    return _PreparedScanData(
      assets: assets,
      totalCount: assets.length,
      fetchCount: assets.length,
      startOffset: 0,
    );
  }

  Future<_ScanBuildResult> _buildPhotoEntities(
    List<AssetEntity> assets, {
    required bool skipExisting,
  }) async {
    final existingAssetIds = <String>{};
    final existingPhotosByAssetId = <String, PhotoEntity>{};
    final buildResults = <_SingleAssetBuildResult>[];
    final refreshedExistingPhotos = <PhotoEntity>[];

    if (skipExisting && assets.isNotEmpty) {
      final assetIdsToCheck = assets
          .map((asset) => asset.id)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (assetIdsToCheck.isNotEmpty) {
        final existingPhotos = await _isar
            .collection<PhotoEntity>()
            .filter()
            .anyOf(
              assetIdsToCheck,
              (query, assetId) => query.assetIdEqualTo(assetId),
            )
            .findAll();
        existingAssetIds.addAll(
          existingPhotos
              .map((photo) => photo.assetId)
              .where((id) => id.isNotEmpty),
        );
        for (final photo in existingPhotos) {
          if (photo.assetId.isNotEmpty) {
            existingPhotosByAssetId[photo.assetId] = photo;
          }
        }
      }
    }

    if (assets.isNotEmpty) {
      var cursor = 0;
      final workerCount = math.min(_assetBuildWorkerCount, assets.length);
      final workers = List<Future<void>>.generate(workerCount, (_) async {
        while (true) {
          final index = cursor;
          cursor++;
          if (index >= assets.length) {
            break;
          }

          final asset = assets[index];
          if (skipExisting && existingAssetIds.contains(asset.id)) {
            final existingPhoto = existingPhotosByAssetId[asset.id];
            if (existingPhoto != null) {
              final refreshed = await _refreshExistingPhotoFromAsset(
                existingPhoto,
                asset,
              );
              if (refreshed != null) {
                refreshedExistingPhotos.add(refreshed);
              }
            }
            continue;
          }

          final result = await _buildSingleAssetPhoto(asset);
          buildResults.add(result);
        }
      });

      await Future.wait(workers);
    }

    final photos = buildResults
        .map((item) => item.photo)
        .whereType<PhotoEntity>()
        .toList(growable: false);
    final insertedNoGps = buildResults.fold<int>(
      0,
      (sum, item) => sum + item.insertedNoGps,
    );
    final skippedInvalidTime = buildResults.fold<int>(
      0,
      (sum, item) => sum + item.skippedInvalidTime,
    );
    final skippedNonCamera = buildResults.fold<int>(
      0,
      (sum, item) => sum + item.skippedNonCamera,
    );
    final skippedScreenshot = buildResults.fold<int>(
      0,
      (sum, item) => sum + item.skippedScreenshot,
    );

    if (refreshedExistingPhotos.isNotEmpty) {
      await _isar.writeTxn(() async {
        await _isar.collection<PhotoEntity>().putAll(refreshedExistingPhotos);
      });
    }

    return _ScanBuildResult(
      photos: photos,
      insertedCount: photos.length,
      insertedNoGps: insertedNoGps,
      skippedInvalidTime: skippedInvalidTime,
      skippedNonCamera: skippedNonCamera,
      skippedScreenshot: skippedScreenshot,
    );
  }

  Future<PhotoEntity?> _refreshExistingPhotoFromAsset(
    PhotoEntity existingPhoto,
    AssetEntity asset,
  ) async {
    final file = await _resolveReadableFile(asset);
    if (file == null) {
      return null;
    }

    final refreshedTimestamp = _resolveBestTimestampMs(asset, file);
    final refreshedWidth = asset.width;
    final refreshedHeight = asset.height;

    var changed = false;
    if (PhotoFilterHelper.hasValidTimestamp(refreshedTimestamp) &&
        existingPhoto.timestamp != refreshedTimestamp) {
      existingPhoto.timestamp = refreshedTimestamp;
      changed = true;
    }
    if (file.path.isNotEmpty && existingPhoto.path != file.path) {
      existingPhoto.path = file.path;
      changed = true;
    }
    if (refreshedWidth > 0 && existingPhoto.width != refreshedWidth) {
      existingPhoto.width = refreshedWidth;
      changed = true;
    }
    if (refreshedHeight > 0 && existingPhoto.height != refreshedHeight) {
      existingPhoto.height = refreshedHeight;
      changed = true;
    }

    if (!changed) {
      return null;
    }
    return existingPhoto;
  }

  Future<_SingleAssetBuildResult> _buildSingleAssetPhoto(
    AssetEntity asset,
  ) async {
    final file = await _resolveReadableFile(asset);
    if (file == null) {
      print('⚠️ 资源无法解析为本地文件: assetId=${asset.id} title=${asset.title}');
      return const _SingleAssetBuildResult(skippedNonCamera: 1);
    }

    final width = asset.width;
    final height = asset.height;
    if (width <= 0 || height <= 0) {
      return const _SingleAssetBuildResult(skippedNonCamera: 1);
    }

    final screenshotByRatio = PhotoFilterHelper.isLikelyScreenshotByRatio(
      width,
      height,
    );
    final likelyCameraPhoto = PhotoFilterHelper.isLikelyCameraPhoto(file.path);

    var skippedScreenshot = 0;
    var skippedNonCamera = 0;
    if (screenshotByRatio) {
      skippedScreenshot = 1;
      // continue;
    }
    if (!likelyCameraPhoto) {
      skippedNonCamera = 1;
      // continue;
    }

    final shouldResolveGps = !screenshotByRatio && likelyCameraPhoto;
    final latLong = shouldResolveGps ? await asset.latlngAsync() : null;
    if (_verboseAssetLogging) {
      _logAssetExtInfo(asset: asset, filePath: file.path, latLong: latLong);
    }

    final timestamp = _resolveBestTimestampMs(asset, file);
    if (!PhotoFilterHelper.hasValidTimestamp(timestamp)) {
      return _SingleAssetBuildResult(
        skippedInvalidTime: 1,
        skippedNonCamera: skippedNonCamera,
        skippedScreenshot: skippedScreenshot,
      );
    }

    final hasGps = PhotoFilterHelper.hasValidGps(
      latLong?.latitude,
      latLong?.longitude,
    );
    final newPhoto = PhotoEntity()
      ..assetId = asset.id
      ..timestamp = timestamp
      ..path = file.path
      ..width = width
      ..height = height
      ..latitude = hasGps ? latLong!.latitude : null
      ..longitude = hasGps ? latLong!.longitude : null
      ..isLocationProcessed = false;

    return _SingleAssetBuildResult(
      photo: newPhoto,
      insertedNoGps: hasGps ? 0 : 1,
      skippedNonCamera: skippedNonCamera,
      skippedScreenshot: skippedScreenshot,
    );
  }

  Future<File?> _resolveReadableFile(AssetEntity asset) async {
    final directFile = await asset.file;
    if (directFile != null && directFile.path.isNotEmpty) {
      return directFile;
    }

    final originFile = await asset.originFile;
    if (originFile != null && originFile.path.isNotEmpty) {
      print(
        'ℹ️ 资源使用 originFile 兜底: assetId=${asset.id} path=${originFile.path}',
      );
      return originFile;
    }

    return null;
  }

  void _logAssetExtInfo({
    required AssetEntity asset,
    required String? filePath,
    required LatLng? latLong,
  }) {
    final timestamp = asset.createDateTime.millisecondsSinceEpoch;
    final modified = asset.modifiedDateTime;
    final hasValidTime = PhotoFilterHelper.hasValidTimestamp(timestamp);
    final hasValidGps = PhotoFilterHelper.hasValidGps(
      latLong?.latitude,
      latLong?.longitude,
    );

    print(
      '🧾 [EXTINFO] id=${asset.id} file=${filePath ?? 'null'} '
      'time=${asset.createDateTime.toIso8601String()} modified=${modified.toIso8601String()} '
      'size=${asset.width}x${asset.height} '
      'lat=${latLong?.latitude.toStringAsFixed(6) ?? 'null'} '
      'lon=${latLong?.longitude.toStringAsFixed(6) ?? 'null'} '
      'validTime=$hasValidTime validGps=$hasValidGps',
    );
  }

  Future<int> _removeUnavailablePhotos() async {
    final localPhotos = await _isar.collection<PhotoEntity>().where().findAll();
    if (localPhotos.isEmpty) {
      return 0;
    }

    final removedIds = <int>[];
    final repairedPhotos = <PhotoEntity>[];
    var cursor = 0;
    final workerCount = math.min(
      _assetExistenceWorkerCount,
      localPhotos.length,
    );
    final workers = List<Future<void>>.generate(workerCount, (_) async {
      while (true) {
        final index = cursor;
        cursor++;
        if (index >= localPhotos.length) {
          break;
        }

        final photo = localPhotos[index];
        final asset = await AssetEntity.fromId(photo.assetId);
        if (asset == null) {
          removedIds.add(photo.id);
          continue;
        }

        final currentFile = photo.path.trim().isEmpty ? null : File(photo.path);
        if (currentFile != null && currentFile.existsSync()) {
          continue;
        }

        final refreshedFile = await _resolveReadableFile(asset);
        if (refreshedFile != null && refreshedFile.existsSync()) {
          photo.path = refreshedFile.path;
          final refreshedTimestamp = _resolveBestTimestampMs(asset, refreshedFile);
          if (PhotoFilterHelper.hasValidTimestamp(refreshedTimestamp)) {
            photo.timestamp = refreshedTimestamp;
          }
          repairedPhotos.add(photo);
        } else {
          removedIds.add(photo.id);
        }
      }
    });

    await Future.wait(workers);

    if (removedIds.isEmpty && repairedPhotos.isEmpty) {
      return 0;
    }

    await _isar.writeTxn(() async {
      if (removedIds.isNotEmpty) {
        await _isar.collection<PhotoEntity>().deleteAll(removedIds);
      }
      if (repairedPhotos.isNotEmpty) {
        await _isar.collection<PhotoEntity>().putAll(repairedPhotos);
      }
    });
    _photoEmbeddingIndexRepository.deleteByPhotoIds(removedIds);
    _faceEmbeddingIndexRepository.deleteByPhotoIds(removedIds);

    if (repairedPhotos.isNotEmpty) {
      print("🩹 已修复 ${repairedPhotos.length} 条失效照片路径");
    }

    print("🧹 已清理系统相册中删除/不可访问的照片: ${removedIds.length} 张");
    return removedIds.length;
  }

  int _resolveBestTimestampMs(AssetEntity asset, File file) {
    final createMs = asset.createDateTime.millisecondsSinceEpoch;
    final modifiedMs = asset.modifiedDateTime.millisecondsSinceEpoch;
    final fileNameMs = PhotoFilterHelper.extractTimestampFromFileName(file.path);

    final candidates = <int>[
      if (fileNameMs != null && PhotoFilterHelper.hasValidTimestamp(fileNameMs))
        fileNameMs,
      if (PhotoFilterHelper.hasValidTimestamp(createMs)) createMs,
      if (PhotoFilterHelper.hasValidTimestamp(modifiedMs)) modifiedMs,
    ]..sort();

    if (candidates.isEmpty) {
      return 0;
    }

    final resolved = candidates.first;
    if (_verboseAssetLogging) {
      final createIso = asset.createDateTime.toIso8601String();
      final modifiedIso = asset.modifiedDateTime.toIso8601String();
      final resolvedIso = DateTime.fromMillisecondsSinceEpoch(resolved)
          .toIso8601String();
      print(
        '🕒 解析拍摄时间 assetId=${asset.id} resolved=$resolvedIso create=$createIso modified=$modifiedIso file=${file.path}',
      );
    }
    return resolved;
  }

  // 📊 获取照片统计信息
  Future<List<PhotoEntity>> reconcileAccessiblePhotos(
    Iterable<PhotoEntity> photos,
  ) async {
    final candidates = photos.toList(growable: false);
    if (candidates.isEmpty) {
      return const <PhotoEntity>[];
    }

    final stopwatch = Stopwatch()..start();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final removedIds = <int>{};
    final repairedIds = <int>{};
    var cacheHits = 0;
    var removedCount = 0;
    var repairedCount = 0;
    var cursor = 0;
    final workerCount = math.min(_assetExistenceWorkerCount, candidates.length);
    final workers = List<Future<void>>.generate(workerCount, (_) async {
      while (true) {
        final index = cursor;
        cursor++;
        if (index >= candidates.length) {
          break;
        }

        final photo = candidates[index];
        final cacheKey = _photoAccessCacheKey(photo);
        final cacheEntry = _photoAccessCache[cacheKey];
        if (cacheEntry != null &&
            nowMs - cacheEntry.checkedAtMs <= _photoAccessCacheTtl.inMilliseconds) {
          cacheHits++;
          if (cacheEntry.isRemoved) {
            if (photo.id > 0) {
              removedIds.add(photo.id);
            }
            removedCount++;
            continue;
          }
          final resolvedPath = cacheEntry.resolvedPath;
          if (resolvedPath != null && resolvedPath.isNotEmpty) {
            photo.path = resolvedPath;
            continue;
          }
        }

        final currentFile = photo.path.trim().isEmpty ? null : File(photo.path);
        if (currentFile != null && currentFile.existsSync()) {
          _photoAccessCache[cacheKey] = _PhotoAccessCacheEntry(
            checkedAtMs: nowMs,
            resolvedPath: photo.path,
          );
          continue;
        }

        final asset = await AssetEntity.fromId(photo.assetId);
        if (asset == null) {
          if (photo.id > 0) {
            removedIds.add(photo.id);
          }
          _photoAccessCache[cacheKey] = _PhotoAccessCacheEntry(
            checkedAtMs: nowMs,
            isRemoved: true,
          );
          removedCount++;
          continue;
        }

        final refreshedFile = await _resolveReadableFile(asset);
        if (refreshedFile != null && refreshedFile.existsSync()) {
          if (photo.path != refreshedFile.path) {
            photo.path = refreshedFile.path;
            if (photo.id > 0) {
              repairedIds.add(photo.id);
            }
            repairedCount++;
          }
          _photoAccessCache[cacheKey] = _PhotoAccessCacheEntry(
            checkedAtMs: nowMs,
            resolvedPath: refreshedFile.path,
          );
        } else if (photo.id > 0) {
          removedIds.add(photo.id);
          _photoAccessCache[cacheKey] = _PhotoAccessCacheEntry(
            checkedAtMs: nowMs,
            isRemoved: true,
          );
          removedCount++;
        }
      }
    });

    await Future.wait(workers);

    final repairedPhotos = repairedIds.isEmpty
        ? const <PhotoEntity>[]
        : candidates
              .where((photo) => repairedIds.contains(photo.id))
              .toList(growable: false);
    final removedPhotoIds = removedIds.toList(growable: false);

    final staleFaces = removedPhotoIds.isEmpty
        ? const <FaceEntity>[]
        : await _isar
              .collection<FaceEntity>()
              .filter()
              .anyOf(
                removedPhotoIds,
                (query, photoId) => query.photoIdEqualTo(photoId),
              )
              .findAll();

    if (removedPhotoIds.isNotEmpty || repairedPhotos.isNotEmpty) {
      await _isar.writeTxn(() async {
        if (staleFaces.isNotEmpty) {
          await _isar.collection<FaceEntity>().deleteAll(
            staleFaces.map((item) => item.id).toList(growable: false),
          );
        }
        if (removedPhotoIds.isNotEmpty) {
          await _isar.collection<PhotoEntity>().deleteAll(removedPhotoIds);
        }
        if (repairedPhotos.isNotEmpty) {
          await _isar.collection<PhotoEntity>().putAll(repairedPhotos);
        }
      });
    }

    if (removedPhotoIds.isNotEmpty) {
      _photoEmbeddingIndexRepository.deleteByPhotoIds(removedPhotoIds);
      _faceEmbeddingIndexRepository.deleteByPhotoIds(removedPhotoIds);
    }

    final result = candidates
        .where((photo) => !removedIds.contains(photo.id))
        .toList(growable: false);
    stopwatch.stop();
    if (kDebugMode &&
        (candidates.length >= 12 ||
            repairedIds.isNotEmpty ||
            removedIds.isNotEmpty ||
            cacheHits > 0)) {
      debugPrint(
        '🧹 [photo-reconcile] total=${candidates.length} '
        'result=${result.length} cacheHits=$cacheHits '
        'repaired=$repairedCount removed=$removedCount '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
    }
    return result;
  }

  String _photoAccessCacheKey(PhotoEntity photo) {
    if (photo.id > 0) {
      return 'id:${photo.id}';
    }
    return 'asset:${photo.assetId}';
  }

  Future<Map<String, int>> getPhotoStats() async {
    final total = await _isar.collection<PhotoEntity>().count();
    final withGPS = await _isar
        .collection<PhotoEntity>()
        .filter()
        .latitudeIsNotNull()
        .count();
    final aiAnalyzed = await _isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .count();

    return {'total': total, 'withGPS': withGPS, 'aiAnalyzed': aiAnalyzed};
  }

  Future<int> requeueLatestPhotosForAi({int? maxPhotos}) async {
    final query = _isar.collection<PhotoEntity>().where().sortByTimestampDesc();
    final photos = maxPhotos == null
        ? await query.findAll()
        : await query.limit(maxPhotos).findAll();

    if (photos.isEmpty) {
      return 0;
    }

    final taxonomyLabels = memoriaMasterLabels.toSet();
    const passthroughLabels = <String>{
      '截图',
      memoriaOtherLabel,
      JunkPhotoFilterService.junkCandidateTag,
    };

    var updatedCount = 0;
    final updatedPhotos = <PhotoEntity>[];
    final updatedPhotoIds = <int>[];
    for (final photo in photos) {
      final aiTags = photo.aiTags ?? const <String>[];
      final isJunkCandidate = aiTags.contains(
        JunkPhotoFilterService.junkCandidateTag,
      );
      final needsReset =
          photo.isAiAnalyzed &&
          !isJunkCandidate &&
          (aiTags.isEmpty ||
              (photo.imageEmbedding == null || photo.imageEmbedding!.isEmpty));
      final hasOutdatedTags =
          photo.isAiAnalyzed &&
          aiTags.isNotEmpty &&
          aiTags.any(
            (tag) =>
                !taxonomyLabels.contains(tag.trim()) &&
                !passthroughLabels.contains(tag.trim()),
          );

      if (!needsReset && !hasOutdatedTags) {
        continue;
      }

      photo.isAiAnalyzed = false;
      photo.aiTags = <String>[];
      photo.aiCaption = null;
      photo.imageEmbedding = null;
      photo.ocrText = null;
      photo.ocrTags = <String>[];
      photo.faceCount = 0;
      photo.smileProb = 0.0;
      photo.joyScore = 0.0;
      updatedCount++;
      updatedPhotos.add(photo);
      updatedPhotoIds.add(photo.id);
    }

    if (updatedCount == 0) {
      return 0;
    }

    final resetPhotoIds = updatedPhotoIds.toSet().toList(growable: false);
    final staleFaces = resetPhotoIds.isEmpty
        ? const <FaceEntity>[]
        : await _isar
              .collection<FaceEntity>()
              .filter()
              .anyOf(
                resetPhotoIds,
                (query, photoId) => query.photoIdEqualTo(photoId),
              )
              .findAll();

    await _isar.writeTxn(() async {
      if (staleFaces.isNotEmpty) {
        await _isar.collection<FaceEntity>().deleteAll(
          staleFaces.map((item) => item.id).toList(growable: false),
        );
      }
      await _isar.collection<PhotoEntity>().putAll(updatedPhotos);
    });
    _photoEmbeddingIndexRepository.deleteByPhotoIds(resetPhotoIds);
    _faceEmbeddingIndexRepository.deleteByPhotoIds(resetPhotoIds);

    final scopeText = maxPhotos == null
        ? '${photos.length} 张照片'
        : '最近 $maxPhotos 张照片';
    print('🔁 已将 $scopeText 中的 $updatedCount 张重新加入 AI 打标队列');
    return updatedCount;
  }

  Future<int> requeuePhotosForAiByIds(Iterable<int> photoIds) async {
    final normalizedIds = photoIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return 0;
    }

    final photos = (await _isar.collection<PhotoEntity>().getAll(
      normalizedIds,
    )).whereType<PhotoEntity>().toList(growable: false);
    if (photos.isEmpty) {
      return 0;
    }

    var updatedCount = 0;
    for (final photo in photos) {
      photo.isAiAnalyzed = false;
      photo.aiTags = <String>[];
      photo.aiCaption = null;
      photo.imageEmbedding = null;
      photo.ocrText = null;
      photo.ocrTags = <String>[];
      photo.faceCount = 0;
      photo.smileProb = 0.0;
      photo.joyScore = 0.0;
      updatedCount++;
    }

    await _isar.writeTxn(() async {
      await _isar.collection<PhotoEntity>().putAll(photos);
    });
    _photoEmbeddingIndexRepository.deleteByPhotoIds(normalizedIds);

    print('🔁 已将 $updatedCount 张低质量候选重新加入正常 AI 打标队列');
    return updatedCount;
  }

  /// 🚀 Memoria 2.0 升级脚本：重置所有照片的 AI 分析状态

  /// 当底层模型从 ML Kit 切换到 MobileCLIP 时调用

  Future<void> migrateToMobileClip() async {
    print("🔄 开始执行 Memoria 2.0 AI 数据迁移...");

    // 1. 查出所有已经用旧模型（ML Kit）分析过的照片

    final oldPhotos = await _isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .findAll();

    if (oldPhotos.isEmpty) {
      print("✅ 没有需要迁移的旧照片。");

      return;
    }

    // 2. 将它们的状态重置，并清空旧标签

    for (var photo in oldPhotos) {
      photo.isAiAnalyzed = false;

      photo.aiTags = []; // 清空 ML Kit 时代干瘪的标签
      photo.imageEmbedding = null;
      photo.ocrText = null;
      photo.ocrTags = [];
    }

    // 3. 批量写回数据库

    await _isar.writeTxn(() async {
      await _isar.collection<FaceEntity>().clear();
      await _isar.collection<PhotoEntity>().putAll(oldPhotos);
    });
    _photoEmbeddingIndexRepository.deleteAll();
    _faceEmbeddingIndexRepository.deleteAll();

    print("🎉 成功重置了 ${oldPhotos.length} 张照片的 AI 状态！");

    print("后台的闲时 AI 任务将会自动用 MobileCLIP 重新扫描并提取 512 维高维向量。");
  }
}

enum PhotoScanError { permissionDenied, noAlbum, noEligiblePhoto }

class PhotoScanException implements Exception {
  final PhotoScanError code;
  final String message;

  const PhotoScanException(this.code, this.message);

  @override
  String toString() {
    return message;
  }
}

class PhotoScanSummary {
  final int totalBefore;
  final int totalAfter;
  final int removedCount;
  final int insertedCount;
  final List<int> insertedPhotoIds;
  final int scanStartOffset;
  final int scannedCount;
  final int skippedInvalidTime;
  final int insertedNoGps;
  final int skippedNonCamera;
  final int skippedScreenshot;

  const PhotoScanSummary({
    required this.totalBefore,
    required this.totalAfter,
    required this.removedCount,
    required this.insertedCount,
    this.insertedPhotoIds = const <int>[],
    this.scanStartOffset = 0,
    this.scannedCount = 0,
    required this.skippedInvalidTime,
    required this.insertedNoGps,
    required this.skippedNonCamera,
    required this.skippedScreenshot,
  });
}
