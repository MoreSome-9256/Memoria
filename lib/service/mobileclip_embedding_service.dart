import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../models/entity/photo_entity.dart';
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
  final NcnnMobileClipNativeService _ncnnService =
      NcnnMobileClipNativeService();
  final MobileClipBackendPreferenceService _preferenceService =
      MobileClipBackendPreferenceService();

  static const int expectedEmbeddingDim = 512;
  static const Duration _defaultIdleDisposeDelay = Duration(minutes: 3);
  int _workflowLeaseCount = 0;
  Timer? _idleDisposeTimer;

  bool hasReusableEmbedding(PhotoEntity photo) {
    final embedding = photo.imageEmbedding;
    return embedding != null && embedding.length == expectedEmbeddingDim;
  }

  Future<MobileClipEmbeddingResolution> resolvePhotoEmbedding({
    required PhotoEntity photo,
    Uint8List? preferredImageBytes,
    MobileClipBackend? backend,
  }) async {
    _touchUsage();

    final existing = photo.imageEmbedding;
    if (existing != null && existing.length == expectedEmbeddingDim) {
      return const MobileClipEmbeddingResolution(reusedCache: true);
    }

    final effectiveBackend = backend ?? await getSelectedBackend();
    final embedding =
        preferredImageBytes != null && preferredImageBytes.isNotEmpty
        ? await embedImageBytesWithBackend(
            preferredImageBytes,
            effectiveBackend,
          )
        : await embedImageFileWithBackend(File(photo.path), effectiveBackend);

    if (embedding.length != expectedEmbeddingDim) {
      throw StateError(
        'MobileCLIP 向量维度异常: ${embedding.length} (expected=$expectedEmbeddingDim)',
      );
    }

    photo.imageEmbedding = embedding;
    return const MobileClipEmbeddingResolution(reusedCache: false);
  }

  Future<void> beginWorkflowSession() async {
    _workflowLeaseCount++;
    _cancelIdleDisposeTimer();
  }

  Future<void> endWorkflowSession({
    Duration idleDisposeDelay = _defaultIdleDisposeDelay,
  }) async {
    if (_workflowLeaseCount > 0) {
      _workflowLeaseCount--;
    }
    if (_workflowLeaseCount == 0) {
      _scheduleIdleDispose(idleDisposeDelay);
    }
  }

  void _touchUsage() {
    _cancelIdleDisposeTimer();
  }

  void _cancelIdleDisposeTimer() {
    _idleDisposeTimer?.cancel();
    _idleDisposeTimer = null;
  }

  void _scheduleIdleDispose(Duration delay) {
    _cancelIdleDisposeTimer();
    _idleDisposeTimer = Timer(delay, () async {
      if (_workflowLeaseCount > 0) {
        return;
      }
      try {
        await _mobileclip2OnnxService.dispose();
      } catch (_) {}
      try {
        await _ncnnService.dispose();
      } catch (_) {}
    });
  }

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
    _touchUsage();
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
    _touchUsage();
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

    // 按需加载：切换配置时只持久化选择，不在设置阶段预热模型。
    if (_workflowLeaseCount == 0) {
      await releaseBackend(currentBackend);
    }
    await _preferenceService.setSelectedBackend(newBackend);
  }

  Future<List<double>> embedImageFileWithBackend(
    File imageFile,
    MobileClipBackend backend,
  ) async {
    _touchUsage();
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
    _touchUsage();
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

class MobileClipEmbeddingResolution {
  const MobileClipEmbeddingResolution({required this.reusedCache});

  final bool reusedCache;
}
