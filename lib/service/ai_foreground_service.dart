import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class AIForegroundService {
  AIForegroundService._internal();

  static final AIForegroundService _instance = AIForegroundService._internal();

  factory AIForegroundService() => _instance;

  static const String channelId = 'ai_progress_channel';
  static const String channelName = 'AI 打标进度';
  static const int notificationId = 43001;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: channelId,
        channelName: channelName,
        channelDescription: '用于保持 AI 打标任务在后台持续处理',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _initialized = true;
  }

  Future<void> sync({
    required bool shouldRun,
    required String title,
    required String text,
  }) async {
    await initialize();
    if (!_initialized) {
      return;
    }

    final running = await FlutterForegroundTask.isRunningService;

    if (!shouldRun) {
      if (running) {
        await FlutterForegroundTask.stopService();
      }
      return;
    }

    if (running) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: notificationId,
      notificationTitle: title,
      notificationText: text,
      callback: _startCallback,
    );
  }
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_AIForegroundTaskHandler());
}

class _AIForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}
