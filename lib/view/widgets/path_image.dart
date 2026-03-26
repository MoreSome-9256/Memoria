import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class PathImage extends StatefulWidget {
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;
  final bool enableSmartCache;
  final VoidCallback? onFirstFrame;

  const PathImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.enableSmartCache = true,
    this.onFirstFrame,
  });

  @override
  State<PathImage> createState() => _PathImageState();
}

class _PathImageState extends State<PathImage> {
  bool _frameReported = false;

  @override
  void didUpdateWidget(covariant PathImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _frameReported = false;
    }
  }

  void _reportFirstFrame() {
    if (_frameReported) {
      return;
    }
    _frameReported = true;
    widget.onFirstFrame?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cache = _resolveCacheSize(context, constraints);
        final uri = Uri.tryParse(widget.path);
        final scheme = uri?.scheme.toLowerCase();
        Widget frameBuilder(
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

        if (scheme == 'http' || scheme == 'https') {
          return Image.network(
            widget.path,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            cacheWidth: cache.$1,
            cacheHeight: cache.$2,
            filterQuality: FilterQuality.low,
            frameBuilder: frameBuilder,
            errorBuilder: (_, _, _) => _fallback(),
          );
        }

        final file = _resolveLocalFile(uri);
        return Image.file(
          file,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          cacheWidth: cache.$1,
          cacheHeight: cache.$2,
          filterQuality: FilterQuality.low,
          frameBuilder: frameBuilder,
          errorBuilder: (_, _, _) => _fallback(),
        );
      },
    );
  }

  (int?, int?) _resolveCacheSize(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    if (!widget.enableSmartCache) {
      return (null, null);
    }

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final logicalWidth =
        widget.width ??
        (constraints.hasBoundedWidth ? constraints.maxWidth : null);
    final logicalHeight =
        widget.height ??
        (constraints.hasBoundedHeight ? constraints.maxHeight : null);

    int? toCache(double? logical) {
      if (logical == null || !logical.isFinite || logical <= 0) {
        return null;
      }
      final pixels = (logical * dpr).round();
      return math.max(80, math.min(2200, pixels));
    }

    final cw = toCache(logicalWidth);
    final ch = toCache(logicalHeight);

    // ==========================================
    // 🌟 核心修复补丁：绝不能同时限制宽高！
    // ==========================================
    if (cw != null && ch != null) {
      // 取较长的一边作为缓存基准，另一边传 null，完美保持原图比例！
      if (cw > ch) {
        return (cw, null);
      } else {
        return (null, ch);
      }
    }

    return (cw, ch);
  }

  File _resolveLocalFile(Uri? uri) {
    if (uri != null && uri.scheme.toLowerCase() == 'file') {
      return File.fromUri(uri);
    }
    return File(widget.path);
  }

  Widget _fallback() {
    return Container(
      color: Colors.grey.shade300,
      child: const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
