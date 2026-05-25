/// AI 服务的主处理管线 — Spool 编排模式。
///
/// 主进程：写 manifest → 启动前台服务 → (后台) 轮询 spool → 消费结果 → 写 ObjectBox。
/// 前台服务：读 manifest → 纯计算 → 写 result/embedding/progress → 写 done.marker。

part of 'ai_service.dart';

extension AIServicePipeline on AIService {
  /// 启动 AI 分析管线。
  ///
  /// [manageForegroundService] = true（默认）：写 manifest + 启动前台服务，返回后
  /// 前台服务在独立 isolate 中做纯计算，结果写入 spool。
  ///
  /// [manageForegroundService] = false：在调用方 isolate 中直接运行完整管线
  /// （仅供旧路径兼容，新代码应走 spool 模式）。
  Future<void> analyzePhotosInBackground({
    int batchSize = 6,
    int? maxPhotos,
    List<int>? photoIds,
    bool manageForegroundService = true,
  }) async {
    if (!manageForegroundService) {
      await _AiPipelineRunner(
        service: this,
        batchSize: batchSize,
        maxPhotos: maxPhotos,
        photoIds: photoIds,
        manageForegroundService: manageForegroundService,
      ).run();
      return;
    }

    // ── Spool 模式：写 manifest → 启动前台服务 ──
    final existingJobId = await _pendingSpoolJobId();
    if (existingJobId != null) {
      final spool = AnalysisSpoolService.instance;
      if (await spool.hasDoneMarker(existingJobId)) {
        await consumeSpoolResults(existingJobId, startNextPending: false);
      } else {
        final manifest = await spool.readManifest(existingJobId);
        final snapshot = await spool.readProgress(existingJobId);
        if (manifest != null) {
          final processed = snapshot?.processed ?? 0;
          final failed = snapshot?.failed ?? 0;
          final control = await spool.readControl(existingJobId);
          final paused =
              control.pauseRequested || snapshot?.status == 'paused';
          final stopping =
              control.stopRequested || snapshot?.status == 'stopping';
          final serviceRunning = await AiBackgroundTaskService.instance.isRunning;
          final settings = await AppAiSettingsService.instance.load();
          final manuallyStopped = await _readManualStopPending();
          final canAutoRestart =
              settings.autoResumeAnalysis && !manuallyStopped;
          final serviceOffline = !paused && !stopping && !serviceRunning;
          final currentStep = serviceOffline && !canAutoRestart
              ? '后台服务未运行，任务已保留；点击继续后恢复'
              : snapshot != null && snapshot.currentStep.isNotEmpty
                  ? snapshot.currentStep
                  : '后台分析中 $processed/${manifest.totalItems}';
          _progressNotifier.value = AIAnalysisProgress(
            isRunning:
                !paused && !stopping && (!serviceOffline || canAutoRestart),
            isPaused: paused || (serviceOffline && !canAutoRestart),
            isStopping: stopping,
            total: manifest.totalItems,
            completed: processed,
            failed: failed,
            currentStep: currentStep,
            elapsedMs: _elapsedMsForSpoolProgress(manifest, snapshot),
            warmUpCompleted: snapshot?.warmUpCompleted ?? 0,
            warmUpTotal: snapshot?.warmUpTotal ?? 0,
          );
          SpoolProgressNotifier.instance.startPolling(existingJobId);
          if (serviceOffline && canAutoRestart) {
            await AiBackgroundTaskService.instance.startAnalysisWorker();
          }
          debugPrint('[spool] 已存在未完成 job=$existingJobId，跳过新建 manifest');
          return;
        }
      }
    }

    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();

    final requestedPhotoIds = photoIds
        ?.where((id) => id > 0)
        .toSet()
        .toList(growable: false);

    final q = requestedPhotoIds != null && requestedPhotoIds.isNotEmpty
        ? photoBox
            .query(
              PhotoEntity_.isAiAnalyzed
                  .equals(false)
                  .and(PhotoEntity_.id.oneOf(requestedPhotoIds)),
            )
            .order(PhotoEntity_.timestamp, flags: Order.descending)
            .build()
        : photoBox
            .query(PhotoEntity_.isAiAnalyzed.equals(false))
            .order(PhotoEntity_.timestamp, flags: Order.descending)
            .build();
    final pendingPhotos = q.find();
    q.close();

    final limit = maxPhotos ?? pendingPhotos.length;
    final batch = pendingPhotos.take(limit).toList(growable: false);

    if (batch.isEmpty) {
      debugPrint('[spool] 没有待分析的照片');
      _progressNotifier.value = AIAnalysisProgress.idle();
      return;
    }

    final jobId = 'ai_${DateTime.now().millisecondsSinceEpoch}';
    final items = await _prepareSpoolItems(jobId, batch);
    if (items.isEmpty) {
      debugPrint('[spool] 没有可交给前台服务的稳定输入文件');
      _progressNotifier.value = AIAnalysisProgress.idle();
      return;
    }
    final manifest = AnalysisJobManifest(
      jobId: jobId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      mode: 'full',
      items: items,
    );

    // 启动前台服务
    await AiBackgroundTaskService.instance.startAnalysisWorker(
      manifest: manifest,
    );
    debugPrint(
      '[spool] manifest 已写入并提交前台服务 jobId=$jobId items=${items.length}',
    );

    _progressNotifier.value = AIAnalysisProgress.running(
      total: items.length,
      completed: 0,
      failed: 0,
      currentStep: '已提交 ${items.length} 张照片到后台分析服务',
      elapsedMs: 0,
    );
    SpoolProgressNotifier.instance.startPolling(jobId);
    unawaited(_persistRuntimeState(isActive: true, total: items.length));
  }

  Future<List<AnalysisSpoolItem>> _prepareSpoolItems(
    String jobId,
    List<PhotoEntity> photos,
  ) async {
    final spool = AnalysisSpoolService.instance;
    await spool.ensureJobDirs(jobId);

    final items = <AnalysisSpoolItem>[];
    for (final photo in photos) {
      var path = photo.path;

      if (path.startsWith('content://')) {
        final copiedPath = await _copyContentUriToSpoolInput(jobId, photo);
        if (copiedPath == null) {
          debugPrint(
            '[spool] 跳过无法复制到 spool 输入目录的 content uri photoId=${photo.id} uri=${photo.path}',
          );
          continue;
        }
        path = copiedPath;
      } else {
        final file = File(path);
        if (!await file.exists()) {
          debugPrint('[spool] 跳过不存在的输入文件 photoId=${photo.id} path=$path');
          continue;
        }
      }

      items.add(
        AnalysisSpoolItem(
          photoKey: photo.assetId,
          contentUri: null,
          path: path,
          photoId: photo.id,
          modifiedAt: photo.timestamp,
          latitude: photo.latitude,
          longitude: photo.longitude,
          width: photo.width,
          height: photo.height,
        ),
      );
    }
    return items;
  }

  Future<String?> _copyContentUriToSpoolInput(
    String jobId,
    PhotoEntity photo,
  ) async {
    try {
      final bytes = await MediaAccessGrantService.instance
          .readContentUriBytes(photo.path);
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      final inputFile = await AnalysisSpoolService.instance.inputFileFor(
        jobId: jobId,
        photoKey: photo.assetId,
        extension: _analysisInputExtension(photo.path),
      );
      await inputFile.writeAsBytes(bytes, flush: true);
      return inputFile.path;
    } catch (error) {
      debugPrint(
        '[spool] content uri 输入复制失败 photoId=${photo.id} uri=${photo.path}: $error',
      );
      return null;
    }
  }

  String _analysisInputExtension(String source) {
    final path = Uri.tryParse(source)?.path ?? source;
    final slash = path.lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    if (dot > slash && dot < path.length - 1) {
      final ext = path.substring(dot + 1).toLowerCase();
      if (ext.length <= 8 && RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
        return ext;
      }
    }
    return 'bin';
  }

  /// 消费 spool 结果：检测 done.marker → 读取所有 pending result → 写入 ObjectBox。
  Future<SpoolConsumeReport> consumeSpoolResults(
    String jobId, {
    bool requireDoneMarker = true,
    bool startNextPending = true,
    bool dismissUnfinishedItems = false,
  }) {
    final active = _activeSpoolConsumes[jobId];
    if (active != null) {
      debugPrint('[spool] job=$jobId 已有消费流程在运行，复用同一个 future');
      return active;
    }
    final future = _consumeSpoolResultsInternal(
      jobId,
      requireDoneMarker: requireDoneMarker,
      startNextPending: startNextPending,
      dismissUnfinishedItems: dismissUnfinishedItems,
    );
    _activeSpoolConsumes[jobId] = future;
    future.whenComplete(() => _activeSpoolConsumes.remove(jobId));
    return future;
  }

  Future<SpoolConsumeReport> _consumeSpoolResultsInternal(
    String jobId, {
    bool requireDoneMarker = true,
    bool startNextPending = true,
    bool dismissUnfinishedItems = false,
  }) async {
    final spool = AnalysisSpoolService.instance;
    final manifest = await spool.readManifest(jobId);
    if (manifest == null) {
      return SpoolConsumeReport(jobId: jobId, consumedCount: 0);
    }

    if (requireDoneMarker && !await spool.hasDoneMarker(jobId)) {
      return SpoolConsumeReport(jobId: jobId, consumedCount: 0);
    }

    final pendingFiles = await spool.listPendingResults(jobId);
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    var consumedCount = 0;
    var failedCount = 0;
    var affectedEventIds = <int>{};
    final succeededPhotoIds = <int>{};

    final photoById = <int, PhotoEntity>{};
    for (final photo in photoBox.getAll()) {
      photoById[photo.id] = photo;
    }

    for (final filePath in pendingFiles) {
      final result = await spool.readResultFile(filePath);
      if (result == null) {
        final basename = filePath.split(Platform.pathSeparator).last;
        final key = basename.endsWith('.json')
            ? basename.substring(0, basename.length - 5)
            : 'unknown_${DateTime.now().millisecondsSinceEpoch}';
        await spool.moveToFailed(jobId, key);
        failedCount++;
        continue;
      }

      final photo = result.photoId > 0
          ? photoById[result.photoId]
          : null;
      if (photo == null) {
        await spool.moveToFailed(jobId, result.photoKey);
        failedCount++;
        continue;
      }

      if (result.isSucceeded && _isCompleteSpoolResult(result)) {
        List<double>? embedding;
        if (result.embeddingFile != null) {
          embedding = await spool.readEmbedding(jobId, result.photoKey);
        }
        if (embedding == null || embedding.isEmpty) {
          await _resetIncompletePhoto(photo);
          await spool.moveToFailed(jobId, result.photoKey);
          failedCount++;
          debugPrint(
            '[spool] succeeded result 缺少 embedding，保持未分析 photoId=${photo.id} key=${result.photoKey}',
          );
          continue;
        }

        final faceResults = await _readFaceResults(spool, jobId, result.photoKey);

        try {
          await _applySpoolResult(
            photo: photo,
            embedding: embedding,
            faceResults: faceResults,
            result: result,
          );
        } catch (error) {
          await _resetIncompletePhoto(photo);
          await spool.moveToFailed(jobId, result.photoKey);
          failedCount++;
          debugPrint(
            '[spool] 写库阶段失败，保持未分析 photoId=${photo.id} key=${result.photoKey}: $error',
          );
          continue;
        }

        if (photo.eventId != null && photo.eventId! > 0) {
          affectedEventIds.add(photo.eventId!);
        }

        await spool.moveToCommitted(jobId, result.photoKey);
        if (photo.id > 0) {
          succeededPhotoIds.add(photo.id);
        }
        consumedCount++;
      } else {
        await _resetIncompletePhoto(photo);
        await spool.moveToFailed(jobId, result.photoKey);
        failedCount++;
        if (result.isSucceeded) {
          debugPrint(
            '[spool] result 阶段未完整，保持未分析 photoId=${photo.id} '
            'ocr=${result.ocrRequired}/${result.ocrCompleted} '
            'face=${result.faceAnalysisRequired}/${result.faceAnalysisCompleted}',
          );
        }
      }
    }

    if (dismissUnfinishedItems) {
      await _resetUnfinishedSpoolItems(
        manifest: manifest,
        succeededPhotoIds: succeededPhotoIds,
      );
    }

    // 刷新事件智能信息
    if (affectedEventIds.isNotEmpty) {
      await EventService().refreshEventSmartInfo(affectedEventIds.toList());
    }

    // 清理 spool job 目录 + 清除 pending 标记
    await spool.cleanupJob(jobId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spool_pending_manifest_job_id');
    SpoolProgressNotifier.instance.stopPolling();
    _progressNotifier.value = AIAnalysisProgress.idle();
    await _persistRuntimeState(isActive: false);

    if (startNextPending) {
      await _startNextPendingSpoolBatchIfNeeded(
        previousJobPhotoIds: manifest.items
            .map((item) => item.photoId ?? 0)
            .where((id) => id > 0)
            .toSet(),
      );
    }

    return SpoolConsumeReport(
      jobId: jobId,
      consumedCount: consumedCount,
      failedCount: failedCount,
    );
  }

  Future<void> _startNextPendingSpoolBatchIfNeeded({
    required Set<int> previousJobPhotoIds,
  }) async {
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final pendingQ = photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(false))
        .build();
    final pendingPhotoIds = pendingQ
        .find()
        .map((photo) => photo.id)
        .where((id) => id > 0 && !previousJobPhotoIds.contains(id))
        .toList(growable: false);
    pendingQ.close();
    if (pendingPhotoIds.isEmpty) {
      return;
    }
    debugPrint('[spool] 检测到 ${pendingPhotoIds.length} 张新增待分析照片，自动提交下一轮 spool');
    unawaited(analyzePhotosInBackground(photoIds: pendingPhotoIds));
  }

  Future<void> _resetUnfinishedSpoolItems({
    required AnalysisJobManifest manifest,
    required Set<int> succeededPhotoIds,
  }) async {
    final unfinishedIds = manifest.items
        .map((item) => item.photoId ?? 0)
        .where((id) => id > 0 && !succeededPhotoIds.contains(id))
        .toSet()
        .toList(growable: false);
    if (unfinishedIds.isEmpty) {
      return;
    }

    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    final photos = photoBox
        .getMany(unfinishedIds)
        .whereType<PhotoEntity>()
        .toList(growable: false);
    if (photos.isEmpty) {
      return;
    }

    store.runInTransaction(TxMode.write, () {
      for (final photo in photos) {
        photo.isAiAnalyzed = false;
        if (photo.imageEmbedding == null || photo.imageEmbedding!.isEmpty) {
          photo.aiTags = <String>[];
          photo.aiCaption = null;
          photo.ocrText = null;
          photo.ocrTags = <String>[];
          photo.faceCount = 0;
          photo.smileProb = 0;
          photo.joyScore = 0;
        }
      }
      photoBox.putMany(photos);
    });
    debugPrint('[spool] 已保留 ${photos.length} 张未完成照片为待分析状态');
  }

  Future<void> _resetIncompletePhoto(PhotoEntity photo) async {
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    store.runInTransaction(TxMode.write, () {
      final p = photoBox.get(photo.id);
      if (p == null) return;
      p.isAiAnalyzed = false;
      if (p.imageEmbedding == null || p.imageEmbedding!.isEmpty) {
        p.aiTags = <String>[];
        p.aiCaption = null;
        p.ocrText = null;
        p.ocrTags = <String>[];
        p.faceCount = 0;
        p.smileProb = 0;
        p.joyScore = 0;
      }
      photoBox.put(p);
    });
  }

  bool _isCompleteSpoolResult(AnalysisSpoolResult result) {
    if (!result.isSucceeded) {
      return false;
    }
    if (result.embeddingFile == null || result.embeddingDim <= 0) {
      return false;
    }
    if (result.ocrRequired && !result.ocrCompleted) {
      return false;
    }
    if (result.faceAnalysisRequired && !result.faceAnalysisCompleted) {
      return false;
    }
    return true;
  }

  Future<List<_SpoolFaceFileResult>> _readFaceResults(
    AnalysisSpoolService spool,
    String jobId,
    String photoKey,
  ) async {
    final baseDir = await spool.baseDir;
    final key = Uri.encodeComponent(photoKey);
    final faceFile = File(
      '${baseDir.path}/jobs/$jobId/results_pending/${key}_faces.json',
    );
    if (!await faceFile.exists()) return const <_SpoolFaceFileResult>[];
    try {
      final json = await faceFile.readAsString();
      final decoded = jsonDecode(json) as List<Object?>;
      return decoded
          .cast<Map<String, Object?>>()
          .map(_SpoolFaceFileResult.fromJson)
          .toList();
    } catch (_) {
      return const <_SpoolFaceFileResult>[];
    }
  }

  Future<void> _applySpoolResult({
    required PhotoEntity photo,
    required List<double> embedding,
    required List<_SpoolFaceFileResult> faceResults,
    required AnalysisSpoolResult result,
  }) async {
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();

    final selectedBackend = await MobileClipEmbeddingService()
        .getSelectedBackend();

    store.runInTransaction(TxMode.write, () {
      final p = photoBox.get(photo.id);
      if (p == null) return;

      p.aiTags = result.tags;
      p.isAiAnalyzed = false;
      p.aiCaption = result.aiCaption.isEmpty ? null : result.aiCaption;
      p.imageEmbedding = embedding.isEmpty ? null : embedding;
      p.ocrText = result.ocrText.isEmpty ? null : result.ocrText;
      p.ocrTags = result.ocrTags;
      p.faceCount = result.faceCount;
      p.smileProb = result.smileProb;
      p.joyScore = result.joyScore;

      p.province = result.province;
      p.city = result.city;
      p.district = result.district;
      p.locationName = result.locationName;
      p.formattedAddress = result.formattedAddress;
      p.adcode = result.adcode;
      p.isLocationProcessed =
          result.province != null || result.city != null;

      photoBox.put(p);
    });

    // 写入 embedding 索引
    if (embedding.isNotEmpty) {
      _photoEmbeddingIndexRepository.upsertEmbedding(
        photoId: photo.id,
        vector: embedding,
        modelVersion: buildPhotoEmbeddingModelVersion(selectedBackend),
      );
    }

    // 写入 face 结果
    if (faceResults.isNotEmpty) {
      await _applyFaceResults(photo, faceResults);
    }

    store.runInTransaction(TxMode.write, () {
      final p = photoBox.get(photo.id);
      if (p == null) return;
      p.isAiAnalyzed = true;
      photoBox.put(p);
    });
  }

  Future<void> _applyFaceResults(
    PhotoEntity photo,
    List<_SpoolFaceFileResult> faceResults,
  ) async {
    if (faceResults.isEmpty) return;

    final store = ObjectBoxService().store;
    final faceBox = store.box<FaceEntity>();

    final existingQ = faceBox
        .query(FaceEntity_.photoId.equals(photo.id))
        .build();
    final existingIds = existingQ.find().map((f) => f.id).toList();
    existingQ.close();

    // 加载原图，用于人脸裁剪 -> 嵌入计算
    img.Image? decodedImage;
    try {
      if (photo.path.startsWith('content://')) {
        final bytes = await MediaAccessGrantService.instance
            .readContentUriBytes(photo.path);
        if (bytes != null && bytes.isNotEmpty) {
          decodedImage = FaceCropUtil.decodeSourceImageBytes(bytes);
        }
      } else {
        final imageFile = File(photo.path);
        if (await imageFile.exists()) {
          decodedImage = await FaceCropUtil.decodeSourceImage(imageFile);
        }
      }
    } catch (_) {}

    FaceEmbeddingService? embeddingService;
    final now = DateTime.now().millisecondsSinceEpoch;
    final faces = <FaceEntity>[];

    for (final fr in faceResults) {
      List<double>? embedding;
      String modelVersion = '';

      if (decodedImage != null) {
        try {
          final faceRect = Rect.fromLTRB(
            fr.left, fr.top, fr.right, fr.bottom,
          );
          final cropped = FaceCropUtil.cropFaceImage(
            sourceImage: decodedImage,
            boundingBox: faceRect,
          );
          if (cropped != null) {
            final cropBytes = FaceCropUtil.encodeFaceImageToJpegBytes(cropped);
            embeddingService ??= OnnxFaceEmbeddingService(
              fallbackService: MobileClipFaceEmbeddingService(),
            );
            final result = await embeddingService.embedFaceCropBytes(cropBytes);
            if (result != null) {
              embedding = result.embedding;
              modelVersion = result.modelVersion;
            }
          }
        } catch (_) {}
      }

      faces.add(FaceEntity()
        ..photoId = photo.id
        ..assetId = photo.assetId
        ..faceIndex = fr.faceIndex
        ..left = fr.left
        ..top = fr.top
        ..right = fr.right
        ..bottom = fr.bottom
        ..roll = fr.roll
        ..yaw = fr.yaw
        ..smilingProbability = fr.smilingProbability
        ..leftEyeOpenProbability = fr.leftEyeOpenProbability
        ..rightEyeOpenProbability = fr.rightEyeOpenProbability
        ..embedding = embedding
        ..embeddingModelVersion = modelVersion
        ..qualityScore = fr.qualityScore
        ..isPrimaryFace = fr.isPrimaryFace
        ..clusterId = null
        ..createdAt = now
        ..updatedAt = now);
    }

    store.runInTransaction(TxMode.write, () {
      if (existingIds.isNotEmpty) {
        faceBox.removeMany(existingIds);
      }
      faceBox.putMany(faces);
    });

    final faceIndexRepo = FaceEmbeddingIndexRepository();
    faceIndexRepo.replaceForPhoto(
      photoId: photo.id,
      faces: faces,
    );
  }

  void _enqueueAsyncCaption(_AsyncCaptionTask task) {
    if (_stopRequested) {
      _disposeSkippedCaptionTask(task);
      return;
    }
    _pendingCaptionTasks.addLast(task);
    _pumpAsyncCaptionQueue();
  }

  void _pumpAsyncCaptionQueue() {
    if (_stopRequested) {
      _clearPendingCaptionTasks();
      return;
    }
    while (_activeCaptionTasks < AIService._maxConcurrentCaptionWorkers &&
        _pendingCaptionTasks.isNotEmpty) {
      final task = _pendingCaptionTasks.removeFirst();
      _activeCaptionTasks++;
      unawaited(_runAsyncCaptionTask(task));
    }
  }

  Future<void> _runAsyncCaptionTask(_AsyncCaptionTask task) async {
    final watch = Stopwatch()..start();
    try {
      final caption = await task.captionService.generateCaption(
        imageFile: task.imageFile,
        visualTags: task.visualTags,
        ocrTags: task.ocrTags,
        ocrText: task.ocrText,
        location: task.location,
        takenAt: task.takenAt,
        isProbablyScreenshot: task.isProbablyScreenshot,
        faceCount: task.faceCount,
      );
      if (caption.trim().isNotEmpty) {
        await _updatePhotoCaption(task.photoId, caption);
      }
      watch.stop();
      debugPrint(
        'AI async caption photoId=${task.photoId} '
        'updated=${caption.trim().isNotEmpty} '
        'elapsedMs=${(watch.elapsedMicroseconds / 1000.0).toStringAsFixed(1)}',
      );
    } catch (error) {
      watch.stop();
      debugPrint(
        '⚠️ AI async caption failed photoId=${task.photoId} '
        'elapsedMs=${(watch.elapsedMicroseconds / 1000.0).toStringAsFixed(1)} '
        'error=$error',
      );
    } finally {
      if (task.deleteImageFileAfterUse && task.imageFile.existsSync()) {
        try {
          await task.imageFile.delete();
        } catch (_) {}
      }
      _activeCaptionTasks = math.max(0, _activeCaptionTasks - 1);
      _pumpAsyncCaptionQueue();
    }
  }

  void _clearPendingCaptionTasks() {
    if (_pendingCaptionTasks.isEmpty) return;
    final skipped = _pendingCaptionTasks.length;
    while (_pendingCaptionTasks.isNotEmpty) {
      _disposeSkippedCaptionTask(_pendingCaptionTasks.removeFirst());
    }
    debugPrint('🛑 已清空待生成 caption 队列: $skipped 个任务');
  }

  void _clearAnalysisQueue() {
    if (_analysisQueue.isEmpty) return;
    final dropped = _analysisQueue.length;
    for (final photo in _analysisQueue) {
      _analysisQueuedPhotoIds.remove(photo.id);
    }
    _analysisQueue.clear();
    debugPrint('🛑 已清空 AI 打标任务队列: $dropped 个任务');
  }

  void _disposeSkippedCaptionTask(_AsyncCaptionTask task) {
    if (!task.deleteImageFileAfterUse) return;
    unawaited(
      Future<void>(() async {
        try {
          if (await task.imageFile.exists()) {
            await task.imageFile.delete();
          }
        } catch (_) {}
      }),
    );
  }

  Future<void> _updatePhotoCaption(int photoId, String caption) async {
    final trimmed = caption.trim();
    if (trimmed.isEmpty) return;
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    store.runInTransaction(TxMode.write, () {
      final photo = photoBox.get(photoId);
      if (photo == null) return;
      photo.aiCaption = trimmed;
      photoBox.put(photo);
    });
  }

  int _resolveWorkerCount(int workItems) {
    if (workItems <= 1) return 1;
    final cpuCores = Platform.numberOfProcessors;
    final suggested = Platform.isAndroid || Platform.isIOS
        ? (cpuCores <= 4 ? 2 : 3)
        : (cpuCores <= 2 ? 1 : math.max(2, cpuCores - 1));
    final bounded = math.min(AIService._maxParallelWorkers, suggested);
    return math.max(1, math.min(bounded, workItems));
  }

  Future<String?> _pendingSpoolJobId() async {
    final prefs = await SharedPreferences.getInstance();
    final jobId = prefs.getString('spool_pending_manifest_job_id');
    if (jobId == null || jobId.isEmpty) return null;
    return jobId;
  }

  String _formatWorkerWarmupStatus(List<int> readyWorkers, int totalWorkers) {
    if (readyWorkers.isEmpty) return 'workers无 / 共$totalWorkers';
    final labels = readyWorkers.map((id) => 'workers$id').join(',');
    return '$labels / 共$totalWorkers';
  }
}

/// Spool 消费报告。
class SpoolConsumeReport {
  final String jobId;
  final int consumedCount;
  final int failedCount;

  const SpoolConsumeReport({
    required this.jobId,
    required this.consumedCount,
    this.failedCount = 0,
  });
}

/// Spool face result 反序列化模型。
class _SpoolFaceFileResult {
  final int faceIndex;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double? roll;
  final double? yaw;
  final double? smilingProbability;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final List<double>? embedding;
  final String? embeddingModelVersion;
  final double qualityScore;
  final bool isPrimaryFace;

  const _SpoolFaceFileResult({
    required this.faceIndex,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.roll,
    this.yaw,
    this.smilingProbability,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.embedding,
    this.embeddingModelVersion,
    required this.qualityScore,
    required this.isPrimaryFace,
  });

  factory _SpoolFaceFileResult.fromJson(Map<String, Object?> json) {
    return _SpoolFaceFileResult(
      faceIndex: (json['faceIndex'] as num).toInt(),
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      right: (json['right'] as num).toDouble(),
      bottom: (json['bottom'] as num).toDouble(),
      roll: (json['roll'] as num?)?.toDouble(),
      yaw: (json['yaw'] as num?)?.toDouble(),
      smilingProbability:
          (json['smilingProbability'] as num?)?.toDouble(),
      leftEyeOpenProbability:
          (json['leftEyeOpenProbability'] as num?)?.toDouble(),
      rightEyeOpenProbability:
          (json['rightEyeOpenProbability'] as num?)?.toDouble(),
      embedding: (json['embedding'] as List<Object?>?)
          ?.cast<double>(),
      embeddingModelVersion: json['embeddingModelVersion'] as String?,
      qualityScore: (json['qualityScore'] as num).toDouble(),
      isPrimaryFace: (json['isPrimaryFace'] as bool?) ?? false,
    );
  }
}
