import 'dart:io';
import 'dart:math' as math;

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/entity/face_entity.dart';
import '../models/entity/photo_entity.dart';
import '../models/entity/event_entity.dart';
import '../models/entity/story_entity.dart';
import '../data/tag_taxonomy_v2.dart';
import '../service/junk_photo_filter_service.dart';
import '../utils/photo_filter_helper.dart';

class _PreparedScanData {
  const _PreparedScanData({
    required this.assets,
    required this.totalCount,
    required this.fetchCount,
  });

  final List<AssetEntity> assets;
  final int totalCount;
  final int fetchCount;
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

class PhotoService {
  late Isar _isar;
  static const bool _verboseAssetLogging = false;

  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  // 私有构造函数
  PhotoService._internal();

  // 暴露 isar 实例供其他服务使用
  Isar get isar => _isar;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [
        PhotoEntitySchema,
        FaceEntitySchema,
        EventEntitySchema,
        StoryEntitySchema,
      ], // 注册所有实体
      directory: dir.path,
    );
  }

  Future<void> clearAllCachedData() async {
    await _isar.writeTxn(() async {
      await _isar.collection<StoryEntity>().clear();
      await _isar.collection<EventEntity>().clear();
      await _isar.collection<FaceEntity>().clear();
      await _isar.collection<PhotoEntity>().clear();
    });

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
      await _isar.collection<StoryEntity>().clear();
      await _isar.collection<EventEntity>().clear();
      await _isar.collection<FaceEntity>().clear();
      await _isar.collection<PhotoEntity>().clear();
      await _isar.collection<PhotoEntity>().putAll(built.photos);
    });

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
    final totalBefore = await _isar.collection<PhotoEntity>().count();
    final prepared = await _prepareScan(maxAssets: maxAssets);

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

    if (built.photos.isNotEmpty) {
      await _isar.writeTxn(() async {
        await _isar.collection<PhotoEntity>().putAll(built.photos);
      });
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
      skippedInvalidTime: built.skippedInvalidTime,
      insertedNoGps: built.insertedNoGps,
      skippedNonCamera: built.skippedNonCamera,
      skippedScreenshot: built.skippedScreenshot,
    );
  }

  Future<_PreparedScanData> _prepareScan({int? maxAssets}) async {
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

    final preferredAlbums = await PhotoManager.getAssetPathList(
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
    for (final album in albums) {
      final count = await album.assetCountAsync;
      print('📂 相册 [${album.name}] 内有 $count 张图片');
      if (count > selectedCount) {
        selectedAlbum = album;
        selectedCount = count;
      }
    }

    if ((selectedAlbum == null || selectedCount <= 0) && preferredAlbums.isNotEmpty) {
      final fallbackAlbums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: false,
        filterOption: safeFilter,
      );
      for (final album in fallbackAlbums) {
        final count = await album.assetCountAsync;
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
    final fetchCount = maxAssets == null
        ? totalCount
        : (maxAssets < totalCount ? maxAssets : totalCount);
    final startIndex = maxAssets == null ? 0 : math.max(0, totalCount - fetchCount);
    final assets = await selectedAlbum.getAssetListRange(
      start: startIndex,
      end: totalCount,
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
    );
  }

  Future<_PreparedScanData> _prepareGlobalScan({int? maxAssets}) async {
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
    );
  }

  Future<_ScanBuildResult> _buildPhotoEntities(
    List<AssetEntity> assets, {
    required bool skipExisting,
  }) async {
    final photos = <PhotoEntity>[];
    final existingAssetIds = <String>{};
    var skippedInvalidTime = 0;
    var insertedNoGps = 0;
    var skippedNonCamera = 0;
    var skippedScreenshot = 0;

    if (skipExisting) {
      final existingPhotos = await _isar.collection<PhotoEntity>().where().findAll();
      existingAssetIds.addAll(
        existingPhotos.map((photo) => photo.assetId).where((id) => id.isNotEmpty),
      );
    }

    for (final asset in assets) {
      if (skipExisting && existingAssetIds.contains(asset.id)) {
        continue;
      }

      final file = await _resolveReadableFile(asset);
      if (file == null) {
        print('⚠️ 资源无法解析为本地文件: assetId=${asset.id} title=${asset.title}');
        skippedNonCamera++;
        continue;
      }

      final width = asset.width;
      final height = asset.height;
      if (width <= 0 || height <= 0) {
        skippedNonCamera++;
        continue;
      }

      final screenshotByRatio = PhotoFilterHelper.isLikelyScreenshotByRatio(
        width,
        height,
      );
      final likelyCameraPhoto = PhotoFilterHelper.isLikelyCameraPhoto(
        file.path,
      );
      if (screenshotByRatio) {
        skippedScreenshot++;
        // continue;
      }
      if (!likelyCameraPhoto) {
        skippedNonCamera++;
        // continue;
      }

      final shouldResolveGps = !screenshotByRatio && likelyCameraPhoto;
      final latLong = shouldResolveGps ? await asset.latlngAsync() : null;
      if (_verboseAssetLogging) {
        _logAssetExtInfo(asset: asset, filePath: file.path, latLong: latLong);
      }

      final timestamp = asset.createDateTime.millisecondsSinceEpoch;
      if (!PhotoFilterHelper.hasValidTimestamp(timestamp)) {
        skippedInvalidTime++;
        continue;
      }

      final hasGps = PhotoFilterHelper.hasValidGps(
        latLong?.latitude,
        latLong?.longitude,
      );
      if (!hasGps) {
        insertedNoGps++;
      }

      final newPhoto = PhotoEntity()
        ..assetId = asset.id
        ..timestamp = timestamp
        ..path = file.path
        ..width = width
        ..height = height
        ..latitude = hasGps ? latLong!.latitude : null
        ..longitude = hasGps ? latLong!.longitude : null
        ..isLocationProcessed = false;
      photos.add(newPhoto);
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

  Future<File?> _resolveReadableFile(AssetEntity asset) async {
    final directFile = await asset.file;
    if (directFile != null && directFile.path.isNotEmpty) {
      return directFile;
    }

    final originFile = await asset.originFile;
    if (originFile != null && originFile.path.isNotEmpty) {
      print('ℹ️ 资源使用 originFile 兜底: assetId=${asset.id} path=${originFile.path}');
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
    for (final photo in localPhotos) {
      final asset = await AssetEntity.fromId(photo.assetId);
      if (asset == null) {
        removedIds.add(photo.id);
      }
    }

    if (removedIds.isEmpty) {
      return 0;
    }

    await _isar.writeTxn(() async {
      await _isar.collection<PhotoEntity>().deleteAll(removedIds);
    });

    print("🧹 已清理系统相册中删除/不可访问的照片: ${removedIds.length} 张");
    return removedIds.length;
  }

  // 📊 获取照片统计信息
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
    final updatedPhotoIds = <int>[];
    for (final photo in photos) {
      final aiTags = photo.aiTags ?? const <String>[];
      final isJunkCandidate = aiTags.contains(JunkPhotoFilterService.junkCandidateTag);
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
      updatedPhotoIds.add(photo.id);
    }

    if (updatedCount == 0) {
      return 0;
    }

    final resetPhotoIds = updatedPhotoIds
        .toSet()
        .toList(growable: false);
    final staleFaces = resetPhotoIds.isEmpty
        ? const <FaceEntity>[]
        : await _isar
              .collection<FaceEntity>()
              .filter()
              .anyOf(resetPhotoIds, (query, photoId) => query.photoIdEqualTo(photoId))
              .findAll();

    await _isar.writeTxn(() async {
      if (staleFaces.isNotEmpty) {
        await _isar.collection<FaceEntity>().deleteAll(
          staleFaces.map((item) => item.id).toList(growable: false),
        );
      }
      await _isar.collection<PhotoEntity>().putAll(photos);
    });

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

    final photos = (await _isar.collection<PhotoEntity>().getAll(normalizedIds))
        .whereType<PhotoEntity>()
        .toList(growable: false);
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

    final staleFaces = await _isar.collection<FaceEntity>().where().findAll();

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
      if (staleFaces.isNotEmpty) {
        await _isar.collection<FaceEntity>().deleteAll(
          staleFaces.map((item) => item.id).toList(growable: false),
        );
      }
      await _isar.collection<PhotoEntity>().putAll(oldPhotos);
    });

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
  final int skippedInvalidTime;
  final int insertedNoGps;
  final int skippedNonCamera;
  final int skippedScreenshot;

  const PhotoScanSummary({
    required this.totalBefore,
    required this.totalAfter,
    required this.removedCount,
    required this.insertedCount,
    required this.skippedInvalidTime,
    required this.insertedNoGps,
    required this.skippedNonCamera,
    required this.skippedScreenshot,
  });
}
