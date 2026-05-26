/// 延迟加载路径图片组件，适合在列表或相册中按需解码。

import 'dart:async';
import 'package:flutter/material.dart';

import '../../utils/media_type_helper.dart';
import 'media_thumbnail.dart';

class DeferredPathImage extends StatefulWidget {
  const DeferredPathImage({
    super.key,
    required this.path,
    this.assetId,
    this.kind,
    this.thumbnailPath,
    this.fit = BoxFit.cover,
  });

  final String path;
  final String? assetId;
  final MemoriaMediaKind? kind;
  final String? thumbnailPath;
  final BoxFit fit;

  @override
  State<DeferredPathImage> createState() => _DeferredPathImageState();
}

class _DeferredPathImageState extends State<DeferredPathImage> {
  bool _ready = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant DeferredPathImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.assetId != widget.assetId ||
        oldWidget.kind != widget.kind ||
        oldWidget.thumbnailPath != widget.thumbnailPath) {
      _ready = false;
      _timer?.cancel();
      _scheduleLoad();
    }
  }

  void _scheduleLoad() {
    final delayMs = 30 + (widget.path.hashCode.abs() % 11) * 28;
    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return MediaThumbnail(
        path: widget.path,
        assetId: widget.assetId,
        kind: widget.kind,
        thumbnailPath: widget.thumbnailPath,
        fit: widget.fit,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.grey.shade200),
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
