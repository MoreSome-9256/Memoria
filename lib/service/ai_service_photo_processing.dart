part of 'ai_service.dart';

extension AIServicePhotoProcessing on AIService {
  Future<_PhotoProcessResult> _processSinglePhoto(
    _AiPhotoProcessingRequest request,
  ) {
    return const _AiPhotoProcessor().process(request);
  }

  Future<_PhotoProcessResult> _applyPhotoProcessResult(
    _PhotoProcessResult result, {
    required Isar isar,
    required MobileClipBackend selectedBackend,
  }) async {
    final writeRequest = result.persistenceRequest;
    try {
      if (writeRequest != null) {
        final persistenceProfile = await _markAsAnalyzed(
          writeRequest.photoId,
          writeRequest.tags,
          writeRequest.imageEmbedding,
          writeRequest.aiCaption,
          writeRequest.ocrText,
          writeRequest.ocrTags,
          writeRequest.faceCount,
          writeRequest.smileProb,
          writeRequest.joyScore,
          isar,
          selectedBackend,
          skipVectorIndexWrite: writeRequest.skipVectorIndexWrite,
        );
        result.profile.isarWriteMs = persistenceProfile.isarWriteMs;
        result.profile.objectBoxWriteMs = persistenceProfile.objectBoxWriteMs;
      }
      if (result.deferredCaptionTask != null) {
        _enqueueAsyncCaption(result.deferredCaptionTask!);
      }
      return result;
    } catch (error) {
      debugPrint(
        '鈿狅笍 AI apply processed photo failed '
        'photoId=${result.profile.photoId} error=$error',
      );
      result.profile.outcome = 'error';
      result.profile.error = error.toString();
      return _PhotoProcessResult.failed(profile: result.profile);
    }
  }

  Future<_AiPersistenceProfile> _markAsAnalyzed(
    Id id,
    List<String> tags,
    List<double> imageEmbedding,
    String aiCaption,
    String ocrText,
    List<String> ocrTags,
    int faceCount,
    double smileProb,
    double joyScore,
    Isar isar,
    MobileClipBackend selectedBackend, {
    bool skipVectorIndexWrite = false,
  }) async {
    final isarWriteWatch = Stopwatch()..start();
    await isar.writeTxn(() async {
      final p = await isar.collection<PhotoEntity>().get(id);
      if (p != null) {
        p.aiTags = tags;
        p.isAiAnalyzed = true;
        p.aiCaption = aiCaption.isEmpty ? null : aiCaption;
        p.imageEmbedding = imageEmbedding.isEmpty ? null : imageEmbedding;
        p.ocrText = ocrText.isEmpty ? null : ocrText;
        p.ocrTags = ocrTags;
        p.faceCount = faceCount;
        p.smileProb = smileProb;
        p.joyScore = joyScore;
        await isar.collection<PhotoEntity>().put(p);
      }
    });
    isarWriteWatch.stop();

    var objectBoxWriteMs = 0.0;
    if (!skipVectorIndexWrite) {
      final objectBoxWriteWatch = Stopwatch()..start();
      if (imageEmbedding.isEmpty) {
        _photoEmbeddingIndexRepository.deleteByPhotoIds(<int>[id]);
      } else {
        _photoEmbeddingIndexRepository.upsertEmbedding(
          photoId: id,
          vector: imageEmbedding,
          modelVersion: buildPhotoEmbeddingModelVersion(selectedBackend),
        );
      }
      objectBoxWriteWatch.stop();
      objectBoxWriteMs = objectBoxWriteWatch.elapsedMicroseconds / 1000.0;
    }

    return _AiPersistenceProfile(
      isarWriteMs: isarWriteWatch.elapsedMicroseconds / 1000.0,
      objectBoxWriteMs: objectBoxWriteMs,
    );
  }

  Future<Map<String, int>> getAnalysisProgress() async {
    final isar = PhotoService().isar;

    final total = await isar.collection<PhotoEntity>().count();
    final analyzed = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .count();

    return {'total': total, 'analyzed': analyzed, 'pending': total - analyzed};
  }
}

Future<(int, int)?> _readImageDimensions(
  File imageFile, {
  int? knownWidth,
  int? knownHeight,
}) async {
  try {
    if (knownWidth != null &&
        knownHeight != null &&
        knownWidth > 0 &&
        knownHeight > 0) {
      return (knownWidth, knownHeight);
    }

    final bytes = await imageFile.readAsBytes();
    final decoder = img.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info != null && info.width > 0 && info.height > 0) {
      return (info.width, info.height);
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }
    final baked = img.bakeOrientation(decoded);
    return (baked.width, baked.height);
  } catch (error) {
    debugPrint('鈿狅笍 璇诲彇鍒嗘瀽鍥惧昂瀵稿け璐?path=${imageFile.path}: $error');
    return null;
  }
}
