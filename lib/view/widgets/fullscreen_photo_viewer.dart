/// 全屏照片查看器组件，提供放大浏览和过渡动画。

import 'package:flutter/material.dart';

import 'path_image.dart';

Future<void> showFullscreenPhotoViewer(
  BuildContext context, {
  required String path,
  String? heroTag,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (context, animation, secondaryAnimation) {
        return _FullscreenPhotoViewer(path: path, heroTag: heroTag);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _FullscreenPhotoViewer extends StatelessWidget {
  const _FullscreenPhotoViewer({required this.path, required this.heroTag});

  final String path;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    // Fullscreen viewing should preserve the photo's intrinsic aspect ratio.
    // Smart cache sizing can provide both width and height hints from the
    // viewport, which may distort the decoded bitmap for some images.
    final image = PathImage(
      path: path,
      fit: BoxFit.contain,
      enableSmartCache: false,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Center(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: heroTag == null
                        ? image
                        : Hero(tag: heroTag!, child: image),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
