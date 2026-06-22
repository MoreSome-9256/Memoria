import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    show Face, FaceDetector, FaceDetectorMode, FaceDetectorOptions;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    show InputImage;
import 'package:objectbox/objectbox.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/entity/photo_entity.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../utils/ai_score_helper.dart';
import '../utils/media_type_helper.dart';
import 'face_pipeline_service.dart';
import 'geo_cell_cache_service.dart';
import 'media_analysis_image_reader.dart';
import 'ocr_service.dart';
import 'photo_caption_service.dart';
import 'photo_search_index_service.dart';

enum PhotoAttributeType { location, faceDetection, ocr, caption }

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
  factory PhotoAttributeBackgroundService.instance() => _instance;

  final Queue<int> _queue = Queue<int>();
  final Map<int, PhotoAttributeTask> _pendingByPhotoId =
      <int, PhotoAttributeTask>{};
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  bool _isRunning = false;
  int _processed = 0;
  Completer<void>? _idleCompleter;
  final Map<int, Object> _failedTasks = <int, Object>{};

  Future<void> enqueueAttributeTask({
    required int photoId,
    required Set<PhotoAttributeType> types,
  }) async {
    _enqueuePendingTask(
      PhotoAttributeTask(
        photoId: photoId,
        types: types,
        enqueuedAt: DateTime.now(),
      ),
    );

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
      _enqueuePendingTask(
        PhotoAttributeTask(photoId: photoId, types: types, enqueuedAt: now),
      );
    }

    if (!_isRunning) {
      unawaited(_runBackgroundWorker());
    }
  }

  Future<void> waitUntilIdle() async {
    if (!_isRunning && _queue.isEmpty) {
      _throwIfTasksFailed();
      return;
    }
    if (!_isRunning) {
      unawaited(_runBackgroundWorker());
    }
    await (_idleCompleter ??= Completer<void>()).future;
    _throwIfTasksFailed();
  }

  void beginRun() {
    if (_isRunning || _queue.isNotEmpty || _pendingByPhotoId.isNotEmpty) {
      throw StateError('属性分析 worker 尚未结束，不能开始新的分析任务。');
    }
    _failedTasks.clear();
  }

  void _throwIfTasksFailed() {
    if (_failedTasks.isEmpty) return;
    final ids = _failedTasks.keys.take(8).join(',');
    throw StateError(
      '属性分析失败 ${_failedTasks.length} 项，照片 ID: $ids。'
      '失败项目会在下一次扫描时重新分析。',
    );
  }

  void _enqueuePendingTask(PhotoAttributeTask task) {
    final existing = _pendingByPhotoId[task.photoId];
    if (existing == null) {
      _pendingByPhotoId[task.photoId] = task;
      _queue.add(task.photoId);
      return;
    }

    _pendingByPhotoId[task.photoId] = PhotoAttributeTask(
      photoId: task.photoId,
      types: <PhotoAttributeType>{...existing.types, ...task.types},
      enqueuedAt: existing.enqueuedAt,
    );
  }

  Future<void> _runBackgroundWorker() async {
    if (_isRunning) return;
    _isRunning = true;

    debugPrint('[attribute-worker] started');

    try {
      while (_queue.isNotEmpty) {
        final photoId = _queue.removeFirst();
        final task = _pendingByPhotoId.remove(photoId);
        if (task == null) {
          continue;
        }
        try {
          await _processAttributeTask(task);
          _processed++;
        } catch (error) {
          _failedTasks[task.photoId] = error;
          debugPrint(
            '[attribute-worker] task failed photoId=${task.photoId}: $error',
          );
        }
      }
    } finally {
      _isRunning = false;
      final completer = _idleCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      _idleCompleter = null;
      debugPrint('[attribute-worker] stopped processed=$_processed');
    }
  }

  Future<void> _processAttributeTask(PhotoAttributeTask task) async {
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    final photo = photoBox.get(task.photoId);

    if (photo == null) {
      debugPrint('[attribute-worker] photoId=${task.photoId} not found');
      return;
    }

    if (task.types.contains(PhotoAttributeType.location)) {
      await _processLocationAttribute(photo, photoBox);
    }

    final processVisualAttributes =
        task.types.contains(PhotoAttributeType.faceDetection) ||
        task.types.contains(PhotoAttributeType.ocr) ||
        task.types.contains(PhotoAttributeType.caption);
    if (processVisualAttributes) {
      await _processVisualAttributes(
        photo,
        photoBox,
        runFaceDetection: task.types.contains(PhotoAttributeType.faceDetection),
        runOcr: task.types.contains(PhotoAttributeType.ocr),
        runCaption: task.types.contains(PhotoAttributeType.caption),
      );
    }

    store.runInTransaction(TxMode.write, () {
      final completed = photoBox.get(task.photoId);
      if (completed == null) return;
      completed
        ..isAiAnalyzed = true
        ..isAiAnalysisCandidate = false;
      photoBox.put(completed);
    });
  }

  Future<void> _processLocationAttribute(
    PhotoEntity photo,
    Box<PhotoEntity> photoBox,
  ) async {
    var latest = photoBox.get(photo.id) ?? photo;
    if (latest.isLocationProcessed && latest.geoIndexVersion >= 1) {
      return;
    }
    if (latest.latitude == null || latest.longitude == null) {
      latest = await _refreshCoordinatesFromAsset(latest, photoBox);
    }
    if (latest.latitude == null || latest.longitude == null) {
      debugPrint(
        '[attribute-worker] location unavailable photoId=${photo.id} '
        'assetId=${photo.assetId}',
      );
      return;
    }

    final lat = latest.latitude!;
    final lng = latest.longitude!;

    if (lat.abs() < 0.001 && lng.abs() < 0.001) {
      return;
    }

    final geoResult = await GeoCellCacheService.instance.reverseGeocode(
      latitude: lat,
      longitude: lng,
    );

    if (geoResult == null) {
      debugPrint(
        '[attribute-worker] reverse geocode failed photoId=${photo.id}',
      );
      return;
    }

    final store = ObjectBoxService().store;
    store.runInTransaction(TxMode.write, () {
      final p = photoBox.get(photo.id);
      if (p == null) return;

      p.country = geoResult.country;
      p.province = geoResult.province;
      p.city = geoResult.city;
      p.district = geoResult.district;
      p.locationName = geoResult.locationName;
      p.formattedAddress = geoResult.formattedAddress;
      p.adcode = geoResult.adcode;
      p.township = geoResult.township;
      p.businessAreaText = geoResult.businessAreaText;
      p.aoiNameText = geoResult.aoiNameText;
      p.poiNameText = geoResult.poiNameText;
      p.aoiIdText = geoResult.aoiIdText;
      p.poiIdText = geoResult.poiIdText;
      p.geoTextTokens = geoResult.geoTextTokens;
      p.geoIndexedAt = DateTime.now().millisecondsSinceEpoch;
      p.geoIndexVersion = 1;
      p.isLocationProcessed = true;

      photoBox.put(p);
    });

    debugPrint(
      '[attribute-worker] location written photoId=${photo.id} '
      'location=${geoResult.locationName}',
    );
  }

  Future<PhotoEntity> _refreshCoordinatesFromAsset(
    PhotoEntity photo,
    Box<PhotoEntity> photoBox,
  ) async {
    try {
      final asset = await AssetEntity.fromId(photo.assetId);
      if (asset == null) {
        return photo;
      }
      final latLng = await asset.latlngAsync();
      final latitude = latLng?.latitude;
      final longitude = latLng?.longitude;
      if (latitude == null ||
          longitude == null ||
          (latitude.abs() < 0.001 && longitude.abs() < 0.001)) {
        return photo;
      }

      final store = ObjectBoxService().store;
      late PhotoEntity latest;
      store.runInTransaction(TxMode.write, () {
        latest = photoBox.get(photo.id) ?? photo;
        latest
          ..latitude = latitude
          ..longitude = longitude
          ..isLocationProcessed = false
          ..geoIndexVersion = 0;
        PhotoSearchIndexService.updateCoordinateFields(latest);
        photoBox.put(latest);
      });
      debugPrint(
        '[attribute-worker] GPS refreshed photoId=${photo.id} '
        'lat=${latitude.toStringAsFixed(5)} lon=${longitude.toStringAsFixed(5)}',
      );
      return latest;
    } catch (error) {
      debugPrint(
        '[attribute-worker] GPS refresh failed photoId=${photo.id}: $error',
      );
      return photo;
    }
  }

  Future<void> _processVisualAttributes(
    PhotoEntity photo,
    Box<PhotoEntity> photoBox, {
    required bool runFaceDetection,
    required bool runOcr,
    required bool runCaption,
  }) async {
    final mediaKind = MediaTypeHelper.fromStorageValue(
      photo.mediaKind,
      path: photo.path,
    );
    if (mediaKind != MemoriaMediaKind.image) {
      if (runCaption) {
        await _persistCaptionAndOcr(
          photo: photo,
          photoBox: photoBox,
          runOcr: false,
        );
      }
      return;
    }

    final input = await MediaAnalysisImageReader.instance.readAssetById(
      photo.assetId,
    );
    if (input == null || input.analysisImageBytes.isEmpty) {
      throw StateError('无法读取属性分析图片 photoId=${photo.id}');
    }

    final imageFile = await _writeTempAnalysisImage(
      photoId: photo.id,
      bytes: input.analysisImageBytes,
    );
    try {
      var latest = photoBox.get(photo.id) ?? photo;
      List<Face> faces = const <Face>[];

      if (runFaceDetection) {
        faces = await _faceDetector.processImage(
          InputImage.fromFile(imageFile),
        );
        await _persistFaceSummary(
          photo: latest,
          photoBox: photoBox,
          faces: faces,
        );
        latest = photoBox.get(photo.id) ?? latest;
      }

      if (runCaption) {
        await _persistCaptionAndOcr(
          photo: latest,
          photoBox: photoBox,
          imageFile: imageFile,
          runOcr: runOcr,
        );
        latest = photoBox.get(photo.id) ?? latest;
      }

      if (runFaceDetection) {
        await FacePipelineService.instance.rebuildFacesForPhoto(
          photo: latest,
          imageFile: imageFile,
          imageBytes: input.analysisImageBytes,
          faces: faces,
        );
      }
    } finally {
      if (await imageFile.exists()) {
        await imageFile.delete();
      }
    }
  }

  Future<void> _persistFaceSummary({
    required PhotoEntity photo,
    required Box<PhotoEntity> photoBox,
    required List<Face> faces,
  }) async {
    final maxSmile = _maxSmileProbability(faces);
    final joyScore = AIScoreHelper.calculateJoyScore(
      faceCount: faces.length,
      maxSmileProb: maxSmile,
      tags: photo.aiTags ?? const <String>[],
    );

    final store = ObjectBoxService().store;
    store.runInTransaction(TxMode.write, () {
      final p = photoBox.get(photo.id);
      if (p == null) return;

      p.faceCount = faces.length;
      p.smileProb = maxSmile;
      p.joyScore = joyScore;
      p.isFaceAnalyzed = true;

      photoBox.put(p);
    });

    debugPrint(
      '[attribute-worker] face summary written photoId=${photo.id} '
      'faces=${faces.length} smile=${maxSmile.toStringAsFixed(2)} '
      'joy=${joyScore.toStringAsFixed(2)}',
    );
  }

  Future<void> _persistCaptionAndOcr({
    required PhotoEntity photo,
    required Box<PhotoEntity> photoBox,
    File? imageFile,
    required bool runOcr,
  }) async {
    final visualTags = photo.aiTags ?? const <String>[];
    final shouldRunOcr =
        runOcr && imageFile != null && OcrService.shouldRunOcr(visualTags);
    final ocrResult = shouldRunOcr
        ? await OcrService().analyzeImageFile(imageFile)
        : OcrResult.empty();
    final caption = await PhotoCaptionService().generateCaption(
      visualTags: visualTags,
      ocrTags: ocrResult.tags,
      ocrText: ocrResult.text,
      location: photo.locationName ?? photo.district ?? photo.city,
      takenAt: DateTime.fromMillisecondsSinceEpoch(photo.timestamp),
      faceCount: photo.faceCount,
    );

    final store = ObjectBoxService().store;
    store.runInTransaction(TxMode.write, () {
      final p = photoBox.get(photo.id);
      if (p == null) return;

      p.ocrText = ocrResult.text.isEmpty ? null : ocrResult.text;
      p.ocrTags = ocrResult.tags;
      p.aiCaption = caption.trim().isEmpty ? null : caption.trim();
      p.isOcrAnalyzed = runOcr;
      p.isCaptionAnalyzed = true;

      photoBox.put(p);
    });

    debugPrint(
      '[attribute-worker] text attributes written photoId=${photo.id} '
      'ocrTags=${ocrResult.tags.length} caption=${caption.isNotEmpty}',
    );
  }

  double _maxSmileProbability(List<Face> faces) {
    var maxSmile = 0.0;
    for (final face in faces) {
      final value = face.smilingProbability;
      if (value != null && value > maxSmile) {
        maxSmile = value;
      }
    }
    return maxSmile.clamp(0.0, 1.0);
  }

  Future<File> _writeTempAnalysisImage({
    required int photoId,
    required Uint8List bytes,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      'memoria_attr_${photoId}_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: false);
    return file;
  }

  @visibleForTesting
  void enqueueAttributeTaskForTesting({
    required int photoId,
    required Set<PhotoAttributeType> types,
  }) {
    _enqueuePendingTask(
      PhotoAttributeTask(
        photoId: photoId,
        types: types,
        enqueuedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  }

  @visibleForTesting
  List<PhotoAttributeTask> pendingTasksForTesting() {
    return _queue
        .map((photoId) => _pendingByPhotoId[photoId])
        .whereType<PhotoAttributeTask>()
        .toList(growable: false);
  }

  @visibleForTesting
  void resetForTesting() {
    _queue.clear();
    _pendingByPhotoId.clear();
    _failedTasks.clear();
    _isRunning = false;
    _processed = 0;
    _idleCompleter = null;
  }

  int get queueSize => _queue.length;
  bool get isRunning => _isRunning;
  int get processedCount => _processed;
}
