import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

enum MemoriaMediaKind {
  image,
  dynamicImage,
  video,
}

class MediaTypeHelper {
  MediaTypeHelper._();

  static const Set<String> _videoExtensions = <String>{
    '.mp4',
    '.mov',
    '.m4v',
    '.3gp',
    '.3gpp',
    '.avi',
    '.mkv',
    '.webm',
  };

  static const Set<String> _dynamicImageExtensions = <String>{
    '.gif',
    '.webp',
    '.heic',
    '.heif',
  };

  static bool isVideoPath(String? path) =>
      _videoExtensions.contains(_extension(path));

  static bool isDynamicImagePath(String? path) =>
      _dynamicImageExtensions.contains(_extension(path));

  static MemoriaMediaKind fromPath(String? path) {
    if (isVideoPath(path)) {
      return MemoriaMediaKind.video;
    }
    if (isDynamicImagePath(path)) {
      return MemoriaMediaKind.dynamicImage;
    }
    return MemoriaMediaKind.image;
  }

  static Future<MemoriaMediaKind> resolve({
    required String? path,
    required String? assetId,
  }) async {
    final pathKind = fromPath(path);
    if (pathKind == MemoriaMediaKind.video) {
      return MemoriaMediaKind.video;
    }

    if (assetId != null && assetId.isNotEmpty) {
      try {
        final asset = await AssetEntity.fromId(assetId);
        if (asset != null) {
          if (asset.type == AssetType.video) {
            return MemoriaMediaKind.video;
          }
          if (asset.isLivePhoto) {
            return MemoriaMediaKind.dynamicImage;
          }
          final mimeType = asset.mimeType ?? await asset.mimeTypeAsync;
          final normalizedMime = mimeType?.toLowerCase() ?? '';
          if (normalizedMime.startsWith('video/')) {
            return MemoriaMediaKind.video;
          }
          if (normalizedMime == 'image/gif' ||
              normalizedMime == 'image/webp' ||
              normalizedMime == 'image/heic' ||
              normalizedMime == 'image/heif') {
            return MemoriaMediaKind.dynamicImage;
          }
        }
      } catch (_) {
        // Fall back to path-based detection.
      }
    }

    return pathKind;
  }

  static String _extension(String? rawPath) {
    final value = rawPath?.trim();
    if (value == null || value.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(value);
    final path = uri?.path.isNotEmpty == true ? uri!.path : value;
    final basename = path.split(Platform.pathSeparator).last;
    final dot = basename.lastIndexOf('.');
    if (dot < 0) {
      return '';
    }
    return basename.substring(dot).toLowerCase();
  }
}
