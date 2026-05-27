/// AI 服务中的照片处理分组，包含预处理、提取和结果整合逻辑。

part of 'ai_service.dart';

extension AIServicePhotoProcessing on AIService {
  Future<_PhotoProcessResult> _processSinglePhoto(
    _AiPhotoProcessingRequest request,
  ) {
    return const _AiPhotoProcessor().process(request);
  }

  Future<_PhotoProcessResult> _applyPhotoProcessResult(
    _PhotoProcessResult result, {
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
          selectedBackend,
          skipVectorIndexWrite: writeRequest.skipVectorIndexWrite,
        );
        result.profile.isarWriteMs = persistenceProfile.isarWriteMs;
        result.profile.objectBoxWriteMs = persistenceProfile.objectBoxWriteMs;
      }
      if (result.deferredCaptionTask != null) {
        await _runAsyncCaptionTask(result.deferredCaptionTask!);
      }
      return result;
    } catch (error) {
      debugPrint(
        'AI 写入照片分析结果失败 photoId=${result.profile.photoId} error=$error',
      );
      result.profile.outcome = 'error';
      result.profile.error = error.toString();
      return _PhotoProcessResult.failed(profile: result.profile);
    }
  }

  Future<_AiPersistenceProfile> _markAsAnalyzed(
    int id,
    List<String> tags,
    List<double> imageEmbedding,
    String aiCaption,
    String ocrText,
    List<String> ocrTags,
    int faceCount,
    double smileProb,
    double joyScore,
    MobileClipBackend selectedBackend, {
    bool skipVectorIndexWrite = false,
  }) async {
    final isarWriteWatch = Stopwatch()..start();
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    var storeImageEmbedding = true;
    store.runInTransaction(TxMode.write, () {
      final p = photoBox.get(id);
      if (p != null) {
        final mediaKind = MediaTypeHelper.fromStorageValue(
          p.mediaKind,
          path: p.path,
        );
        storeImageEmbedding = mediaKind == MemoriaMediaKind.image;
        p.aiTags = tags;
        p.isAiAnalyzed = true;
        p.aiCaption = aiCaption.isEmpty ? null : aiCaption;
        p.imageEmbedding = storeImageEmbedding && imageEmbedding.isNotEmpty
            ? imageEmbedding
            : null;
        p.ocrText = ocrText.isEmpty ? null : ocrText;
        p.ocrTags = ocrTags;
        p.faceCount = faceCount;
        p.smileProb = smileProb;
        p.joyScore = joyScore;
        photoBox.put(p);
      }
    });
    isarWriteWatch.stop();

    var objectBoxWriteMs = 0.0;
    if (!skipVectorIndexWrite) {
      final objectBoxWriteWatch = Stopwatch()..start();
      if (imageEmbedding.isEmpty || !storeImageEmbedding) {
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
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final total = photoBox.count();
    final q = photoBox.query(PhotoEntity_.isAiAnalyzed.equals(true)).build();
    final analyzed = q.count();
    q.close();

    return {'total': total, 'analyzed': analyzed, 'pending': total - analyzed};
  }
}
