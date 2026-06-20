/// 发布页面，提供故事分享和发布相关功能。

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;
import 'package:video_player/video_player.dart';
import 'package:open_file_manager/open_file_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import '../../service/llm_service.dart';
import '../../service/video_cache_service.dart';

class PublishPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<String> captions;
  final String targetPlatform;
  final String exportedVideoPath;
  final Future<String>? generatedCopyFuture;

  const PublishPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.captions,
    required this.targetPlatform,
    required this.exportedVideoPath,
    this.generatedCopyFuture,
  });

  @override
  State<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends State<PublishPage> {
  final TextEditingController _copyController = TextEditingController();
  final GlobalKey _shareButtonKey = GlobalKey();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _generateCopy();
  }

  @override
  void dispose() {
    _copyController.dispose();
    super.dispose();
  }

  Future<void> _generateCopy() async {
    String result = '';
    try {
      if (widget.generatedCopyFuture != null) {
        result = await widget.generatedCopyFuture!;
      } else {
        result = await LLMService().generateSocialMediaCopy(
          platform: widget.targetPlatform,
          title: widget.title,
          subtitle: widget.subtitle,
          captions: widget.captions,
        );
      }
    } catch (e) {
      result = 'AI 生成文案时开小差了，请手动写点什么吧~';
    }

    if (mounted) {
      setState(() {
        _copyController.text = result;
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _copyController.text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.content_copy, color: Colors.white),
            SizedBox(width: 8),
            Text('📋 文案已复制到剪贴板', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: Colors.blue.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _shareVideo() async {
    final videoFile = File(widget.exportedVideoPath);
    if (!videoFile.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('❌ 视频文件未找到'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }

    try {
      String shareText = '📱 ${_copyController.text}\n\n';
      shareText += '🎬 使用「智能影记」制作的回忆视频\n';
      shareText += '#${widget.targetPlatform} #回忆 #故事';

      await Share.shareXFiles(
        [XFile(widget.exportedVideoPath)],
        text: shareText,
        subject: '${widget.title} - ${widget.subtitle}',
        sharePositionOrigin: _sharePositionOrigin(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('分享失败: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Rect _sharePositionOrigin() {
    final renderObject =
        _shareButtonKey.currentContext?.findRenderObject() ??
        context.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (!rect.isEmpty) {
        return rect;
      }
    }

    final screenSize = MediaQuery.sizeOf(context);
    return Rect.fromCenter(
      center: Offset(screenSize.width / 2, screenSize.height / 2),
      width: 1,
      height: 1,
    );
  }

  /// 用 Flutter 内置播放器播放视频，有完整的退出控制
  void _playVideo() {
    final videoFile = File(widget.exportedVideoPath);
    if (!videoFile.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('❌ 视频文件未找到'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VideoPlayerPage(videoPath: widget.exportedVideoPath),
      ),
    );
  }

  /// 保存视频并打开
  /// Android: 使用系统文件选择器让用户选择保存位置
  /// iOS: 保存到共享文件夹并打开文件 App 展示
  Future<void> _openFolder() async {
    final videoFile = File(widget.exportedVideoPath);
    if (!videoFile.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('❌ 视频文件未找到'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      return;
    }

    try {
      if (Platform.isAndroid) {
        await _saveVideoOnAndroid(videoFile);
      } else if (Platform.isIOS) {
        await _saveVideoOnIOS(videoFile);
      } else {
        throw UnsupportedError('当前平台暂不支持打开系统文件 App');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存视频失败: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  /// Android: 使用 Storage Access Framework 让用户选择保存位置
  Future<void> _saveVideoOnAndroid(File videoFile) async {
    final bytes = await videoFile.readAsBytes();

    final String? savedPath = await FilePicker.saveFile(
      dialogTitle: '选择保存位置',
      fileName: path.basename(widget.exportedVideoPath),
      type: FileType.custom,
      allowedExtensions: ['mp4'],
      bytes: bytes,
    );

    if (savedPath == null) return;

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '✅ 视频已保存',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: '打开文件',
          textColor: Colors.white,
          onPressed: () async {
            final result = await OpenFile.open(savedPath);
            if (result.type != ResultType.done && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('无法打开文件: ${result.message}'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  /// iOS: 先把缓存视频复制/补齐到 Documents/StoryExports，再打开"文件"APP。
  Future<void> _saveVideoOnIOS(File videoFile) async {
    await VideoCacheService.instance.ensureExportedVideoAvailable(
      videoFile.path,
    );

    await openFileManager(
      androidConfig: AndroidConfig(
        folderType: AndroidFolderType.other,
        folderPath:
            (await VideoCacheService.instance.getExportsDirectory()).path,
      ),
      iosConfig: IosConfig(folderPath: 'StoryExports'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 极光渐变背景
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE8DEFF),
                  Color(0xFFE1F5FE),
                  Color(0xFFFCE4EC),
                ],
                stops: [0.1, 0.5, 0.9],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                AppBar(
                  title: const Text(
                    '🎉 分享你的故事',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  centerTitle: true,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  iconTheme: const IconThemeData(color: Colors.black87),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 16.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 顶部图标
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.pinkAccent.withValues(alpha: 0.1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.pinkAccent.withValues(alpha: 0.2),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.share,
                            color: Colors.pinkAccent,
                            size: 72,
                          ),
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          '视频已准备好分享！',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'AI 已为您生成【${widget.targetPlatform}】专属文案，一键分享到社交平台',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // 毛玻璃文案编辑区
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  width: 1.5,
                                ),
                              ),
                              padding: const EdgeInsets.all(20),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 200,
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            CircularProgressIndicator(
                                              color: Colors.pinkAccent,
                                            ),
                                            SizedBox(height: 20),
                                            Text(
                                              '🤖 AI 正在疯狂查阅小红书爆款指南...',
                                              style: TextStyle(
                                                color: Colors.black54,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : TextField(
                                      controller: _copyController,
                                      maxLines: 12,
                                      cursorColor: Colors.pinkAccent,
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        hintText: '这里是发帖文案...',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        height: 1.6,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // ── 按钮区 ──────────────────────────────────

                        // 1. 一键分享（主操作）
                        SizedBox(
                          key: _shareButtonKey,
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _shareVideo,
                            icon: const Icon(Icons.share_rounded),
                            label: const Text(
                              '一键分享到社交平台',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              backgroundColor: Colors.pinkAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 2. 播放视频（Flutter 内置播放器）
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _playVideo,
                            icon: const Icon(Icons.play_circle_outline_rounded),
                            label: const Text(
                              '预览视频',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.deepOrange.shade400,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 3. 保存并打开文件
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _openFolder,
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text(
                              '保存并查看视频',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.deepPurple.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 4. 仅复制文案（次要操作）
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _copyToClipboard,
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text(
                              '仅复制文案',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(
                                color: Colors.pinkAccent.shade200,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              foregroundColor: Colors.pinkAccent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 5. 返回首页
                        TextButton(
                          onPressed: () => Navigator.popUntil(
                            context,
                            (route) => route.isFirst,
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            '返回首页',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Flutter 内置视频播放页，有完整的退出按钮
// ─────────────────────────────────────────────────────────────────────────────
class _VideoPlayerPage extends StatefulWidget {
  final String videoPath;
  const _VideoPlayerPage({required this.videoPath});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _showControls = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        if (mounted) {
          setState(() {
            _errorMessage = '视频文件不存在';
          });
        }
        return;
      }

      _controller = VideoPlayerController.file(file);

      await _controller!.initialize();

      if (mounted) {
        setState(() => _initialized = true);
        _controller!.setLooping(true);
        _controller!.play();
      }

      _controller!.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (e) {
      debugPrint('❌ 视频播放器初始化失败: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '视频加载失败: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频画面
            Center(
              child: _initialized
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),

            // 控制层（点击切换显示/隐藏）
            if (_showControls)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xAA000000),
                        Colors.transparent,
                        Colors.transparent,
                        Color(0xAA000000),
                      ],
                      stops: [0.0, 0.2, 0.75, 1.0],
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        // 顶部：退出按钮
                        Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),

                        const Spacer(),

                        // 底部：进度条 + 播放控制
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 进度条
                              if (_initialized && _controller != null)
                                VideoProgressIndicator(
                                  _controller!,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(
                                    playedColor: Colors.pinkAccent,
                                    bufferedColor: Colors.white38,
                                    backgroundColor: Colors.white12,
                                  ),
                                ),
                              const SizedBox(height: 8),

                              // 时间 + 播放/暂停
                              Row(
                                children: [
                                  if (_initialized && _controller != null)
                                    Text(
                                      '${_formatDuration(_controller!.value.position)} / ${_formatDuration(_controller!.value.duration)}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  const Spacer(),
                                  if (_controller != null)
                                    IconButton(
                                      icon: Icon(
                                        _controller!.value.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 36,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _controller!.value.isPlaying
                                              ? _controller!.pause()
                                              : _controller!.play();
                                        });
                                      },
                                    ),
                                  const Spacer(),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
