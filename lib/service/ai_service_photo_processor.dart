/// AI 服务的照片处理器分组，封装具体的图片分析实现。
///
/// 重计算操作已迁移到 `_process*Isolate` 顶层函数中，通过 `compute()`
/// 在后台 isolate 执行，不阻塞主 UI isolate。

part of 'ai_service.dart';

// ── 后台 isolate 计算函数 ──────────────────────────────────────────
// 这些函数必须是顶层函数（或静态函数），才能被 `compute()` / `Isolate.run()` 调用。
// 输入输出均为可序列化的简单类型，通过 Map/List 跨 isolate 传递。

/// 后台 isolate：垃圾照片过滤（余弦相似度 × 7 个分类原型）
Map<String, Object?> _computeJunkFilter(Map<String, Object?> params) {
  final embedding = (params['embedding'] as List<Object?>).cast<double>();
  final prototypes = (params['prototypes'] as Map<String, Object?>).map(
    (k, v) => MapEntry(k, (v as List<Object?>).cast<double>()),
  );
  final isProbablyScreenshot = params['isProbablyScreenshot'] as bool? ?? false;
  final ocrText = params['ocrText'] as String? ?? '';
  final definitions = (params['definitions'] as List<Object?>)
      .cast<Map<String, Object?>>();

  final hits = <Map<String, Object?>>[];
  for (final def in definitions) {
    final id = def['id'] as String;
    final prototype = prototypes[id];
    if (prototype == null || prototype.length != embedding.length) continue;

    var score = _cosineSimilarity(embedding, prototype);
    final screenshotBoost = (def['screenshotBoost'] as num?)?.toDouble() ?? 0.0;
    if (screenshotBoost > 0 && isProbablyScreenshot) score += screenshotBoost;
    final ocrBoost = (def['ocrBoost'] as num?)?.toDouble() ?? 0.0;
    final ocrThreshold = (def['ocrBoostThreshold'] as num?)?.toInt() ?? 9999;
    if (ocrBoost > 0 && ocrText.length >= ocrThreshold) score += ocrBoost;
    score = score.clamp(-1.0, 1.0);

    final threshold = (def['threshold'] as num).toDouble();
    if (score >= threshold) {
      hits.add(<String, Object?>{
        'categoryId': id,
        'label': def['label'] as String,
        'description': def['description'] as String,
        'score': score,
        'threshold': threshold,
      });
    }
  }
  hits.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
  return <String, Object?>{'shouldFilter': hits.isNotEmpty, 'hits': hits};
}

/// 后台 isolate：标签匹配（coarse → fine 两级余弦相似度）
List<String> _computeTagRetrieval(Map<String, Object?> params) {
  final embedding = (params['embedding'] as List<Object?>).cast<double>();
  final coarsePrototypes = (params['coarsePrototypes'] as Map<String, Object?>)
      .map((k, v) => MapEntry(k, (v as List<Object?>).cast<double>()));
  final finePrototypes = (params['finePrototypes'] as Map<String, Object?>).map(
    (k, v) => MapEntry(k, (v as List<Object?>).cast<double>()),
  );
  final fineLabelToCoarse =
      (params['fineLabelToCoarse'] as Map<String, Object?>).map(
        (k, v) => MapEntry(k, v as String),
      );
  final dimThresholds = (params['dimThresholds'] as Map<String, Object?>).map(
    (k, v) => MapEntry(k, (v as num).toDouble()),
  );
  final coarseThreshold =
      (params['coarseThreshold'] as num?)?.toDouble() ?? 0.16;
  final coarseProbThreshold =
      (params['coarseProbThreshold'] as num?)?.toDouble() ?? 0.035;
  final coarseMargin = (params['coarseMargin'] as num?)?.toDouble() ?? 0.075;
  final blockedTags =
      (params['blockedTags'] as List<Object?>?)?.cast<String>() ?? <String>[];
  final coarseTopK = (params['coarseTopK'] as num?)?.toInt() ?? 2;
  final topK = (params['topK'] as num?)?.toInt() ?? 3;

  // ── 粗粒度匹配（~17 个类别）──────────────────────────
  final coarseScored = <Map<String, Object?>>[];
  for (final entry in coarsePrototypes.entries) {
    final score = _cosineSimilarity(embedding, entry.value);
    if (score >= coarseThreshold) {
      coarseScored.add(<String, Object?>{
        'coarseId': entry.key,
        'score': score,
      });
    }
  }
  coarseScored.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));

  // softmax normalized probabilities
  final scores = coarseScored
      .map((e) => (e['score'] as num).toDouble())
      .toList();
  final maxScore = scores.isEmpty
      ? 0.0
      : scores.reduce((a, b) => a > b ? a : b);
  final expScores = scores.map((s) => _fastExp(s - maxScore)).toList();
  final expSum = expScores.isEmpty ? 1.0 : expScores.reduce((a, b) => a + b);

  // enrich scored with probability
  for (var i = 0; i < coarseScored.length; i++) {
    coarseScored[i] = <String, Object?>{
      ...coarseScored[i],
      'probability': expScores[i] / expSum,
    };
  }

  // filter by probability threshold
  coarseScored.retainWhere(
    (e) => (e['probability'] as num).toDouble() >= coarseProbThreshold,
  );

  // max-topK & margin filter
  coarseScored.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
  final topScore = coarseScored.isNotEmpty
      ? (coarseScored.first['score'] as num).toDouble()
      : 0.0;
  coarseScored.retainWhere(
    (e) => topScore - (e['score'] as num).toDouble() <= coarseMargin,
  );
  final coarseSelected = coarseScored.take(coarseTopK).toList();

  if (coarseSelected.isEmpty) {
    return <String>['照片', '其他'];
  }

  final selectedCoarseIds = coarseSelected
      .map((e) => e['coarseId'] as String)
      .toSet();
  final coarseProbById = <String, double>{
    for (final e in coarseSelected)
      e['coarseId'] as String: (e['probability'] as num).toDouble(),
  };

  // ── 细粒度匹配（~200 个标签）──────────────────────────
  final scored = <_TagCandidate>[];
  for (final entry in finePrototypes.entries) {
    final label = entry.key;
    if (blockedTags.contains(label)) continue;
    final coarseId = fineLabelToCoarse[label];
    if (coarseId == null || !selectedCoarseIds.contains(coarseId)) continue;
    final score = _cosineSimilarity(embedding, entry.value);
    final coarseProb = coarseProbById[coarseId] ?? 0.0;
    final weightedScore = score * (0.5 + 0.5 * coarseProb);

    final dimThreshold = switch (coarseId) {
      'subject' => dimThresholds['subject'] ?? 0.165,
      'scene' => dimThresholds['scene'] ?? 0.17,
      'activity' => dimThresholds['activity'] ?? 0.18,
      'atmosphere' => dimThresholds['atmosphere'] ?? 0.19,
      'media' => dimThresholds['media'] ?? 0.205,
      _ => 0.2,
    };
    if (score < dimThreshold) continue;
    scored.add(
      _TagCandidate(label: label, score: score, weightedScore: weightedScore),
    );
  }

  if (scored.isEmpty) return <String>['照片', '其他'];

  // ── 排序 + 选择 top-K ──────────────────────────────
  scored.sort((a, b) => b.weightedScore.compareTo(a.weightedScore));
  final selected = <String>[];
  final selectedSet = <String>{};
  // 每个 coarse 至少选一个最佳标签
  for (final coarseId in selectedCoarseIds) {
    final best = scored
        .where((c) => fineLabelToCoarse[c.label] == coarseId)
        .toList();
    if (best.isNotEmpty && !selectedSet.contains(best.first.label)) {
      selected.add(best.first.label);
      selectedSet.add(best.first.label);
    }
  }
  // 按排名填充剩余名额
  for (final candidate in scored) {
    if (selected.length >= topK) break;
    if (selectedSet.contains(candidate.label)) continue;
    selected.add(candidate.label);
    selectedSet.add(candidate.label);
  }
  return selected.isEmpty ? <String>['照片', '其他'] : selected;
}

class _TagCandidate {
  final String label;
  final double score;
  final double weightedScore;
  const _TagCandidate({
    required this.label,
    required this.score,
    required this.weightedScore,
  });
}

/// 后台 isolate：将图像压缩为 1024×1024 JPEG（质量 80）
List<int>? _computeCompressImage(String filePath) {
  try {
    final file = File(filePath);
    if (!file.existsSync()) return null;
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final resized = img.copyResize(decoded, width: 1024, height: 1024);
    final jpegBytes = img.encodeJpg(resized, quality: 80);
    return jpegBytes;
  } catch (_) {
    return null;
  }
}

/// 后台 isolate：仅读文件头（前 8KB）解析图像尺寸
(int, int)? _computeReadImageDims(String filePath) {
  try {
    final file = File(filePath);
    if (!file.existsSync()) return null;
    final raf = file.openSync(mode: FileMode.read);
    try {
      final header = raf.readSync(8192);
      final decoder = img.findDecoderForData(header);
      final info = decoder?.startDecode(header);
      if (info != null && info.width > 0 && info.height > 0) {
        return (info.width, info.height);
      }
      return null;
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return null;
  }
}

/// 轻量余弦相似度（点积，向量已 L2 归一化）
double _cosineSimilarity(List<double> a, List<double> b) {
  final len = a.length;
  if (len == 0 || len != b.length) return 0.0;
  var dot = 0.0;
  for (var i = 0; i < len; i++) {
    dot += a[i] * b[i];
  }
  return dot.clamp(-1.0, 1.0);
}

/// 快速指数函数
double _fastExp(double x) {
  return math.exp(x);
}

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
        await PhotoService().removeUnavailablePhotosByIds(<int>[
          request.photo.id,
        ]);
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
        final junkResult = await compute(_computeJunkFilter, <String, Object?>{
          'embedding': embedding,
          'prototypes': request.junkPhotoFilterService.prototypeCache,
          'isProbablyScreenshot': request.photo.isProbablyScreenshot,
          'ocrText': '',
          'definitions': request.junkPhotoFilterService.definitionsJson,
        });
        junkWatch.stop();
        profile.junkFilterMs = junkWatch.elapsedMicroseconds / 1000.0;
        final shouldFilter = junkResult['shouldFilter'] as bool? ?? false;
        if (shouldFilter) {
          final rawHits =
              (junkResult['hits'] as List<Object?>?)
                  ?.cast<Map<String, Object?>>() ??
              <Map<String, Object?>>[];
          final hits = rawHits
              .map(
                (h) => JunkPhotoHit(
                  categoryId: h['categoryId'] as String,
                  label: h['label'] as String,
                  description: h['description'] as String,
                  score: (h['score'] as num).toDouble(),
                  threshold: (h['threshold'] as num).toDouble(),
                ),
              )
              .toList(growable: false);
          profile.outcome = 'junk_filtered';
          return _PhotoProcessResult.success(
            eventId: request.photo.eventId,
            junkCandidate: JunkPhotoCleanupCandidate(
              photoId: request.photo.id,
              assetId: request.photo.assetId,
              path: request.photo.path,
              timestamp: request.photo.timestamp,
              reasons: hits,
            ),
            persistenceRequest: _AiPhotoWriteRequest(
              photoId: request.photo.id,
              tags: const <String>[
                JunkPhotoFilterService.pendingJunkCandidateTag,
              ],
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
      final tagSvc = request.mobileClipTagService;
      List<String> mobileClipTags;
      if (tagSvc.isWarmedUp) {
        mobileClipTags = await compute(_computeTagRetrieval, <String, Object?>{
          'embedding': embedding,
          'coarsePrototypes': tagSvc.coarsePrototypes,
          'finePrototypes': tagSvc.finePrototypes,
          'fineLabelToCoarse': memoriaFineLabelToCoarseId,
          'dimThresholds': <String, double>{
            'subject': 0.165,
            'scene': 0.17,
            'activity': 0.18,
            'atmosphere': 0.19,
            'media': 0.205,
          },
          'coarseThreshold': 0.16,
          'coarseProbThreshold': 0.035,
          'coarseMargin': 0.075,
          'blockedTags': <String>['套路', '未婚妻', '字幕', '房主', '采购员'],
          'coarseTopK': 2,
          'topK': 3,
        });
      } else {
        mobileClipTags = await request.mobileClipTagService.retrieveTags(
          embedding,
        );
      }
      tagWatch.stop();
      profile.tagRetrievalMs = tagWatch.elapsedMicroseconds / 1000.0;
      final visualTags = _sanitizeVisualTags(mobileClipTags);

      final auxiliaryFileWatch = Stopwatch()..start();
      // 在后台 isolate 压缩图像
      final compressedBytes = await compute(
        _computeCompressImage,
        prepared.file.path,
      );
      _ResolvedAnalysisFile resolvedAnalysisFile;
      if (compressedBytes != null && compressedBytes.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
        final targetPath =
            '${tempDir.path}/temp_mlkit_${request.photo.id}_$uniqueSuffix.jpg';
        final cf = File(targetPath);
        await cf.writeAsBytes(compressedBytes, flush: true);
        resolvedAnalysisFile = _ResolvedAnalysisFile(
          file: cf,
          sourceBytes: Uint8List.fromList(compressedBytes),
          source: 'compressed_temp',
          createdTemporaryFile: true,
        );
      } else {
        resolvedAnalysisFile = await _AnalysisFileResolver(
          config: AIService._analysisAuxiliaryConfig,
          createCompressedFile: _createAuxiliaryAnalysisFile,
        ).resolve(sourceFile: prepared.file, photoId: request.photo.id);
      }
      analysisFile = resolvedAnalysisFile.file;
      auxiliaryFileWatch.stop();
      profile.auxiliaryFileMs = auxiliaryFileWatch.elapsedMicroseconds / 1000.0;
      profile.auxiliarySource = resolvedAnalysisFile.source;
      profile.auxiliaryCreated = resolvedAnalysisFile.createdTemporaryFile;
      final inputImage = InputImage.fromFile(analysisFile);

      var ocrResult = OcrResult.empty();
      if (request.ocrEnabled &&
          OcrService.shouldRunOcr(
            visualTags,
            aspectRatio: request.photo.aspectRatio,
          )) {
        final ocrWatch = Stopwatch()..start();
        ocrResult = await request.ocrService.analyzeImageFile(analysisFile);
        ocrWatch.stop();
        profile.ocrMs = ocrWatch.elapsedMicroseconds / 1000.0;
      }

      final dimensionWatch = Stopwatch()..start();
      (int, int)? analysisDimensions;
      if (request.photo.width > 0 && request.photo.height > 0) {
        analysisDimensions = (request.photo.width, request.photo.height);
      } else {
        final dims = await compute(_computeReadImageDims, analysisFile.path);
        if (dims != null) analysisDimensions = dims;
      }
      dimensionWatch.stop();
      profile.analysisDecodeMs = dimensionWatch.elapsedMicroseconds / 1000.0;
      final canRunFaceDetection =
          request.faceAnalysisEnabled &&
          analysisDimensions != null &&
          analysisDimensions.$1 >= AIService._minFaceDetectorInputSize &&
          analysisDimensions.$2 >= AIService._minFaceDetectorInputSize;
      if (!canRunFaceDetection) {
        final sizeLabel = analysisDimensions == null
            ? 'unknown'
            : '${analysisDimensions.$1}x${analysisDimensions.$2}';
        debugPrint(
          '⏭️ 跳过人脸检测 photoId=${request.photo.id} '
          'dbSize=${request.photo.width}x${request.photo.height} '
          'analysisSize=$sizeLabel path=${analysisFile.path}',
        );
      }

      final faceDetectionWatch = Stopwatch()..start();
      List<Face> faces;
      if (canRunFaceDetection && request.faceDetector != null) {
        final lock = request.faceDetectorLock;
        if (lock != null) {
          await lock.acquire();
        }
        try {
          faces = await request.faceDetector!.processImage(inputImage);
        } finally {
          lock?.release();
        }
      } else {
        faces = const <Face>[];
      }
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

      if (request.faceAnalysisEnabled) {
        final facePipelineProfile = await request.facePipelineService
            .rebuildFacesForPhoto(
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
      }

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
      debugPrint('AI analysis failed photoId=${request.photo.id}: $error');
      profile.outcome = 'error';
      profile.error = error.toString();
      return _PhotoProcessResult.failed(profile: profile);
    } finally {
      if (analysisFile != null &&
          analysisFile.path != request.photo.path &&
          await analysisFile.exists()) {
        try {
          await analysisFile.delete();
        } catch (error) {
          debugPrint('Failed to delete temporary analysis file: $error');
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
      if (normalized.contains('\u667a\u80fd\u5f71\u8bb0') ||
          normalized.contains('\u6211\u7684\u76f8\u518c')) {
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
    final file = await PhotoService().openOriginalMediaFile(
      photo,
      purpose: 'ai_photo_processor',
    );

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
      debugPrint('Failed to read system thumbnail photoId=${photo.id}: $error');
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
      throw Exception('image compression failed');
    }
    final file = File(targetPath);
    await file.writeAsBytes(bytes, flush: true);
    return _CreatedAnalysisFile(file: file, bytes: bytes);
  }
}
