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
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
import 'package:gal/gal.dart';

class StoryVideoPage extends StatefulWidget {
  final String title;
  final List<StorySection> sections;
  final bool isHorizontal;

  const StoryVideoPage({
    super.key,
    required this.title,
    required this.sections,
    this.isHorizontal = false,
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
  final String _rawUserInput =
      "魅かれ離れ時が過ぎて / 揺れる揺れる夏を見てた / 心臓の暴走も止められないで / 永遠にそれを繰り返すんだろうな / 空然と有限の時が過ぎて / 君の存在も薄れゆけと / ぞんざいな感情にとらわれたまま / 消えない消えない消えない / 夏が遠く遠く未来で / また今に出会える頃 / 僕はどんなんだ? / 君を覚えてるかな? / 忘れたらそれでいいさ / あの日と君の全てを / 「んなわけないじゃん」って / 走り出しても / 明日はまだ来ない / 右の裸足散る三日月 / 知らない海辺をただ歩いて / 浮かぶ浮かぶ懐かしさが見えて / 駆け出す駆け出す駆け出したって / 時間には逆らえないな / 願ってもどうしようもないことさ / 「大嫌いだ」って / 君を全部そうやって / 忘れたらそれでいいんだ / 満たした感情が崩れていく / 途絶えた運命に / 行くあても無くなって / 夏が遠く遠く未来で / また今に出会える頃 / 僕はどんなんだ? / 君を覚えてるかな? / 忘れたらそれでいいさ / あの日と君の全てを / 「んなわけないじゃん」って / 走り出しても / 明日はまだ来ない";
  List<String> _lyricQueue = [];
  int _currentLyricIndex = 0;
  String _currentLyricText = "";
  // 🎛️ VFX 控制台参数
  double _shakeIntensity = 0.0; // 震动幅度 (Amplitude)
  double _shakeFrequency = 1.0; // 🌟 新增：震动频率/马达转速 (Frequency)，默认15

  bool _enableFlash = true;
  double _textBlurIntensity = 4.0;
  final GlobalKey _renderKey = GlobalKey();
  int _beatIntervalMs = 500; // 默认给个500，等加载JSON时会被覆盖

  // 🔤 字幕引擎参数
  String _currentTextStyle =
      'hero'; // 'standard' (普通底栏), 'hero' (居中大字), 'cards' (字卡散落)
  double _textYPosition = 0.8; // 0.0 为顶部，0.5 为屏幕正中，1.0 为贴底
  double _textSize = 24.0;
  String _fontFamily = 'sans-serif'; // 以后可以接入 Google Fonts

  bool _isExporting = false; // 🌟 控制是否处于导出模式
  double _exportProgress = 0.0; // 🌟 导出百分比 (0.0 到 1.0)

  List<dynamic> _beatData = []; // 存完整的 JSON 数据（包含 ms 和 energy）

  // 💥 震动与闪光控制器
  late AnimationController _vfxController;

  @override
  void initState() {
    super.initState();
    // 初始化特效控制器，时长很短，制造“爆发感”
    // _vfxController = AnimationController(vsync: this, duration: 250.ms);
    // 🌟 沙盒模式：让特效控制器无限极其快速地往复循环（模拟高频震动和闪烁）
    _vfxController = AnimationController(vsync: this, duration: 50.ms)
      ..repeat(reverse: true);
    // 🌟 极简解析：按 / 分割，并去掉两边的空格
    _lyricQueue = _rawUserInput
        .split('/')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (_lyricQueue.isNotEmpty) {
      _currentLyricText = _lyricQueue[0];
    }
    // 🚀 加载 JSON
    _loadBeatDataAndStart();
  }

  // 🧠 核心逻辑：加载 Librosa 导出的数据
  Future<void> _loadBeatDataAndStart() async {
    try {
      // 1. 加载包含能量信息的 JSON
      final String jsonString = await rootBundle.loadString(
        'assets/audio/sandal_leap_beats.json',
      );
      final Map<String, dynamic> data = json.decode(jsonString);
      // 我们这次不仅需要时间，还需要随时查阅“当前节拍的能量”
      _beatData = data['data'];

      // 🌟 1. 从 JSON 提取真·BPM
      double bpm = (data['bpm'] as num).toDouble();

      // 🌟 2. 算出一拍到底有多少毫秒 (60000 / BPM)
      _beatIntervalMs = (60000 / bpm).round(); // 保存到全局变量
      debugPrint("🎵 当前曲目 BPM: $bpm, 每拍间隔: ${_beatIntervalMs}ms");

      // 🌟 3. 让控制器的周期完美对齐一拍的长度，并无限循环！
      // 注意：这里去掉了 reverse: true，因为我们需要的是心跳那种“砰...砰...”的单向衰减
      _vfxController.duration = Duration(milliseconds: _beatIntervalMs);
      _vfxController.repeat();

      _initAudioAndListener();
      _togglePlay();
    } catch (e) {
      debugPrint("❌ JSON加载失败，采用无特效保底模式");
      _beatData = List.generate(
        widget.sections.length,
        (i) => {"ms": (i + 1) * 3500, "energy": 0.0},
      );
      _initAudioAndListener();
      _togglePlay();
    }
  }

  /*Future<void> _initAudioAndListener() async {
    // 计算全曲平均能量，用于触发特效的阈值
    double avgEnergy = _beatData.isEmpty
        ? 0
        : _beatData
                  .map((e) => (e['energy'] as num).toDouble())
                  .reduce((a, b) => a + b) /
              _beatData.length;

    int beatIndex = 0;

    _positionSubscription = _audioPlayer.onPositionChanged.listen((Duration p) {
      if (beatIndex < _beatData.length &&
          _currentIndex < widget.sections.length - 1) {
        if (p.inMilliseconds >= _beatData[beatIndex]['ms']) {
          double currentEnergy = (_beatData[beatIndex]['energy'] as num)
              .toDouble();

          // 🧠 核心导演逻辑：
          if (currentEnergy > avgEnergy * 1.2) {
            // 💥 高能爆发点！(比如重低音砸下)
            // 1. 触发一次全屏爆震特效
            _vfxController.forward(from: 0);
            // 2. 快速切图 (跳跃步长变小)
            beatIndex += 4;
            if (mounted) setState(() => _currentIndex++);
          } else {
            // 🍃 平缓过渡段
            beatIndex += 8;
            if (mounted) setState(() => _currentIndex++);
          }
        }
      }
    });

    // ... 播完重置逻辑略 ...
  }*/
  Future<void> _initAudioAndListener() async {
    // 🌟 修复 2：下一个要切图的节拍目标，直接设为第 8 拍！
    int nextSwitchBeat = 8;

    _positionSubscription = _audioPlayer.onPositionChanged.listen((Duration p) {
      int totalBeatsNeeded = widget.sections.length * 8;

      // 检查是否结束
      if (nextSwitchBeat >= totalBeatsNeeded) {
        _audioPlayer.stop();
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _currentIndex = 0;
            nextSwitchBeat = 8; // 🌟 播放完重置回第 8 拍
            if (_lyricQueue.isNotEmpty) {
              _currentLyricText = _lyricQueue[0]; // 🌟 歌词也重置回第一句
            }
          });
        }
        return;
      }

      if (nextSwitchBeat < _beatData.length &&
          _currentIndex < widget.sections.length - 1) {
        // 🌟 只在到达我们设定的目标拍 (8, 16, 24...) 时才切图！
        if (p.inMilliseconds >= _beatData[nextSwitchBeat]['ms']) {
          if (mounted) {
            setState(() {
              _currentIndex++;
              nextSwitchBeat += 8; // 🌟 安排下一次切图目标

              if (_lyricQueue.isNotEmpty) {
                int lyricIdx = _currentIndex % _lyricQueue.length;
                _currentLyricText = _lyricQueue[lyricIdx];
              }
            });
          }
        }
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentIndex = 0;
          _currentLyricIndex = 0;
          if (_lyricQueue.isNotEmpty)
            _currentLyricText = _lyricQueue[0]; // 兜底重置
        });
      }
    });
  }

  @override
  void dispose() {
    _vfxController.dispose(); // 别忘了释放内存
    _positionSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      // 这里的音乐路径要和 Python 脚本分析的那首一致
      await _audioPlayer.play(AssetSource('audio/sandal_leap.mp3'));
    }
    if (mounted) {
      setState(() {
        _isPlaying = !_isPlaying;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty)
      return const Scaffold(body: Center(child: Text('无内容')));

    final currentSection = widget.sections[_currentIndex];
    final subtitleLayer = SubtitleEffectLayer(
      text: _currentLyricText,
      effectType: _currentTextStyle,
      yPosition: _textYPosition,
      fontSize: _textSize,
      fontFamily: _fontFamily,
      blurIntensity: _textBlurIntensity,
      vfxController: _vfxController,
    );

    // 🌟 1. 定义纯净的视频内容层（包含震动、闪光、图片和字幕，但不含背景）
    // 🔪 核心修复：在这里套上 ClipRect，强行把所有溢出的放大和震动画面裁掉！
    Widget videoContent = ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 💥 底层图片（带震动和放大动画）
          AnimatedBuilder(
            animation: _vfxController,
            builder: (context, child) {
              final shakeOffset = Offset(
                _shakeIntensity *
                    math.sin(
                      _vfxController.value * math.pi * 2 * _shakeFrequency,
                    ),
                _shakeIntensity *
                    math.cos(
                      _vfxController.value * math.pi * 1.5 * _shakeFrequency,
                    ),
              );
              return Transform.translate(offset: shakeOffset, child: child);
            },
            child: AnimatedSwitcher(
              duration: 800.ms,
              child: _buildPureImageLayer(
                currentSection.photo.path,
                subtitleLayer,
              ),
            ),
          ),

          // 💥 白场闪光层
          AnimatedBuilder(
            animation: _vfxController,
            builder: (context, child) {
              final double decay = math
                  .pow(1 - _vfxController.value, 3)
                  .toDouble();
              final double flashAlpha = _enableFlash ? 0.3 * decay : 0.0;
              return IgnorePointer(
                child: Container(
                  color: Colors.white.withValues(alpha: flashAlpha),
                ),
              );
            },
          ),
        ],
      ),
    );

    // 🌟 2. 动态决定 取景器(RepaintBoundary) 放在哪
    Widget screenBody;
    if (widget.isHorizontal) {
      if (_isExporting) {
        // 🎬 导出模式：取景器被强行限制在 16:9 的尺寸里！导出的视频将是纯正的横屏，无黑边！
        screenBody = Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: RepaintBoundary(key: _renderKey, child: videoContent),
          ),
        );
      } else {
        // 👀 预览模式：全屏显示，底下垫一层模糊背景好看一点
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
      // 📱 竖屏模式：全屏都是视频
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
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
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
                              max: 3.0,
                              divisions: 30,
                              activeColor: Colors.pinkAccent,
                              onChanged: (val) {
                                setModalState(() => _shakeIntensity = val);
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
                              max: 50.0, // 最高一拍震 50 次，绝对够鬼畜了
                              divisions: 49,
                              activeColor: Colors.orangeAccent, // 换个颜色区分
                              onChanged: (val) {
                                setModalState(() => _shakeFrequency = val);
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
                        activeColor: Colors.pinkAccent,
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
                                setModalState(() => _textBlurIntensity = val);
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                value: 'strip',
                                child: Text('Strip (文字条)'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() => _currentTextStyle = val);
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
                                setModalState(() => _textYPosition = val);
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
                    ],
                  ),
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

  // ⏱️ 时光机器：手动驱动 UI 状态
  void _updateStateForFrame(int frameIndex) {
    // 假设我们导出 30 帧/秒，计算当前帧对应的是第几毫秒
    double currentTimeMs = (frameIndex / 24.0) * 1000.0;

    // 1. 驱动震动/闪光控制器 _vfxController (0.0 到 1.0 循环)
    double progressInBeat = (currentTimeMs % _beatIntervalMs) / _beatIntervalMs;
    _vfxController.value = progressInBeat;

    // 2. 寻找当前时间点对应的 节拍索引 (beatIndex)
    int targetBeatIndex = 0;
    for (int j = 0; j < _beatData.length; j++) {
      if (currentTimeMs >= _beatData[j]['ms']) {
        targetBeatIndex = j;
      } else {
        break; // 超过当前时间就停止寻找
      }
    }

    // 🌟 修复 3：前摇补偿。如果你觉得离线导出的卡点还是稍微早了一点点，
    // 可以把这个 beatOffset 设为 1 或 2，强行把算法识别的拍子往后推。
    // 默认我们先设为 0，因为前面的逻辑修复大概率已经解决问题了。
    int beatOffset = 0;
    int adjustedBeat = math.max(0, targetBeatIndex - beatOffset);

    // 3. 计算切图和切词（复刻你之前 beatIndex += 8 才切图的逻辑）
    int targetImageIndex = targetBeatIndex ~/ 8;

    // 防止超出照片总数
    if (targetImageIndex >= widget.sections.length) {
      targetImageIndex = widget.sections.length - 1;
    }

    // 4. 强制刷新页面状态
    setState(() {
      _currentIndex = targetImageIndex;
      if (_lyricQueue.isNotEmpty) {
        int lyricIdx = _currentIndex % _lyricQueue.length;
        _currentLyricText = _lyricQueue[lyricIdx];
      }

      // 这里的 _exportProgress 就是传给 UI 遮罩的进度条！
      // 它会在 _startExport 里被不断更新
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

      // 1. 提取资产音乐到手机沙盒
      final ByteData audioData = await rootBundle.load(
        'assets/audio/sandal_leap.mp3',
      );
      final File tempAudioFile = File('${docDir.path}/temp_audio.mp3');
      await tempAudioFile.writeAsBytes(audioData.buffer.asUint8List());

      // 2. 定义最终导出的 MP4 路径
      final String outputPath =
          "${docDir.path}/FINAL_STORY_${DateTime.now().millisecondsSinceEpoch}.mp4";

      // 3. 构造魔法咒语
      // -y : 强制覆盖同名文件
      // -framerate 30 : 以 30 帧速率读取图片
      String command =
          "-y -framerate 24 -start_number 0 -i $frameDirPath/frame_%05d.png -i ${tempAudioFile.path} -t $exactSeconds -vf scale=trunc(iw/2)*2:trunc(ih/2)*2 -c:v libx264 -pix_fmt yuv420p -c:a aac $outputPath";

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
