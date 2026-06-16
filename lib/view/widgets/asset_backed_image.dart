import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../service/media_thumbnail_cache_service.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/vo/photo.dart';
import '../../objectbox.g.dart';
import '../../storage/objectbox/objectbox_service.dart';

final Map<String, Uint8List> _assetPreviewMemoryCache = <String, Uint8List>{};

Future<void> warmAssetBackedImages(Iterable<Photo> photos) async {
  for (final photo in photos) {
    final assetId = photo.id.trim();
    if (assetId.isEmpty || _assetPreviewMemoryCache.containsKey(assetId)) {
      continue;
    }
    await resolveAssetBackedImageBytes(photo);
  }
}

Future<Uint8List?> resolveAssetBackedImageBytes(Photo photo) async {
  final assetId = photo.id.trim();
  if (assetId.isEmpty) {
    return null;
  }
  final cached = _assetPreviewMemoryCache[assetId];
  if (cached != null && cached.isNotEmpty) {
    return cached;
  }
  try {
    final asset = await AssetEntity.fromId(assetId);
    final bytes = await asset?.thumbnailDataWithOption(
      const ThumbnailOption(
        size: ThumbnailSize.square(2048),
        format: ThumbnailFormat.jpeg,
        quality: 92,
      ),
    );
    if (bytes != null && bytes.isNotEmpty) {
      _rememberAssetPreview(assetId, bytes);
      return bytes;
    }
  } catch (_) {
    // Widget callers can still decide how to render a missing asset preview.
  }
  return null;
}

Uint8List? peekCachedAssetBytes(String assetId) {
  return _assetPreviewMemoryCache[assetId.trim()];
}

void _rememberAssetPreview(String assetId, Uint8List bytes) {
  _assetPreviewMemoryCache[assetId] = bytes;
  if (_assetPreviewMemoryCache.length > 96) {
    _assetPreviewMemoryCache.remove(_assetPreviewMemoryCache.keys.first);
  }
}

class AssetBackedImage extends StatefulWidget {
  const AssetBackedImage({
    super.key,
    required this.path,
    required this.assetId,
    this.thumbnailBytes,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.enableSmartCache = true,
  });

  final String path;
  final String? assetId;
  final Uint8List? thumbnailBytes;
  final BoxFit fit;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final bool enableSmartCache;

  @override
  State<AssetBackedImage> createState() => _AssetBackedImageState();
}

class _AssetBackedImageState extends State<AssetBackedImage> {
  late Future<_AssetBackedImageData> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  @override
  void didUpdateWidget(covariant AssetBackedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.assetId != widget.assetId ||
        oldWidget.thumbnailBytes != widget.thumbnailBytes) {
      _future = _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_AssetBackedImageData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data?.bytes case final bytes? when bytes.isNotEmpty) {
          return Image.memory(
            bytes,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            alignment: widget.alignment,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _fallback(),
          );
        }
        final resolvedPath = data?.path ?? widget.path;
        if (resolvedPath.trim().isNotEmpty) {
          return LayoutBuilder(
            builder: (context, constraints) =>
                _buildPathImage(context, constraints, resolvedPath),
          );
        }
        return _fallback();
      },
    );
  }

  Future<_AssetBackedImageData> _resolve() async {
    var assetId = widget.assetId?.trim();
    if ((assetId == null || assetId.isEmpty) && widget.path.trim().isNotEmpty) {
      assetId = _findIndexedAssetIdByPath(widget.path);
    }
    if (assetId != null && assetId.isNotEmpty) {
      final cachedPreview = _assetPreviewMemoryCache[assetId];
      if (cachedPreview != null && cachedPreview.isNotEmpty) {
        return _AssetBackedImageData(bytes: cachedPreview);
      }
      try {
        final asset = await AssetEntity.fromId(assetId);
        final bytes = await asset?.thumbnailDataWithOption(
          const ThumbnailOption(
            size: ThumbnailSize.square(2048),
            format: ThumbnailFormat.jpeg,
            quality: 92,
          ),
        );
        if (bytes != null && bytes.isNotEmpty) {
          _rememberAssetPreview(assetId, bytes);
          return _AssetBackedImageData(bytes: bytes);
        }
        final file = await asset?.file;
        if (file != null && await file.exists()) {
          return _AssetBackedImageData(path: file.path);
        }
      } catch (error, stackTrace) {
        debugPrint(
          'AssetBackedImage asset recovery failed: assetId=$assetId '
          'error=$error\n$stackTrace',
        );
      }
    }

    final path = widget.path.trim();
    if (path.isNotEmpty) {
      final uri = Uri.tryParse(path);
      if (uri?.scheme == 'http' || uri?.scheme == 'https') {
        return _AssetBackedImageData(path: path);
      }
      final file = uri?.scheme == 'file' ? File.fromUri(uri!) : File(path);
      if (await file.exists()) {
        return _AssetBackedImageData(path: path);
      }
    }

    final cachedBytes = await MediaThumbnailCacheService.instance
        .decompressBytes(widget.thumbnailBytes);
    return _AssetBackedImageData(bytes: cachedBytes);
  }

  String? _findIndexedAssetIdByPath(String path) {
    try {
      final box = ObjectBoxService().store.box<PhotoEntity>();
      final query = box.query(PhotoEntity_.path.equals(path)).build();
      query.limit = 1;
      final photo = query.findFirst();
      query.close();
      return photo?.assetId.trim();
    } catch (_) {
      return null;
    }
  }

  Widget _buildPathImage(
    BuildContext context,
    BoxConstraints constraints,
    String path,
  ) {
    final cache = _resolveCacheSize(context, constraints);
    final uri = Uri.tryParse(path);
    final scheme = uri?.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      return Image.network(
        path,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        alignment: widget.alignment,
        cacheWidth: cache.$1,
        cacheHeight: cache.$2,
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    final file = scheme == 'file' ? File.fromUri(uri!) : File(path);
    return Image.file(
      file,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      alignment: widget.alignment,
      cacheWidth: cache.$1,
      cacheHeight: cache.$2,
      errorBuilder: (_, _, _) => _fallback(),
    );
  }

  (int?, int?) _resolveCacheSize(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    if (!widget.enableSmartCache) return (null, null);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    int? pixels(double? logical) {
      if (logical == null || !logical.isFinite || logical <= 0) return null;
      return math.max(80, math.min(2048, (logical * dpr).round()));
    }

    final width = pixels(
      widget.width ??
          (constraints.hasBoundedWidth ? constraints.maxWidth : null),
    );
    final height = pixels(
      widget.height ??
          (constraints.hasBoundedHeight ? constraints.maxHeight : null),
    );
    if (width != null && height != null) {
      return width > height ? (width, null) : (null, height);
    }
    return (width, height);
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.grey.shade200),
      child: Center(
        child: Icon(Icons.image_outlined, color: Colors.grey.shade500),
      ),
    );
  }
}

class _AssetBackedImageData {
  const _AssetBackedImageData({this.path, this.bytes});

  final String? path;
  final Uint8List? bytes;
}
