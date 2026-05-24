import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

class MediaAccessGrantSnapshot {
  const MediaAccessGrantSnapshot();

  bool get hasAnyGrant => true;
  int get manualMediaCount => 0;
}

class MediaAccessGrantService {
  MediaAccessGrantService._();
  static final MediaAccessGrantService instance = MediaAccessGrantService._();

  static const _channel = MethodChannel('memoria/media_access');

  Future<MediaAccessGrantSnapshot> loadSnapshot() async {
    return const MediaAccessGrantSnapshot();
  }

  Future<void> presentLimitedLibraryPicker() async {
    await PhotoManager.presentLimited();
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return false;
    final result = await _channel.invokeMethod<bool>(
      'requestIgnoreBatteryOptimizations',
    );
    return result ?? false;
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    final result = await _channel.invokeMethod<bool>(
      'isIgnoringBatteryOptimizations',
    );
    return result ?? false;
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openBatteryOptimizationSettings');
  }

  Future<Uint8List?> readContentUriBytes(String uri) async {
    if (!Platform.isAndroid || !uri.startsWith('content://')) return null;
    return _channel.invokeMethod<Uint8List>('readContentUriBytes', uri);
  }
}
