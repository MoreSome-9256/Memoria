import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';
import 'package:pool/pool.dart';
import 'package:zstandard/zstandard.dart';

class MediaThumbnailCacheService {
  MediaThumbnailCacheService._();

  static final MediaThumbnailCacheService instance =
      MediaThumbnailCacheService._();

  static const int thumbnailSize = 200;
  static const int maxThumbnailBytes = 1024 * 1024;
  static final Pool _thumbnailPool = Pool(3);

  Future<Uint8List?> generateCompressedBytes(AssetEntity asset) async {
    return await _thumbnailPool.withResource(() async {
      try {
        final bytes = await asset.thumbnailDataWithSize(
          const ThumbnailSize.square(thumbnailSize),
          quality: 65,
        );
        if (bytes == null ||
            bytes.isEmpty ||
            bytes.lengthInBytes > maxThumbnailBytes) {
          return null;
        }
        return bytes;
      } catch (_) {
        return null;
      }
    });
  }

  Future<Uint8List?> decompressBytes(Uint8List? compressed) async {
    if (compressed == null || compressed.isEmpty) return null;
    if (compressed.length < 4 ||
        compressed[0] != 0x28 ||
        compressed[1] != 0xB5 ||
        compressed[2] != 0x2F ||
        compressed[3] != 0xFD) {
      return compressed;
    }
    return (await compressed.decompress()) ?? compressed;
  }
}
