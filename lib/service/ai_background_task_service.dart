/// AI 前台任务处理器 — 保持进程存活。
///
/// 正常情况下 AI 计算由主 isolate 执行；如果主 isolate 心跳停止，
/// 前台服务 isolate 会接管未完成队列。
///
/// 主 isolate 通过 [_syncProgressNotification] 更新前台通知内容和心跳；
/// 当分析完成或停止时，[AiBackgroundTaskService.stop] 被调用。

part of 'ai_service.dart';

/// 前台任务回调入口，在后台 isolate 中运行。
@pragma('vm:entry-point')
void foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_MemoriaTaskHandler());
}

class _MemoriaTaskHandler extends TaskHandler {
  bool _takeoverStarted = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_takeoverStarted) {
      return;
    }
    unawaited(_takeOverIfMainIsolateStopped());
  }

  Future<void> _takeOverIfMainIsolateStopped() async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getBool(AIService._runtimeActiveKey) ?? false;
    if (!active) {
      return;
    }
    final heartbeatAtMs = prefs.getInt(AIService._runtimeHeartbeatAtKey) ?? 0;
    final staleMs = DateTime.now().millisecondsSinceEpoch - heartbeatAtMs;
    if (heartbeatAtMs > 0 && staleMs < const Duration(seconds: 20).inMilliseconds) {
      return;
    }
    _takeoverStarted = true;
    WidgetsFlutterBinding.ensureInitialized();
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
        await aiService.analyzePhotosInBackground(
          manageForegroundService: false,
        );
      } finally {
        if (listenerAttached) {
          aiService.progressListenable.removeListener(syncForegroundProgress);
        }
      }
    } catch (error) {
      debugPrint('❌ 前台服务接管 AI 队列失败: $error');
      _takeoverStarted = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

class AiBackgroundTaskService {
  AiBackgroundTaskService._();
  static final AiBackgroundTaskService instance = AiBackgroundTaskService._();

  static bool _initialized = false;

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
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
      ),
    );
  }

  Future<void> startIfAllowed({
    required String title,
    required String text,
  }) async {
    final settings = await AppAiSettingsService.instance.load();
    if (!Platform.isAndroid || !settings.androidForegroundServiceEnabled) {
      return;
    }
    await _ensureInitialized();
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
}
