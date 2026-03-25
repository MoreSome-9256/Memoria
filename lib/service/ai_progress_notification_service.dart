import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'ai_foreground_service.dart';

class AIProgressNotificationService {
  AIProgressNotificationService._internal();

  static final AIProgressNotificationService _instance =
      AIProgressNotificationService._internal();

  factory AIProgressNotificationService() => _instance;

  static const String _channelId = 'ai_progress_channel';
  static const int _notificationId = 43001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _lastShownAtMs = 0;
  String _lastSignature = '';

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    await _plugin.initialize(settings);
    await AIForegroundService().initialize();

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
    final body = '$completed/$total${failed > 0 ? ' · 失败 $failed' : ''}';

    // Android: 使用前台服务承载常驻通知，提升后台存活概率。
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await AIForegroundService().sync(
        shouldRun: isVisible,
        title: title,
        text: '$body · $currentStep',
      );
    }

    if (!isVisible) {
      await _plugin.cancel(_notificationId);
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final signature =
        '$isRunning|$isPaused|$isStopping|$completed|$total|$failed|${fraction.toStringAsFixed(3)}|$currentStep';

    // 节流通知更新，避免频繁刷通知导致额外卡顿。
    if (signature == _lastSignature && nowMs - _lastShownAtMs < 1000) {
      return;
    }
    _lastSignature = signature;
    _lastShownAtMs = nowMs;

    // iOS / 其他端：继续使用本地通知展示进度。
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return;
    }

    final safeProgress = (fraction.clamp(0, 1) * 100).round();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      'AI 打标进度',
      channelDescription: '展示 AI 打标任务进度',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: isRunning || isPaused || isStopping,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: safeProgress,
      indeterminate: false,
      category: AndroidNotificationCategory.progress,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentSound: false,
      presentBadge: false,
    );

    await _plugin.show(
      _notificationId,
      title,
      '$body · $currentStep',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}
