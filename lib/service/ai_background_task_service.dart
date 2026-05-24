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
      final maxPhotos = await AiBackgroundTaskService.instance
          .readRequestedMaxPhotos();
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
        await aiService.analyzePhotosInBackground(
          manageForegroundService: false,
          maxPhotos: maxPhotos,
        );
      } finally {
        if (listenerAttached) {
          aiService.progressListenable.removeListener(syncForegroundProgress);
        }
      }
    } catch (error) {
      debugPrint('❌ AI worker 执行失败: $error');
    } finally {
      await AiBackgroundTaskService.instance.clearRequest();
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

  Future<void> startAnalysisWorker({int? maxPhotos}) async {
    await _writeRequest(maxPhotos: maxPhotos);
    if (!Platform.isAndroid) {
      debugPrint('AI durable worker is not wired for this platform yet.');
      return;
    }
    final settings = await AppAiSettingsService.instance.load();
    if (!settings.androidForegroundServiceEnabled) {
      debugPrint(
        'AI durable worker request saved; Android foreground worker is disabled.',
      );
      return;
    }
    await startIfAllowed(
      title: 'Memoria 正在分析媒体',
      text: '只处理你加入分析队列的照片和视频',
    );
  }

  Future<void> startIfAllowed({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    await _ensureInitialized();
    if (await FlutterForegroundTask.isRunningService) {
      await updateNotification(title: title, text: text);
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
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.stopService();
  }

  Future<void> _writeRequest({int? maxPhotos}) async {
    final prefs = await SharedPreferences.getInstance();
    if (maxPhotos == null) {
      await prefs.remove(_requestMaxPhotosKey);
    } else {
      await prefs.setInt(_requestMaxPhotosKey, maxPhotos);
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

  Future<void> clearRequest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_requestMaxPhotosKey);
    await prefs.remove(_requestCreatedAtKey);
  }
}
