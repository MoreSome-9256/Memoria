/// AI 服务的主处理管线，串联输入准备、分析执行和结果落盘。

part of 'ai_service.dart';

extension AIServicePipeline on AIService {
  Future<void> analyzePhotosInBackground({
    int batchSize = 6,
    int? maxPhotos,
    List<int>? photoIds,
    bool manageForegroundService = true,
  }) async {
    if (manageForegroundService) {
      await AiBackgroundTaskService.instance.startAnalysisWorker(
        maxPhotos: maxPhotos,
        photoIds: photoIds,
      );
      return;
    }
    await _AiPipelineRunner(
      service: this,
      batchSize: batchSize,
      maxPhotos: maxPhotos,
      photoIds: photoIds,
      manageForegroundService: manageForegroundService,
    ).run();
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
    if (_pendingCaptionTasks.isEmpty) {
      return;
    }
    final skipped = _pendingCaptionTasks.length;
    while (_pendingCaptionTasks.isNotEmpty) {
      _disposeSkippedCaptionTask(_pendingCaptionTasks.removeFirst());
    }
    debugPrint('🛑 已清空待生成 caption 队列: $skipped 个任务');
  }

  void _clearAnalysisQueue() {
    if (_analysisQueue.isEmpty) {
      return;
    }
    final dropped = _analysisQueue.length;
    for (final photo in _analysisQueue) {
      _analysisQueuedPhotoIds.remove(photo.id);
    }
    _analysisQueue.clear();
    debugPrint('🛑 已清空 AI 打标任务队列: $dropped 个任务');
  }

  void _disposeSkippedCaptionTask(_AsyncCaptionTask task) {
    if (!task.deleteImageFileAfterUse) {
      return;
    }
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
    if (trimmed.isEmpty) {
      return;
    }

    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    store.runInTransaction(TxMode.write, () {
      final photo = photoBox.get(photoId);
      if (photo == null) {
        return;
      }
      photo.aiCaption = trimmed;
      photoBox.put(photo);
    });
  }

  int _resolveWorkerCount(int workItems) {
    if (workItems <= 1) {
      return 1;
    }
    final cpuCores = Platform.numberOfProcessors;
    final suggested = Platform.isAndroid || Platform.isIOS
        ? (cpuCores <= 4 ? 2 : 3)
        : (cpuCores <= 2 ? 1 : math.max(2, cpuCores - 1));
    final bounded = math.min(AIService._maxParallelWorkers, suggested);
    return math.max(1, math.min(bounded, workItems));
  }

  String _formatWorkerWarmupStatus(List<int> readyWorkers, int totalWorkers) {
    if (readyWorkers.isEmpty) {
      return 'workers无 / 共$totalWorkers';
    }
    final labels = readyWorkers.map((id) => 'workers$id').join(',');
    return '$labels / 共$totalWorkers';
  }
}
