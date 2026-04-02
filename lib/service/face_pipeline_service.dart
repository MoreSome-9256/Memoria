import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:isar/isar.dart';

import '../models/entity/face_entity.dart';
import '../models/entity/photo_entity.dart';
import '../storage/vector_index/face_embedding_index_repository.dart';
import '../utils/face_crop_util.dart';
import 'face_embedding_service.dart';
import 'onnx_face_embedding_service.dart';

class FacePipelineService {
  FacePipelineService({FaceEmbeddingService? embeddingService})
    : _embeddingService =
          embeddingService ??
          OnnxFaceEmbeddingService(
            fallbackService: MobileClipFaceEmbeddingService(),
          );

  static const bool _persistDebugCrops = bool.fromEnvironment(
    'FACE_DEBUG_CROPS',
    defaultValue: false,
  );

  final FaceEmbeddingService _embeddingService;
  final FaceEmbeddingIndexRepository _faceEmbeddingIndexRepository =
      FaceEmbeddingIndexRepository();

  Future<FacePipelineProfile> rebuildFacesForPhoto({
    required Isar isar,
    required PhotoEntity photo,
    required File imageFile,
    required List<Face> faces,
  }) async {
    final totalWatch = Stopwatch()..start();
    final existingReadWatch = Stopwatch()..start();
    final existingFaces = await _loadExistingFaces(
      isar: isar,
      photoId: photo.id,
    );
    existingReadWatch.stop();
    final existingIds = existingFaces
        .map((face) => face.id)
        .toList(growable: false);

    var sourceDecodeMs = 0.0;
    var embeddingWarmUpMs = 0.0;
    var cropMs = 0.0;
    var debugCropMs = 0.0;
    var tempFileMs = 0.0;
    var embeddingMs = 0.0;
    var isarWriteMs = 0.0;
    var objectBoxWriteMs = 0.0;
    var cleanupMs = 0.0;

    if (faces.isEmpty) {
      if (existingIds.isNotEmpty) {
        final isarWriteWatch = Stopwatch()..start();
        await isar.writeTxn(() async {
          await isar.collection<FaceEntity>().deleteAll(existingIds);
        });
        isarWriteWatch.stop();
        isarWriteMs = isarWriteWatch.elapsedMicroseconds / 1000.0;

        final objectBoxWriteWatch = Stopwatch()..start();
        _faceEmbeddingIndexRepository.deleteByPhotoIds(<int>[photo.id]);
        objectBoxWriteWatch.stop();
        objectBoxWriteMs = objectBoxWriteWatch.elapsedMicroseconds / 1000.0;
      }

      final cleanupWatch = Stopwatch()..start();
      _deleteDebugCropFiles(existingFaces);
      cleanupWatch.stop();
      cleanupMs = cleanupWatch.elapsedMicroseconds / 1000.0;

      totalWatch.stop();
      return FacePipelineProfile(
        requestedFaces: faces.length,
        persistedFaces: 0,
        existingFaces: existingFaces.length,
        existingReadMs: existingReadWatch.elapsedMicroseconds / 1000.0,
        sourceDecodeMs: sourceDecodeMs,
        embeddingWarmUpMs: embeddingWarmUpMs,
        cropMs: cropMs,
        debugCropMs: debugCropMs,
        tempFileMs: tempFileMs,
        embeddingMs: embeddingMs,
        isarWriteMs: isarWriteMs,
        objectBoxWriteMs: objectBoxWriteMs,
        cleanupMs: cleanupMs,
        totalMs: totalWatch.elapsedMicroseconds / 1000.0,
      );
    }

    final sourceDecodeWatch = Stopwatch()..start();
    final decodedImage = await FaceCropUtil.decodeSourceImage(imageFile);
    sourceDecodeWatch.stop();
    sourceDecodeMs = sourceDecodeWatch.elapsedMicroseconds / 1000.0;
    if (decodedImage == null) {
      debugPrint('⚠️ 无法解码原图以提取人脸 crop: ${imageFile.path}');
      totalWatch.stop();
      return FacePipelineProfile(
        requestedFaces: faces.length,
        persistedFaces: 0,
        existingFaces: existingFaces.length,
        existingReadMs: existingReadWatch.elapsedMicroseconds / 1000.0,
        sourceDecodeMs: sourceDecodeMs,
        embeddingWarmUpMs: embeddingWarmUpMs,
        cropMs: cropMs,
        debugCropMs: debugCropMs,
        tempFileMs: tempFileMs,
        embeddingMs: embeddingMs,
        isarWriteMs: isarWriteMs,
        objectBoxWriteMs: objectBoxWriteMs,
        cleanupMs: cleanupMs,
        totalMs: totalWatch.elapsedMicroseconds / 1000.0,
      );
    }

    final warmUpWatch = Stopwatch()..start();
    await _embeddingService.warmUp();
    warmUpWatch.stop();
    embeddingWarmUpMs = warmUpWatch.elapsedMicroseconds / 1000.0;

    final primaryIndex = _pickPrimaryFaceIndex(faces);
    final now = DateTime.now().millisecondsSinceEpoch;
    final results = <FaceEntity>[];

    for (var index = 0; index < faces.length; index++) {
      final face = faces[index];

      final cropWatch = Stopwatch()..start();
      final croppedFace = FaceCropUtil.cropFaceImage(
        sourceImage: decodedImage,
        boundingBox: face.boundingBox,
      );
      cropWatch.stop();
      cropMs += cropWatch.elapsedMicroseconds / 1000.0;
      if (croppedFace == null) {
        continue;
      }

      File? debugCropFile;
      if (_persistDebugCrops) {
        final debugCropWatch = Stopwatch()..start();
        debugCropFile = await FaceCropUtil.writeDebugCropFile(
          croppedFace: croppedFace,
          photoId: photo.id,
          faceIndex: index,
          uniqueSuffix: now,
        );
        debugCropWatch.stop();
        debugCropMs += debugCropWatch.elapsedMicroseconds / 1000.0;
      }

      final tempFileWatch = Stopwatch()..start();
      final cropBytes = FaceCropUtil.encodeFaceImageToJpegBytes(croppedFace);
      tempFileWatch.stop();
      tempFileMs += tempFileWatch.elapsedMicroseconds / 1000.0;

      FaceEmbeddingResult? embeddingResult;
      try {
        final embeddingWatch = Stopwatch()..start();
        embeddingResult = await _embeddingService.embedFaceCropBytes(cropBytes);
        embeddingWatch.stop();
        embeddingMs += embeddingWatch.elapsedMicroseconds / 1000.0;
      } catch (error) {
        debugPrint(
          '⚠️ face embedding 失败 photo=${photo.id} face=$index: $error',
        );
      }

      final qualityScore = _estimateQualityScore(face, photo);
      results.add(
        FaceEntity()
          ..photoId = photo.id
          ..assetId = photo.assetId
          ..faceIndex = index
          ..left = face.boundingBox.left
          ..top = face.boundingBox.top
          ..right = face.boundingBox.right
          ..bottom = face.boundingBox.bottom
          ..roll = face.headEulerAngleZ
          ..yaw = face.headEulerAngleY
          ..smilingProbability = face.smilingProbability
          ..leftEyeOpenProbability = face.leftEyeOpenProbability
          ..rightEyeOpenProbability = face.rightEyeOpenProbability
          ..debugCropPath = debugCropFile?.path
          ..embedding = embeddingResult?.embedding
          ..embeddingModelVersion =
              embeddingResult?.modelVersion ??
              kMobileClipFaceEmbeddingModelVersion
          ..qualityScore = qualityScore
          ..clusterId = null
          ..isPrimaryFace = index == primaryIndex
          ..createdAt = now
          ..updatedAt = now,
      );
    }

    if (results.isEmpty) {
      final cleanupWatch = Stopwatch()..start();
      _deleteDebugCropFiles(existingFaces);
      cleanupWatch.stop();
      cleanupMs = cleanupWatch.elapsedMicroseconds / 1000.0;

      totalWatch.stop();
      return FacePipelineProfile(
        requestedFaces: faces.length,
        persistedFaces: 0,
        existingFaces: existingFaces.length,
        existingReadMs: existingReadWatch.elapsedMicroseconds / 1000.0,
        sourceDecodeMs: sourceDecodeMs,
        embeddingWarmUpMs: embeddingWarmUpMs,
        cropMs: cropMs,
        debugCropMs: debugCropMs,
        tempFileMs: tempFileMs,
        embeddingMs: embeddingMs,
        isarWriteMs: isarWriteMs,
        objectBoxWriteMs: objectBoxWriteMs,
        cleanupMs: cleanupMs,
        totalMs: totalWatch.elapsedMicroseconds / 1000.0,
      );
    }

    final isarWriteWatch = Stopwatch()..start();
    await isar.writeTxn(() async {
      if (existingIds.isNotEmpty) {
        await isar.collection<FaceEntity>().deleteAll(existingIds);
      }
      await isar.collection<FaceEntity>().putAll(results);
    });
    isarWriteWatch.stop();
    isarWriteMs = isarWriteWatch.elapsedMicroseconds / 1000.0;

    final objectBoxWriteWatch = Stopwatch()..start();
    _faceEmbeddingIndexRepository.replaceForPhoto(
      photoId: photo.id,
      faces: results,
    );
    objectBoxWriteWatch.stop();
    objectBoxWriteMs = objectBoxWriteWatch.elapsedMicroseconds / 1000.0;

    final cleanupWatch = Stopwatch()..start();
    _deleteDebugCropFiles(existingFaces);
    cleanupWatch.stop();
    cleanupMs = cleanupWatch.elapsedMicroseconds / 1000.0;

    totalWatch.stop();
    return FacePipelineProfile(
      requestedFaces: faces.length,
      persistedFaces: results.length,
      existingFaces: existingFaces.length,
      existingReadMs: existingReadWatch.elapsedMicroseconds / 1000.0,
      sourceDecodeMs: sourceDecodeMs,
      embeddingWarmUpMs: embeddingWarmUpMs,
      cropMs: cropMs,
      debugCropMs: debugCropMs,
      tempFileMs: tempFileMs,
      embeddingMs: embeddingMs,
      isarWriteMs: isarWriteMs,
      objectBoxWriteMs: objectBoxWriteMs,
      cleanupMs: cleanupMs,
      totalMs: totalWatch.elapsedMicroseconds / 1000.0,
    );
  }

  Future<List<FaceEntity>> _loadExistingFaces({
    required Isar isar,
    required int photoId,
  }) async {
    return isar
        .collection<FaceEntity>()
        .filter()
        .photoIdEqualTo(photoId)
        .findAll();
  }

  void _deleteDebugCropFiles(List<FaceEntity> faces) {
    for (final face in faces) {
      final path = face.debugCropPath;
      if (path == null || path.isEmpty) {
        continue;
      }
      final file = File(path);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {
          // Ignore debug crop cleanup failures.
        }
      }
    }
  }

  int _pickPrimaryFaceIndex(List<Face> faces) {
    var bestIndex = 0;
    var bestScore = -double.infinity;

    for (var index = 0; index < faces.length; index++) {
      final face = faces[index];
      final rect = face.boundingBox;
      final areaScore = rect.width * rect.height;
      final smileScore = face.smilingProbability ?? 0.0;
      final score = areaScore + smileScore * 1000;
      if (score > bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }

    return bestIndex;
  }

  double _estimateQualityScore(Face face, PhotoEntity photo) {
    final areaRatio =
        (face.boundingBox.width * face.boundingBox.height) /
        math.max(1, photo.width * photo.height);
    final smile = face.smilingProbability ?? 0.0;
    final eyes =
        ((face.leftEyeOpenProbability ?? 0.0) +
            (face.rightEyeOpenProbability ?? 0.0)) /
        2;
    final yawPenalty = (face.headEulerAngleY?.abs() ?? 0.0) / 90.0;
    final rollPenalty = (face.headEulerAngleZ?.abs() ?? 0.0) / 90.0;

    final raw = areaRatio * 2.5 + smile * 0.1 + eyes * 0.1;
    final penalty = (yawPenalty + rollPenalty) * 0.15;
    return (raw - penalty).clamp(0.0, 1.0);
  }
}

class FacePipelineProfile {
  const FacePipelineProfile({
    required this.requestedFaces,
    required this.persistedFaces,
    required this.existingFaces,
    required this.existingReadMs,
    required this.sourceDecodeMs,
    required this.embeddingWarmUpMs,
    required this.cropMs,
    required this.debugCropMs,
    required this.tempFileMs,
    required this.embeddingMs,
    required this.isarWriteMs,
    required this.objectBoxWriteMs,
    required this.cleanupMs,
    required this.totalMs,
  });

  final int requestedFaces;
  final int persistedFaces;
  final int existingFaces;
  final double existingReadMs;
  final double sourceDecodeMs;
  final double embeddingWarmUpMs;
  final double cropMs;
  final double debugCropMs;
  final double tempFileMs;
  final double embeddingMs;
  final double isarWriteMs;
  final double objectBoxWriteMs;
  final double cleanupMs;
  final double totalMs;
}
