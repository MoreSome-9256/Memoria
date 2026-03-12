import 'dart:io';

import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_vision_service.dart';
import 'ncnn_mobileclip_native_service.dart';

class MobileClipEmbeddingService {
  MobileClipEmbeddingService._internal();

  static final MobileClipEmbeddingService _instance =
      MobileClipEmbeddingService._internal();

  factory MobileClipEmbeddingService() => _instance;

  final MobileClipVisionService _onnxService = MobileClipVisionService();
  final NcnnMobileClipNativeService _ncnnService = NcnnMobileClipNativeService();
  final MobileClipBackendPreferenceService _preferenceService =
      MobileClipBackendPreferenceService();

  Future<MobileClipBackend> getSelectedBackend() async {
    return _preferenceService.getSelectedBackend();
  }

  Future<void> releaseBackend(MobileClipBackend backend) async {
    switch (backend) {
      case MobileClipBackend.onnx:
        await _onnxService.dispose();
      case MobileClipBackend.ncnn:
        await _ncnnService.dispose();
    }
  }

  Future<String?> validateBackend(MobileClipBackend backend) async {
    switch (backend) {
      case MobileClipBackend.onnx:
        await _onnxService.warmUp();
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
      case MobileClipBackend.onnx:
        await _onnxService.warmUp();
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
      case MobileClipBackend.onnx:
        return _onnxService.embedImageFile(imageFile);
      case MobileClipBackend.ncnn:
        final bytes = await imageFile.readAsBytes();
        return _ncnnService.encodeImageBytes(bytes);
    }
  }
}