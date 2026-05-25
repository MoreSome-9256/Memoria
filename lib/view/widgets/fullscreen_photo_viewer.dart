/// 全屏照片查看器组件，提供放大浏览和过渡动画。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../utils/media_type_helper.dart';
import 'path_image.dart';

Future<void> showFullscreenPhotoViewer(
  BuildContext context, {
  required String path,
  String? assetId,
  String? heroTag,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (context, animation, secondaryAnimation) {
        return _FullscreenPhotoViewer(
          path: path,
          assetId: assetId,
          heroTag: heroTag,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _FullscreenPhotoViewer extends StatelessWidget {
  const _FullscreenPhotoViewer({
    required this.path,
    required this.assetId,
    required this.heroTag,
  });

  final String path;
  final String? assetId;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MemoriaMediaKind>(
      future: MediaTypeHelper.resolve(path: path, assetId: assetId),
      builder: (context, snapshot) {
        final kind = snapshot.data ?? MediaTypeHelper.fromPath(path);
        if (kind == MemoriaMediaKind.video) {
          return _FullscreenMediaScaffold(
            child: _FullscreenVideoPlayer(path: path, assetId: assetId),
          );
        }

        final image = PathImage(
          path: path,
          fit: BoxFit.contain,
          enableSmartCache: false,
        );
        return _FullscreenMediaScaffold(
          child: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: heroTag == null
                  ? image
                  : Hero(tag: heroTag!, child: image),
            ),
          ),
        );
      },
    );
  }
}

class _FullscreenMediaScaffold extends StatelessWidget {
  const _FullscreenMediaScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: child,
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

class _FullscreenVideoPlayer extends StatefulWidget {
  const _FullscreenVideoPlayer({required this.path, required this.assetId});

  final String path;
  final String? assetId;

  @override
  State<_FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<_FullscreenVideoPlayer> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      File? file;
      if (widget.assetId != null && widget.assetId!.isNotEmpty) {
        final asset = await AssetEntity.fromId(widget.assetId!);
        file = await asset?.file;
      }
      file ??= File(widget.path);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return Center(
        child: Text(
          '视频无法播放',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }
}
