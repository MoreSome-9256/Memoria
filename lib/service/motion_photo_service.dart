import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

class MotionPhotoService {
  MotionPhotoService._();

  static const int _maxTailScanBytes = 32 * 1024 * 1024;

  static Future<File?> extractByAssetId(String assetId) async {
    if (!Platform.isAndroid || assetId.trim().isEmpty) return null;

    final cacheDirectory = await getTemporaryDirectory();
    final safeId = assetId.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
    final output = File('${cacheDirectory.path}/motion_photo_$safeId.mp4');
    if (await output.exists() && await output.length() > 16) {
      return output;
    }

    final asset = await AssetEntity.fromId(assetId);
    final bytes = await asset?.originBytes;
    if (bytes == null || bytes.isEmpty) return null;

    final offset = await compute(findEmbeddedMp4Offset, bytes);
    if (offset == null) return null;

    await output.writeAsBytes(
      Uint8List.sublistView(bytes, offset),
      flush: true,
    );
    return await output.length() > 16 ? output : null;
  }

  static int? findEmbeddedMp4Offset(Uint8List bytes) {
    if (bytes.length < 16) return null;

    final start = math.max(0, bytes.length - _maxTailScanBytes);
    final data = ByteData.sublistView(bytes);
    for (
      var index = math.max(4, start + 4);
      index < bytes.length - 8;
      index++
    ) {
      if (bytes[index] != 0x66 ||
          bytes[index + 1] != 0x74 ||
          bytes[index + 2] != 0x79 ||
          bytes[index + 3] != 0x70) {
        continue;
      }
      final boxSize = data.getUint32(index - 4, Endian.big);
      final offset = index - 4;
      if (boxSize >= 8 && offset > 0 && bytes.length - offset > 16) {
        return offset;
      }
    }
    return null;
  }
}
