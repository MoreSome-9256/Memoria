import 'dart:io';

import 'package:flutter/services.dart';

const _androidSystemSettingsChannel = MethodChannel('memoria/android_settings');

Future<void> openAndroidBatteryOptimizationSettings() async {
  if (!Platform.isAndroid) return;
  await _androidSystemSettingsChannel.invokeMethod<void>(
    'openBatteryOptimizationSettings',
  );
}
