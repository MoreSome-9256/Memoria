part of 'ai_service.dart';

class _AiPhotoProcessor {
  const _AiPhotoProcessor();

  Future<_PhotoProcessResult> process(_AiPhotoProcessingRequest request) async {
    final profile = _AiPhotoProfile(
      photoId: request.photo.id,
      backendLabel: request.selectedBackend.label,
    );
    File? analysisFile;
    try {
      profile.inputStrategy = AIService._analysisInputConfig.strategy.label;
      profile.auxiliaryStrategy =
          AIService._analysisAuxiliaryConfig.strategy.label;
      final prepared = await _prepareAnalysisInputConfigured(request.photo);
      if (prepared == null) {
        profile.outcome = 'prepare_failed';
        return _PhotoProcessResult.failed(profile: profile);
      }

      profile.inputLoadMs = prepared.loadMs;
      profile.thumbnailReadMs = prepared.thumbnailReadMs;
      profile.fileReadMs = prepared.fileReadMs;
      profile.inputBytes = prepared.mobileClipBytes.lengthInBytes;
      profile.inputSource = prepared.inputSource;
      profile.inputStrategy = prepared.inputStrategy;
      profile.usedThumbnail = prepared.usedThumbnail;
      profile.thumbnailAttempted = prepared.thumbnailAttempted;
      profile.thumbnailTimedOut = prepared.thumbnailTimedOut;
      profile.fallbackToOriginal = prepared.fallbackToOriginal;
      profile.fallbackReason = prepared.fallbackReason;

      final resolution = await request.mobileClipEmbeddingService
          .resolvePhotoEmbedding(
            photo: request.photo,
            preferredImageBytes: prepared.mobileClipBytes,
            backend: request.selectedBackend,
          );
      final embeddingProfile = resolution.profile;
      profile.embeddingCacheHit = resolution.reusedCache;
      if (embeddingProfile != null) {
        profile.providerLabel = embeddingProfile.providerLabel;
        profile.decodeMs = embeddingProfile.decodeMs;
        profile.resizeNormalizeMs = embeddingProfile.resizeNormalizeMs;
        profile.tensorBuildMs = embeddingProfile.tensorBuildMs;
        profile.inferenceMs = embeddingProfile.inferenceMs;
        profile.objectBoxWriteMs = embeddingProfile.vectorIndexWriteMs;
      }
      final embedding = request.photo.imageEmbedding ?? const <double>[];
      if (embedding.isEmpty) {
        profile.outcome = 'embedding_empty';
        return _PhotoProcessResult.failed(profile: profile);
      }

      if (!request.skipJunkFilter) {
        final junkWatch = Stopwatch()..start();
        final junkDecision = await request.junkPhotoFilterService.evaluatePhoto(
          photo: request.photo,
          imageEmbedding: embedding,
        );
        junkWatch.stop();
        profile.junkFilterMs = junkWatch.elapsedMicroseconds / 1000.0;
        if (junkDecision.shouldFilter) {
          profile.outcome = 'junk_filtered';
          return _PhotoProcessResult.success(
            eventId: request.photo.eventId,
            junkCandidate: JunkPhotoCleanupCandidate(
              photoId: request.photo.id,
              assetId: request.photo.assetId,
              path: request.photo.path,
              timestamp: request.photo.timestamp,
              reasons: junkDecision.hits,
            ),
            persistenceRequest: _AiPhotoWriteRequest(
              photoId: request.photo.id,
              tags: const <String>[JunkPhotoFilterService.junkCandidateTag],
              imageEmbedding: embedding,
              aiCaption: '',
              ocrText: '',
              ocrTags: const <String>[],
              faceCount: 0,
              smileProb: 0.0,
              joyScore: 0.0,
              skipVectorIndexWrite: true,
            ),
            profile: profile,
          );
        }
      }

      final tagWatch = Stopwatch()..start();
      final mobileClipTags = await request.mobileClipTagService.retrieveTags(
        embedding,
      );
      tagWatch.stop();
      profile.tagRetrievalMs = tagWatch.elapsedMicroseconds / 1000.0;
      final visualTags = _sanitizeVisualTags(mobileClipTags);

      final auxiliaryFileWatch = Stopwatch()..start();
      final resolvedAnalysisFile = await _AnalysisFileResolver(
        config: AIService._analysisAuxiliaryConfig,
        createCompressedFile: _createAuxiliaryAnalysisFile,
      ).resolve(sourceFile: prepared.file, photoId: request.photo.id);
      analysisFile = resolvedAnalysisFile.file;
      auxiliaryFileWatch.stop();
      profile.auxiliaryFileMs = auxiliaryFileWatch.elapsedMicroseconds / 1000.0;
      profile.auxiliarySource = resolvedAnalysisFile.source;
      profile.auxiliaryCreated = resolvedAnalysisFile.createdTemporaryFile;
      final inputImage = InputImage.fromFile(analysisFile);

      var ocrResult = OcrResult.empty();
      if (OcrService.shouldRunOcr(
        visualTags,
        aspectRatio: request.photo.aspectRatio,
      )) {
        final ocrWatch = Stopwatch()..start();
        ocrResult = await request.ocrService.analyzeImageFile(analysisFile);
        ocrWatch.stop();
        profile.ocrMs = ocrWatch.elapsedMicroseconds / 1000.0;
      }

      final dimensionWatch = Stopwatch()..start();
      final analysisDimensions = await _readImageDimensions(
        analysisFile,
        knownWidth: request.photo.width,
        knownHeight: request.photo.height,
      );
      dimensionWatch.stop();
      profile.analysisDecodeMs = dimensionWatch.elapsedMicroseconds / 1000.0;
      final canRunFaceDetection =
          analysisDimensions != null &&
          analysisDimensions.$1 >= AIService._minFaceDetectorInputSize &&
          analysisDimensions.$2 >= AIService._minFaceDetectorInputSize;
      if (!canRunFaceDetection) {
        final sizeLabel = analysisDimensions == null
            ? 'unknown'
            : '${analysisDimensions.$1}x${analysisDimensions.$2}';
        debugPrint(
          '鈴笍 璺宠繃浜鸿劯妫€娴?photoId=${request.photo.id} '
          'dbSize=${request.photo.width}x${request.photo.height} '
          'analysisSize=$sizeLabel path=${analysisFile.path}',
        );
      }

      final faceDetectionWatch = Stopwatch()..start();
      final faces = canRunFaceDetection
          ? await request.faceDetector.processImage(inputImage)
          : const <Face>[];
      faceDetectionWatch.stop();
      profile.faceDetectionMs = faceDetectionWatch.elapsedMicroseconds / 1000.0;
      final faceCount = faces.length;
      final maxSmileProb = faces.isNotEmpty
          ? faces
                .map((face) => face.smilingProbability ?? 0.0)
                .reduce((a, b) => a > b ? a : b)
          : 0.0;
      final joyScore = AIScoreHelper.calculateJoyScore(
        faceCount: faceCount,
        maxSmileProb: maxSmileProb,
        tags: visualTags,
      );

      final facePipelineProfile = await request.facePipelineService
          .rebuildFacesForPhoto(
            isar: request.isar,
            photo: request.photo,
            imageFile: analysisFile,
            imageBytes: resolvedAnalysisFile.sourceBytes,
            faces: faces,
          );
      profile.facePersistMs = facePipelineProfile.totalMs;
      profile.faceExistingReadMs = facePipelineProfile.existingReadMs;
      profile.faceSourceDecodeMs = facePipelineProfile.sourceDecodeMs;
      profile.faceWarmUpMs = facePipelineProfile.embeddingWarmUpMs;
      profile.faceCropMs = facePipelineProfile.cropMs;
      profile.faceDebugCropMs = facePipelineProfile.debugCropMs;
      profile.faceTempFileMs = facePipelineProfile.tempFileMs;
      profile.faceEmbeddingMs = facePipelineProfile.embeddingMs;
      profile.faceIsarWriteMs = facePipelineProfile.isarWriteMs;
      profile.faceIsarDeleteMs = facePipelineProfile.isarDeleteMs;
      profile.faceIsarPutMs = facePipelineProfile.isarPutMs;
      profile.faceObjectBoxWriteMs = facePipelineProfile.objectBoxWriteMs;
      profile.faceCleanupMs = facePipelineProfile.cleanupMs;
      profile.faceRequestedCount = facePipelineProfile.requestedFaces;
      profile.facePersistedCount = facePipelineProfile.persistedFaces;
      profile.faceStaleIdsCount = facePipelineProfile.staleIdsCount;
      profile.faceEmbeddingFacesWritten =
          facePipelineProfile.facesWithEmbedding;
      profile.faceEmbeddingBytesWritten =
          facePipelineProfile.embeddingBytesWritten;
      profile.faceWritesEmbeddingToIsar =
          facePipelineProfile.writesEmbeddingToIsar;

      final captionLocation =
          request.photo.locationName ??
          request.photo.district ??
          request.photo.city ??
          request.photo.province;
      final takenAt = DateTime.fromMillisecondsSinceEpoch(
        request.photo.timestamp,
      );
      var caption = '';
      _AsyncCaptionTask? deferredCaptionTask;
      if (request.photoCaptionService.prefersAsyncGeneration &&
          !request.stopRequested) {
        profile.captionDeferred = true;
        deferredCaptionTask = _AsyncCaptionTask(
          photoId: request.photo.id,
          imageFile: prepared.file,
          deleteImageFileAfterUse: false,
          captionService: request.photoCaptionService,
          visualTags: visualTags,
          ocrTags: ocrResult.tags,
          ocrText: ocrResult.text,
          location: captionLocation,
          takenAt: takenAt,
          isProbablyScreenshot: request.photo.isProbablyScreenshot,
          faceCount: faceCount,
        );
      } else {
        final captionWatch = Stopwatch()..start();
        caption = await request.photoCaptionService.generateCaption(
          imageFile: prepared.file,
          visualTags: visualTags,
          ocrTags: ocrResult.tags,
          ocrText: ocrResult.text,
          location: captionLocation,
          takenAt: takenAt,
          isProbablyScreenshot: request.photo.isProbablyScreenshot,
          faceCount: faceCount,
        );
        captionWatch.stop();
        profile.captionMs = captionWatch.elapsedMicroseconds / 1000.0;
      }

      profile.outcome = 'completed';
      return _PhotoProcessResult.success(
        eventId: request.photo.eventId,
        persistenceRequest: _AiPhotoWriteRequest(
          photoId: request.photo.id,
          tags: visualTags,
          imageEmbedding: embedding,
          aiCaption: caption,
          ocrText: ocrResult.text,
          ocrTags: ocrResult.tags,
          faceCount: faceCount,
          smileProb: maxSmileProb,
          joyScore: joyScore,
          skipVectorIndexWrite: true,
        ),
        deferredCaptionTask: deferredCaptionTask,
        profile: profile,
      );
    } catch (error) {
      debugPrint('鉂?AI 鍒嗘瀽澶辫触 photoId=${request.photo.id}: $error');
      profile.outcome = 'error';
      profile.error = error.toString();
      return _PhotoProcessResult.failed(profile: profile);
    } finally {
      if (analysisFile != null &&
          analysisFile.path != request.photo.path &&
          analysisFile.existsSync()) {
        try {
          await analysisFile.delete();
        } catch (error) {
          debugPrint('鈿狅笍 娓呯悊涓存椂鏂囦欢澶辫触: $error');
        }
      }
    }
  }

  List<String> _sanitizeVisualTags(List<String> source, {int maxTags = 5}) {
    final sanitized = <String>[];
    for (final tag in source) {
      final normalized = TagSanitizer.sanitizeVisualTag(tag);
      if (normalized == null || sanitized.contains(normalized)) {
        continue;
      }
      if (AIService._blockedVisualTags.contains(normalized)) {
        continue;
      }
      if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(normalized)) {
        continue;
      }
      if (normalized.contains('鏅鸿兘褰辫') || normalized.contains('鎴戠殑鐩稿唽')) {
        continue;
      }
      sanitized.add(normalized);
      if (sanitized.length >= maxTags) {
        break;
      }
    }
    return TagSanitizer.sanitizeVisualTags(sanitized, maxTags: maxTags);
  }

  Future<_PreparedAnalysisInput?> _prepareAnalysisInputConfigured(
    PhotoEntity photo,
  ) {
    if (AIService._analysisInputConfig.strategy ==
        _AnalysisInputStrategy.thumbnailFirst) {
      return _prepareAnalysisInput(photo);
    }
    return _AnalysisInputLoader(
      config: AIService._analysisInputConfig,
      thumbnailSize: AIService._mobileClipThumbnailSize,
    ).load(photo);
  }

  Future<_PreparedAnalysisInput?> _prepareAnalysisInput(
    PhotoEntity photo,
  ) async {
    final file = File(photo.path);
    if (!file.existsSync()) {
      return null;
    }

    final loadWatch = Stopwatch()..start();
    Uint8List? mobileClipBytes;
    var thumbnailReadMs = 0.0;
    var fileReadMs = 0.0;
    var inputSource = 'original_file';
    var fallbackReason = 'none';
    try {
      final asset = await AssetEntity.fromId(photo.assetId);
      final thumbnailWatch = Stopwatch()..start();
      mobileClipBytes = await asset?.thumbnailDataWithSize(
        AIService._mobileClipThumbnailSize,
      );
      thumbnailWatch.stop();
      thumbnailReadMs = thumbnailWatch.elapsedMicroseconds / 1000.0;
      if (mobileClipBytes != null && mobileClipBytes.isNotEmpty) {
        inputSource = 'thumbnail';
      } else if (asset == null) {
        fallbackReason = 'asset_unavailable';
      } else {
        fallbackReason = 'thumbnail_empty';
      }
    } catch (error) {
      fallbackReason = 'thumbnail_error';
      debugPrint('鈿狅笍 璇诲彇绯荤粺缂╃暐鍥惧け璐?photoId=${photo.id}: $error');
    }

    if (mobileClipBytes == null || mobileClipBytes.isEmpty) {
      final fileReadWatch = Stopwatch()..start();
      mobileClipBytes = await file.readAsBytes();
      fileReadWatch.stop();
      fileReadMs = fileReadWatch.elapsedMicroseconds / 1000.0;
    }
    if (mobileClipBytes.isEmpty) {
      return null;
    }
    loadWatch.stop();

    return _PreparedAnalysisInput(
      photo: photo,
      file: file,
      mobileClipBytes: mobileClipBytes,
      usedThumbnail: inputSource == 'thumbnail',
      inputSource: inputSource,
      inputStrategy: _AnalysisInputStrategy.thumbnailFirst.label,
      thumbnailAttempted: true,
      thumbnailTimedOut: false,
      fallbackToOriginal: inputSource != 'thumbnail',
      fallbackReason: inputSource == 'thumbnail' ? 'none' : fallbackReason,
      loadMs: loadWatch.elapsedMicroseconds / 1000.0,
      thumbnailReadMs: thumbnailReadMs,
      fileReadMs: fileReadMs,
    );
  }

  Future<_CreatedAnalysisFile> _createAuxiliaryAnalysisFile(
    File sourceFile,
    int photoId,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
    final targetPath =
        '${tempDir.path}/temp_mlkit_${photoId}_$uniqueSuffix.jpg';
    final bytes = await FlutterImageCompress.compressWithFile(
      sourceFile.absolute.path,
      minWidth: 1024,
      minHeight: 1024,
      quality: 80,
    );
    if (bytes == null || bytes.isEmpty) {
      throw Exception('鍘嬬缉澶辫触');
    }
    final file = File(targetPath);
    await file.writeAsBytes(bytes, flush: true);
    return _CreatedAnalysisFile(file: file, bytes: bytes);
  }
}
