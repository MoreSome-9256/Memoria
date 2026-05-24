/// AI 前台任务处理器 — 独立执行持久 AI 队列。
///
/// App 只负责写入待分析照片和启动服务；实际计算在本服务 isolate 中完成。
/// 进度通过持久状态和前台服务通知暴露，不依赖界面进程。

part of 'ai_service.dart';

/// 前台任务回调入口，在后台 isolate 中运行。
@pragma('vm:entry-point')
void foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_MemoriaTaskHandler());
}

class _MemoriaTaskHandler extends TaskHandler {
  bool _started = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (_started) {
      return;
    }
    _started = true;
    unawaited(_runWorker());
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  Future<void> _runWorker() async {
    try {
      await ObjectBoxService().init();
      await PhotoService().init();
      final settings = await AppAiSettingsService.instance.load();
      OcrPolicy.setRuntimeEnabled(settings.ocrEnabled);
      AIService.uiIntegrationEnabled = false;
      final aiService = AIService();
      var listenerAttached = false;
      void syncForegroundProgress() {
        final progress = aiService.progressListenable.value;
        if (!progress.isVisible) {
          return;
        }
        final title = progress.isStopping
            ? 'AI 打标正在结束'
            : progress.isPaused
            ? 'AI 打标已暂停'
            : 'AI 打标进行中';
        final text =
            '${progress.completed}/${progress.total}${progress.failed > 0 ? ' · 失败 ${progress.failed}' : ''} · ${progress.currentStep}';
        unawaited(
          AiBackgroundTaskService.instance.updateNotification(
            title: title,
            text: text,
          ),
        );
      }
      aiService.progressListenable.addListener(syncForegroundProgress);
      listenerAttached = true;
      try {
        while (true) {
          final request = await AiBackgroundTaskService.instance.readRequest();
          if (request == null) {
            break;
          }
          await AiBackgroundTaskService.instance.clearRequest(
            createdAtMs: request.createdAtMs,
          );
          await aiService.analyzePhotosInBackground(
            manageForegroundService: false,
            maxPhotos: request.maxPhotos,
            photoIds: request.photoIds,
          );
        }
      } finally {
        if (listenerAttached) {
          aiService.progressListenable.removeListener(syncForegroundProgress);
        }
      }
    } catch (error) {
      debugPrint('❌ AI worker 执行失败: $error');
    } finally {
      await AiBackgroundTaskService.instance.stop();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class AiBackgroundTaskService {
  AiBackgroundTaskService._();
  static final AiBackgroundTaskService instance = AiBackgroundTaskService._();

  static bool _initialized = false;
  static const _requestMaxPhotosKey = 'ai_worker_request_max_photos';
  static const _requestPhotoIdsKey = 'ai_worker_request_photo_ids';
  static const _requestCreatedAtKey = 'ai_worker_request_created_at';

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'memoria_ai_foreground_task',
        channelName: 'Memoria AI 分析',
        channelDescription: '展示 AI 打标任务的前台服务通知',
        onlyAlertOnce: true,
        priority: NotificationPriority.LOW,
        channelImportance: NotificationChannelImportance.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
      ),
    );
  }

  Future<void> startAnalysisWorker({
    int? maxPhotos,
    List<int>? photoIds,
  }) async {
    await _writeRequest(maxPhotos: maxPhotos, photoIds: photoIds);
    if (!Platform.isAndroid) {
      if (!Platform.isIOS) {
        debugPrint('AI durable worker is not wired for this platform yet.');
        return;
      }
      await startService(
        title: 'Memoria 正在分析媒体',
        text: '只处理你加入分析队列的照片和视频',
      );
      return;
    }
    await startService(
      title: 'Memoria 正在分析媒体',
      text: '只处理你加入分析队列的照片和视频',
    );
  }

  Future<void> startService({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    await _ensureInitialized();
    if (await FlutterForegroundTask.isRunningService) {
      await updateNotification(title: title, text: text);
      FlutterForegroundTask.sendDataToTask(<String, Object?>{
        'type': 'run_request_updated',
      });
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 43021,
      notificationTitle: title,
      notificationText: text,
      notificationIcon: null,
      notificationInitialRoute: '/',
      callback: foregroundTaskCallback,
    );
  }

  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  Future<void> stop() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await FlutterForegroundTask.stopService();
  }

  Future<void> _writeRequest({
    int? maxPhotos,
    List<int>? photoIds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (maxPhotos == null) {
      await prefs.remove(_requestMaxPhotosKey);
    } else {
      await prefs.setInt(_requestMaxPhotosKey, maxPhotos);
    }
    final normalizedPhotoIds = photoIds
        ?.where((id) => id > 0)
        .map((id) => id.toString())
        .toList(growable: false);
    if (normalizedPhotoIds == null || normalizedPhotoIds.isEmpty) {
      await prefs.remove(_requestPhotoIdsKey);
    } else {
      await prefs.setStringList(_requestPhotoIdsKey, normalizedPhotoIds);
    }
    await prefs.setInt(
      _requestCreatedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<int?> readRequestedMaxPhotos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_requestMaxPhotosKey);
  }

  Future<List<int>?> readRequestedPhotoIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_requestPhotoIdsKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final ids = raw
        .map((value) => int.tryParse(value))
        .whereType<int>()
        .where((id) => id > 0)
        .toList(growable: false);
    return ids.isEmpty ? null : ids;
  }

  Future<_AiWorkerRequest?> readRequest() async {
    final prefs = await SharedPreferences.getInstance();
    final maxPhotos = prefs.getInt(_requestMaxPhotosKey);
    final photoIds = await readRequestedPhotoIds();
    final createdAtMs = prefs.getInt(_requestCreatedAtKey) ?? 0;
    if (maxPhotos == null && (photoIds == null || photoIds.isEmpty)) {
      return null;
    }
    return _AiWorkerRequest(
      maxPhotos: maxPhotos,
      photoIds: photoIds,
      createdAtMs: createdAtMs,
    );
  }

  Future<void> clearRequest({int? createdAtMs}) async {
    final prefs = await SharedPreferences.getInstance();
    if (createdAtMs != null &&
        prefs.getInt(_requestCreatedAtKey) != createdAtMs) {
      return;
    }
    await prefs.remove(_requestMaxPhotosKey);
    await prefs.remove(_requestPhotoIdsKey);
    await prefs.remove(_requestCreatedAtKey);
  }
}

class _AiWorkerRequest {
  const _AiWorkerRequest({
    required this.maxPhotos,
    required this.photoIds,
    required this.createdAtMs,
  });

  final int? maxPhotos;
  final List<int>? photoIds;
  final int createdAtMs;
}
