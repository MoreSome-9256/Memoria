import 'package:isar/isar.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/entity/photo_entity.dart';
import '../models/entity/event_entity.dart';
import '../models/entity/story_entity.dart';
import '../utils/photo_filter_helper.dart';

class PhotoService {
  late Isar _isar;

  static final PhotoService _instance = PhotoService._internal();
  factory PhotoService() => _instance;
  // 私有构造函数
  PhotoService._internal();

  // 暴露 isar 实例供其他服务使用
  Isar get isar => _isar;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [PhotoEntitySchema, EventEntitySchema, StoryEntitySchema], // 注册所有实体
      directory: dir.path,
    );
  }

  Future<void> clearAllCachedData() async {
    await _isar.writeTxn(() async {
      await _isar.collection<StoryEntity>().clear();
      await _isar.collection<EventEntity>().clear();
      await _isar.collection<PhotoEntity>().clear();
    });

    print("🗑️ 已清空 Isar 缓存数据（照片/事件/故事）");
  }

  // 1️⃣ 扫描相册 (快速入库，带截图过滤)
  Future<PhotoScanSummary> scanAndSyncPhotos() async {
    final totalBefore = await _isar.collection<PhotoEntity>().count();

    // 🌟 核心修复：针对 Android 10+ 的动态权限申请
    if (Platform.isAndroid) {
      // 1. 弹出系统弹窗，请求访问媒体位置（解决 0 GPS 的关键）
      final locationStatus = await Permission.accessMediaLocation.request();
      if (locationStatus.isGranted) {
        print("✅ 成功获得读取照片真实 GPS 的特权");
      } else {
        print("⚠️ 用户拒绝了位置特权，照片经纬度将被系统抹除为 null");
      }
    }

    // 权限检查
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      throw const PhotoScanException(
        PhotoScanError.permissionDenied,
        '未获得相册访问权限，请在系统设置中允许访问照片。',
      );
    }

    // 获取图片资源
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image, // 📸 只读图片，过滤视频
      onlyAll: true,
    );

    if (albums.isEmpty) {
      throw const PhotoScanException(PhotoScanError.noAlbum, '未找到可读取的相册。');
    }

    // 先做反向同步：清理系统相册已删除/已不可访问的照片
    final removedCount = await _removeUnavailablePhotos();
    // 🌟 新增：获取相册里的真实总照片数
    final int totalCount = await albums[0].assetCountAsync;

    // 🌟 修改：将 end: 200 改为 end: totalCount，全量读取！
    final List<AssetEntity> assets = await albums[0].getAssetListRange(
      start: 0,
      end: totalCount,
    );

    print("🚀 开始扫描相册...");

    int skippedInvalidTime = 0;
    int insertedNoGps = 0;
    int skippedNonCamera = 0;
    int skippedScreenshot = 0;
    int insertedCount = 0;

    await _isar.writeTxn(() async {
      for (final asset in assets) {
        // 🌟 核心修复 1：把增量检查提到最前面！
        final existing = await _isar
            .collection<PhotoEntity>()
            .filter()
            .assetIdEqualTo(asset.id)
            .findFirst();

        // 如果数据库里已经有了，直接跳过，绝不触发后续极其耗时的 IO 操作！
        if (existing != null) continue;

        // 🌟 核心修复 2：只有全新的照片，才去底层拿数据
        final file = await asset.file;
        if (file == null) continue;

        final latLong = await asset.latlngAsync();

        // 现在的日志只会打印【新增】的照片，终端终于不会被疯狂刷屏了！
        _logAssetExtInfo(asset: asset, filePath: file.path, latLong: latLong);

        final timestamp = asset.createDateTime.millisecondsSinceEpoch;
        if (!PhotoFilterHelper.hasValidTimestamp(timestamp)) {
          skippedInvalidTime++;
          continue;
        }

        // 📐 获取图片尺寸并过滤
        final width = asset.width;
        final height = asset.height;
        if (width <= 0 || height <= 0) {
          skippedNonCamera++;
          continue;
        }

        final hasGps = PhotoFilterHelper.hasValidGps(
          latLong?.latitude,
          latLong?.longitude,
        );
        if (!hasGps) insertedNoGps++;

        // 入库新照片
        final newPhoto = PhotoEntity()
          ..assetId = asset.id
          ..timestamp = timestamp
          ..path = file.path
          ..width = width
          ..height = height
          ..latitude = hasGps ? latLong!.latitude : null
          ..longitude = hasGps ? latLong!.longitude : null
          ..isLocationProcessed = false;

        await _isar.collection<PhotoEntity>().put(newPhoto);
        insertedCount++;
      }
    });

    print(
      "✅ 基础数据同步完成: 删除=$removedCount 入库=$insertedCount 其中无GPS入库=$insertedNoGps 跳过[无时间=$skippedInvalidTime 截图=$skippedScreenshot]",
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
      insertedCount: insertedCount,
      skippedInvalidTime: skippedInvalidTime,
      insertedNoGps: insertedNoGps,
      skippedNonCamera: skippedNonCamera,
      skippedScreenshot: skippedScreenshot,
    );
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

  /// 🚀 Memoria 2.0 升级脚本：重置所有照片的 AI 分析状态

  /// 当底层模型从 ML Kit 切换到 MobileCLIP 时调用

  Future<void> migrateToMobileClip() async {

    print("🔄 开始执行 Memoria 2.0 AI 数据迁移...");



    // 1. 查出所有已经用旧模型（ML Kit）分析过的照片

    final oldPhotos = await _isar.collection<PhotoEntity>()

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

      // photo.vector = null; // 如果你未来加了向量字段，也在这里清空

    }



    // 3. 批量写回数据库

    await _isar.writeTxn(() async {

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
