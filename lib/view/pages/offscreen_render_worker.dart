/// 离屏渲染工作页，负责在后台渲染复杂组件或图片。

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import '../../models/vo/photo.dart';
import '../../models/vo/story_section.dart';
import '../../effects/subtitle_effect.dart';
import '../../effects/glitch_effect.dart';
import '../../effects/static_filters.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import '../../service/llm_service.dart';
import '../../service/music_service.dart';
import '../../service/media_thumbnail_cache_service.dart';
import '../../service/story_service.dart';
import '../../service/video_cache_service.dart';
import '../../storage/objectbox/objectbox_service.dart';
import '../../utils/media_type_helper.dart';
import '../../models/entity/story_entity.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import '../widgets/asset_backed_image.dart';

class OffscreenRenderWorker extends StatefulWidget {
  final String title;
  final List<StorySection> sections;
  final bool isHorizontal;
  final String? customMusicPath;
  final Map<String, dynamic>? dynamicBeatData;
  final String subtitle;
  final String targetPlatform;
  final Function(String videoPath, Future<String>? aiCopy) onComplete;
  final void Function(Object error, StackTrace stackTrace)? onError;

  // 🌟 新增：接收老板（预览页）传来的所有特效和字幕状态！
  final String currentTextStyle;
  final double textYPosition;
  final double textSize;
  final double textBlurIntensity;
  final double shakeIntensity;
  final double shakeFrequency;
  final double glitchIntensity;
  final double imageSaturation; // 🌟 新增：饱和度
  final String imageFilterType; // 🌟 新增：滤镜类型
  final bool enableFlash;
  final bool useVignette;
  final bool useGrain;
  final bool useCameraFrame;
  final bool useGlowRing;
  final bool useCloudBorder;

  // 🌟 新增：工作进度汇报专线
  final Function(double progress)? onProgress;
  final int? storyEntityId;

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
    this.onError,
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
    required this.imageSaturation,
    required this.imageFilterType,
    this.onProgress,
    this.storyEntityId,
  });

  @override
  State<OffscreenRenderWorker> createState() => _OffscreenRenderWorkerState();
}

class _OffscreenRenderWorkerState extends State<OffscreenRenderWorker>
    with TickerProviderStateMixin {
  int _currentIndex = 0;

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
  bool _isExporting = false; // 🌟 控制是否处于导出模式

  List<dynamic> _beatData = []; // 存完整的 JSON 数据（包含 ms 和 energy）
  late final Future<void> _beatLoadFuture;
  int? _audioDurationMs;

  // 💥 震动与闪光控制器
  late AnimationController _vfxController;

  @override
  void initState() {
    super.initState();
    _shakeIntensity = widget.shakeIntensity;
    _shakeFrequency = widget.shakeFrequency;
    _glitchIntensity = widget.glitchIntensity;
    _enableFlash = widget.enableFlash;
    _textBlurIntensity = widget.textBlurIntensity;
    _currentTextStyle = widget.currentTextStyle;
    _textYPosition = widget.textYPosition;
    _textSize = widget.textSize;

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

    _beatLoadFuture = _loadBeatDataFromLocalAnalyzer();

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
      final durationRaw = beatResponse['duration_ms'];
      _audioDurationMs = durationRaw is num && durationRaw > 0
          ? durationRaw.toInt()
          : null;
    });

    debugPrint(
      "🎵 成功加载真实节拍！BPM: ${bpmRaw.toDouble()}, 间隔: ${_beatIntervalMs}ms, 共 ${_beatData.length} 拍",
    );
  }

  Future<void> _loadBeatDataFromLocalAnalyzer() async {
    // 优先使用上一个页面已经分析好的数据。
    if (widget.dynamicBeatData != null &&
        widget.dynamicBeatData!['data'] != null) {
      _applyBeatData(widget.dynamicBeatData!);
      return;
    }

    try {
      // fallback 也走本地分析：使用当前实际要播放的音频文件。
      String audioPath;
      String? resolvedMusicPath;
      if (widget.storyEntityId != null) {
        try {
          final store = ObjectBoxService().store;
          final storyBox = store.box<StoryEntity>();
          final story = storyBox.get(widget.storyEntityId!);
          if (story != null) {
            resolvedMusicPath = await StoryService.resolveMusicFile(story);
          }
        } catch (_) {}
      }
      resolvedMusicPath ??= widget.customMusicPath;

      if (resolvedMusicPath != null &&
          resolvedMusicPath.isNotEmpty &&
          await File(resolvedMusicPath).exists()) {
        audioPath = resolvedMusicPath;
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

      debugPrint("⚠️ fallback 本地节拍分析失败，保留最小兜底节拍");
    } catch (e) {
      debugPrint("❌ fallback 本地节拍分析异常: $e");
    }
  }

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
                          child: ColorGradingEffect(
                            saturation: widget.imageSaturation,
                            filterType: widget.imageFilterType,
                            child: _buildPureImageLayer(
                              currentSection.photo,
                              subtitleLayer,
                            ),
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
        ),
      ),
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

  // 🎬 核心特效：根据长宽比自适应的视觉层（已支持字幕嵌入）
  void _updateStateForFrame(int frameIndex) {
    if (_beatData.isEmpty) return;

    double currentTimeMs = (frameIndex / 24.0) * 1000.0;
    final storyDurationMs = _storyTimelineDurationMs();

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

    final targetImageIndex = _targetSectionIndexForTime(
      currentTimeMs,
      storyDurationMs,
    );
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

  int _storyTimelineDurationMs() {
    if (_audioDurationMs != null && _audioDurationMs! > 0) {
      return _audioDurationMs!;
    }

    final durationRaw = widget.dynamicBeatData?['duration_ms'];
    if (durationRaw is num && durationRaw > 0) {
      return durationRaw.toInt();
    }

    final data = widget.dynamicBeatData?['data'];
    if (data is List && data.isNotEmpty) {
      final lastMs = (data.last as Map?)?['ms'];
      if (lastMs is num && lastMs > 0) {
        return lastMs.toInt() + _beatIntervalMs;
      }
    }

    if (_beatData.isNotEmpty) {
      final lastMs = (_beatData.last as Map?)?['ms'];
      if (lastMs is num && lastMs > 0) {
        return lastMs.toInt() + _beatIntervalMs;
      }
    }

    final totalBeatsNeeded = widget.sections.length * 8;
    return math.max(_beatIntervalMs, totalBeatsNeeded * _beatIntervalMs);
  }

  int _targetSectionIndexForTime(double currentTimeMs, int storyDurationMs) {
    if (widget.sections.length <= 1 || storyDurationMs <= 0) return 0;
    final progress = (currentTimeMs / storyDurationMs).clamp(0.0, 0.999999);
    return (progress * widget.sections.length)
        .floor()
        .clamp(0, widget.sections.length - 1)
        .toInt();
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
    try {
      await _runExport();
    } catch (error, stackTrace) {
      debugPrint('❌ 故事视频导出失败: $error\n$stackTrace');
      if (mounted) {
        setState(() => _isExporting = false);
      }
      widget.onError?.call(error, stackTrace);
    }
  }

  Future<void> _runExport() async {
    await _beatLoadFuture;
    await _prepareExportMediaFrames();
    await warmAssetBackedImages(
      widget.sections.map((section) => section.photo),
    );
    if (!mounted) return;
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;

    // 🚀 保持 AI 自动写文案在后台运行
    List<String> currentCaptions = widget.sections.map((s) => s.text).toList();
    _aiCopyFuture = LLMService().generateSocialMediaCopy(
      platform: widget.targetPlatform,
      title: widget.title,
      subtitle: widget.subtitle,
      captions: currentCaptions,
    );

    final sectionsData = widget.sections
        .asMap()
        .entries
        .map((entry) => _sectionCacheData(entry.value, entry.key))
        .toList(growable: false);

    _exportCacheKey = VideoCacheService.instance.buildVideoCacheKey(
      title: widget.title,
      subtitle: widget.subtitle,
      sections: sectionsData,
      customMusicPath: widget.customMusicPath,
      dynamicBeatData: widget.dynamicBeatData,
      targetPlatform: widget.targetPlatform,
      isHorizontal: widget.isHorizontal,
      currentTextStyle: widget.currentTextStyle,
      textYPosition: widget.textYPosition,
      textSize: widget.textSize,
      textBlurIntensity: widget.textBlurIntensity,
      shakeIntensity: widget.shakeIntensity,
      shakeFrequency: widget.shakeFrequency,
      glitchIntensity: widget.glitchIntensity,
      enableFlash: widget.enableFlash,
      useVignette: widget.useVignette,
      useGrain: widget.useGrain,
      useCameraFrame: widget.useCameraFrame,
      useGlowRing: widget.useGlowRing,
      useCloudBorder: widget.useCloudBorder,
    );

    // 🌟 第一步：优先检查故事实体中固化的视频路径
    String? cachedVideoPath;
    if (widget.storyEntityId != null) {
      try {
        final store = ObjectBoxService().store;
        final storyBox = store.box<StoryEntity>();
        final story = storyBox.get(widget.storyEntityId!);
        if (story?.cachedVideoPath != null &&
            await File(story!.cachedVideoPath!).exists()) {
          cachedVideoPath = story.cachedVideoPath;
          debugPrint('✅ 使用故事实体固化视频路径: $cachedVideoPath');
        }
      } catch (_) {}
    }

    // 第二步：回退到缓存服务检查
    if (cachedVideoPath == null) {
      cachedVideoPath = await VideoCacheService.instance.getCachedVideoPath(
        sections: sectionsData,
        cacheKey: _exportCacheKey,
      );
    }

    if (cachedVideoPath != null) {
      debugPrint('✅ 使用缓存视频: $cachedVideoPath');
      widget.onProgress?.call(1.0);
      await _handleExportSuccess(cachedVideoPath);
      return;
    }

    // 🌟 第二步：没有缓存，开始生成新视频
    debugPrint('🔄 未找到缓存，开始生成新视频...');

    // 计算最终毫秒数：优先使用真实音频时长，保证一轮动画与音乐恰好同时结束。
    final int finalExportDurationMs = _storyTimelineDurationMs();
    double exactExportSeconds = finalExportDurationMs / 1000.0;

    // 🎬 1. 抓取第0帧，主要是为了获取屏幕真正的硬件像素分辨率
    _updateStateForFrame(0);
    await Future.delayed(const Duration(milliseconds: 50)); // 给UI一点时间渲染第一帧
    var firstFrame = await _captureFrameRgba();
    if (firstFrame.$1 == null) {
      throw StateError('无法获取初始渲染帧');
    }

    int videoWidth = firstFrame.$2;
    int videoHeight = firstFrame.$3;
    final int videoBitrate = (videoWidth * videoHeight * 12)
        .clamp(16000000, 80000000)
        .toInt();

    final tempDir = await getTemporaryDirectory();
    final String silentVideoPath =
        "${tempDir.path}/silent_temp_${DateTime.now().millisecondsSinceEpoch}.mp4";

    // 🎬 2. 轰鸣启动硬件编码器引擎！确保启用 GPU 硬件加速
    try {
      FlutterQuickVideoEncoder.setLogLevel(LogLevel.none); // 保持控制台清爽
      // 🌟 硬件编码配置：使用 main profile 以获得更好的硬件编码支持
      await FlutterQuickVideoEncoder.setup(
        width: videoWidth,
        height: videoHeight,
        fps: 24,
        videoBitrate: videoBitrate, // 按实际分辨率动态提高码率，尽量保留细节
        profileLevel: ProfileLevel
            .any, // ✅ 插件自动选择最优硬件编码配置（iOS: H.264/HEVC, Android: H.264）
        filepath: silentVideoPath,
        // 👇 新增这三个必填的音频占位参数
        audioBitrate: 128000, // 提升到 128kbps 以获得更好音质
        audioChannels: 2, // 双声道立体声
        sampleRate: 44100, // 标准的 44.1kHz 采样率
      );
      debugPrint('🚀 硬件视频编码器已启动（自动检测最优硬件编码方案：iOS/Android 均优先 H.264/HEVC 硬件路径）');
    } catch (e) {
      throw StateError('硬件视频编码器启动失败: $e');
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

    // 🎬 5. 移交接力棒，进行音视频合并
    await _fastMuxAudio(silentVideoPath, exactExportSeconds);
  }

  Future<void> _fastMuxAudio(
    String silentVideoPath,
    double exactSeconds,
  ) async {
    widget.onProgress?.call(0.95);
    final tempDir = await getTemporaryDirectory();
    String audioPath;
    File? tempAudioFile;
    File? safeAudioFile;

    // 准备音频
    String? resolvedMusicPath;
    if (widget.storyEntityId != null) {
      try {
        final store = ObjectBoxService().store;
        final storyBox = store.box<StoryEntity>();
        final story = storyBox.get(widget.storyEntityId!);
        if (story != null) {
          resolvedMusicPath = await StoryService.resolveMusicFile(story);
        }
      } catch (_) {}
    }
    resolvedMusicPath ??= widget.customMusicPath;

    if (resolvedMusicPath != null && await File(resolvedMusicPath).exists()) {
      safeAudioFile = File(
        '${tempDir.path}/safe_custom_audio_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      if (safeAudioFile.existsSync()) safeAudioFile.deleteSync();
      await File(resolvedMusicPath).copy(safeAudioFile.path);
      audioPath = safeAudioFile.path;
    } else {
      final ByteData audioData = await rootBundle.load(
        'assets/audio/sandal_leap.mp3',
      );
      tempAudioFile = File(
        '${tempDir.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await tempAudioFile.writeAsBytes(audioData.buffer.asUint8List());
      audioPath = tempAudioFile.path;
    }

    // 生成 FFmpeg 合成临时视频路径。
    // 最终缓存由 VideoCacheService.cacheVideo() 从这里复制到 App 内部视频缓存。
    final cacheVideoPath =
        "${tempDir.path}/mux_temp_${DateTime.now().millisecondsSinceEpoch}.mp4";

    try {
      // 使用 FFmpeg 合并音频和视频
      debugPrint('🎵 开始使用 FFmpeg 合并音频和视频...');

      // 优先使用 stream copy（不重新编码，最快）
      // 如果失败，则使用硬件加速重新编码
      bool success = await _tryMergeWithStreamCopy(
        silentVideoPath,
        audioPath,
        cacheVideoPath,
        exactSeconds,
      );

      if (success) {
        try {
          await File(silentVideoPath).delete();
        } catch (_) {}
        await _handleExportSuccess(cacheVideoPath);
      } else {
        // 如果 stream copy 失败，尝试使用硬件加速重新编码
        debugPrint('⚠️ Stream copy 失败，尝试使用硬件加速重新编码...');
        success = await _tryMergeWithHardwareAccel(
          silentVideoPath,
          audioPath,
          cacheVideoPath,
          exactSeconds,
        );

        if (success) {
          try {
            await File(silentVideoPath).delete();
          } catch (_) {}
          await _handleExportSuccess(cacheVideoPath);
        } else {
          // 最后回退：使用无声视频
          debugPrint('⚠️ 所有合并方法失败，使用无声视频作为最终产物');
          await File(silentVideoPath).copy(cacheVideoPath);
          try {
            await File(silentVideoPath).delete();
          } catch (_) {}
          await _handleExportSuccess(cacheVideoPath);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ 音频合并异常: $e');
      debugPrint('Stack trace: $stackTrace');
      // 回退：使用无声视频
      try {
        await File(silentVideoPath).copy(cacheVideoPath);
        try {
          await File(silentVideoPath).delete();
        } catch (_) {}
        debugPrint('⚠️ 使用回退路径：生成无声视频作为最终产物');
        await _handleExportSuccess(cacheVideoPath);
      } catch (e2) {
        throw StateError('音频合并及无声视频回退均失败: $e2');
      }
    } finally {
      try {
        if (tempAudioFile != null && tempAudioFile.existsSync()) {
          tempAudioFile.deleteSync();
        }
      } catch (_) {}
      try {
        if (safeAudioFile != null && safeAudioFile.existsSync()) {
          safeAudioFile.deleteSync();
        }
      } catch (_) {}
    }
  }

  /// 尝试使用 stream copy 合并（不重新编码，最快）
  Future<bool> _tryMergeWithStreamCopy(
    String videoPath,
    String audioPath,
    String outputPath,
    double duration,
  ) async {
    try {
      // -c:v copy: 直接复制视频流，不重新编码
      // -c:a aac: 使用 AAC 编码音频
      final command =
          '-y -i "$videoPath" -i "$audioPath" '
          '-map 0:v:0 -map 1:a:0 '
          '-t $duration -c:v copy -c:a aac -b:a 128k -shortest "$outputPath"';

      debugPrint('🎬 FFmpeg (stream copy): $command');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('✅ FFmpeg stream copy 成功');
        return true;
      } else {
        final output = await session.getOutput();
        debugPrint('❌ FFmpeg stream copy 失败: $output');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Stream copy 异常: $e');
      return false;
    }
  }

  /// 尝试使用硬件加速重新编码合并
  Future<bool> _tryMergeWithHardwareAccel(
    String videoPath,
    String audioPath,
    String outputPath,
    double duration,
  ) async {
    try {
      String videoCodec;

      // 根据平台选择硬件编码器
      if (Platform.isIOS || Platform.isMacOS) {
        // iOS/macOS: 使用 VideoToolbox 硬件加速
        videoCodec = 'h264_videotoolbox';
      } else if (Platform.isAndroid) {
        // Android: 使用 MediaCodec 硬件加速
        videoCodec = 'h264_mediacodec';
      } else {
        // 其他平台：使用软件编码
        videoCodec = 'libx264';
      }

      // 使用硬件加速编码
      // -c:v: 视频编码器
      // -b:v: 视频比特率
      // -preset: 编码速度预设（仅软件编码）
      final command =
          '-y -i "$videoPath" -i "$audioPath" '
          '-map 0:v:0 -map 1:a:0 '
          '-t $duration -c:v $videoCodec -b:v 2500k -c:a aac -b:a 128k '
          '-shortest "$outputPath"';

      debugPrint('🎬 FFmpeg (hardware accel): $command');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        debugPrint('✅ FFmpeg 硬件加速编码成功');
        return true;
      } else {
        final output = await session.getOutput();
        debugPrint('❌ FFmpeg 硬件加速失败: $output');

        // 如果硬件加速失败，尝试软件编码
        if (videoCodec != 'libx264') {
          debugPrint('⚠️ 硬件加速失败，尝试软件编码...');
          final softwareCommand =
              '-y -i "$videoPath" -i "$audioPath" '
              '-map 0:v:0 -map 1:a:0 '
              '-t $duration -c:v libx264 -preset ultrafast -b:v 2500k '
              '-c:a aac -b:a 128k -shortest "$outputPath"';

          debugPrint('🎬 FFmpeg (software): $softwareCommand');

          final softwareSession = await FFmpegKit.execute(softwareCommand);
          final softwareReturnCode = await softwareSession.getReturnCode();

          if (ReturnCode.isSuccess(softwareReturnCode)) {
            debugPrint('✅ FFmpeg 软件编码成功');
            return true;
          } else {
            final softwareOutput = await softwareSession.getOutput();
            debugPrint('❌ FFmpeg 软件编码失败: $softwareOutput');
            return false;
          }
        }

        return false;
      }
    } catch (e) {
      debugPrint('❌ 硬件加速编码异常: $e');
      return false;
    }
  }

  // 🌟 新增一个变量，用来装这个“未来的文案”
  Future<String>? _aiCopyFuture;
  String? _exportCacheKey;
  final Map<String, Uint8List> _exportMediaFrames = <String, Uint8List>{};

  Future<void> _handleExportSuccess(String cacheVideoPath) async {
    debugPrint('✅ 视频生成完成，缓存路径: $cacheVideoPath');

    // 🌟 第一步：缓存视频（只基于图片和文本）
    final sectionsData = widget.sections
        .asMap()
        .entries
        .map((entry) => _sectionCacheData(entry.value, entry.key))
        .toList();

    final cachedPath = await VideoCacheService.instance.cacheVideo(
      sections: sectionsData,
      videoPath: cacheVideoPath,
      cacheKey: _exportCacheKey,
    );

    debugPrint('✅ 视频已缓存: $cachedPath');
    debugPrint('📱 视频保留在 App 内部缓存；只有用户手动保存时才写入外部位置');

    // 🌟 第三步：保存视频路径、音乐和渲染参数到故事实体
    if (widget.storyEntityId != null) {
      try {
        final store = ObjectBoxService().store;
        final storyBox = store.box<StoryEntity>();
        final story = storyBox.get(widget.storyEntityId!);
        if (story != null) {
          story.cachedVideoPath = cachedPath;
          story.cachedVideoKey = _exportCacheKey;
          story.customMusicPath = widget.customMusicPath;
          story.dynamicBeatDataJson = widget.dynamicBeatData != null
              ? jsonEncode(widget.dynamicBeatData)
              : null;
          story.videoParamsJson = jsonEncode({
            'currentTextStyle': widget.currentTextStyle,
            'textYPosition': widget.textYPosition,
            'textSize': widget.textSize,
            'textBlurIntensity': widget.textBlurIntensity,
            'shakeIntensity': widget.shakeIntensity,
            'shakeFrequency': widget.shakeFrequency,
            'glitchIntensity': widget.glitchIntensity,
            'enableFlash': widget.enableFlash,
            'useVignette': widget.useVignette,
            'useGrain': widget.useGrain,
            'useCameraFrame': widget.useCameraFrame,
            'useGlowRing': widget.useGlowRing,
            'useCloudBorder': widget.useCloudBorder,
            'targetPlatform': widget.targetPlatform,
            'isHorizontal': widget.isHorizontal,
          });
          storyBox.put(story);
          debugPrint('✅ 视频参数已固化保存到故事实体 ID=${widget.storyEntityId}');
        }
      } catch (e) {
        debugPrint('❌ 保存视频参数到故事实体失败: $e');
      }
    }

    // 🌟 第四步：清理本次导出产生的临时文件
    await VideoCacheService.instance.cleanupExportTempFiles();

    // 🌟 核心：触发回调，通知 ExportManager 任务完成！
    widget.onComplete(cachedPath, _aiCopyFuture);
  }

  Map<String, dynamic> _sectionCacheData(StorySection section, int index) {
    final photo = section.photo;
    return <String, dynamic>{
      'photo': <String, dynamic>{
        'fingerprint': _mediaCacheFingerprint(photo, index),
        'mediaKind': photo.mediaKind,
        'dateTaken': photo.dateTaken.millisecondsSinceEpoch,
        'width': photo.width,
        'height': photo.height,
      },
      'text': section.text,
    };
  }

  String _mediaCacheFingerprint(Photo photo, int index) {
    final bytes = photo.thumbnailBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return 'thumb:${sha256.convert(bytes)}';
    }
    return [
      'meta',
      index,
      photo.dateTaken.millisecondsSinceEpoch,
      photo.mediaKind,
      photo.width,
      photo.height,
    ].join(':');
  }

  // 🎬 专门给取景器提供纯净画面的层（无黑边）
  Widget _buildPureImageLayer(Photo photo, Widget subtitle) {
    final mediaKind = MediaTypeHelper.fromStorageValue(photo.mediaKind);
    final posterFrame = _exportMediaFrames[_exportMediaFrameKey(photo)];
    final mediaLayer = posterFrame != null
        ? Image.memory(
            posterFrame,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
          )
        : mediaKind == MemoriaMediaKind.image
        ? AssetBackedImage(
            path: '',
            assetId: photo.id,
            thumbnailBytes: photo.thumbnailBytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            enableSmartCache: true,
          )
        : const ColoredBox(color: Colors.black);
    return Stack(
      key: ValueKey<String>(photo.id),
      fit: StackFit.expand,
      children: [
        TweenAnimationBuilder(
          tween: Tween<double>(begin: 1.0, end: 1.15),
          duration: const Duration(seconds: 5),
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: mediaLayer,
        ),
        subtitle, // 字幕层
      ],
    );
  }

  Future<void> _prepareExportMediaFrames() async {
    for (final section in widget.sections) {
      final photo = section.photo;
      final kind = await MediaTypeHelper.resolve(path: '', assetId: photo.id);
      if (kind == MemoriaMediaKind.image) continue;

      final frame = await _resolveExportMediaFrame(photo);
      if (frame == null || frame.isEmpty) {
        throw StateError('无法通过系统相册读取媒体帧: ${photo.id}');
      }
      _exportMediaFrames[_exportMediaFrameKey(photo)] = frame;
    }
  }

  String _exportMediaFrameKey(Photo photo) => photo.id;

  Future<Uint8List?> _resolveExportMediaFrame(Photo photo) async {
    try {
      final cached = await MediaThumbnailCacheService.instance.decompressBytes(
        photo.thumbnailBytes,
      );
      if (cached != null && cached.isNotEmpty) return cached;

      final assetThumbnail = await MediaThumbnailCacheService.instance
          .loadAssetThumbnailById(photo.id);
      final bytes = assetThumbnail?.bytes;
      if (bytes != null && bytes.isNotEmpty) return bytes;
      return null;
    } catch (error, stackTrace) {
      debugPrint(
        '⚠️ 解析导出媒体帧失败: ${photo.id} '
        'error=$error\n$stackTrace',
      );
      return null;
    }
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
