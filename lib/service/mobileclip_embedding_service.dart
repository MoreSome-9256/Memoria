/// MobileCLIP 图像嵌入服务，负责提取图片语义向量。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../models/entity/photo_entity.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../storage/vector_index/vector_index_constants.dart';
import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_litert_service.dart';
import 'app_ai_settings_service.dart';
import 'ncnn_mobileclip_native_service.dart';

class MobileClipEmbeddingService {
  MobileClipEmbeddingService._internal();

  static final MobileClipEmbeddingService _instance =
      MobileClipEmbeddingService._internal();

  factory MobileClipEmbeddingService() => _instance;

  MobileClipLiteRtService _mobileclip2LiteRtService = MobileClipLiteRtService();
  final NcnnMobileClipNativeService _ncnnService =
      NcnnMobileClipNativeService();
  final MobileClipBackendPreferenceService _preferenceService =
      MobileClipBackendPreferenceService();
  final PhotoEmbeddingIndexRepository _photoEmbeddingIndexRepository =
      PhotoEmbeddingIndexRepository();

  static const int expectedEmbeddingDim = 512;
  static const Duration _defaultIdleDisposeDelay = Duration(minutes: 3);
  int _workflowLeaseCount = 0;
  Timer? _idleDisposeTimer;

  Future<String> getSelectedModelVersion({MobileClipBackend? backend}) async {
    final effectiveBackend = backend ?? await getSelectedBackend();
    return buildPhotoEmbeddingModelVersion(effectiveBackend);
  }

  List<double>? readIndexedEmbeddingForPhoto({
    required PhotoEntity photo,
    required String modelVersion,
  }) {
    return _photoEmbeddingIndexRepository.readEmbeddingForPhoto(
      photo,
      modelVersion: modelVersion,
    );
  }

  bool hasReusableEmbedding(PhotoEntity photo, {required String modelVersion}) {
    final embedding = readIndexedEmbeddingForPhoto(
      photo: photo,
      modelVersion: modelVersion,
    );
    return embedding != null && embedding.length == expectedEmbeddingDim;
  }

  Future<MobileClipEmbeddingResolution> resolvePhotoEmbedding({
    required PhotoEntity photo,
    Uint8List? preferredImageBytes,
    MobileClipBackend? backend,
  }) async {
    _touchUsage();

    final effectiveBackend = backend ?? await getSelectedBackend();
    final activeModelVersion = await getSelectedModelVersion(
      backend: effectiveBackend,
    );
    final existing = _photoEmbeddingIndexRepository.readEmbeddingForPhoto(
      photo,
      modelVersion: activeModelVersion,
    );
    if (existing != null && existing.length == expectedEmbeddingDim) {
      photo.imageEmbedding = existing;
      return MobileClipEmbeddingResolution(
        reusedCache: true,
        profile: MobileClipEmbeddingProfile(
          backendLabel: effectiveBackend.label,
          providerLabel: 'ObjectBox cache',
        ),
      );
    }

    final profile = await _profileEmbedding(
      preferredImageBytes: preferredImageBytes,
      imageFile: File(photo.path),
      backend: effectiveBackend,
    );
    final embedding = profile.embedding;

    if (embedding.length != expectedEmbeddingDim) {
      throw StateError(
        'MobileCLIP 向量维度异常: ${embedding.length} (expected=$expectedEmbeddingDim)',
      );
    }

    photo.imageEmbedding = embedding;
    final vectorWriteWatch = Stopwatch()..start();
    _photoEmbeddingIndexRepository.upsertEmbedding(
      photoId: photo.id,
      vector: embedding,
      modelVersion: activeModelVersion,
    );
    vectorWriteWatch.stop();
    return MobileClipEmbeddingResolution(
      reusedCache: false,
      profile: profile.copyWith(
        vectorIndexWriteMs: vectorWriteWatch.elapsedMicroseconds / 1000.0,
      ),
    );
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
        await _mobileclip2LiteRtService.dispose();
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
      case MobileClipBackend.mobileclip2LiteRt:
        await _mobileclip2LiteRtService.dispose();
      case MobileClipBackend.ncnn:
        await _ncnnService.dispose();
    }
  }

  Future<String?> validateBackend(MobileClipBackend backend) async {
    _touchUsage();
    switch (backend) {
      case MobileClipBackend.mobileclip2LiteRt:
        _mobileclip2LiteRtService = await _resolveLiteRtService();
        await _mobileclip2LiteRtService.warmUp();
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
      case MobileClipBackend.mobileclip2LiteRt:
        _mobileclip2LiteRtService = await _resolveLiteRtService();
        await _mobileclip2LiteRtService.warmUp();
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
      case MobileClipBackend.mobileclip2LiteRt:
        _mobileclip2LiteRtService = await _resolveLiteRtService();
        return _mobileclip2LiteRtService.embedImageFile(imageFile);
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
      case MobileClipBackend.mobileclip2LiteRt:
        _mobileclip2LiteRtService = await _resolveLiteRtService();
        return _mobileclip2LiteRtService.embedImageBytes(imageBytes);
      case MobileClipBackend.ncnn:
        return _ncnnService.encodeImageBytes(imageBytes);
    }
  }

  Future<MobileClipEmbeddingProfile> _profileEmbedding({
    required Uint8List? preferredImageBytes,
    required File imageFile,
    required MobileClipBackend backend,
  }) async {
    final imageBytes =
        preferredImageBytes != null && preferredImageBytes.isNotEmpty
        ? preferredImageBytes
        : await imageFile.readAsBytes();

    switch (backend) {
      case MobileClipBackend.mobileclip2LiteRt:
        _mobileclip2LiteRtService = await _resolveLiteRtService();
        final profile = await _mobileclip2LiteRtService.profileImageBytes(
          imageBytes,
        );
        return MobileClipEmbeddingProfile(
          embedding: profile.embedding,
          backendLabel: backend.label,
          providerLabel: _mobileclip2LiteRtService.executionProviderLabel,
          decodeMs: profile.decodeMs,
          resizeNormalizeMs: profile.resizeNormalizeMs,
          tensorBuildMs: profile.tensorBuildMs,
          inferenceMs: profile.inferenceMs,
        );
      case MobileClipBackend.ncnn:
        final profile = await _ncnnService.profileEncodeImageBytes(imageBytes);
        return MobileClipEmbeddingProfile(
          embedding: profile.embedding,
          backendLabel: backend.label,
          providerLabel: _ncnnService.getStatus().version,
          decodeMs: profile.preprocessMs,
          resizeNormalizeMs: 0,
          tensorBuildMs: 0,
          inferenceMs: profile.inferenceMs,
        );
    }
  }

  Future<MobileClipLiteRtService> _resolveLiteRtService() async {
    final settings = await AppAiSettingsService.instance.load();
    return MobileClipLiteRtService.withAccelerator(
      settings.inferenceAccelerator,
    );
  }
}

class MobileClipEmbeddingResolution {
  const MobileClipEmbeddingResolution({
    required this.reusedCache,
    this.profile,
  });

  final bool reusedCache;
  final MobileClipEmbeddingProfile? profile;
}

class MobileClipEmbeddingProfile {
  const MobileClipEmbeddingProfile({
    this.embedding = const <double>[],
    required this.backendLabel,
    required this.providerLabel,
    this.decodeMs = 0,
    this.resizeNormalizeMs = 0,
    this.tensorBuildMs = 0,
    this.inferenceMs = 0,
    this.vectorIndexWriteMs = 0,
  });

  final List<double> embedding;
  final String backendLabel;
  final String providerLabel;
  final double decodeMs;
  final double resizeNormalizeMs;
  final double tensorBuildMs;
  final double inferenceMs;
  final double vectorIndexWriteMs;

  double get preprocessMs => decodeMs + resizeNormalizeMs;

  MobileClipEmbeddingProfile copyWith({
    List<double>? embedding,
    String? backendLabel,
    String? providerLabel,
    double? decodeMs,
    double? resizeNormalizeMs,
    double? tensorBuildMs,
    double? inferenceMs,
    double? vectorIndexWriteMs,
  }) {
    return MobileClipEmbeddingProfile(
      embedding: embedding ?? this.embedding,
      backendLabel: backendLabel ?? this.backendLabel,
      providerLabel: providerLabel ?? this.providerLabel,
      decodeMs: decodeMs ?? this.decodeMs,
      resizeNormalizeMs: resizeNormalizeMs ?? this.resizeNormalizeMs,
      tensorBuildMs: tensorBuildMs ?? this.tensorBuildMs,
      inferenceMs: inferenceMs ?? this.inferenceMs,
      vectorIndexWriteMs: vectorIndexWriteMs ?? this.vectorIndexWriteMs,
    );
  }
}
