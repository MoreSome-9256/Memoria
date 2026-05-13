/// AI 进度通知服务，向前台 UI 广播分析状态和操作入口。

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  static const String navigationAlbum = 'album';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _lastShownAtMs = 0;
  String _lastSignature = '';

  ValueChanged<String>? _actionHandler;
  ValueChanged<String>? _navigationHandler;
  String? _pendingAction;
  String? _pendingNavigation;

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
      settings: settings,
      onDidReceiveNotificationResponse: _onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true && launchResponse != null) {
      _handleNotificationResponse(launchResponse);
    }

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
    final pending = _pendingAction;
    if (pending != null) {
      _pendingAction = null;
      handler(pending);
    }
  }

  void bindNavigationHandler(ValueChanged<String> handler) {
    _navigationHandler = handler;
    final pending = _pendingNavigation;
    if (pending != null) {
      _pendingNavigation = null;
      handler(pending);
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundResponse(NotificationResponse response) {
    _instance._handleNotificationResponse(response);
  }

  void _onForegroundResponse(NotificationResponse response) {
    _handleNotificationResponse(response);
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId ?? '';
    if (actionId.isNotEmpty) {
      _dispatchOrQueueAction(actionId);
      return;
    }

    final payload = response.payload ?? '';
    if (payload.isNotEmpty) {
      _dispatchOrQueueNavigation(payload);
    }
  }

  void _dispatchOrQueueAction(String actionId) {
    debugPrint('🔔 通知动作: $actionId (handlerBound=${_actionHandler != null})');
    final handler = _actionHandler;
    if (handler != null) {
      handler(actionId);
      return;
    }
    _pendingAction = actionId;
  }

  void _dispatchOrQueueNavigation(String payload) {
    debugPrint('🔔 通知导航: $payload (handlerBound=${_navigationHandler != null})');
    final handler = _navigationHandler;
    if (handler != null) {
      handler(payload);
      return;
    }
    _pendingNavigation = payload;
  }

  Future<void> clearProgressNotificationSurfaces() async {
    await initialize();
    await _plugin.cancel(id: _notificationId);
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
      await _plugin.cancel(id: _notificationId);
      return;
    }

    final actions = <AndroidNotificationAction>[
      AndroidNotificationAction(
        isPaused ? actionResume : actionPause,
        isPaused ? '继续' : '暂停',
        // 关键：走前台/UI isolate 回调，确保能命中 AIService 里绑定的 action handler。
        // 若为 false，动作会走后台 isolate，当前实现中的内存状态无法直接驱动主流程暂停/继续。
        showsUserInterface: true,
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
      ongoing: true,
      autoCancel: false,
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
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: navigationAlbum,
    );
  }
}
