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

    await _methodChannel.invokeMethod<void>('sync', <String, dynamic>{
      'shouldRun': shouldRun,
      'isPaused': isPaused,
      'progress': progress.clamp(0, 100),
      'title': title,
      'text': text,
    });
  }
}
