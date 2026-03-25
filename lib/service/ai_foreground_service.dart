import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class AIForegroundService {
  AIForegroundService._internal();

  static final AIForegroundService _instance = AIForegroundService._internal();

  factory AIForegroundService() => _instance;

  static const String actionPause = 'pause';
  static const String actionResume = 'resume';

  bool _initialized = false;
  ValueChanged<String>? _actionHandler;

  Future<void> initialize() async {
    if (_initialized || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ai_fg_service_channel',
        channelName: 'AI 后台处理',
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

    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);

    _initialized = true;
  }

  void bindActionHandler(ValueChanged<String> handler) {
    _actionHandler = handler;
  }

  void _onTaskData(Object data) {
    if (data is! String) {
      return;
    }
    const prefix = 'ai_action:';
    if (!data.startsWith(prefix)) {
      return;
    }
    final action = data.substring(prefix.length).trim();
    if (action.isEmpty) {
      return;
    }
    _actionHandler?.call(action);
  }

  Future<void> sync({
    required bool shouldRun,
    required bool isPaused,
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

    final buttons = <NotificationButton>[
      NotificationButton(
        id: isPaused ? actionResume : actionPause,
        text: isPaused ? '继续' : '暂停',
      ),
    ];

    if (running) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
        notificationButtons: buttons,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 43002,
      notificationTitle: title,
      notificationText: text,
      notificationButtons: buttons,
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
  void onNotificationButtonPressed(String id) {
    FlutterForegroundTask.sendDataToMain('ai_action:$id');
  }

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}
