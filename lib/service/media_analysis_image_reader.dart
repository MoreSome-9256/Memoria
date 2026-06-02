import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../utils/media_type_helper.dart';

class MediaAnalysisImageInput {
  const MediaAnalysisImageInput({
    required this.kind,
    required this.imageBytes,
    required this.analysisImageBytes,
    required this.videoFrameBytes,
    required this.width,
    required this.height,
    required this.sourceLabel,
    this.sourceFile,
  });

  final MemoriaMediaKind kind;
  final Uint8List imageBytes;
  final Uint8List analysisImageBytes;
  final List<Uint8List> videoFrameBytes;
  final int width;
  final int height;
  final String sourceLabel;
  final File? sourceFile;
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
  static final MediaAnalysisImageReader instance =
      MediaAnalysisImageReader._();

  static const int defaultImageSize = 384;
  static const int defaultAnalysisSize = 1024;
  static const int defaultFrameCount = 8;

  Future<MediaAnalysisImageInput?> readAsset(
    AssetEntity asset, {
    int imageSize = defaultImageSize,
    int analysisSize = defaultAnalysisSize,
    int frameCount = defaultFrameCount,
    File? fallbackFile,
    bool allowFileFallback = true,
  }) async {
    final kind = _kindForAsset(asset, fallbackFile?.path);
    final sourceFile = allowFileFallback
        ? fallbackFile ?? await _bestReadableAssetFile(asset)
        : null;
    final dims = _boundedSize(
      width: asset.width,
      height: asset.height,
      maxSide: analysisSize,
    );

    final imageBytes =
        await _readAssetThumbnail(
          asset,
          ThumbnailSize.square(imageSize),
          quality: 92,
        ) ??
        (sourceFile == null
            ? null
            : await _decodeFileAsJpegBytes(sourceFile, maxSide: imageSize));
    final analysisBytes =
        await _readAssetThumbnail(
          asset,
          ThumbnailSize(dims.$1, dims.$2),
          quality: 92,
        ) ??
        imageBytes ??
        (sourceFile == null
            ? null
            : await _decodeFileAsJpegBytes(sourceFile, maxSide: analysisSize));
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
            sourceFile: sourceFile,
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
      sourceFile: sourceFile,
    );
  }

  Future<MediaAnalysisImageInput?> readAssetById(
    String assetId, {
    int imageSize = defaultImageSize,
    int analysisSize = defaultAnalysisSize,
    int frameCount = defaultFrameCount,
    File? fallbackFile,
    bool allowFileFallback = true,
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
      fallbackFile: fallbackFile,
      allowFileFallback: allowFileFallback,
    );
  }

  Future<MediaAnalysisFrameFiles> readFrameFilesFromAsset(
    String assetId, {
    required bool videoLike,
    File? fallbackFile,
    bool allowFileFallback = false,
    int maxFrames = defaultFrameCount,
  }) async {
    final asset = await AssetEntity.fromId(assetId);
    if (asset != null) {
      if (asset.type == AssetType.video || asset.isLivePhoto || videoLike) {
        final sourceFile = await _bestReadableAssetFile(asset);
        if (sourceFile != null) {
          final fromVideo = await _extractFrameFiles(
            sourceFile,
            maxFrames: maxFrames,
          );
          if (fromVideo.frames.isNotEmpty) {
            return fromVideo;
          }
          if (asset.isLivePhoto || _isGifLike(asset)) {
            final decoded = await _decodeGifFrameFiles(
              sourceFile,
              maxFrames: maxFrames,
            );
            if (decoded.frames.isNotEmpty) {
              return decoded;
            }
          }
        }
        final frameBytes = await _readAssetFrameBytes(
          asset,
          sourceFile: null,
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
        return _writeFrameBytes(bytes, prefix: 'memoria_asset_vlm');
      }
    }
    if (allowFileFallback && fallbackFile != null) {
      return readFrameFilesFromFile(
        fallbackFile,
        videoLike: videoLike,
        maxFrames: maxFrames,
      );
    }
    return const MediaAnalysisFrameFiles(
      frames: <File>[],
      cleanupPaths: <String>[],
      sourceLabel: 'asset_unreadable',
    );
  }

  Future<MediaAnalysisFrameFiles> readFrameFilesFromFile(
    File file, {
    required bool videoLike,
    int maxFrames = defaultFrameCount,
  }) async {
    if (!await file.exists()) {
      return const MediaAnalysisFrameFiles(
        frames: <File>[],
        cleanupPaths: <String>[],
        sourceLabel: 'missing_file',
      );
    }
    final path = file.path.toLowerCase();
    final isGif = path.endsWith('.gif');
    final isVideo = videoLike || MediaTypeHelper.isVideoPath(file.path);
    if (isVideo) {
      final extracted = await _extractFrameFiles(file, maxFrames: maxFrames);
      if (extracted.frames.isNotEmpty) {
        return extracted;
      }
    }
    if (isGif) {
      final decoded = await _decodeGifFrameFiles(file, maxFrames: maxFrames);
      if (decoded.frames.isNotEmpty) {
        return decoded;
      }
    }
    final bytes = await _decodeFileAsJpegBytes(
      file,
      maxSide: defaultAnalysisSize,
    );
    if (bytes != null && bytes.isNotEmpty) {
      return _writeFrameBytes(bytes, prefix: 'memoria_file_vlm');
    }
    return MediaAnalysisFrameFiles(
      frames: <File>[file],
      cleanupPaths: const <String>[],
      sourceLabel: 'original_file',
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
      return bytes == null || bytes.isEmpty ? null : bytes;
    } catch (error) {
      debugPrint('[media-reader] thumbnail failed asset=${asset.id}: $error');
      return null;
    }
  }

  Future<List<Uint8List>> _readAssetFrameBytes(
    AssetEntity asset, {
    required File? sourceFile,
    required int frameCount,
    required int imageSize,
  }) async {
    if (sourceFile != null) {
      final extracted = await _extractFrameFiles(
        sourceFile,
        maxFrames: frameCount,
      );
      if (extracted.frames.isNotEmpty) {
        return Future.wait(extracted.frames.map((file) => file.readAsBytes()))
            .whenComplete(() => _deletePaths(extracted.cleanupPaths));
      }
    }

    final durationSeconds = math.max(1, asset.duration);
    final frames = <Uint8List>[];
    for (var i = 0; i < frameCount; i++) {
      final frameMicros =
          (((i + 0.5) / frameCount) * durationSeconds * 1000000).round();
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

  Future<File?> _bestReadableAssetFile(AssetEntity asset) async {
    try {
      if (asset.isLivePhoto && (Platform.isIOS || Platform.isMacOS)) {
        final liveVideo = await asset.loadFile(
          isOrigin: false,
          withSubtype: true,
          darwinFileType: PMDarwinAVFileType.mov,
        );
        if (liveVideo != null && liveVideo.path.isNotEmpty) {
          return liveVideo;
        }
      }
    } catch (_) {}
    try {
      return await asset.file ?? await asset.originFile;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _decodeFileAsJpegBytes(
    File file, {
    required int maxSide,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        return Uint8List.fromList(
          img.encodeJpg(_resizeToMaxSide(decoded, maxSide), quality: 90),
        );
      }
    } catch (_) {}

    final extracted = await _extractFrameFiles(file, maxFrames: 1);
    if (extracted.frames.isEmpty) {
      return null;
    }
    try {
      return await extracted.frames.first.readAsBytes();
    } finally {
      await _deletePaths(extracted.cleanupPaths);
    }
  }

  Future<MediaAnalysisFrameFiles> _decodeGifFrameFiles(
    File file, {
    required int maxFrames,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final gif = img.decodeGif(bytes);
      if (gif == null || gif.numFrames <= 0) {
        return const MediaAnalysisFrameFiles(
          frames: <File>[],
          cleanupPaths: <String>[],
          sourceLabel: 'gif_decode_empty',
        );
      }
      final sampleCount = math.min(maxFrames, math.max(1, gif.numFrames));
      final dir = await getTemporaryDirectory();
      final runId = DateTime.now().microsecondsSinceEpoch;
      final frames = <File>[];
      final paths = <String>[];
      final step = gif.numFrames / sampleCount;
      for (var i = 0; i < sampleCount; i++) {
        final frameIndex = (i * step).floor().clamp(0, gif.numFrames - 1);
        final frame = gif.getFrame(frameIndex);
        final path =
            '${dir.path}/memoria_gif_vlm_${runId}_${i.toString().padLeft(2, '0')}.jpg';
        final out = File(path);
        await out.writeAsBytes(img.encodeJpg(frame, quality: 90), flush: true);
        frames.add(out);
        paths.add(path);
      }
      return MediaAnalysisFrameFiles(
        frames: frames,
        cleanupPaths: paths,
        sourceLabel: 'gif_frames',
      );
    } catch (error) {
      debugPrint('[media-reader] gif decode failed: $error');
      return const MediaAnalysisFrameFiles(
        frames: <File>[],
        cleanupPaths: <String>[],
        sourceLabel: 'gif_decode_failed',
      );
    }
  }

  Future<MediaAnalysisFrameFiles> _extractFrameFiles(
    File file, {
    required int maxFrames,
  }) async {
    final dir = await getTemporaryDirectory();
    final runId = DateTime.now().microsecondsSinceEpoch;
    final framePattern = '${dir.path}/memoria_media_${runId}_%02d.jpg';
    final command =
        '-y -i ${_quote(file.path)} -vf fps=1,scale=640:-2 -frames:v $maxFrames ${_quote(framePattern)}';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      debugPrint('[media-reader] ffmpeg frame extraction failed: $logs');
    }
    final frames = <File>[];
    final paths = <String>[];
    for (var i = 1; i <= maxFrames; i++) {
      final path =
          '${dir.path}/memoria_media_${runId}_${i.toString().padLeft(2, '0')}.jpg';
      final out = File(path);
      if (await out.exists()) {
        frames.add(out);
        paths.add(path);
      }
    }
    return MediaAnalysisFrameFiles(
      frames: frames,
      cleanupPaths: paths,
      sourceLabel: 'ffmpeg_frames',
    );
  }

  Future<MediaAnalysisFrameFiles> _writeFrameBytes(
    Uint8List bytes, {
    required String prefix,
  }) async {
    return _writeFrameByteList(<Uint8List>[bytes], prefix: prefix);
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
      if (bytes.isEmpty) {
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
    return path == null ? MemoriaMediaKind.image : MediaTypeHelper.fromPath(path);
  }

  bool _isGifLike(AssetEntity asset) {
    final mime = asset.mimeType?.toLowerCase() ?? '';
    return mime == 'image/gif' || mime == 'image/webp';
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
    return (math.max(1, (width * scale).round()), math.max(1, (height * scale).round()));
  }

  img.Image _resizeToMaxSide(img.Image source, int maxSide) {
    final longSide = math.max(source.width, source.height);
    if (longSide <= maxSide) {
      return source;
    }
    if (source.width >= source.height) {
      return img.copyResize(source, width: maxSide);
    }
    return img.copyResize(source, height: maxSide);
  }

  Future<void> _deletePaths(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  String _quote(String value) => '"${value.replaceAll('"', r'\"')}"';
}
