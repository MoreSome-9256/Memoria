import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';
import 'package:pool/pool.dart';
import 'package:zstandard/zstandard.dart';

import '../utils/media_type_helper.dart';

class AssetThumbnailResult {
  const AssetThumbnailResult({required this.kind, required this.bytes});

  final MemoriaMediaKind kind;
  final Uint8List? bytes;
}

class MediaThumbnailCacheService {
  MediaThumbnailCacheService._();

  static final MediaThumbnailCacheService instance =
      MediaThumbnailCacheService._();

  static const int thumbnailSize = 200;
  static const int maxThumbnailBytes = 1024 * 1024;
  static final Pool _thumbnailPool = Pool(3);

  Future<AssetThumbnailResult?> loadAssetThumbnailById(String? assetId) async {
    final normalized = assetId?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    final asset = await AssetEntity.fromId(normalized);
    if (asset == null) return null;
    final kind = asset.type == AssetType.video
        ? MemoriaMediaKind.video
        : asset.isLivePhoto
        ? MemoriaMediaKind.dynamicImage
        : MemoriaMediaKind.image;
    return AssetThumbnailResult(
      kind: kind,
      bytes: await generateCompressedBytes(asset),
    );
  }

  Future<Uint8List?> generateCompressedBytes(AssetEntity asset) async {
    return await _thumbnailPool.withResource(() async {
      try {
        final bytes = await asset.thumbnailDataWithSize(
          const ThumbnailSize.square(thumbnailSize),
          quality: 65,
        );
        if (bytes == null ||
            !isSupportedImageBytes(bytes) ||
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
    try {
      if (compressed.length < 4 ||
          compressed[0] != 0x28 ||
          compressed[1] != 0xB5 ||
          compressed[2] != 0x2F ||
          compressed[3] != 0xFD) {
        return isSupportedImageBytes(compressed) ? compressed : null;
      }
      final decompressed = (await compressed.decompress()) ?? compressed;
      return isSupportedImageBytes(decompressed) ? decompressed : null;
    } catch (_) {
      // Corrupt cached bytes must not prevent an asset-backed thumbnail retry.
      return null;
    }
  }

  static bool isSupportedImageBytes(Uint8List bytes) {
    if (bytes.lengthInBytes < 12) return false;
    final jpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    final png =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final gif =
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38;
    final webp =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return jpeg || png || gif || webp;
  }
}
