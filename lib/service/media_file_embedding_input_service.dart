import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/media_type_helper.dart';
import 'mobileviclip_video_service.dart';

class MediaFileEmbeddingInput {
  const MediaFileEmbeddingInput({
    required this.kind,
    required this.path,
    required this.imageOrThumbnailBytes,
    required this.videoFrameBytes,
    required this.cleanupPaths,
  });

  final MemoriaMediaKind kind;
  final String path;
  final Uint8List imageOrThumbnailBytes;
  final List<Uint8List> videoFrameBytes;
  final List<String> cleanupPaths;
}

class MediaFileEmbeddingInputService {
  Future<MediaFileEmbeddingInput> prepare(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw ArgumentError('文件不存在: $path');
    }
    final kind = MediaTypeHelper.fromPath(path);
    if (kind != MemoriaMediaKind.video) {
      final bytes = await file.readAsBytes();
      return MediaFileEmbeddingInput(
        kind: kind,
        path: path,
        imageOrThumbnailBytes: bytes,
        videoFrameBytes: const <Uint8List>[],
        cleanupPaths: const <String>[],
      );
    }

    final extracted = await _extractVideoFrames(path);
    if (extracted.frames.isEmpty) {
      throw StateError('无法从视频提取测试帧: $path');
    }
    return MediaFileEmbeddingInput(
      kind: kind,
      path: path,
      imageOrThumbnailBytes: extracted.frames.first,
      videoFrameBytes: extracted.frames,
      cleanupPaths: extracted.paths,
    );
  }

  Future<_ExtractedFrames> _extractVideoFrames(String path) async {
    final dir = await getTemporaryDirectory();
    final runId = DateTime.now().microsecondsSinceEpoch;
    final framePattern = '${dir.path}/memoria_viclip_${runId}_%02d.jpg';
    final command =
        '-y -i ${_quote(path)} -vf fps=1,scale=512:-1 -frames:v ${MobileViClipVideoService.frameCount} ${_quote(framePattern)}';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      debugPrint('FFmpeg 视频抽帧失败: $logs');
    }

    final frames = <Uint8List>[];
    final paths = <String>[];
    for (var i = 1; i <= MobileViClipVideoService.frameCount; i++) {
      final framePath =
          '${dir.path}/memoria_viclip_${runId}_${i.toString().padLeft(2, '0')}.jpg';
      final frameFile = File(framePath);
      if (!frameFile.existsSync()) continue;
      paths.add(framePath);
      frames.add(await frameFile.readAsBytes());
    }
    return _ExtractedFrames(frames: frames, paths: paths);
  }

  String _quote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}

class _ExtractedFrames {
  const _ExtractedFrames({
    required this.frames,
    required this.paths,
  });

  final List<Uint8List> frames;
  final List<String> paths;
}
