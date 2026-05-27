import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../service/media_thumbnail_cache_service.dart';
import '../../utils/media_type_helper.dart';

class MediaThumbnail extends StatefulWidget {
  const MediaThumbnail({
    super.key,
    required this.path,
    this.assetId,
    this.kind,
    this.thumbnailPath,
    this.fit = BoxFit.cover,
    this.onFirstFrame,
    this.showBadge = true,
  });

  final String path;
  final String? assetId;
  final MemoriaMediaKind? kind;
  final String? thumbnailPath;
  final BoxFit fit;
  final VoidCallback? onFirstFrame;
  final bool showBadge;

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  static const int _thumbnailSize = 256;
  static const int _maxMemoryCacheEntries = 96;
  static final Map<String, _MediaThumbnailData> _memoryCache =
      <String, _MediaThumbnailData>{};

  late Future<_MediaThumbnailData> _future;
  bool _frameReported = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant MediaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.assetId != widget.assetId ||
        oldWidget.kind != widget.kind ||
        oldWidget.thumbnailPath != widget.thumbnailPath) {
      _frameReported = false;
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MediaThumbnailData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final kind =
            data?.kind ?? widget.kind ?? MediaTypeHelper.fromPath(widget.path);
        final thumb = data?.thumbnailBytes;
        final child = thumb != null && thumb.isNotEmpty
            ? Image.memory(
                thumb,
                fit: widget.fit,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: _thumbnailSize,
                cacheHeight: _thumbnailSize,
                filterQuality: FilterQuality.low,
                frameBuilder: _frameBuilder,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _fallbackForKind(kind),
              )
            : _fallbackForKind(kind);

        if (!widget.showBadge ||
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
      _reportFirstFrame();
    }
    return child;
  }

  void _reportFirstFrame() {
    if (_frameReported) {
      return;
    }
    _frameReported = true;
    widget.onFirstFrame?.call();
  }

  Widget _fallbackForKind(MemoriaMediaKind kind) {
    _reportFirstFrame();
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.grey.shade200),
      child: Center(
        child: Icon(
          kind == MemoriaMediaKind.video
              ? Icons.play_arrow_rounded
              : Icons.image_outlined,
          color: Colors.grey.shade500,
        ),
      ),
    );
  }

  Future<_MediaThumbnailData> _load() async {
    final indexedKind = widget.kind ?? MediaTypeHelper.fromPath(widget.path);
    final cacheKey =
        '${widget.assetId ?? ''}|${widget.path}|${widget.thumbnailPath ?? ''}|${indexedKind.name}';
    final cached = _memoryCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final kind =
        widget.kind ??
        await MediaTypeHelper.resolve(
          path: widget.path,
          assetId: widget.assetId,
        );
    final indexedThumbBytes = await MediaThumbnailCacheService.instance
        .readBytes(widget.thumbnailPath);
    if (indexedThumbBytes != null && indexedThumbBytes.isNotEmpty) {
      return _remember(
        cacheKey,
        _MediaThumbnailData(kind: kind, thumbnailBytes: indexedThumbBytes),
      );
    }

    return _remember(cacheKey, _MediaThumbnailData(kind: kind));
  }

  _MediaThumbnailData _remember(String key, _MediaThumbnailData data) {
    _memoryCache[key] = data;
    if (_memoryCache.length > _maxMemoryCacheEntries) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    return data;
  }
}

class _MediaThumbnailData {
  const _MediaThumbnailData({required this.kind, this.thumbnailBytes});

  final MemoriaMediaKind kind;
  final Uint8List? thumbnailBytes;
}
