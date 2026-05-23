import 'dart:io';

import 'package:flutter/services.dart';

import 'app_ai_settings_service.dart';

class AiBackgroundTaskService {
  AiBackgroundTaskService._();
  static final AiBackgroundTaskService instance = AiBackgroundTaskService._();

  static const _channel = MethodChannel('memoria/ai_background_task');

  Future<void> startIfAllowed({
    required String title,
    required String text,
  }) async {
    final settings = await AppAiSettingsService.instance.load();
    if (!Platform.isAndroid || !settings.androidForegroundServiceEnabled) {
      return;
    }
    await _channel.invokeMethod<void>('startForegroundTask', <String, Object?>{
      'title': title,
      'text': text,
    });
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('stopForegroundTask');
  }
}
