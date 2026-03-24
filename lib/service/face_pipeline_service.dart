import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:isar/isar.dart';

import '../models/entity/face_entity.dart';
import '../models/entity/photo_entity.dart';
import '../utils/face_crop_util.dart';
import 'face_embedding_service.dart';
import 'onnx_face_embedding_service.dart';

class FacePipelineService {
  FacePipelineService({
    FaceEmbeddingService? embeddingService,
  }) : _embeddingService =
           embeddingService ??
           OnnxFaceEmbeddingService(
             fallbackService: MobileClipFaceEmbeddingService(),
           );

  final FaceEmbeddingService _embeddingService;

  Future<void> rebuildFacesForPhoto({
    required Isar isar,
    required PhotoEntity photo,
    required File imageFile,
    required List<Face> faces,
  }) async {
    final existingFaces = await _loadExistingFaces(
      isar: isar,
      photoId: photo.id,
    );
    final existingIds = existingFaces
        .map((face) => face.id)
        .toList(growable: false);
    if (faces.isEmpty) {
      if (existingIds.isNotEmpty) {
        await isar.writeTxn(() async {
          await isar.collection<FaceEntity>().deleteAll(existingIds);
        });
      }
      _deleteDebugCropFiles(existingFaces);
      return;
    }

    final decodedImage = await FaceCropUtil.decodeSourceImage(imageFile);
    if (decodedImage == null) {
      debugPrint('⚠️ 无法解码原图以提取人脸 crop: ${imageFile.path}');
      return;
    }

    await _embeddingService.warmUp();
    final primaryIndex = _pickPrimaryFaceIndex(faces);
    final now = DateTime.now().millisecondsSinceEpoch;
    final results = <FaceEntity>[];

    for (var index = 0; index < faces.length; index++) {
      final face = faces[index];
      final croppedFace = FaceCropUtil.cropFaceImage(
        sourceImage: decodedImage,
        boundingBox: face.boundingBox,
      );
      if (croppedFace == null) {
        continue;
      }

      final debugCropFile = await FaceCropUtil.writeDebugCropFile(
        croppedFace: croppedFace,
        photoId: photo.id,
        faceIndex: index,
        uniqueSuffix: now,
      );
      final cropFile = await FaceCropUtil.writeFaceImageToTempFile(
        faceImage: croppedFace,
        photoId: photo.id,
        faceIndex: index,
      );

      FaceEmbeddingResult? embeddingResult;
      try {
        embeddingResult = await _embeddingService.embedFaceCrop(cropFile);
      } catch (error) {
        debugPrint('⚠️ face embedding 失败 photo=${photo.id} face=$index: $error');
      } finally {
        if (cropFile.existsSync()) {
          cropFile.deleteSync();
        }
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
      return;
    }

    await isar.writeTxn(() async {
      if (existingIds.isNotEmpty) {
        await isar.collection<FaceEntity>().deleteAll(existingIds);
      }
      await isar.collection<FaceEntity>().putAll(results);
    });
    _deleteDebugCropFiles(existingFaces);
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
