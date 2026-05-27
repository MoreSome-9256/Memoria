import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/entity/photo_entity.dart';
import '../storage/objectbox/objectbox_service.dart';
import 'amap_geo_service.dart';
import '../objectbox.g.dart';

enum PhotoAttributeType {
  location,
  faceDetection,
  caption,
}

class PhotoAttributeTask {
  const PhotoAttributeTask({
    required this.photoId,
    required this.types,
    required this.enqueuedAt,
  });

  final int photoId;
  final Set<PhotoAttributeType> types;
  final DateTime enqueuedAt;
}

class PhotoAttributeBackgroundService {
  PhotoAttributeBackgroundService._internal();

  static final PhotoAttributeBackgroundService _instance =
      PhotoAttributeBackgroundService._internal();
  factory PhotoAttributeBackgroundService.instance => _instance;

  final Queue<PhotoAttributeTask> _queue = Queue<PhotoAttributeTask>();
  bool _isRunning = false;
  int _processed = 0;

  Future<void> enqueueAttributeTask({
    required int photoId,
    required Set<PhotoAttributeType> types,
  }) async {
    _queue.add(PhotoAttributeTask(
      photoId: photoId,
      types: types,
      enqueuedAt: DateTime.now(),
    ));

    if (!_isRunning) {
      unawaited(_runBackgroundWorker());
    }
  }

  Future<void> enqueueBatchAttributeTasks({
    required List<int> photoIds,
    required Set<PhotoAttributeType> types,
  }) async {
    final now = DateTime.now();
    for (final photoId in photoIds) {
      _queue.add(PhotoAttributeTask(
        photoId: photoId,
        types: types,
        enqueuedAt: now,
      ));
    }

    if (!_isRunning) {
      unawaited(_runBackgroundWorker());
    }
  }

  Future<void> _runBackgroundWorker() async {
    if (_isRunning) return;
    _isRunning = true;

    debugPrint('[attribute-worker] 后台属性服务启动');

    try {
      while (_queue.isNotEmpty) {
        final task = _queue.removeFirst();
        await _processAttributeTask(task);
        _processed++;
      }
    } catch (error) {
      debugPrint('[attribute-worker] 错误: $error');
    } finally {
      _isRunning = false;
      debugPrint('[attribute-worker] 后台属性服务停止: processed=$_processed');
    }
  }

  Future<void> _processAttributeTask(PhotoAttributeTask task) async {
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    final photo = photoBox.get(task.photoId);

    if (photo == null) {
      debugPrint('[attribute-worker] photoId=${task.photoId} 不存在');
      return;
    }

    for (final type in task.types) {
      try {
        switch (type) {
          case PhotoAttributeType.location:
            await _processLocationAttribute(photo, photoBox);
            break;
          case PhotoAttributeType.faceDetection:
            break;
          case PhotoAttributeType.caption:
            break;
        }
      } catch (error) {
        debugPrint(
          '[attribute-worker] 处理 $type 失败 photoId=${task.photoId}: $error',
        );
      }
    }
  }

  Future<void> _processLocationAttribute(
    PhotoEntity photo,
    dynamic photoBox,
  ) async {
    if (photo.latitude == null ||
        photo.longitude == null ||
        photo.isLocationProcessed) {
      return;
    }

    final lat = photo.latitude!;
    final lng = photo.longitude!;

    if (lat.abs() < 0.001 && lng.abs() < 0.001) {
      return;
    }

    final geoResult = await AMapGeoService().reverseGeocode(lat, lng);

    if (geoResult == null) {
      debugPrint('[attribute-worker] 逆地理编码失败 photoId=${photo.id}');
      return;
    }

    final store = ObjectBoxService().store;
    store.runInTransaction(TxMode.write, () {
      final p = photoBox.get(photo.id);
      if (p == null) return;

      p.province = geoResult.province;
      p.city = geoResult.city;
      p.district = geoResult.district;
      p.locationName = geoResult.locationName;
      p.formattedAddress = geoResult.formattedAddress;
      p.adcode = geoResult.adcode;
      p.isLocationProcessed = true;

      photoBox.put(p);
    });

    debugPrint(
      '[attribute-worker] 已填写地址 photoId=${photo.id} '
      'location=${geoResult.locationName}',
    );
  }

  int get queueSize => _queue.length;
  bool get isRunning => _isRunning;
  int get processedCount => _processed;
}
