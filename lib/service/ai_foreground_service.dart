import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AIForegroundService {
  AIForegroundService._internal();

  static final AIForegroundService _instance = AIForegroundService._internal();

  factory AIForegroundService() => _instance;

  static const MethodChannel _methodChannel =
      MethodChannel('memoria/ai_foreground_notification');
  static const EventChannel _eventChannel =
      EventChannel('memoria/ai_foreground_actions');
  static const String actionPause = 'pause';
  static const String actionResume = 'resume';

  bool _initialized = false;
  ValueChanged<String>? _actionHandler;

  Future<void> initialize() async {
    if (_initialized || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    _eventChannel.receiveBroadcastStream().listen((dynamic data) {
      if (data is String && data.isNotEmpty) {
        _actionHandler?.call(data);
      }
    });

    _initialized = true;
  }

  void bindActionHandler(ValueChanged<String> handler) {
    _actionHandler = handler;
  }

  Future<void> sync({
    required bool shouldRun,
    required bool isPaused,
    required int progress,
    required String title,
    required String text,
  }) async {
    await initialize();
    if (!_initialized) {
      return;
    }

    try {
      await _methodChannel.invokeMethod<void>('sync', <String, dynamic>{
        'shouldRun': shouldRun,
        'isPaused': isPaused,
        'progress': progress.clamp(0, 100),
        'title': title,
        'text': text,
      });
    } on PlatformException catch (error) {
      debugPrint('⚠️ 前台通知同步失败: ${error.code} ${error.message}');
    }
  }

  Future<void> stop() async {
    await sync(
      shouldRun: false,
      isPaused: false,
      progress: 0,
      title: '',
      text: '',
    );
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final value = await _methodChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openIgnoreBatteryOptimizationSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final value = await _methodChannel.invokeMethod<bool>(
        'openIgnoreBatteryOptimizationSettings',
      );
      return value ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> getAndroidFgsPolicySummary() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return '';
    }
    try {
      final value = await _methodChannel.invokeMethod<String>(
        'getAndroidFgsPolicySummary',
      );
      return value ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<bool> isForegroundServiceRunning() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final value = await _methodChannel.invokeMethod<bool>(
        'isForegroundServiceRunning',
      );
      return value ?? false;
    } catch (_) {
      return false;
    }
  }
}
