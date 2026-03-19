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

class StoryVideoPage extends StatefulWidget {
  final String title;
  final List<StorySection> sections;
  final bool isHorizontal;
  final String? customMusicPath;
  final Map<String, dynamic>? dynamicBeatData; // 🌟 接收云端数据
  final String subtitle;

  const StoryVideoPage({
    super.key,
    required this.title,
    required this.sections,
    this.isHorizontal = false,
    this.customMusicPath,
    this.dynamicBeatData,
    required this.subtitle,
  });

  @override
  State<StoryVideoPage> createState() => _StoryVideoPageState();
}

class _StoryVideoPageState extends State<StoryVideoPage>
    with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();

  int _currentIndex = 0;
  bool _isPlaying = false;
  StreamSubscription? _positionSubscription;
  
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

    // ==========================================
    // 🚀 核心：解析 Librosa 云端传来的真实数据
    // ==========================================
    if (widget.dynamicBeatData != null &&
        widget.dynamicBeatData!['data'] != null) {
      _beatData = widget.dynamicBeatData!['data'];
      double bpm = (widget.dynamicBeatData!['bpm'] as num).toDouble();
      _beatIntervalMs = (60000 / bpm).round(); // 根据真实 BPM 算出每拍的毫秒数
      debugPrint(
        "🎵 成功加载真实节拍！BPM: $bpm, 间隔: ${_beatIntervalMs}ms, 共 ${_beatData.length} 拍",
      );
    } else {
      // 如果没拿到数据，给个兜底防崩溃
      debugPrint("⚠️ 未接收到真实节拍数据，使用默认沙盒模式");
      _beatData = [
        {"ms": 0, "energy": 0.1},
        {"ms": 500, "energy": 0.8}, // 假装这是一记重鼓
        {"ms": 1000, "energy": 0.2},
      ];
      _beatIntervalMs = 500;
    }

    if (widget.sections.isNotEmpty) {
      _currentLyricText = widget.sections[0].text;
    } else {
      _currentLyricText = "";
    }

    // 🌟 修复 1：挂上离合，踩下油门！
    _initAudioAndListener(); // 启动音频实时监听
    _togglePlay(); // 自动开始播放
  }
  
  int _currentBeatIndexForPreview = -1; // 记录当前演到第几拍了

  Future<void> _initAudioAndListener() async {
    _positionSubscription = _audioPlayer.onPositionChanged.listen((Duration p) {
      if (_beatData.isEmpty || _isExporting) return; // 导出时不要干扰

      double currentTimeMs = p.inMilliseconds.toDouble();

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
          _enableFlash = false;
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
      screenBody = RepaintBoundary(key: _renderKey, child: videoContent);
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
  Future<Uint8List?> _captureFrame() async {
    try {
      // 找到那根“虚拟取景器”的边界
      RenderRepaintBoundary boundary =
          _renderKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;

      // 🚀 提速点 1：把 pixelRatio 从 2.0 降回 1.0 (测试时甚至可改 0.5)
      ui.Image image = await boundary.toImage(pixelRatio: 1.0);

      // 洗出相片：转成 PNG 格式的字节流
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint("❌ 抓拍当前帧失败: $e");
      return null;
    }
  }

  Future<void> _startExport() async {
    if (_isPlaying) await _togglePlay();

    // 🌟 1. 精准计算“视觉画面”需要的总时长
    int totalBeatsNeeded = widget.sections.length * 8;
    int visualDurationMs = totalBeatsNeeded * _beatIntervalMs;
    // 如果 JSON 数据够长，直接从 JSON 里取那个节拍的真实毫秒数，更准！
    if (_beatData.length > totalBeatsNeeded) {
      visualDurationMs = (_beatData[totalBeatsNeeded]['ms'] as num).toInt();
    } else if (_beatData.isNotEmpty) {
      // ⚠️ 修复拖尾：如果图片太多，超过了歌曲总长度，强制以歌曲最后一个节拍为准！
      visualDurationMs = (_beatData.last['ms'] as num).toInt();
    }

    // 2. 获取音频真实时长，防止用户选了1000张图但歌只有1分钟
    Duration? duration = await _audioPlayer.getDuration();
    int audioDurationMs = duration?.inMilliseconds ?? 15000;

    // 🌟 2. 最终导出时长：决不许超过音乐时长，也决不许多等一张图！
    int finalExportDurationMs = math.min(visualDurationMs, audioDurationMs);
    // 把这精准的时长转换成秒
    double exactExportSeconds = finalExportDurationMs / 1000.0;

    final directory = await getTemporaryDirectory();
    final frameDir = Directory('${directory.path}/story_frames');
    if (frameDir.existsSync()) {
      frameDir.deleteSync(recursive: true);
    }
    frameDir.createSync();

    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
    });

    // 4. 按 24 FPS 算出到底需要截多少帧
    int fps = 24;
    int totalFrames = (finalExportDurationMs / 1000 * fps).floor();
    // 🌟 新增：准备一个篮子，装所有的写入任务
    List<Future> writeTasks = [];

    for (int i = 0; i < totalFrames; i++) {
      _updateStateForFrame(i); // ⚠️ 记得去把 _updateStateForFrame 里的 30.0 改成 24.0

      setState(() => _exportProgress = i / totalFrames);

      await Future.delayed(const Duration(milliseconds: 16));

      final frameBytes = await _captureFrame();
      if (frameBytes != null) {
        final file = File(
          '${frameDir.path}/frame_${i.toString().padLeft(5, '0')}.png',
        );
        // 🌟 把写入任务丢进篮子里，不要在这里死等
        writeTasks.add(file.writeAsBytes(frameBytes));
      }
    }
    setState(() => _exportProgress = 0.95); // 给用户一点心理安慰

    // 🌟 修复：强行等篮子里的所有图片确确实实全都写进硬盘了，再往下走！
    await Future.wait(writeTasks);

    await _runFFmpegCombine(frameDir.path, exactExportSeconds);
  }

  Future<void> _runFFmpegCombine(
    String frameDirPath,
    double exactSeconds,
  ) async {
    setState(() {
      // 进度条文字可以变一下（自己可以再去加个状态位，为了简便暂用这个进度）
      _exportProgress = 0.99;
    });

    try {
      final docDir = await getApplicationDocumentsDirectory();
      String audioPath;

      // 🌟 核心改动：确定导出时使用的音频路径
      if (widget.customMusicPath != null) {
        // 🚨 修复致命的“文件名包含空格/日文”断裂 Bug
        // 我们不直接用原路径，而是把它拷贝成一个绝对安全的纯英文路径
        File originalAudio = File(widget.customMusicPath!);
        File safeAudioFile = File('${docDir.path}/safe_custom_audio.mp3');

        // 如果之前有残留，先删掉
        if (safeAudioFile.existsSync()) safeAudioFile.deleteSync();

        // 复制一份过去
        await originalAudio.copy(safeAudioFile.path);
        audioPath = safeAudioFile.path;
      } else {
        // 如果是默认音乐，先从 assets 提取到沙盒
        final ByteData audioData = await rootBundle.load(
          'assets/audio/sandal_leap.mp3',
        );
        final File tempAudioFile = File('${docDir.path}/temp_audio.mp3');
        await tempAudioFile.writeAsBytes(audioData.buffer.asUint8List());
        audioPath = tempAudioFile.path;
      }

      // 2. 定义最终导出的 MP4 路径
      final String outputPath =
          "${docDir.path}/FINAL_STORY_${DateTime.now().millisecondsSinceEpoch}.mp4";

      // 3. 构造魔法咒语 (🌟 为了极其安全，给路径都加上单引号)
      String command =
          "-y -framerate 24 -start_number 0 -i '$frameDirPath/frame_%05d.png' -i '$audioPath' -t $exactSeconds -vf scale=trunc(iw/2)*2:trunc(ih/2)*2 -c:v libx264 -pix_fmt yuv420p -c:a aac '$outputPath'";

      debugPrint("🎬 FFmpeg 开始合成: $command");

      // 4. 召唤神龙
      await FFmpegKit.execute(command).then((session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          debugPrint("✅✅✅ 完美导出！视频保存在沙盒: $outputPath");

          // 🌟 核心新增：拷贝进系统相册
          try {
            // gal 插件非常智能，如果没有权限它会自动弹窗问用户要
            await Gal.putVideo(outputPath);
            debugPrint("📸 视频已成功保存至手机系统相册！");

            // 给用户一个极其舒适的视觉反馈
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🎉 视频渲染完成，已保存至手机相册！快去图库看看吧！'),
                  backgroundColor: Colors.pinkAccent,
                  behavior: SnackBarBehavior.floating, // 悬浮样式更好看
                  duration: Duration(seconds: 4),
                ),
              );
            }
          } catch (e) {
            debugPrint("❌ 保存到相册失败: $e");
          }
        } else {
          final logs = await session.getLogsAsString();
          debugPrint("❌ FFmpeg 炸了，真正的原因是:\n$logs");
        }
      });
    } finally {
      // 6. 收工，撤掉黑布
      setState(() {
        _isExporting = false;
        _exportProgress = 0.0;
      });
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
