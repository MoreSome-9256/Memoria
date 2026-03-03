import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

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

    // 当前限制单次扫描数量，避免一次性处理过多资源
    final List<AssetEntity> assets = await albums[0].getAssetListRange(
      start: 0,
      end: 200,
    );

    print("🚀 开始扫描相册...");

    int skippedInvalidTime = 0;
    int insertedNoGps = 0;
    int skippedNonCamera = 0;
    int skippedScreenshot = 0;
    int insertedCount = 0;

    await _isar.writeTxn(() async {
      for (final asset in assets) {
        final file = await asset.file;
        final latLong = await asset.latlngAsync();
        // 不需要打印了
        _logAssetExtInfo(asset: asset, filePath: file?.path, latLong: latLong);

        // 增量更新检查
        final existing = await _isar
            .collection<PhotoEntity>()
            .filter()
            .assetIdEqualTo(asset.id)
            .findFirst();
        if (existing != null) continue;

        if (file == null) continue;

        final timestamp = asset.createDateTime.millisecondsSinceEpoch;
        if (!PhotoFilterHelper.hasValidTimestamp(timestamp)) {
          skippedInvalidTime++;
          continue;
        }

        // 📐 获取图片尺寸并过滤截图
        final width = asset.width;
        final height = asset.height;
        if (width <= 0 || height <= 0) {
          skippedNonCamera++;
          continue;
        }

        if (PhotoFilterHelper.isLikelyScreenshotByRatio(width, height)) {
          skippedScreenshot++;
          print("⏭️  跳过截图: ${file.path.split('/').last} (宽=$width 高=$height)");
          continue; // 跳过截图
        }

        // if (!PhotoFilterHelper.isLikelyCameraPhoto(file.path)) {
        //   skippedNonCamera++;
        //   print("⏭️  跳过非相机命名: ${file.path.split('/').last}");
        //   continue;
        // }

        // 无 GPS 图片也入库，后续聚类会按“时间信号”参与
        final hasGps = PhotoFilterHelper.hasValidGps(
          latLong?.latitude,
          latLong?.longitude,
        );
        if (!hasGps) insertedNoGps++;

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
