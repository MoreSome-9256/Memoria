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
import '../../effects/cloud_border_effect.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import 'publish_page.dart';
import '../../service/llm_service.dart';
import '../../service/music_service.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';

class StoryVideoPage extends StatefulWidget {
  final String title;
  final List<StorySection> sections;
  final bool isHorizontal;
  final String? customMusicPath;
  final Map<String, dynamic>? dynamicBeatData; // 🌟 接收云端数据
  final String subtitle;
  final String targetPlatform;

  const StoryVideoPage({
    super.key,
    required this.title,
    required this.sections,
    this.isHorizontal = false,
    this.customMusicPath,
    this.dynamicBeatData,
    required this.subtitle,
    required this.targetPlatform,
  });

  @override
  State<StoryVideoPage> createState() => _StoryVideoPageState();
}

// 🌟 核心新增：转场特效的“身份证”
class TransitionMaterial {
  final String id; // 唯一标识
  final String name; // 在控制台里显示的名字，比如 "梦幻漏光"
  final String movPath; // 导出用的 .mov 路径
  final String webpPath; // 预览用的 .webp 路径
  final int offsetMs; // 🌟 灵魂属性：这个转场需要提前多少毫秒播放才能完美卡点？
  final int durationMs; // 🌟 新增：这个转场总共多长（毫秒）？

  const TransitionMaterial({
    required this.id,
    required this.name,
    required this.movPath,
    required this.webpPath,
    required this.offsetMs,
    required this.durationMs,
  });
}

class _StoryVideoPageState extends State<StoryVideoPage>
    with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();

  int _currentIndex = 0;
  bool _isPlaying = false;
  StreamSubscription? _positionSubscription;

  // 🌟 核心新增：记录音频循环播放的状态
  int _audioLoopCount = 0; // 记圈器：已经循环了几遍？
  double _lastAudioPositionMs = 0; // 上一次拿到的播放进度
  int _singleLoopMs = 15000; // 单首音乐的真实长度

  int _currentLyricIndex = 0;
  String _currentLyricText = "";
  // 🎛️ VFX 控制台参数
  double _shakeIntensity = 0.0; // 震动幅度 (Amplitude)
  double _shakeFrequency = 1.0; // 🌟 新增：震动频率/马达转速 (Frequency)，默认15

  // 🌟 新增 1：故障特效的独立强度 (0.0 到 1.0)
  double _glitchIntensity = 0.0;
  // 🌟 新增 2：给故障特效专用的“永动机”时间控制器
  late AnimationController _continuousTimeController;

  // 滤镜状态
  bool _useVignette = false; // 暗角
  bool _useGrain = false; // 噪点
  bool _useCameraFrame = false; // 相机边框
  bool _useGlowRing = false; // 光圈
  bool _useCloudBorder = false; // 云朵边框

  bool _showPreviewTransition = false;

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
      duration: Duration(milliseconds: 500), // 先随便给个值，后面会被覆盖
    );

    // 🌟 新增：启动一个 2 秒一循环的永动机，专门驱动常驻特效
    _continuousTimeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(); // 无限重复！

    // 先给一个最小可播放节拍，随后异步替换为后端分析结果。
    _beatData = [
      {"ms": 0, "energy": 0.1},
      {"ms": 500, "energy": 0.6},
      {"ms": 1000, "energy": 0.2},
    ];
    _beatIntervalMs = 500;
    unawaited(_loadBeatDataFromBackend());

    if (widget.sections.isNotEmpty) {
      _currentLyricText = widget.sections[0].text;
    } else {
      _currentLyricText = "";
    }

    // 🌟 修复 1：挂上离合，踩下油门！
    _initAudioAndListener(); // 启动音频实时监听
    _togglePlay(); // 自动开始播放
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
    if (widget.dynamicBeatData != null && widget.dynamicBeatData!['data'] != null) {
      _applyBeatData(widget.dynamicBeatData!);
      return;
    }

    try {
      // fallback 也走云端分析：上传当前实际要播放的音频文件。
      String audioPath;
      if (widget.customMusicPath != null && widget.customMusicPath!.isNotEmpty) {
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

  Future<void> _initAudioAndListener() async {
    // 🌟 1. 获取这首歌的真实时长（比如 15000 毫秒）
    await _audioPlayer.setSourceDeviceFile(widget.customMusicPath!);
    Duration? songDuration = await _audioPlayer.getDuration();
    // 🌟 修复：把获取到的时长存进我们刚才定义的全局变量里！
    _singleLoopMs = songDuration?.inMilliseconds ?? 15000;
    int singleLoopMs = _singleLoopMs;

    // 🌟 2. 核心补丁：无限繁衍节拍数据！
    // 假设我们粗暴地把它复制 20 遍（足以应付 5 分钟的视频）
    if (_beatData.isNotEmpty && _beatData.last['ms'] < singleLoopMs * 1.5) {
      List<Map<String, dynamic>> extendedBeats = [];
      List<dynamic> originalBeats = List.from(_beatData); // 拷贝原版 15 秒的节拍

      for (int loopIndex = 0; loopIndex < 20; loopIndex++) {
        // 每循环一次，时间戳就要加上单曲的总时长
        int timeOffset = loopIndex * singleLoopMs;

        for (var beat in originalBeats) {
          extendedBeats.add({
            'ms': (beat['ms'] as int) + timeOffset,
            'energy': beat['energy'],
          });
        }
      }
      _beatData = extendedBeats; // 替换成拥有几百个节拍的“超级节拍本”！
      debugPrint("🔄 已将节拍数据无缝循环扩充至 ${_beatData.length} 个节拍！");
    }

    // 🌟 3. 设置播放器为无限循环模式
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    _positionSubscription = _audioPlayer.onPositionChanged.listen((Duration p) {
      if (_beatData.isEmpty || _isExporting) return; // 导出时不要干扰

      double currentPosMs = p.inMilliseconds.toDouble();

      // ==========================================
      // 🌟 核心补丁：精准捕获“循环重置”瞬间！
      // ==========================================
      // 如果当前时间突然比上一次的时间小了超过 1 秒，说明它肯定是从头开始循环了！
      if (currentPosMs < _lastAudioPositionMs - 1000) {
        _audioLoopCount++;
        debugPrint("🔄 音乐第 $_audioLoopCount 次循环，当前真实总时长已延长！");
      }
      _lastAudioPositionMs = currentPosMs;

      // 🌟 真实的连续时间 = 当前播放条位置 + (已经循环的圈数 * 一圈的总时长)
      double currentTimeMs = currentPosMs + (_audioLoopCount * _singleLoopMs);

      // ==========================================
      // 🌟 核心升级：根据 BPM 动态计算片头结束的确切时间！
      // ==========================================
      // 第一张图（片头）固定在第 8 拍时切换到正片
      double firstCutTimeMs = 8 * _beatIntervalMs.toDouble();

      // 动态获取当前选中转场的卡点时间
      int offset = _currentTransition.offsetMs;
      int duration = _currentTransition.durationMs;
      // 开始时间 = 切图点 - 提前量
      double transitionStartMs = firstCutTimeMs - offset;
      // 🌟 结束时间 = 开始时间 + 转场总长（保证它一定能完完整整播完！）
      double transitionEndMs = transitionStartMs + duration;

      bool shouldShow =
          currentTimeMs >= transitionStartMs &&
          currentTimeMs <= transitionEndMs;

      if (_showPreviewTransition != shouldShow) {
        setState(() {
          _showPreviewTransition = shouldShow;
        });
      }

      // 1. 找当前是第几拍
      int targetBeatIndex = 0;
      for (int j = 0; j < _beatData.length; j++) {
        if (currentTimeMs >= _beatData[j]['ms']) {
          targetBeatIndex = j;
        } else {
          break;
        }
      }

      // 🌟 2. 只有当跨入“新的一拍”时，才触发导演逻辑！
      if (targetBeatIndex != _currentBeatIndexForPreview) {
        _currentBeatIndexForPreview = targetBeatIndex;

        double currentEnergy =
            (_beatData[targetBeatIndex]['energy'] as num?)?.toDouble() ?? 0.0;

        // 🎯 触发高能震动特效
        if (currentEnergy > 0.15) {
          _shakeIntensity = currentEnergy * 15.0 * (_shakeFrequency / 15.0);
          // _enableFlash = true;
          _shakeIntensity = (currentEnergy * 15.0 * (_shakeFrequency / 15.0))
              .clamp(0.0, 10.0);
          // 🚀 核心魔法：从 0 开始播放特效动画，结合下方的 UI 构建，产生真实的物理衰减！
          _vfxController.forward(from: 0.0);
        } else {
          _shakeIntensity = 0.0;
          // _enableFlash = false;
        }

        // 🖼️ 决定切图 (每 8 拍切一张)
        int beatsPerImage = 8;
        int targetImageIndex = targetBeatIndex ~/ beatsPerImage;
        if (targetImageIndex >= widget.sections.length) {
          targetImageIndex = widget.sections.length - 1;
        }

        if (mounted) {
          setState(() {
            _currentIndex = targetImageIndex;
            // 🌟 替换掉之前的 _lyricQueue 逻辑
            _currentLyricText = widget.sections[_currentIndex].text;
          });
        }
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentIndex = 0;
          _currentBeatIndexForPreview = -1;
          // 🌟 记得在这里把循环记录清零
          _audioLoopCount = 0;
          _lastAudioPositionMs = 0;
          if (widget.sections.isNotEmpty) {
            _currentLyricText = widget.sections[0].text;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _vfxController.dispose(); // 别忘了释放内存
    _continuousTimeController.dispose();
    _positionSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      // 🌟 核心改动：判断音乐来源
      if (widget.customMusicPath != null) {
        // 如果是用户手动导入的音乐，使用 DeviceFileSource
        await _audioPlayer.play(DeviceFileSource(widget.customMusicPath!));
      } else {
        // 否则播放 assets 里的默认测试音乐
        await _audioPlayer.play(AssetSource('audio/sandal_leap.mp3'));
      }
    }
    if (mounted) {
      setState(() {
        _isPlaying = !_isPlaying;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) {
      return const Scaffold(body: Center(child: Text('无内容')));
    }

    final currentSection = widget.sections[_currentIndex];

    // 🌟 核心判断：当前是不是第 0 帧（片头帧）
    final bool isIntro = _currentIndex == 0;

    final subtitleLayer = SubtitleEffectLayer(
      // 🌟 修改：如果是片头，强行把字幕抽空，给片头大字让路！
      text: isIntro ? "" : _currentLyricText,
      effectType: _currentTextStyle,
      yPosition: _textYPosition,
      fontSize: _textSize,
      fontFamily: _fontFamily,
      blurIntensity: _textBlurIntensity,
      vfxController: _vfxController,
    );

    // 🌟 1. 定义纯净的视频内容层（包含震动、闪光、图片和字幕，但不含背景）
    Widget videoContent = ClipRect(
      child: CameraFrameEffect(
        enabled: _useCameraFrame,
        isHorizontal: widget.isHorizontal, // 传入当前视频画幅状态
        child: VignetteEffect(
          enabled: _useVignette,
          child: GrainEffect(
            enabled: _useGrain,
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
                  // 💥 底层图片（带阻尼震动动画，且内部包含了单句小字幕）
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
                        subtitleLayer, // 👆 刚才被抽空的字幕层在这里被渲染
                      ),
                    ),
                  ),

                  // 🌟 霓虹光圈层
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
                        enabled: _useGlowRing,
                        time: _continuousTimeController.value,
                        beatIntensity: decay,
                      );
                    },
                  ),

                  // 💥 白场闪光层
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

                  // ==========================================
                  // 🎬 核心新增：电影感片头层！
                  // 放在所有图层的最顶端（闪光层之上），保证片头文字清晰无比
                  // ==========================================
                  if (isIntro)
                    Positioned.fill(
                      child: CinematicTitleIntro(
                        title: widget.title, // 使用上一个页面传来的标题
                        subtitle: widget.subtitle, // 使用上一个页面传来的副标题
                      ),
                    ),
                    // ==========================================
                  // 🎭 核心新增：预览专属的转场替身！
                  // ⚠️ 注意条件：只在规定的时间显示，并且导出时绝对不显示！
                  // ==========================================
                  /*if (_showPreviewTransition && !_isExporting)
                    Positioned.fill(
                      child: IgnorePointer(
                        // 用 BoxFit.cover 撑满整个屏幕
                        child: Image.asset(
                          _currentTransition.webpPath,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    if (_useCloudBorder)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: CloudBorderEffect(
                          cloudColor: Colors.white,
                          shadowColor: Color(0x80EAD9EC),
                        ),
                      ),
                    ),*/
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 🌟 2. 动态决定 取景器(RepaintBoundary) 放在哪
    Widget screenBody;
    if (widget.isHorizontal) {
      if (_isExporting) {
        screenBody = Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: RepaintBoundary(key: _renderKey, child: videoContent),
          ),
        );
      } else {
        screenBody = Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(currentSection.photo.path), fit: BoxFit.cover),
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(color: Colors.black.withValues(alpha: 0.6)),
            ),
            Center(
              child: AspectRatio(aspectRatio: 16 / 9, child: videoContent),
            ),
          ],
        );
      }
    } else {
      // 用 SizedBox 或 AspectRatio 给它一个绝对偶数的逻辑容器
screenBody = Center(
  child: SizedBox(
    // 取决于你手机的逻辑分辨率，这里给一个标准的 9:16 偶数容器
    width: 360,  // 360 * pixelRatio(2.0) = 720 (偶数)
    height: 640, // 640 * pixelRatio(2.0) = 1280 (偶数)
    child: RepaintBoundary(key: _renderKey, child: videoContent),
  ),
);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          screenBody,
          if (!_isExporting) _buildControls(),
          if (_isExporting) _buildExportProgressOverlay(),
        ],
      ),
    );
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

  // 控件 UI 层
  Widget _buildControls() {
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 顶部：返回按钮 + 视频标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 4)],
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 4)],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 🌟 新增：导演控制台呼出按钮
                IconButton(
                  icon: const Icon(Icons.tune, color: Colors.white),
                  onPressed: _showVfxPanel,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.movie_creation,
                    color: Colors.pinkAccent,
                  ),
                  onPressed: () {
                    // 点击后直接执行我们写的那个硬核导出循环
                    _startExport();
                  },
                ),
              ],
            ),
          ),

          // 底部：播放控制键
          Padding(
            padding: const EdgeInsets.only(bottom: 30),
            child: GestureDetector(
              onTap: _togglePlay,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isPlaying ? 0.0 : 1.0, // 播放时隐藏，暂停时显示
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 1. 定义你的素材库 (假设你目前准备了这几个)
  final List<TransitionMaterial> _transitions = const [
    TransitionMaterial(
      id: 'none',
      name: '无转场',
      movPath: '',
      webpPath: '',
      offsetMs: 0,
      durationMs: 0,
    ),
    TransitionMaterial(
      id: 'orange_and_red',
      name: '橙色动画',
      movPath: 'assets/transitions/orange_and_red.mov',
      webpPath: 'assets/transitions/orange_and_red.webp',
      offsetMs: 800, // 提前 0.8 秒
      durationMs: 2000,
    ),
    TransitionMaterial(
      id: 'white_circle',
      name: '白底圆圈',
      movPath: 'assets/transitions/white_circle.mov',
      webpPath: 'assets/transitions/white_circle.webp',
      offsetMs: 500, // 动作快，提前 0.5 秒就够了
      durationMs: 2000,
    ),
    TransitionMaterial(
      id: 'light',
      name: '光效转场',
      movPath: 'assets/transitions/light.mov',
      webpPath: 'assets/transitions/light.webp',
      offsetMs: 500, 
      durationMs: 2000,
    ),
    TransitionMaterial(
      id: 'blue_circle',
      name: '蓝色圆形',
      movPath: 'assets/transitions/blue_circle.mov',
      webpPath: 'assets/transitions/blue_circle.webp',
      offsetMs: 500,
      durationMs: 1000,
    ),
    TransitionMaterial(
      id: 'red',
      name: '红色箭头',
      movPath: 'assets/transitions/red.mov',
      webpPath: 'assets/transitions/red.webp',
      offsetMs: 500, 
      durationMs: 1000,
    ),
    TransitionMaterial(
      id: 'green',
      name: '彩色切分',
      movPath: 'assets/transitions/green.mov',
      webpPath: 'assets/transitions/green.webp',
      offsetMs: 0,
      durationMs: 3000,
    ),
    TransitionMaterial(
      id: 'glass',
      name: '蓝色玻璃',
      movPath: 'assets/transitions/glass.mov',
      webpPath: 'assets/transitions/glass.webp',
      offsetMs: 500,
      durationMs: 3000,
    ),
  ];

  // 2. 记住用户当前选了哪个（默认选漏光）
  late TransitionMaterial _currentTransition = _transitions[1];

  // 🎛️ 导演控制台面板
  void _showVfxPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      barrierColor: Colors.transparent, // 透明背景，不遮挡视频观看
      isScrollControlled: true, // 允许我们自己控制高度
      // 🌟 新增：圆角设计，让控制台看起来更精致
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // 🌟 新增：获取屏幕高度
        final screenHeight = MediaQuery.of(context).size.height;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              // 🌟 核心修改：用 Container 约束最大高度为屏幕的一半
              child: Container(
                constraints: BoxConstraints(maxHeight: screenHeight * 0.5),
                child: Column(
                  children: [
                    // 🌟 顶部加一个小小的“把手”指示器，提示用户这是个可以拖动的面板
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // 🌟 剩下的内容放进 Expanded 和 SingleChildScrollView 里，确保它可以滑动
                    Expanded(
                      child: SingleChildScrollView(
                        physics:
                            const BouncingScrollPhysics(), // 增加 iOS 风格的回弹效果
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24.0,
                            vertical: 8.0,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'VFX 特效控制台',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // --- 下面完全是你的原有代码，一字未改 ---

                              // 1. 震动幅度滑块
                              Row(
                                children: [
                                  const Text(
                                    '震动幅度',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _shakeIntensity,
                                      min: 0,
                                      max: 10.0,
                                      divisions: 30,
                                      activeColor: Colors.pinkAccent,
                                      onChanged: (val) {
                                        setModalState(
                                          () => _shakeIntensity = val,
                                        );
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),

                              // 🌟 1.5 新增：震动频率 (马达转速) 滑块
                              Row(
                                children: [
                                  const Text(
                                    '震动频率',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _shakeFrequency,
                                      min: 1.0,
                                      max: 50.0,
                                      divisions: 49,
                                      activeColor: Colors.orangeAccent,
                                      onChanged: (val) {
                                        setModalState(
                                          () => _shakeFrequency = val,
                                        );
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              // 🌟 新增：故障干扰 (Glitch) 滑块
                              Row(
                                children: [
                                  const Text(
                                    '故障干扰',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _glitchIntensity,
                                      min: 0.0,
                                      max: 1.0,
                                      divisions: 20,
                                      activeColor: Colors.greenAccent,
                                      onChanged: (val) {
                                        setModalState(
                                          () => _glitchIntensity = val,
                                        );
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              // 2. 闪光弹开关
                              SwitchListTile(
                                title: const Text(
                                  '高光闪烁 (Flash)',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                activeThumbColor: Colors.pinkAccent,
                                value: _enableFlash,
                                onChanged: (val) {
                                  setModalState(() => _enableFlash = val);
                                  setState(() {});
                                },
                              ),

                              // 3. 字幕模糊度滑块
                              Row(
                                children: [
                                  const Text(
                                    '字幕失焦',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _textBlurIntensity,
                                      min: 0,
                                      max: 20,
                                      activeColor: Colors.cyanAccent,
                                      onChanged: (val) {
                                        setModalState(
                                          () => _textBlurIntensity = val,
                                        );
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white24, height: 32),
                              const Text(
                                '🔤 排版与字幕',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // 1. 字幕风格选择器
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '字幕特效',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  DropdownButton<String>(
                                    value: _currentTextStyle,
                                    dropdownColor: Colors.grey[900],
                                    style: const TextStyle(
                                      color: Colors.pinkAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    underline: const SizedBox(),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'standard',
                                        child: Text('Standard (底部平滑)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'hero',
                                        child: Text('Hero (居中呼吸)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'cards',
                                        child: Text('Cards (字卡逐字)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'layered',
                                        child: Text('Layered (图层堆叠)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'outline',
                                        child: Text('Outline (大字描边)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'typewriter',
                                        child: Text('Typewriter (打字机)'),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setModalState(
                                          () => _currentTextStyle = val,
                                        );
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),

                              // 2. Y轴位置滑块
                              Row(
                                children: [
                                  const Text(
                                    '垂直位置',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _textYPosition,
                                      min: 0.1,
                                      max: 0.9,
                                      activeColor: Colors.blueAccent,
                                      onChanged: (val) {
                                        setModalState(
                                          () => _textYPosition = val,
                                        );
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),

                              // 3. 字号滑块
                              Row(
                                children: [
                                  const Text(
                                    '字体大小',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _textSize,
                                      min: 14.0,
                                      max: 60.0,
                                      activeColor: Colors.blueAccent,
                                      onChanged: (val) {
                                        setModalState(() => _textSize = val);
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '片头转场',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  DropdownButton<TransitionMaterial>(
                                    value: _currentTransition,
                                    dropdownColor: Colors.grey[900],
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    underline: const SizedBox(),
                                    items: _transitions.map((material) {
                                      return DropdownMenuItem(
                                        value: material,
                                        child: Text(material.name),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setModalState(() => _currentTransition = val);
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white24),
                              CheckboxListTile(
                                title: const Text(
                                  '复古暗角',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                value: _useVignette,
                                activeColor: Colors.pinkAccent,
                                onChanged: (val) {
                                  setModalState(() => _useVignette = val!);
                                  setState(() {});
                                },
                              ),
                              CheckboxListTile(
                                title: const Text(
                                  '胶片噪点',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                value: _useGrain,
                                activeColor: Colors.pinkAccent,
                                onChanged: (val) {
                                  setModalState(() => _useGrain = val!);
                                  setState(() {});
                                },
                              ),
                              CheckboxListTile(
                                title: const Text(
                                  '相机取景器',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                value: _useCameraFrame,
                                activeColor: Colors.pinkAccent,
                                onChanged: (val) {
                                  setModalState(() => _useCameraFrame = val!);
                                  setState(() {});
                                },
                              ),
                              CheckboxListTile(
                                title: const Text(
                                  '霓虹光圈',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                value: _useGlowRing,
                                activeColor: Colors.pinkAccent,
                                onChanged: (val) {
                                  setModalState(() => _useGlowRing = val!);
                                  setState(() {});
                                },
                              ),
                              CheckboxListTile(
                                title: const Text(
                                  '云朵边框',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                value: _useCloudBorder,
                                activeColor: Colors.pinkAccent,
                                onChanged: (val) {
                                  // 这里极其重要：必须同时调用 setModalState 和 setState
                                  // 这样才能让面板上的勾选框和背后的视频画面同时刷新！
                                  setModalState(() => _useCloudBorder = val!);
                                  setState(() {});
                                },
                              ),
                              // 底部留出一点空白，防止被系统手势条挡住
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 📊 导出时的进度遮罩层
  Widget _buildExportProgressOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.8), // 调暗背景
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.pinkAccent),
            ),
            const SizedBox(height: 24),
            Text(
              "正在渲染视频帧... ${(_exportProgress * 100).toInt()}%",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "请勿关闭页面，渲染完成后将自动合成 MP4",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
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
    if (_isPlaying) await _togglePlay();

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

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

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

      if (i % 5 == 0) {
        // UI 节流，不要每帧都 setState
        setState(() => _exportProgress = (i / totalFrames) * 0.85);
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
    setState(() => _exportProgress = 0.95); // 进度来到最后一步

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
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportProgress = 0.0;
        });
      }
    }
  }

  // 🌟 新增一个变量，用来装这个“未来的文案”
  Future<String>? _aiCopyFuture;

  // 辅助方法：处理成功后的跳转（提取出你原有的逻辑）
  void _handleExportSuccess(String outputPath) async {
    try {
      await Gal.putVideo(outputPath);
      if (mounted) {
        List<String> currentCaptions = widget.sections
            .map((s) => s.text)
            .toList();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => PublishPage(
              title: widget.title,
              subtitle: widget.subtitle,
              captions: currentCaptions,
              targetPlatform: widget.targetPlatform,
              exportedVideoPath: outputPath,
              generatedCopyFuture: _aiCopyFuture,
            ),
          ),
        );
      }
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
