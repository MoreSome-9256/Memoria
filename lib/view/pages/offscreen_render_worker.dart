import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'story_result_page.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import '../../effects/subtitle_effect.dart';
import '../../effects/glitch_effect.dart';
import '../../effects/static_filters.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import '../../service/llm_service.dart';
import '../../service/music_service.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';

class OffscreenRenderWorker extends StatefulWidget {
  final String title;
  final List<StorySection> sections;
  final bool isHorizontal;
  final String? customMusicPath;
  final Map<String, dynamic>? dynamicBeatData;
  final String subtitle;
  final String targetPlatform;
  final Function(String videoPath, Future<String>? aiCopy) onComplete;

  // 🌟 新增：接收老板（预览页）传来的所有特效和字幕状态！
  final String currentTextStyle;
  final double textYPosition;
  final double textSize;
  final double textBlurIntensity;
  final double shakeIntensity;
  final double shakeFrequency;
  final double glitchIntensity;
  final bool enableFlash;
  final bool useVignette;
  final bool useGrain;
  final bool useCameraFrame;
  final bool useGlowRing;
  final bool useCloudBorder;

  // 🌟 新增：工作进度汇报专线
  final Function(double progress)? onProgress;

  const OffscreenRenderWorker({
    super.key,
    required this.title,
    required this.sections,
    this.isHorizontal = false,
    this.customMusicPath,
    this.dynamicBeatData,
    required this.subtitle,
    required this.targetPlatform,
    required this.onComplete,
    // 🌟 新增构造参数
    required this.currentTextStyle,
    required this.textYPosition,
    required this.textSize,
    required this.textBlurIntensity,
    required this.shakeIntensity,
    required this.shakeFrequency,
    required this.glitchIntensity,
    required this.enableFlash,
    required this.useVignette,
    required this.useGrain,
    required this.useCameraFrame,
    required this.useGlowRing,
    required this.useCloudBorder,
    this.onProgress,
  });

  @override
  State<OffscreenRenderWorker> createState() => _OffscreenRenderWorkerState();
}

class _OffscreenRenderWorkerState extends State<OffscreenRenderWorker>
    with TickerProviderStateMixin {

  int _currentIndex = 0;

  int _currentLyricIndex = 0;
  String _currentLyricText = "";
  // 🎛️ VFX 控制台参数
  double _shakeIntensity = 0.0; // 震动幅度 (Amplitude)
  double _shakeFrequency = 1.0; // 🌟 新增：震动频率/马达转速 (Frequency)，默认15

  // 🌟 新增 1：故障特效的独立强度 (0.0 到 1.0)
  double _glitchIntensity = 0.0;
  // 🌟 新增 2：给故障特效专用的“永动机”时间控制器
  late AnimationController _continuousTimeController;

  bool _enableFlash = true;
  double _textBlurIntensity = 4.0;
  final GlobalKey _renderKey = GlobalKey();
  int _beatIntervalMs = 500; // 默认给个500，等加载JSON时会被覆盖

  // 🔤 字幕引擎参数
  String _currentTextStyle =
      'hero'; // 'standard' (普通底栏), 'hero' (居中大字), 'cards' (字卡散落)
  double _textYPosition = 0.8; // 0.0 为顶部，0.5 为屏幕正中，1.0 为贴底
  double _textSize = 24.0;
  final String _fontFamily = 'sans-serif'; // 以后可以接入 Google Fonts

  bool _isExporting = false; // 🌟 控制是否处于导出模式
  double _exportProgress = 0.0; // 🌟 导出百分比 (0.0 到 1.0)

  List<dynamic> _beatData = []; // 存完整的 JSON 数据（包含 ms 和 energy）

  // 💥 震动与闪光控制器
  late AnimationController _vfxController;

  @override
  void initState() {
    super.initState();
    _vfxController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _continuousTimeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // 默认给个初始值
    _beatData = [
      {"ms": 0, "energy": 0.1},
      {"ms": 500, "energy": 0.6},
      {"ms": 1000, "energy": 0.2},
    ];
    _beatIntervalMs = 500;

    // 我们强制让它处于导出模式
    _isExporting = true;

    unawaited(_loadBeatDataFromBackend());

    if (widget.sections.isNotEmpty) {
      _currentLyricText = widget.sections[0].text;
    } else {
      _currentLyricText = "";
    }

    // 🌟 核心改动：删除原有的 _togglePlay()，改成等 UI 挂载完毕后直接发车开始渲染！
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startExport();
    });
  }
  void _applyBeatData(Map<String, dynamic> beatResponse) {
    final data = beatResponse['data'];
    final bpmRaw = beatResponse['bpm'];
    if (data is! List || data.isEmpty || bpmRaw is! num || bpmRaw <= 0) {
      return;
    }

    setState(() {
      _beatData = data;
      _beatIntervalMs = (60000 / bpmRaw.toDouble()).round();
      _currentBeatIndexForPreview = -1;
    });

    debugPrint(
      "🎵 成功加载真实节拍！BPM: ${bpmRaw.toDouble()}, 间隔: ${_beatIntervalMs}ms, 共 ${_beatData.length} 拍",
    );
  }

  Future<void> _loadBeatDataFromBackend() async {
    // 优先使用上一个页面已经分析好的数据。
    if (widget.dynamicBeatData != null &&
        widget.dynamicBeatData!['data'] != null) {
      _applyBeatData(widget.dynamicBeatData!);
      return;
    }

    try {
      // fallback 也走云端分析：上传当前实际要播放的音频文件。
      String audioPath;
      if (widget.customMusicPath != null &&
          widget.customMusicPath!.isNotEmpty) {
        audioPath = widget.customMusicPath!;
      } else {
        audioPath = await _extractAssetForFFmpeg(
          'assets/audio/sandal_leap.mp3',
          'sandal_leap_for_analysis.mp3',
        );
      }

      final beatResponse = await MusicService.analyzeAudio(audioPath);
      if (beatResponse != null && mounted) {
        _applyBeatData(beatResponse);
        return;
      }

      debugPrint("⚠️ fallback 云端节拍分析失败，保留最小兜底节拍");
    } catch (e) {
      debugPrint("❌ fallback 云端节拍分析异常: $e");
    }
  }

  int _currentBeatIndexForPreview = -1; // 记录当前演到第几拍了


  @override
  void dispose() {
    _vfxController.dispose(); // 别忘了释放内存
    _continuousTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) {
      return const SizedBox.shrink(); // 没数据就占个空位
    }

    final currentSection = widget.sections[_currentIndex];
    final bool isIntro = _currentIndex == 0;

    final subtitleLayer = SubtitleEffectLayer(
      text: isIntro ? "" : _currentLyricText,
      effectType: widget.currentTextStyle,
      yPosition: widget.textYPosition,
      fontSize: widget.textSize,
      fontFamily: 'sans-serif',
      blurIntensity: widget.textBlurIntensity,
      vfxController: _vfxController,
    );

    // 1. 定义纯净的视频内容层
    Widget videoContent = Material(
      type: MaterialType.transparency, // 🌟 极其关键：必须是透明的，否则会强行加个白色大背景
      child: DefaultTextStyle(
        style: const TextStyle(
          decoration: TextDecoration.none, // 🌟 灵魂属性：彻底拔掉那条该死的黄线！
          color: Colors.white, // 给一个兜底颜色
        ),
        child: ClipRect(
          child: CameraFrameEffect(
            enabled: widget.useCameraFrame,
            isHorizontal: widget.isHorizontal,
            child: VignetteEffect(
              enabled: widget.useVignette,
              child: GrainEffect(
                enabled: widget.useGrain,
                time: _continuousTimeController.value,
                child: AnimatedBuilder(
                  animation: _continuousTimeController,
                  builder: (context, child) {
                    return GlitchEffect(
                      intensity: _glitchIntensity,
                      time: _continuousTimeController.value,
                      child: child!,
                    );
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 底层震动图片
                      AnimatedBuilder(
                        animation: _vfxController,
                        builder: (context, child) {
                          double decay = math.max(
                            0.0,
                            1.0 - (_vfxController.value * 2.5),
                          );
                          final shakeOffset = Offset(
                            _shakeIntensity *
                                decay *
                                math.sin(
                                  _vfxController.value *
                                      math.pi *
                                      10 *
                                      _shakeFrequency,
                                ),
                            _shakeIntensity *
                                decay *
                                math.cos(
                                  _vfxController.value *
                                      math.pi *
                                      12 *
                                      _shakeFrequency,
                                ),
                          );
                          return Transform.translate(
                            offset: shakeOffset,
                            child: child,
                          );
                        },
                        child: AnimatedSwitcher(
                          duration: 800.ms,
                          child: _buildPureImageLayer(
                            currentSection.photo.path,
                            subtitleLayer,
                          ),
                        ),
                      ),

                      // 光圈层
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          _vfxController,
                          _continuousTimeController,
                        ]),
                        builder: (context, child) {
                          double decay = math.max(
                            0.0,
                            1.0 - (_vfxController.value * 2.5),
                          );
                          return GlowRingEffect(
                            enabled: widget.useGlowRing,
                            time: _continuousTimeController.value,
                            beatIntensity: decay,
                          );
                        },
                      ),

                      // 闪光层
                      AnimatedBuilder(
                        animation: _vfxController,
                        builder: (context, child) {
                          double decay = math
                              .pow(1.0 - _vfxController.value, 3)
                              .toDouble();
                          final double flashAlpha = _enableFlash
                              ? 0.3 * decay
                              : 0.0;
                          return IgnorePointer(
                            child: Container(
                              color: Colors.white.withValues(alpha: flashAlpha),
                            ),
                          );
                        },
                      ),

                      // 片头
                      if (isIntro)
                        Positioned.fill(
                          child: CinematicTitleIntro(
                            title: widget.title,
                            subtitle: widget.subtitle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        )
      )
    );

    // 🌟 2. 核心化简：只返回取景器本身，去掉所有的 Scaffold 和进度条
    if (widget.isHorizontal) {
      return Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: RepaintBoundary(key: _renderKey, child: videoContent),
        ),
      );
    } else {
      return Center(
        child: SizedBox(
          width: 720,
          height: 1280,
          child: RepaintBoundary(key: _renderKey, child: videoContent),
        ),
      );
    }
  }
  // 🎥 核心特效：Ken Burns 运镜效应 (缓慢放大)
  /*Widget _buildKenBurnsImage(String imagePath) {
    final file = File(imagePath);
    return TweenAnimationBuilder(
      key: ValueKey<String>(imagePath), // Key 变了，动画就会重置并重新执行
      tween: Tween<double>(begin: 1.0, end: 1.15), // 从原尺寸缓慢放大到 1.15 倍
      duration: const Duration(seconds: 5), // 设定略大于图片停留时间的动画
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: file.existsSync()
              ? Image.file(
                  file,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                )
              : Container(color: Colors.grey[900]), // 找不到图的防崩兜底
        );
      },
    );
  }*/

  // 🎬 核心特效：根据长宽比自适应的视觉层（已支持字幕嵌入）
  Widget _buildAdaptiveImageLayer(String imagePath, Widget subtitle) {
    final file = File(imagePath);

    // 1. 基础的 Ken Burns 放大动画
    Widget kenBurnsAnimation = TweenAnimationBuilder(
      tween: Tween<double>(begin: 1.0, end: 1.15),
      duration: const Duration(seconds: 5),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: file.existsSync()
              ? Image.file(
                  file,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                )
              : Container(color: Colors.grey[900]),
        );
      },
    );

    // 🌟 将图片和字幕打包成一个“容器内容”
    Widget containerContent = Stack(
      fit: StackFit.expand,
      children: [
        kenBurnsAnimation,
        // 🔒 字幕现在被“锁”在了这个 Stack 里，它的 Alignment 将相对于这个容器
        subtitle,
      ],
    );

    // 🌟 竖屏模式：依然铺满全屏
    if (!widget.isHorizontal) {
      return SizedBox.expand(
        key: ValueKey<String>(imagePath),
        child: containerContent,
      );
    }
    // 🌟 横屏模式：16:9 居中，字幕会被 ClipRect 限制在框内
    else {
      return Stack(
        key: ValueKey<String>(imagePath),
        fit: StackFit.expand,
        children: [
          // 底层模糊背景
          if (file.existsSync()) Image.file(file, fit: BoxFit.cover),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(color: Colors.black.withValues(alpha: 0.6)),
          ),
          // 2. 核心 16:9 画幅层
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRect(
                // 🚀 这里是关键！内容（含字幕）现在只会在 16:9 的框内显示
                child: containerContent,
              ),
            ),
          ),
        ],
      );
    }
  }

  void _updateStateForFrame(int frameIndex) {
    if (_beatData.isEmpty) return;

    double currentTimeMs = (frameIndex / 24.0) * 1000.0;

    int targetBeatIndex = 0;
    for (int j = 0; j < _beatData.length; j++) {
      if (currentTimeMs >= _beatData[j]['ms']) {
        targetBeatIndex = j;
      } else {
        break;
      }
    }

    double currentEnergy =
        (_beatData[targetBeatIndex]['energy'] as num?)?.toDouble() ?? 0.0;
    double timeSinceBeat = currentTimeMs - _beatData[targetBeatIndex]['ms'];

    // 计算当前节拍度过了多少百分比 (0.0 到 1.0)
    double beatProgress = (timeSinceBeat / _beatIntervalMs).clamp(0.0, 1.0);

    // 🌟 手动拨动动画控制器的指针，让离线导出的每一帧和实时预览一模一样！
    _vfxController.value = beatProgress;

    if (currentEnergy > 0.15) {
      _shakeIntensity = currentEnergy * 15.0 * (_shakeFrequency / 15.0);
      // _enableFlash = true;
    } else {
      _shakeIntensity = 0.0;
      // _enableFlash = false;
    }

    int targetImageIndex = targetBeatIndex ~/ 8;
    if (targetImageIndex >= widget.sections.length) {
      targetImageIndex = widget.sections.length - 1;
    }
    // 🌟 核心补偿：在离线导出时，手动驱动 Glitch 的时间轴！
    // 假设它是 2000 毫秒一循环，我们算出当前进度
    if (_isExporting) {
      _continuousTimeController.value = (currentTimeMs % 2000.0) / 2000.0;
    }

    setState(() {
      _currentIndex = targetImageIndex;
      // 🌟 替换掉之前的 _lyricQueue 逻辑
      _currentLyricText = widget.sections[_currentIndex].text;
    });
  }

  // 📸 全新：直接抓取 RGBA 原始像素，并强制裁剪为偶数分辨率
  Future<(Uint8List?, int, int)> _captureFrameRgba() async {
    try {
      RenderRepaintBoundary boundary =
          _renderKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;

      // 这里的 pixelRatio 控制清晰度，2.0 大约等于 1080p。如果想要更快，可以改成 1.5。
      ui.Image rawImage = await boundary.toImage(pixelRatio: 2.0);

      int width = rawImage.width;
      int height = rawImage.height;

      // 🌟 核心保命机制：硬件编码器强制要求长宽为偶数！
      if (width % 2 != 0) width -= 1;
      if (height % 2 != 0) height -= 1;

      ui.Image finalImage = rawImage;

      // 如果原图有奇数边，我们在内存里用画布把它强行切成偶数
      if (width != rawImage.width || height != rawImage.height) {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          rawImage,
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Paint(),
        );
        finalImage = await recorder.endRecording().toImage(width, height);
      }

      // 洗出相片：直接输出原始内存像素 RGBA！彻底告别 PNG 压缩和硬盘 I/O！
      ByteData? byteData = await finalImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      return (byteData?.buffer.asUint8List(), width, height);
    } catch (e) {
      debugPrint("❌ 抓拍当前帧失败: $e");
      return (null, 0, 0);
    }
  }

  Future<void> _startExport() async {
    // 🚀 保持 AI 自动写文案在后台运行
    List<String> currentCaptions = widget.sections.map((s) => s.text).toList();
    _aiCopyFuture = LLMService().generateSocialMediaCopy(
      platform: widget.targetPlatform,
      title: widget.title,
      subtitle: widget.subtitle,
      captions: currentCaptions,
    );

    // 计算最终毫秒数
    int totalBeatsNeeded = widget.sections.length * 8;
    int finalExportDurationMs = totalBeatsNeeded * _beatIntervalMs;
    if (_beatData.length > totalBeatsNeeded) {
      finalExportDurationMs = (_beatData[totalBeatsNeeded]['ms'] as num)
          .toInt();
    } else if (_beatData.isNotEmpty) {
      int missingBeats = totalBeatsNeeded - _beatData.length;
      finalExportDurationMs =
          (_beatData.last['ms'] as num).toInt() +
          (missingBeats * _beatIntervalMs);
    }
    double exactExportSeconds = finalExportDurationMs / 1000.0;

    // 🎬 1. 抓取第0帧，主要是为了获取屏幕真正的硬件像素分辨率
    _updateStateForFrame(0);
    await Future.delayed(const Duration(milliseconds: 50)); // 给UI一点时间渲染第一帧
    var firstFrame = await _captureFrameRgba();
    if (firstFrame.$1 == null) {
      debugPrint("❌ 无法获取初始帧尺寸，导出终止");
      setState(() => _isExporting = false);
      return;
    }

    int videoWidth = firstFrame.$2;
    int videoHeight = firstFrame.$3;

    final docDir = await getApplicationDocumentsDirectory();
    final String silentVideoPath =
        "${docDir.path}/silent_temp_${DateTime.now().millisecondsSinceEpoch}.mp4";

    // 🎬 2. 轰鸣启动硬件编码器引擎！
    try {
      FlutterQuickVideoEncoder.setLogLevel(LogLevel.none); // 保持控制台清爽
      await FlutterQuickVideoEncoder.setup(
        width: videoWidth,
        height: videoHeight,
        fps: 24,
        videoBitrate: 4000000, // 4Mbps 码率，保障画质不糊
        profileLevel: ProfileLevel.any,
        filepath: silentVideoPath,
        // 👇 新增这三个必填的音频占位参数
        audioBitrate: 64000, // 随便给个 64kbps
        audioChannels: 2, // 双声道立体声
        sampleRate: 44100, // 标准的 44.1kHz 采样率
      );
    } catch (e) {
      debugPrint("❌ 硬件编码器启动失败: $e");
      setState(() => _isExporting = false);
      return;
    }

    int fps = 24;
    int totalFrames = (finalExportDurationMs / 1000 * fps).floor();

    // 🌟 新增：计算每一帧视频对应的音频字节数
    // 公式：采样率(44100) * 通道数(2) * 每个采样点的字节数(16-bit = 2字节) / 帧率(24)
    final int bytesPerAudioFrame = (44100 * 2 * 2) ~/ fps;
    // 生成一包全为 0 的静音数据（相当于这段时间的纯静音）
    final Uint8List silentAudioChunk = Uint8List(bytesPerAudioFrame);

    // 在 for 循环外面，新增一个变量，用来装“上一帧的编码任务”
    Future<void>? _previousEncodeTask;

    // 🎬 3. 流水线作业：渲染UI -> 抓像素 -> 塞进芯片
    for (int i = 0; i < totalFrames; i++) {
      _updateStateForFrame(i);
      // 🌟 新增：每隔 5 帧向外广播一次进度，绝不调用 setState！
      if (i % 5 == 0 || i == totalFrames - 1) {
        widget.onProgress?.call((i / totalFrames) * 0.85);
      }

      // 等待 Flutter 把这帧画面画出来
      await WidgetsBinding.instance.endOfFrame;

      final frameData = await _captureFrameRgba();

      if (frameData.$1 != null) {
        // 🚀 核心黑魔法：在开启当前帧的编码前，确保上一帧已经塞进去了
        if (_previousEncodeTask != null) {
          await _previousEncodeTask;
        }

        // 🚀 开启当前帧的编码，但是【不要 await】它！
        // 把任务存起来，让原生层自己去慢慢压制，Dart 立刻进入下一次循环去截下一张图！
        _previousEncodeTask = Future.microtask(() async {
          await FlutterQuickVideoEncoder.appendVideoFrame(frameData.$1!);
          await FlutterQuickVideoEncoder.appendAudioFrame(silentAudioChunk);
        });
      }
    }
    // 循环结束后，确保最后一帧被顺利吃进去
    if (_previousEncodeTask != null) {
      await _previousEncodeTask;
    }

    // 🎬 4. 封口！此时无声的高清视频已经生成完毕
    await FlutterQuickVideoEncoder.finish();

    // 🎬 5. 移交接力棒，让 FFmpeg 做最后的极速音视频缝合
    await _fastMuxAudio(silentVideoPath, exactExportSeconds);
  }

  Future<void> _fastMuxAudio(
    String silentVideoPath,
    double exactSeconds,
  ) async {
    widget.onProgress?.call(0.95);
    try {
      final docDir = await getApplicationDocumentsDirectory();
      String audioPath;

      // 准备音频 (和你之前的逻辑完全一样)
      if (widget.customMusicPath != null) {
        File originalAudio = File(widget.customMusicPath!);
        File safeAudioFile = File('${docDir.path}/safe_custom_audio.mp3');
        if (safeAudioFile.existsSync()) safeAudioFile.deleteSync();
        await originalAudio.copy(safeAudioFile.path);
        audioPath = safeAudioFile.path;
      } else {
        final ByteData audioData = await rootBundle.load(
          'assets/audio/sandal_leap.mp3',
        );
        final File tempAudioFile = File('${docDir.path}/temp_audio.mp3');
        await tempAudioFile.writeAsBytes(audioData.buffer.asUint8List());
        audioPath = tempAudioFile.path;
      }

      final String outputPath =
          "${docDir.path}/FINAL_STORY_${DateTime.now().millisecondsSinceEpoch}.mp4";

      // 🚀 FFmpeg 终极魔法：精准音视频映射
      String command = [
        "-y",
        "-i", "'$silentVideoPath'", // 输入 0：静音视频
        "-stream_loop", "-1", // 音频无限循环
        "-i", "'$audioPath'", // 输入 1：背景音乐
        "-map", "0:v:0", // 🌟 强行指定：只拿第1个输入的视频流
        "-map", "1:a:0", // 🌟 强行指定：只拿第2个输入的音频流
        "-c:v", "copy", // 视频流直接复制
        "-c:a", "aac", // 音频流压成 aac
        "-shortest", // 🌟 关键：以最短的流（通常是视频）为准结束
        "'$outputPath'",
      ].join(" ");

      debugPrint("🎬 FFmpeg 光速混音开始: $command");

      await FFmpegKit.execute(command).then((session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          debugPrint("✅✅✅ 硬件直出+极速混音，完美结束！");

          // 顺手做个垃圾回收，删掉那个无声视频
          File(silentVideoPath).delete().catchError((_) {});

          _handleExportSuccess(outputPath);
        } else {
          final logs = await session.getLogsAsString();
          debugPrint("❌ FFmpeg 混音失败:\n$logs");
        }
      });
    } finally {
      
    }
  }

  // 🌟 新增一个变量，用来装这个“未来的文案”
  Future<String>? _aiCopyFuture;

  void _handleExportSuccess(String outputPath) async {
    try {
      // 可选：你依然可以选择在这里存进相册，或者等上层弹窗点了再去存
      await Gal.putVideo(outputPath);

      // 🌟 核心：触发回调，通知 ExportManager 任务完成！
      widget.onComplete(outputPath, _aiCopyFuture);
    } catch (e) {
      debugPrint("❌ 保存到相册失败: $e");
    }
  }
  // 🎬 专门给取景器提供纯净画面的层（无黑边）
  Widget _buildPureImageLayer(String imagePath, Widget subtitle) {
    final file = File(imagePath);
    return Stack(
      key: ValueKey<String>(imagePath),
      fit: StackFit.expand,
      children: [
        TweenAnimationBuilder(
          tween: Tween<double>(begin: 1.0, end: 1.15),
          duration: const Duration(seconds: 5),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: file.existsSync()
                  ? Image.file(
                      file,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  : Container(color: Colors.grey[900]),
            );
          },
        ),
        subtitle, // 字幕层
      ],
    );
  }

  // 🌟 核心工具：把 asset 里的文件释放到手机真实的临时目录中
  Future<String> _extractAssetForFFmpeg(
    String assetPath,
    String fileName,
  ) async {
    // 获取手机的临时文件夹
    final directory = await getTemporaryDirectory();
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);

    // 如果已经提取过了，就直接返回路径，省得每次都复制（节约性能）
    if (await file.exists()) {
      return filePath;
    }

    // 第一次运行：从 Flutter 的包裹里读取，并写入物理文件
    final byteData = await rootBundle.load(assetPath);
    await file.writeAsBytes(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
    );

    return filePath; // 返回这个绝对路径给 FFmpeg
  }
}

class CinematicTitleIntro extends StatelessWidget {
  final String title;
  final String subtitle;

  const CinematicTitleIntro({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(seconds: 4),
      curve: Curves.easeOutQuart,
      builder: (context, value, child) {
        return Opacity(
          opacity: (value * 2).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1.0 + (value * 0.05),
            child: Container(
              alignment: Alignment.center,
              color: Colors.black.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(horizontal: 24), // 两边留点安全边距
              // 🌟 核心防溢出神器：FittedBox
              child: FittedBox(
                fit: BoxFit.scaleDown, // 太长了就缩小，绝对不换行不溢出
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          Colors.white,
                          Colors.pinkAccent.shade100,
                          Colors.white70,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text(
                        title.isEmpty ? '专属回忆' : title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 48, // 就算你设 100 只要有 FittedBox 也不会报错
                          fontWeight: FontWeight.w900,
                          letterSpacing: 12.0,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 10,
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      subtitle.isEmpty ? '美好的时光' : subtitle,
                      style: const TextStyle(
                        fontSize: 18,
                        letterSpacing: 6.0,
                        color: Colors.white70,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
