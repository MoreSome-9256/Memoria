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
  double _shakeIntensity = 0.8; // 震动幅度 (Amplitude)
  double _shakeFrequency = 15.0; // 🌟 新增：震动频率/马达转速 (Frequency)，默认15

  bool _enableFlash = true;
  double _textBlurIntensity = 4.0;

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
      int beatIntervalMs = (60000 / bpm).round();
      debugPrint("🎵 当前曲目 BPM: $bpm, 每拍间隔: ${beatIntervalMs}ms");

      // 🌟 3. 让控制器的周期完美对齐一拍的长度，并无限循环！
      // 注意：这里去掉了 reverse: true，因为我们需要的是心跳那种“砰...砰...”的单向衰减
      _vfxController.duration = Duration(milliseconds: beatIntervalMs);
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
    int beatIndex = 0;

    _positionSubscription = _audioPlayer.onPositionChanged.listen((Duration p) {
      if (beatIndex < _beatData.length &&
          _currentIndex < widget.sections.length - 1) {
        if (p.inMilliseconds >= _beatData[beatIndex]['ms']) {
          // 🛑 关掉情绪绑定，变成最原始的固定节拍切图 (测试用)
          beatIndex += 8;
          if (mounted) setState(() => _currentIndex++);
          // 🌟 2. 核心修正：无论高能还是平缓，只要触发了节点，图和词就一起切！
          if (mounted) {
            setState(() {
              _currentIndex++; // 切图

              // 切词逻辑：利用取模运算 (%) 让歌词循环播放，防止数组越界报错
              if (_lyricQueue.isNotEmpty) {
                // 如果你想让歌词停在最后一句，就用 min(_currentIndex, _lyricQueue.length - 1)
                // 这里用循环是为了方便你一直测试看效果
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 💥 1. 画面底层：带摄像机震动 (Camera Shake) 的图像层
          AnimatedBuilder(
            animation: _vfxController,
            builder: (context, child) {
              // 正弦波衰减震动算法
              // 随着 controller 从 0 到 1，震动幅度迅速衰减
              /*final shakeOffset = _vfxController.isAnimating
                  ? Offset(
                      (_shakeIntensity *
                          (1 - _vfxController.value) *
                          (DateTime.now().millisecond % 2 == 0 ? 1 : -1)),
                      (_shakeIntensity *
                          (1 - _vfxController.value) *
                          (DateTime.now().millisecond % 3 == 0 ? 1 : -1)),
                    )
                  : Offset.zero;*/
              // 🌟 核心算法升级：加入 _shakeFrequency 控制正弦波的密集度
              // _vfxController.value 在一个 BPM 周期内从 0 走到 1
              // 乘以 _shakeFrequency 意味着在这个周期内，正弦波会完整往复震动这么多次！
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
              child: _buildAdaptiveImageLayer(
                currentSection.photo.path,
              ), // 你的自适应画幅层
            ),
          ),

          // 💥 2. 白场闪光层 (Flash Overlay)
          // 只有在 _vfxController 触发时才瞬间变白，然后迅速隐去
          AnimatedBuilder(
            animation: _vfxController,
            builder: (context, child) {
              /*final double flashAlpha =
                  (_enableFlash && _vfxController.isAnimating)
                  ? 0.8 * (1 - _vfxController.value)
                  : 0.0;*/
              // 刚打拍子时是 1.0 (最亮)，然后极其迅速地掉到 0 (透明)，不会一直糊在脸上
              final double decay = math
                  .pow(1 - _vfxController.value, 3)
                  .toDouble();

              // 最高透明度设为 0.3 就够了，太白了费眼
              final double flashAlpha = _enableFlash ? 0.3 * decay : 0.0;

              return IgnorePointer(
                child: Container(
                  color: Colors.white.withValues(alpha: flashAlpha),
                ),
              );
            },
          ),

          // ⬛ 3. 底部字幕遮罩
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 250,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 🔤 4. Kinetic Typography (动态排版字幕)
          Positioned(
            bottom: 120,
            left: 24,
            right: 24,
            // 🌟 换成真实的动态歌词！
            child: _currentLyricText.isEmpty
                ? const SizedBox.shrink() // 兜底：如果是空行就不渲染
                : Text(
                        _currentLyricText, // 🌟 换成了咱们自己切的歌词变量！
                        key: ValueKey<String>(
                          _currentLyricText,
                        ), // 🌟 关键：把 Key 绑在歌词上，歌词一变，动画就重置！
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          height: 1.5,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              color: Colors.black87,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      )
                      .animate() // 🌟 魔法开始
                      .fade(duration: 400.ms, curve: Curves.easeOut) // 淡入
                      .slideY(
                        begin: 0.5,
                        end: 0,
                        duration: 400.ms,
                        curve: Curves.easeOutBack,
                      ) // 从下往上弹入
                      .shimmer(
                        duration: 1000.ms,
                        color: Colors.white70,
                      ) // 表面扫过一道高光（极度有质感！）
                      .blurXY(
                        begin: _textBlurIntensity, // 换成变量
                        end: 0,
                        duration: 300.ms,
                      ), // 带有焦外模糊逐渐变清晰的电影感
          ),

          // ⏯️ 5. 控制层
          _buildControls(),
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
  // 🎬 核心特效：根据长宽比自适应的视觉层
  Widget _buildAdaptiveImageLayer(String imagePath) {
    final file = File(imagePath);
    if (!file.existsSync()) {
      return Container(
        key: ValueKey<String>(imagePath),
        color: Colors.grey[900],
      );
    }

    // 基础的 Ken Burns 放大动画
    Widget kenBurnsAnimation = TweenAnimationBuilder(
      tween: Tween<double>(begin: 1.0, end: 1.15),
      duration: const Duration(seconds: 5),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        );
      },
    );

    // 🌟 竖屏模式：直接铺满全屏，极度沉浸
    if (!widget.isHorizontal) {
      return SizedBox.expand(
        key: ValueKey<String>(imagePath), // 必须加 Key，保证 AnimatedSwitcher 生效
        child: kenBurnsAnimation,
      );
    }
    // 🌟 横屏模式：16:9 居中显示，上下填充带有高级毛玻璃模糊的背景图
    else {
      return Stack(
        key: ValueKey<String>(imagePath), // 必须加在最外层
        fit: StackFit.expand,
        children: [
          // 1. 底层模糊背景
          Image.file(file, fit: BoxFit.cover),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              color: Colors.black.withValues(alpha: 0.6),
            ), // 加一层黑纱，避免背景太亮抢戏
          ),
          // 2. 核心 16:9 画幅层
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRect(
                // 裁剪掉放大的部分，不让它溢出 16:9 的框
                child: kenBurnsAnimation,
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
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
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
                ],
              ),
            );
          },
        );
      },
    );
  }
}
