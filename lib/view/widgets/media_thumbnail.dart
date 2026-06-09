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
    this.thumbnailBytes,
    this.fit = BoxFit.cover,
    this.onFirstFrame,
    this.onLoadFailed,
    this.showBadge = true,
  });

  final String path;
  final String? assetId;
  final MemoriaMediaKind? kind;
  final Uint8List? thumbnailBytes;
  final BoxFit fit;
  final VoidCallback? onFirstFrame;
  final VoidCallback? onLoadFailed;
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
  bool _failureReported = false;

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
        oldWidget.thumbnailBytes != widget.thumbnailBytes) {
      _frameReported = false;
      _failureReported = false;
      _future = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_MediaThumbnailData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
            'MediaThumbnail load failed: assetId=${widget.assetId} '
            'kind=${widget.kind} error=${snapshot.error}',
          );
        }
        final data = snapshot.data;
        final kind =
            data?.kind ?? widget.kind ?? MediaTypeHelper.fromPath(widget.path);
        final thumb = data?.thumbnailBytes;
        final child = thumb != null && thumb.isNotEmpty
            ? _buildImage(thumb, kind)
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

  Widget _buildImage(Uint8List thumb, MemoriaMediaKind kind) {
    final image = Image.memory(
      thumb,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: _thumbnailSize,
      cacheHeight: _thumbnailSize,
      filterQuality: FilterQuality.medium,
      frameBuilder: _frameBuilder,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _fallbackForKind(kind),
    );
    if (widget.fit != BoxFit.cover) {
      return image;
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.grey.shade100),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              thumb,
              fit: BoxFit.cover,
              cacheWidth: _thumbnailSize,
              cacheHeight: _thumbnailSize,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.08)),
            Image.memory(
              thumb,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: _thumbnailSize,
              cacheHeight: _thumbnailSize,
              filterQuality: FilterQuality.medium,
              frameBuilder: _frameBuilder,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _fallbackForKind(kind),
            ),
          ],
        ),
      ),
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
    final callback = widget.onFirstFrame;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) callback();
      });
    }
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
    final thumbLength = widget.thumbnailBytes?.lengthInBytes ?? 0;
    final cacheKey =
        '${widget.assetId ?? ''}|${widget.path}|$thumbLength|${indexedKind.name}';
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
        .decompressBytes(widget.thumbnailBytes);
    if (indexedThumbBytes != null && indexedThumbBytes.isNotEmpty) {
      return _remember(
        cacheKey,
        _MediaThumbnailData(kind: kind, thumbnailBytes: indexedThumbBytes),
      );
    }

    final assetId = widget.assetId?.trim();
    if (assetId != null && assetId.isNotEmpty) {
      try {
        final result = await MediaThumbnailCacheService.instance
            .loadAssetThumbnailById(assetId);
        final assetThumb = result?.bytes;
        if (assetThumb != null && assetThumb.isNotEmpty) {
          return _remember(
            cacheKey,
            _MediaThumbnailData(kind: result!.kind, thumbnailBytes: assetThumb),
          );
        }
      } catch (error, stackTrace) {
        debugPrint(
          'MediaThumbnail asset fallback failed: assetId=$assetId '
          'kind=$kind error=$error\n$stackTrace',
        );
      }
    }

    _reportLoadFailed();
    return _MediaThumbnailData(kind: kind);
  }

  void _reportLoadFailed() {
    if (_failureReported) return;
    _failureReported = true;
    final callback = widget.onLoadFailed;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) callback();
      });
    }
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
