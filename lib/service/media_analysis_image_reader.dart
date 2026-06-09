import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../utils/media_type_helper.dart';
import 'media_thumbnail_cache_service.dart';

class MediaAnalysisImageInput {
  const MediaAnalysisImageInput({
    required this.kind,
    required this.imageBytes,
    required this.analysisImageBytes,
    required this.videoFrameBytes,
    required this.width,
    required this.height,
    required this.sourceLabel,
  });

  final MemoriaMediaKind kind;
  final Uint8List imageBytes;
  final Uint8List analysisImageBytes;
  final List<Uint8List> videoFrameBytes;
  final int width;
  final int height;
  final String sourceLabel;
}

class MediaAnalysisFrameFiles {
  const MediaAnalysisFrameFiles({
    required this.frames,
    required this.cleanupPaths,
    required this.sourceLabel,
  });

  final List<File> frames;
  final List<String> cleanupPaths;
  final String sourceLabel;
}

class MediaAnalysisImageReader {
  MediaAnalysisImageReader._();
  static final MediaAnalysisImageReader instance = MediaAnalysisImageReader._();

  static const int defaultImageSize = 384;
  static const int defaultAnalysisSize = 1024;
  static const int defaultFrameCount = 8;

  Future<MediaAnalysisImageInput?> readAsset(
    AssetEntity asset, {
    int imageSize = defaultImageSize,
    int analysisSize = defaultAnalysisSize,
    int frameCount = defaultFrameCount,
  }) async {
    final kind = _kindForAsset(asset, null);
    final dims = _boundedSize(
      width: asset.width,
      height: asset.height,
      maxSide: analysisSize,
    );

    final imageBytes = await _readAssetThumbnail(
      asset,
      ThumbnailSize.square(imageSize),
      quality: 92,
    );
    final analysisBytes =
        await _readAssetThumbnail(
          asset,
          ThumbnailSize(dims.$1, dims.$2),
          quality: 92,
        ) ??
        imageBytes;
    if (imageBytes == null ||
        imageBytes.isEmpty ||
        analysisBytes == null ||
        analysisBytes.isEmpty) {
      return null;
    }

    final frames =
        kind == MemoriaMediaKind.video || kind == MemoriaMediaKind.dynamicImage
        ? await _readAssetFrameBytes(
            asset,
            frameCount: frameCount,
            imageSize: imageSize,
          )
        : const <Uint8List>[];

    return MediaAnalysisImageInput(
      kind: kind,
      imageBytes: imageBytes,
      analysisImageBytes: analysisBytes,
      videoFrameBytes: frames.isEmpty ? const <Uint8List>[] : frames,
      width: asset.width > 0 ? asset.width : dims.$1,
      height: asset.height > 0 ? asset.height : dims.$2,
      sourceLabel: imageBytes == analysisBytes ? 'thumbnail' : 'system_reader',
    );
  }

  Future<MediaAnalysisImageInput?> readAssetById(
    String assetId, {
    int imageSize = defaultImageSize,
    int analysisSize = defaultAnalysisSize,
    int frameCount = defaultFrameCount,
  }) async {
    final asset = await AssetEntity.fromId(assetId);
    if (asset == null) {
      return null;
    }
    return readAsset(
      asset,
      imageSize: imageSize,
      analysisSize: analysisSize,
      frameCount: frameCount,
    );
  }

  Future<MediaAnalysisFrameFiles> readFrameFilesFromAsset(
    String assetId, {
    required bool videoLike,
    int maxFrames = defaultFrameCount,
  }) async {
    final asset = await AssetEntity.fromId(assetId);
    if (asset != null) {
      if (asset.type == AssetType.video || asset.isLivePhoto || videoLike) {
        final frameBytes = await _readAssetFrameBytes(
          asset,
          frameCount: maxFrames,
          imageSize: defaultAnalysisSize,
        );
        if (frameBytes.isNotEmpty) {
          return _writeFrameByteList(
            frameBytes,
            prefix: 'memoria_asset_vlm_frame',
          );
        }
      }
      final bytes = await _readAssetThumbnail(
        asset,
        const ThumbnailSize.square(defaultAnalysisSize),
        quality: 92,
      );
      if (bytes != null && bytes.isNotEmpty) {
        return _writeFrameByteList(<Uint8List>[
          bytes,
        ], prefix: 'memoria_asset_vlm');
      }
    }
    return const MediaAnalysisFrameFiles(
      frames: <File>[],
      cleanupPaths: <String>[],
      sourceLabel: 'asset_unreadable',
    );
  }

  Future<Uint8List?> _readAssetThumbnail(
    AssetEntity asset,
    ThumbnailSize size, {
    int quality = 92,
    int frame = 0,
  }) async {
    try {
      final option = Platform.isIOS || Platform.isMacOS
          ? ThumbnailOption.ios(
              size: size,
              format: ThumbnailFormat.jpeg,
              quality: quality,
              resizeContentMode: ResizeContentMode.fit,
            )
          : ThumbnailOption(
              size: size,
              format: ThumbnailFormat.jpeg,
              quality: quality,
              frame: frame,
            );
      final bytes = await asset.thumbnailDataWithOption(option);
      return bytes == null ||
              !MediaThumbnailCacheService.isSupportedImageBytes(bytes)
          ? null
          : bytes;
    } catch (error) {
      debugPrint('[media-reader] thumbnail failed asset=${asset.id}: $error');
      return null;
    }
  }

  Future<List<Uint8List>> _readAssetFrameBytes(
    AssetEntity asset, {
    required int frameCount,
    required int imageSize,
  }) async {
    final durationSeconds = math.max(1, asset.duration);
    final frames = <Uint8List>[];
    for (var i = 0; i < frameCount; i++) {
      final frameMicros = (((i + 0.5) / frameCount) * durationSeconds * 1000000)
          .round();
      final bytes = await _readAssetThumbnail(
        asset,
        ThumbnailSize.square(imageSize),
        quality: 90,
        frame: frameMicros,
      );
      if (bytes != null && bytes.isNotEmpty) {
        frames.add(bytes);
      }
    }
    return frames;
  }

  Future<MediaAnalysisFrameFiles> _writeFrameByteList(
    List<Uint8List> byteList, {
    required String prefix,
  }) async {
    final dir = await getTemporaryDirectory();
    final runId = DateTime.now().microsecondsSinceEpoch;
    final frames = <File>[];
    final paths = <String>[];
    for (var i = 0; i < byteList.length; i++) {
      final bytes = byteList[i];
      if (!MediaThumbnailCacheService.isSupportedImageBytes(bytes)) {
        continue;
      }
      final path =
          '${dir.path}/${prefix}_${runId}_${i.toString().padLeft(2, '0')}.jpg';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      frames.add(file);
      paths.add(path);
    }
    return MediaAnalysisFrameFiles(
      frames: frames,
      cleanupPaths: paths,
      sourceLabel: 'jpeg_frame',
    );
  }

  MemoriaMediaKind _kindForAsset(AssetEntity asset, String? path) {
    if (asset.type == AssetType.video) {
      return MemoriaMediaKind.video;
    }
    if (asset.isLivePhoto) {
      return MemoriaMediaKind.dynamicImage;
    }
    final mime = asset.mimeType?.toLowerCase() ?? '';
    if (mime == 'image/gif') {
      return MemoriaMediaKind.dynamicImage;
    }
    return MemoriaMediaKind.image;
  }

  (int, int) _boundedSize({
    required int width,
    required int height,
    required int maxSide,
  }) {
    if (width <= 0 || height <= 0) {
      return (maxSide, maxSide);
    }
    final scale = math.min(1.0, maxSide / math.max(width, height));
    return (
      math.max(1, (width * scale).round()),
      math.max(1, (height * scale).round()),
    );
  }
}
