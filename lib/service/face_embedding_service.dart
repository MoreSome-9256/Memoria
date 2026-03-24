import 'dart:io';

import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_embedding_service.dart';

const String kMobileClipFaceEmbeddingModelVersion =
    'mobileclip2_face_baseline_v1';

class FaceEmbeddingResult {
  const FaceEmbeddingResult({
    required this.embedding,
    required this.modelVersion,
  });

  final List<double> embedding;
  final String modelVersion;
}

abstract class FaceEmbeddingService {
  const FaceEmbeddingService();

  Future<void> warmUp();
  void resetWarmState();
  Future<FaceEmbeddingResult?> embedFaceCrop(File imageFile);
}

class MobileClipFaceEmbeddingService implements FaceEmbeddingService {
  MobileClipFaceEmbeddingService({
    MobileClipEmbeddingService? embeddingService,
  }) : _embeddingService = embeddingService ?? MobileClipEmbeddingService();

  final MobileClipEmbeddingService _embeddingService;
  MobileClipBackend? _cachedBackend;
  bool _isWarmedUp = false;

  @override
  Future<void> warmUp() async {
    if (_isWarmedUp && _cachedBackend != null) {
      return;
    }
    _cachedBackend = await _embeddingService.getSelectedBackend();
    await _embeddingService.warmUpBackend(_cachedBackend!);
    _isWarmedUp = true;
  }

  @override
  void resetWarmState() {
    _cachedBackend = null;
    _isWarmedUp = false;
  }

  @override
  Future<FaceEmbeddingResult?> embedFaceCrop(File imageFile) async {
    if (!imageFile.existsSync()) {
      return null;
    }

    await warmUp();
    final embedding = await _embeddingService.embedImageFileWithBackend(
      imageFile,
      _cachedBackend!,
    );
    if (embedding.isEmpty) {
      return null;
    }

    return FaceEmbeddingResult(
      embedding: embedding,
      modelVersion: kMobileClipFaceEmbeddingModelVersion,
    );
  }
}
