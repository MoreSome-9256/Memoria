/// 人脸裁剪辅助工具，提供裁剪框换算和图片裁切的通用逻辑。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class FaceCropUtil {
  const FaceCropUtil._();

  static const int debugThumbnailSize = 192;

  static Uint8List encodeFaceImageToJpegBytes(
    img.Image faceImage, {
    int quality = 92,
  }) {
    return Uint8List.fromList(img.encodeJpg(faceImage, quality: quality));
  }

  static Future<img.Image?> decodeSourceImage(File sourceFile) async {
    final bytes = await sourceFile.readAsBytes();
    return decodeSourceImageBytes(bytes);
  }

  static img.Image? decodeSourceImageBytes(Uint8List sourceBytes) {
    if (sourceBytes.isEmpty) {
      return null;
    }
    return img.decodeImage(sourceBytes);
  }

  static img.Image? cropFaceImage({
    required img.Image sourceImage,
    required Rect boundingBox,
    double paddingRatio = 0.18,
  }) {
    final cropRect = _expandAndClampRect(
      boundingBox,
      imageWidth: sourceImage.width.toDouble(),
      imageHeight: sourceImage.height.toDouble(),
      paddingRatio: paddingRatio,
    );
    if (cropRect.width < 8 || cropRect.height < 8) {
      return null;
    }

    return img.copyCrop(
      sourceImage,
      x: cropRect.left.round(),
      y: cropRect.top.round(),
      width: cropRect.width.round(),
      height: cropRect.height.round(),
    );
  }

  static Future<File?> cropFaceToTempFile({
    required img.Image sourceImage,
    required Rect boundingBox,
    required int photoId,
    required int faceIndex,
    double paddingRatio = 0.18,
  }) async {
    final cropped = cropFaceImage(
      sourceImage: sourceImage,
      boundingBox: boundingBox,
      paddingRatio: paddingRatio,
    );
    if (cropped == null) {
      return null;
    }

    final encoded = encodeFaceImageToJpegBytes(cropped);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/face_${photoId}_$faceIndex.jpg');
    await file.writeAsBytes(encoded, flush: true);
    return file;
  }

  static Future<File> writeFaceImageToTempFile({
    required img.Image faceImage,
    required int photoId,
    required int faceIndex,
  }) async {
    final encoded = encodeFaceImageToJpegBytes(faceImage);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/face_${photoId}_$faceIndex.jpg');
    await file.writeAsBytes(encoded, flush: true);
    return file;
  }

  static Future<File?> writeDebugCropFile({
    required img.Image croppedFace,
    required int photoId,
    required int faceIndex,
    required int uniqueSuffix,
  }) async {
    final resized = img.copyResizeCropSquare(
      croppedFace,
      size: debugThumbnailSize,
      interpolation: img.Interpolation.cubic,
    );
    final encoded = encodeFaceImageToJpegBytes(resized, quality: 88);
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/face_debug_${photoId}_${faceIndex}_$uniqueSuffix.jpg',
    );
    await file.writeAsBytes(encoded, flush: true);
    return file;
  }

  static Rect _expandAndClampRect(
    Rect rect, {
    required double imageWidth,
    required double imageHeight,
    required double paddingRatio,
  }) {
    final padX = rect.width * paddingRatio;
    final padY = rect.height * paddingRatio;

    final left = (rect.left - padX).clamp(0.0, imageWidth).toDouble();
    final top = (rect.top - padY).clamp(0.0, imageHeight).toDouble();
    final right = (rect.right + padX).clamp(0.0, imageWidth).toDouble();
    final bottom = (rect.bottom + padY).clamp(0.0, imageHeight).toDouble();

    return Rect.fromLTRB(left, top, right, bottom);
  }
}
