import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class PathImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool enableSmartCache;

  const PathImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.enableSmartCache = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cache = _resolveCacheSize(context, constraints);
        final uri = Uri.tryParse(path);
        final scheme = uri?.scheme.toLowerCase();

        if (scheme == 'http' || scheme == 'https') {
          return Image.network(
            path,
            fit: fit,
            width: width,
            height: height,
            cacheWidth: cache.$1,
            cacheHeight: cache.$2,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => _fallback(),
          );
        }

        final file = _resolveLocalFile(uri);
        return Image.file(
          file,
          fit: fit,
          width: width,
          height: height,
          cacheWidth: cache.$1,
          cacheHeight: cache.$2,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => _fallback(),
        );
      },
    );
  }

  (int?, int?) _resolveCacheSize(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    if (!enableSmartCache) {
      return (null, null);
    }

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final logicalWidth = width ??
        (constraints.hasBoundedWidth ? constraints.maxWidth : null);
    final logicalHeight = height ??
        (constraints.hasBoundedHeight ? constraints.maxHeight : null);

    int? toCache(double? logical) {
      if (logical == null || !logical.isFinite || logical <= 0) {
        return null;
      }
      final pixels = (logical * dpr).round();
      return math.max(80, math.min(2200, pixels));
    }

    return (toCache(logicalWidth), toCache(logicalHeight));
  }

  File _resolveLocalFile(Uri? uri) {
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      return File.fromUri(uri);
    }
    return File(path);
  }

  Widget _fallback() {
    return Container(
      color: Colors.grey.shade300,
      child: const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
