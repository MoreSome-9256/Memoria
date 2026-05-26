import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../utils/media_type_helper.dart';
import 'path_image.dart';

class MediaThumbnail extends StatelessWidget {
  const MediaThumbnail({
    super.key,
    required this.path,
    this.assetId,
    this.fit = BoxFit.cover,
    this.onFirstFrame,
    this.showBadge = true,
  });

  final String path;
  final String? assetId;
  final BoxFit fit;
  final VoidCallback? onFirstFrame;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MediaThumbnailData>(
      future: _load(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final kind = data?.kind ?? MediaTypeHelper.fromPath(path);
        final thumb = data?.thumbnailBytes;
        final child = thumb != null && thumb.isNotEmpty
            ? Image.memory(
                thumb,
                fit: fit,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: 384,
                cacheHeight: 384,
                filterQuality: FilterQuality.low,
                frameBuilder: _frameBuilder,
                errorBuilder: (_, _, _) => _pathImage(),
              )
            : _pathImage();

        if (!showBadge ||
            (kind != MemoriaMediaKind.video &&
                kind != MemoriaMediaKind.dynamicImage)) {
          return child;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned(
              right: 8,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.54),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Icon(
                    kind == MemoriaMediaKind.video
                        ? Icons.play_arrow_rounded
                        : Icons.motion_photos_on_outlined,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _frameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded || frame != null) {
      onFirstFrame?.call();
    }
    return child;
  }

  Widget _pathImage() {
    return PathImage(
      path: path,
      fit: fit,
      onFirstFrame: onFirstFrame,
    );
  }

  Future<_MediaThumbnailData> _load() async {
    final kind = await MediaTypeHelper.resolve(path: path, assetId: assetId);
    if (assetId == null || assetId!.isEmpty) {
      return _MediaThumbnailData(kind: kind);
    }
    if (kind != MemoriaMediaKind.video &&
        kind != MemoriaMediaKind.dynamicImage) {
      return _MediaThumbnailData(kind: kind);
    }
    try {
      final asset = await AssetEntity.fromId(assetId!);
      final bytes = await asset?.thumbnailDataWithSize(
        const ThumbnailSize.square(256),
        quality: 72,
      );
      return _MediaThumbnailData(kind: kind, thumbnailBytes: bytes);
    } catch (_) {
      return _MediaThumbnailData(kind: kind);
    }
  }
}

class _MediaThumbnailData {
  const _MediaThumbnailData({required this.kind, this.thumbnailBytes});

  final MemoriaMediaKind kind;
  final Uint8List? thumbnailBytes;
}
