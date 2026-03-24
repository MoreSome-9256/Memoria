import 'dart:io';
import 'dart:typed_data';

import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_vision_service.dart';
import 'ncnn_mobileclip_native_service.dart';

class MobileClipEmbeddingService {
  MobileClipEmbeddingService._internal();

  static final MobileClipEmbeddingService _instance =
      MobileClipEmbeddingService._internal();

  factory MobileClipEmbeddingService() => _instance;

  final MobileClipVisionService _mobileclip2OnnxService =
      MobileClipVisionService();
  final NcnnMobileClipNativeService _ncnnService = NcnnMobileClipNativeService();
  final MobileClipBackendPreferenceService _preferenceService =
      MobileClipBackendPreferenceService();

  Future<MobileClipBackend> getSelectedBackend() async {
    return _preferenceService.getSelectedBackend();
  }

  Future<void> releaseBackend(MobileClipBackend backend) async {
    switch (backend) {
      case MobileClipBackend.mobileclip2Onnx:
        await _mobileclip2OnnxService.dispose();
      case MobileClipBackend.ncnn:
        await _ncnnService.dispose();
    }
  }

  Future<String?> validateBackend(MobileClipBackend backend) async {
    switch (backend) {
      case MobileClipBackend.mobileclip2Onnx:
        await _mobileclip2OnnxService.warmUp();
        return null;
      case MobileClipBackend.ncnn:
        final status = _ncnnService.getStatus();
        if (!status.libraryLoaded) {
          return status.summary;
        }
        try {
          await _ncnnService.ensureModelInitialized();
        } catch (error) {
          return error.toString();
        }

        final refreshed = _ncnnService.getStatus();
        return refreshed.canEncode ? null : refreshed.summary;
    }
  }

  Future<void> warmUpBackend(MobileClipBackend backend) async {
    final error = await validateBackend(backend);
    if (error != null) {
      throw StateError(error);
    }

    switch (backend) {
      case MobileClipBackend.mobileclip2Onnx:
        await _mobileclip2OnnxService.warmUp();
      case MobileClipBackend.ncnn:
        await _ncnnService.warmUp();
    }
  }

  Future<void> switchBackendAndPersist(MobileClipBackend newBackend) async {
    final currentBackend = await _preferenceService.getSelectedBackend();
    if (currentBackend == newBackend) {
      return;
    }

    await warmUpBackend(newBackend);
    await releaseBackend(currentBackend);
    await _preferenceService.setSelectedBackend(newBackend);
  }

  Future<List<double>> embedImageFileWithBackend(
    File imageFile,
    MobileClipBackend backend,
  ) async {
    if (!imageFile.existsSync()) {
      throw ArgumentError('图片文件不存在: ${imageFile.path}');
    }

    switch (backend) {
      case MobileClipBackend.mobileclip2Onnx:
        return _mobileclip2OnnxService.embedImageFile(imageFile);
      case MobileClipBackend.ncnn:
        final bytes = await imageFile.readAsBytes();
        return _ncnnService.encodeImageBytes(bytes);
    }
  }

  Future<List<double>> embedImageBytesWithBackend(
    Uint8List imageBytes,
    MobileClipBackend backend,
  ) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError('图片字节为空');
    }

    switch (backend) {
      case MobileClipBackend.mobileclip2Onnx:
        return _mobileclip2OnnxService.embedImageBytes(imageBytes);
      case MobileClipBackend.ncnn:
        return _ncnnService.encodeImageBytes(imageBytes);
    }
  }
}