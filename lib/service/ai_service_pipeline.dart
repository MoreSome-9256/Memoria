part of 'ai_service.dart';

extension AIServicePipeline on AIService {
  Future<void> analyzePhotosInBackground({int batchSize = 6, int? maxPhotos}) {
    return _AiPipelineRunner(
      service: this,
      batchSize: batchSize,
      maxPhotos: maxPhotos,
    ).run();
  }

  void _enqueueAsyncCaption(_AsyncCaptionTask task) {
    _pendingCaptionTasks.addLast(task);
    _pumpAsyncCaptionQueue();
  }

  void _pumpAsyncCaptionQueue() {
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

  Future<void> _updatePhotoCaption(Id photoId, String caption) async {
    final trimmed = caption.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final isar = PhotoService().isar;
    await isar.writeTxn(() async {
      final photo = await isar.collection<PhotoEntity>().get(photoId);
      if (photo == null) {
        return;
      }
      photo.aiCaption = trimmed;
      await isar.collection<PhotoEntity>().put(photo);
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
