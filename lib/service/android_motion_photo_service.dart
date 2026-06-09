import 'dart:io';

import 'package:flutter/services.dart';

class AndroidMotionPhotoService {
  AndroidMotionPhotoService._();

  static const _channel = MethodChannel('memoria/media_access');

  static Future<File?> extractByAssetId(String assetId) async {
    if (!Platform.isAndroid || assetId.trim().isEmpty) return null;
    try {
      final path = await _channel.invokeMethod<String>(
        'extractAndroidMotionPhoto',
        assetId,
      );
      if (path == null || path.isEmpty) return null;
      final file = File(path);
      return await file.exists() ? file : null;
    } on PlatformException {
      return null;
    }
  }
}
