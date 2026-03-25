import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'ai_foreground_service.dart';

class AIProgressNotificationService {
  AIProgressNotificationService._internal();

  static final AIProgressNotificationService _instance =
      AIProgressNotificationService._internal();

  factory AIProgressNotificationService() => _instance;

  static const String _channelId = 'ai_progress_channel';
  static const String _channelName = 'AI 打标进度';
  static const int _notificationId = 43001;
  static const String actionPause = 'pause';
  static const String actionResume = 'resume';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _lastShownAtMs = 0;
  String _lastSignature = '';

  ValueChanged<String>? _actionHandler;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImpl?.requestNotificationsPermission();
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final iosImpl =
          _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await iosImpl?.requestPermissions(alert: true, badge: false, sound: false);
    }

    _initialized = true;
  }

  void bindActionHandler(ValueChanged<String> handler) {
    _actionHandler = handler;
  }

  @pragma('vm:entry-point')
  static void _onBackgroundResponse(NotificationResponse response) {
    final actionId = response.actionId ?? '';
    if (actionId.isEmpty) {
      return;
    }
    _instance._actionHandler?.call(actionId);
  }

  void _onForegroundResponse(NotificationResponse response) {
    final actionId = response.actionId ?? '';
    if (actionId.isEmpty) {
      return;
    }
    _actionHandler?.call(actionId);
  }

  Future<void> syncProgress({
    required bool isVisible,
    required bool isRunning,
    required bool isPaused,
    required bool isStopping,
    required int completed,
    required int total,
    required int failed,
    required String currentStep,
    required double fraction,
  }) async {
    await initialize();

    final title = isStopping
        ? 'AI 打标正在结束'
        : isPaused
        ? 'AI 打标已暂停'
        : 'AI 打标进行中';

    final bodyBase = '$completed/$total${failed > 0 ? ' · 失败 $failed' : ''}';
    final progressPercent = (fraction.clamp(0, 1) * 100).round();
    final body = '$bodyBase · $currentStep';

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final signature =
        '$isRunning|$isPaused|$isStopping|$completed|$total|$failed|$progressPercent|$currentStep';

    if (signature == _lastSignature && nowMs - _lastShownAtMs < 900) {
      return;
    }
    _lastSignature = signature;
    _lastShownAtMs = nowMs;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return _syncAndroidForegroundProgress(
        isVisible: isVisible,
        isPaused: isPaused,
        progressPercent: progressPercent,
        title: title,
        body: body,
      );
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return _syncIosProgressToBeImplemented(
        isVisible: isVisible,
        isRunning: isRunning,
        isPaused: isPaused,
        isStopping: isStopping,
        progressPercent: progressPercent,
        title: title,
        body: body,
      );
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      return _syncMacosProgressToBeImplemented(
        isVisible: isVisible,
        isRunning: isRunning,
        isPaused: isPaused,
        isStopping: isStopping,
        progressPercent: progressPercent,
        title: title,
        body: body,
      );
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return _syncWindowsProgressToBeImplemented(
        isVisible: isVisible,
        isRunning: isRunning,
        isPaused: isPaused,
        isStopping: isStopping,
        progressPercent: progressPercent,
        title: title,
        body: body,
      );
    }

    return _syncFallbackLocalProgressNotification(
      isVisible: isVisible,
      isRunning: isRunning,
      isPaused: isPaused,
      isStopping: isStopping,
      progressPercent: progressPercent,
      title: title,
      body: body,
    );
  }

  Future<void> _syncAndroidForegroundProgress({
    required bool isVisible,
    required bool isPaused,
    required int progressPercent,
    required String title,
    required String body,
  }) async {
    await AIForegroundService().sync(
      shouldRun: isVisible,
      isPaused: isPaused,
      progress: progressPercent,
      title: title,
      text: '$progressPercent% · $body',
    );

    // Android 前台保活时仅保留前台服务通知，避免双通知互相覆盖。
    await _plugin.cancel(_notificationId);
  }

  Future<void> _syncIosProgressToBeImplemented({
    required bool isVisible,
    required bool isRunning,
    required bool isPaused,
    required bool isStopping,
    required int progressPercent,
    required String title,
    required String body,
  }) async {
    // TO BE IMPLEMENTED: iOS 专用通知策略（例如 Live Activities / BGTask 对接）。
    return _syncFallbackLocalProgressNotification(
      isVisible: isVisible,
      isRunning: isRunning,
      isPaused: isPaused,
      isStopping: isStopping,
      progressPercent: progressPercent,
      title: title,
      body: body,
    );
  }

  Future<void> _syncMacosProgressToBeImplemented({
    required bool isVisible,
    required bool isRunning,
    required bool isPaused,
    required bool isStopping,
    required int progressPercent,
    required String title,
    required String body,
  }) async {
    // TO BE IMPLEMENTED: macOS 原生通知/菜单栏进度同步实现。
    return _syncFallbackLocalProgressNotification(
      isVisible: isVisible,
      isRunning: isRunning,
      isPaused: isPaused,
      isStopping: isStopping,
      progressPercent: progressPercent,
      title: title,
      body: body,
    );
  }

  Future<void> _syncWindowsProgressToBeImplemented({
    required bool isVisible,
    required bool isRunning,
    required bool isPaused,
    required bool isStopping,
    required int progressPercent,
    required String title,
    required String body,
  }) async {
    // TO BE IMPLEMENTED: Windows toast progress bar / app notification manager。
    return _syncFallbackLocalProgressNotification(
      isVisible: isVisible,
      isRunning: isRunning,
      isPaused: isPaused,
      isStopping: isStopping,
      progressPercent: progressPercent,
      title: title,
      body: body,
    );
  }

  Future<void> _syncFallbackLocalProgressNotification({
    required bool isVisible,
    required bool isRunning,
    required bool isPaused,
    required bool isStopping,
    required int progressPercent,
    required String title,
    required String body,
  }) async {
    if (!isVisible) {
      await _plugin.cancel(_notificationId);
      return;
    }

    final actions = <AndroidNotificationAction>[
      AndroidNotificationAction(
        isPaused ? actionResume : actionPause,
        isPaused ? '继续' : '暂停',
        showsUserInterface: false,
        cancelNotification: false,
      ),
    ];

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '展示 AI 打标任务进度与控制按钮',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      ongoing: isRunning || isPaused || isStopping,
      showProgress: true,
      maxProgress: 100,
      progress: progressPercent,
      indeterminate: false,
      category: AndroidNotificationCategory.progress,
      actions: actions,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentSound: false,
      presentBadge: false,
    );

    await _plugin.show(
      _notificationId,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}
