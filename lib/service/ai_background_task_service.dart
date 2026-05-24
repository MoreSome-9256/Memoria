import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app_ai_settings_service.dart';

@pragma('vm:entry-point')
void foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_MemoriaTaskHandler());
}

class _MemoriaTaskHandler extends TaskHandler {
  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

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
        eventAction: ForegroundTaskEventAction.nothing(),
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
