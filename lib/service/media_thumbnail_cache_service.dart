import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

class MediaThumbnailCacheService {
  MediaThumbnailCacheService._();

  static final MediaThumbnailCacheService instance =
      MediaThumbnailCacheService._();

  static const String _cacheSubdir = 'MediaThumbnailCache';
  static const int thumbnailSize = 256;
  static const int maxThumbnailBytes = 1024 * 1024;

  Future<Directory> getCacheDirectory() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/$_cacheSubdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String?> getCachedPath(String assetId) async {
    if (assetId.isEmpty) return null;
    final file = await _thumbnailFile(assetId);
    if (await file.exists() && await file.length() > 0) {
      return file.path;
    }
    return null;
  }

  Future<String?> ensureForAsset(AssetEntity asset) async {
    final cached = await getCachedPath(asset.id);
    if (cached != null) {
      return cached;
    }
    try {
      final bytes = await asset.thumbnailDataWithSize(
        const ThumbnailSize.square(thumbnailSize),
        quality: 70,
      );
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.lengthInBytes > maxThumbnailBytes) {
        return null;
      }
      final file = await _thumbnailFile(asset.id);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> readBytes(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final length = await file.length();
      if (length <= 0 || length > maxThumbnailBytes) return null;
      return file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    final dir = await getCacheDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
  }

  Future<Map<String, Object>> getStats() async {
    final dir = await getCacheDirectory();
    var count = 0;
    var bytes = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      count++;
      try {
        bytes += await entity.length();
      } catch (_) {}
    }
    return <String, Object>{
      'count': count,
      'bytes': bytes,
      'formattedBytes': _formatBytes(bytes),
    };
  }

  Future<File> _thumbnailFile(String assetId) async {
    final dir = await getCacheDirectory();
    return File('${dir.path}/${Uri.encodeComponent(assetId)}.jpg');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }
}
