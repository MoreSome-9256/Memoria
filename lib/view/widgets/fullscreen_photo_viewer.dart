/// 全屏照片查看器组件，提供放大浏览和过渡动画。

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../service/photo_service.dart';
import '../../service/android_motion_photo_service.dart';
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

class _FullscreenPhotoViewer extends StatefulWidget {
  const _FullscreenPhotoViewer({
    required this.path,
    required this.assetId,
    required this.heroTag,
  });

  final String path;
  final String? assetId;
  final String? heroTag;

  @override
  State<_FullscreenPhotoViewer> createState() => _FullscreenPhotoViewerState();
}

class _FullscreenPhotoViewerState extends State<_FullscreenPhotoViewer> {
  late Future<_ResolvedFullscreenMedia> _mediaFuture;
  bool _cleanupStarted = false;

  @override
  void initState() {
    super.initState();
    _mediaFuture = _resolveMedia();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResolvedFullscreenMedia>(
      future: _mediaFuture,
      builder: (context, snapshot) {
        final media = snapshot.data;
        if (media != null && !media.available) {
          _cleanupUnavailableMedia();
          return const _FullscreenMediaScaffold(
            child: _UnavailableMediaMessage(message: '原始文件已不可访问，正在移除本地记录…'),
          );
        }
        final resolvedPath = media?.path ?? widget.path;
        final kind = media?.kind ?? MediaTypeHelper.fromPath(widget.path);
        if (media?.isLivePhoto == true) {
          return _FullscreenMediaScaffold(
            child: _FullscreenLivePhotoPlayer(
              assetId: widget.assetId!,
              stillPath: resolvedPath,
            ),
          );
        }
        if (kind == MemoriaMediaKind.video) {
          return _FullscreenMediaScaffold(
            child: _FullscreenVideoPlayer(
              path: resolvedPath,
              assetId: widget.assetId,
            ),
          );
        }

        final image =
            widget.assetId != null &&
                widget.assetId!.isNotEmpty &&
                kind == MemoriaMediaKind.image
            ? _FullscreenAndroidMotionPhoto(
                assetId: widget.assetId!,
                fallbackPath: resolvedPath,
              )
            : PathImage(
                path: resolvedPath,
                fit: BoxFit.contain,
                enableSmartCache: false,
              );
        return _FullscreenMediaScaffold(
          child: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: widget.heroTag == null
                  ? image
                  : Hero(tag: widget.heroTag!, child: image),
            ),
          ),
        );
      },
    );
  }

  Future<_ResolvedFullscreenMedia> _resolveMedia() async {
    final kind = await MediaTypeHelper.resolve(
      path: widget.path,
      assetId: widget.assetId,
    );
    if (widget.assetId != null && widget.assetId!.isNotEmpty) {
      final asset = await AssetEntity.fromId(widget.assetId!);
      if (asset == null) {
        return _ResolvedFullscreenMedia(
          kind: kind,
          path: widget.path,
          available: false,
        );
      }
      final file = await asset.file;
      if (file != null && await file.exists()) {
        return _ResolvedFullscreenMedia(
          kind: kind,
          path: file.path,
          available: true,
          isLivePhoto: asset.isLivePhoto,
        );
      }
      final thumbnail = await asset.thumbnailDataWithOption(
        const ThumbnailOption(
          size: ThumbnailSize.square(2048),
          format: ThumbnailFormat.jpeg,
          quality: 92,
        ),
      );
      if (thumbnail != null && thumbnail.isNotEmpty) {
        return _ResolvedFullscreenMedia(
          kind: kind,
          path: widget.path,
          available: true,
          isLivePhoto: asset.isLivePhoto,
        );
      }
    }
    if (widget.path.startsWith('content://')) {
      return _ResolvedFullscreenMedia(
        kind: kind,
        path: widget.path,
        available: true,
      );
    }
    final file = File(widget.path);
    return _ResolvedFullscreenMedia(
      kind: kind,
      path: widget.path,
      available: widget.path.trim().isNotEmpty && await file.exists(),
    );
  }

  void _cleanupUnavailableMedia() {
    if (_cleanupStarted) {
      return;
    }
    _cleanupStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final assetId = widget.assetId?.trim();
      var removed = 0;
      if (assetId != null && assetId.isNotEmpty) {
        removed = await PhotoService().removeUnavailablePhotosByAssetIds(
          <String>[assetId],
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(removed > 0 ? '原始文件已失效，已移除本地记录。' : '原始文件已不可访问。'),
        ),
      );
    });
  }
}

class _ResolvedFullscreenMedia {
  const _ResolvedFullscreenMedia({
    required this.kind,
    required this.path,
    required this.available,
    this.isLivePhoto = false,
  });

  final MemoriaMediaKind kind;
  final String path;
  final bool available;
  final bool isLivePhoto;
}

class _UnavailableMediaMessage extends StatelessWidget {
  const _UnavailableMediaMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
        ),
      ),
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

class _FullscreenLivePhotoPlayer extends StatefulWidget {
  const _FullscreenLivePhotoPlayer({
    required this.assetId,
    required this.stillPath,
  });

  final String assetId;
  final String stillPath;

  @override
  State<_FullscreenLivePhotoPlayer> createState() =>
      _FullscreenLivePhotoPlayerState();
}

class _FullscreenAndroidMotionPhoto extends StatefulWidget {
  const _FullscreenAndroidMotionPhoto({
    required this.assetId,
    required this.fallbackPath,
  });

  final String assetId;
  final String fallbackPath;

  @override
  State<_FullscreenAndroidMotionPhoto> createState() =>
      _FullscreenAndroidMotionPhotoState();
}

class _FullscreenAndroidMotionPhotoState
    extends State<_FullscreenAndroidMotionPhoto> {
  VideoPlayerController? _controller;
  Uint8List? _stillBytes;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final asset = await AssetEntity.fromId(widget.assetId);
      _stillBytes = await asset?.thumbnailDataWithOption(
        const ThumbnailOption(
          size: ThumbnailSize.square(2048),
          format: ThumbnailFormat.jpeg,
          quality: 95,
        ),
      );
      final motionFile = await AndroidMotionPhotoService.extractByAssetId(
        widget.assetId,
      );
      if (motionFile != null) {
        final controller = VideoPlayerController.file(motionFile);
        await controller.initialize();
        await controller.setVolume(0);
        await controller.setLooping(true);
        await controller.play();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() => _controller = controller);
        return;
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Android Motion Photo playback failed: assetId=${widget.assetId} '
        'error=$error\n$stackTrace',
      );
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      return AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      );
    }
    final bytes = _stillBytes;
    return bytes != null && bytes.isNotEmpty
        ? Image.memory(bytes, fit: BoxFit.contain)
        : PathImage(
            path: widget.fallbackPath,
            fit: BoxFit.contain,
            enableSmartCache: false,
          );
  }
}

class _FullscreenLivePhotoPlayerState
    extends State<_FullscreenLivePhotoPlayer> {
  VideoPlayerController? _controller;
  Uint8List? _stillBytes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    VideoPlayerController? controller;
    try {
      final asset = await AssetEntity.fromId(widget.assetId);
      if (asset == null) {
        throw StateError('Live Photo asset is unavailable');
      }
      _stillBytes = await asset.thumbnailDataWithOption(
        const ThumbnailOption(
          size: ThumbnailSize.square(2048),
          format: ThumbnailFormat.jpeg,
          quality: 92,
        ),
      );

      final mediaUrl = await asset.getMediaUrl();
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(mediaUrl),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } else {
        final motionFile = await asset.fileWithSubtype;
        if (motionFile == null || !await motionFile.exists()) {
          throw StateError('Live Photo motion resource is unavailable');
        }
        controller = VideoPlayerController.file(motionFile);
      }
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error, stackTrace) {
      await controller?.dispose();
      debugPrint(
        'Live Photo playback failed: assetId=${widget.assetId} '
        'error=$error\n$stackTrace',
      );
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
    if (controller != null && controller.value.isInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }
    final stillBytes = _stillBytes;
    final still = stillBytes != null && stillBytes.isNotEmpty
        ? Image.memory(stillBytes, fit: BoxFit.contain)
        : PathImage(
            path: widget.stillPath,
            fit: BoxFit.contain,
            enableSmartCache: false,
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: still),
        if (_error == null)
          const Center(child: CircularProgressIndicator())
        else
          Positioned(
            right: 16,
            bottom: 16,
            child: Icon(
              Icons.motion_photos_off_outlined,
              color: Colors.white70,
            ),
          ),
      ],
    );
  }
}
