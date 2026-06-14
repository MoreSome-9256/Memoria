/// 故事视频页面，负责视频预览和播放相关体验。

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import '../../models/entity/story_entity.dart';
import '../../models/vo/story_section.dart';
import '../../effects/subtitle_effect.dart';
import '../../effects/glitch_effect.dart';
import '../../effects/static_filters.dart';
import 'package:path_provider/path_provider.dart';
import 'export_manager.dart';
import 'publish_page.dart';
import '../../service/music_service.dart';
import '../../service/video_cache_service.dart';
import '../widgets/photo_image.dart';
import '../../models/entity/face_entity.dart';
import '../../objectbox.g.dart';
import '../../storage/objectbox/objectbox_service.dart';

class StoryVideoPage extends StatefulWidget {
  const StoryVideoPage({
    super.key,
    required this.title,
    required this.sections,
    this.isHorizontal = false,
    this.customMusicPath,
    this.dynamicBeatData,
    required this.subtitle,
    required this.targetPlatform,
    required this.onComplete,
    this.storyEntityId,
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

  final String title;
  final List<StorySection> sections;
  final bool isHorizontal;
  final String? customMusicPath;
  final Map<String, dynamic>? dynamicBeatData;
  final String subtitle;
  final String targetPlatform;
  final Function(String videoPath, Future<String>? aiCopy) onComplete;

  final int? storyEntityId;

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

  // 🌟 1. 声明一个本地的可变切片列表
  late List<StorySection> _localSections;

  String _currentLyricText = "";
  // 🎛️ VFX 控制台参数（从 widget 参数初始化，允许后续覆盖）
  double _shakeIntensity = 0.0;
  double _shakeFrequency = 1.0;
  double _glitchIntensity = 0.0;
  late AnimationController _continuousTimeController;
  bool _useVignette = false;
  bool _useGrain = false;
  bool _useCameraFrame = false;
  bool _useGlowRing = false;
  bool _useCloudBorder = false;
  bool _enableFlash = true;
  double _textBlurIntensity = 4.0;
  final GlobalKey _renderKey = GlobalKey();
  int _beatIntervalMs = 500;
  String _currentTextStyle = 'hero';
  double _textYPosition = 0.8;
  double _textSize = 24.0;
  final String _fontFamily = 'sans-serif'; // 以后可以接入 Google Fonts

  double _imageSaturation = 1.0; // 默认饱和度为 1.0
  String _imageFilterType = 'none'; // 默认无滤镜

  bool _isExporting = false; // 🌟 控制是否处于导出模式
  double _exportProgress = 0.0; // 🌟 导出百分比 (0.0 到 1.0)

  List<dynamic> _beatData = []; // 存完整的 JSON 数据（包含 ms 和 energy）

  // 💥 震动与闪光控制器
  late AnimationController _vfxController;

  @override
  void initState() {
    super.initState();
    // 🌟 2. 拷贝一份传进来的切片，让它变成可以修改的状态
    _localSections = List.from(widget.sections);

    // 从 widget 参数恢复 VFX 状态
    _shakeIntensity = widget.shakeIntensity;
    _shakeFrequency = widget.shakeFrequency;
    _glitchIntensity = widget.glitchIntensity;
    _useVignette = widget.useVignette;
    _useGrain = widget.useGrain;
    _useCameraFrame = widget.useCameraFrame;
    _useGlowRing = widget.useGlowRing;
    _useCloudBorder = widget.useCloudBorder;
    _enableFlash = widget.enableFlash;
    _textBlurIntensity = widget.textBlurIntensity;
    _currentTextStyle = widget.currentTextStyle;
    _textYPosition = widget.textYPosition;
    _textSize = widget.textSize;

    // 🌟 3. 启动人脸雷达：去数据库捞取人脸数据
    _loadFaceDataAsync();
    _vfxController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500), // 先随便给个值，后面会被覆盖
    );

    // 🌟 新增：启动一个 2 秒一循环的永动机，专门驱动常驻特效
    _continuousTimeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(); // 无限重复！

    // 主题推荐特效（仅在无已保存参数时生效）
    _autoConfigVFXAndSubtitles();

    // 先给一个最小可播放节拍，随后异步替换为本地分析结果。
    _beatData = [
      {"ms": 0, "energy": 0.1},
      {"ms": 500, "energy": 0.6},
      {"ms": 1000, "energy": 0.2},
    ];
    _beatIntervalMs = 500;
    unawaited(_loadBeatDataFromLocalAnalyzer());

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

  String? _resolvePlayableAudioPath() {
    final customPath = widget.customMusicPath?.trim();
    if (customPath != null &&
        customPath.isNotEmpty &&
        File(customPath).existsSync()) {
      return customPath;
    }
    return null;
  }

  int _clampSectionIndex(int index) {
    if (widget.sections.isEmpty) {
      return 0;
    }
    return index.clamp(0, widget.sections.length - 1).toInt();
  }

  // ==========================================
  // 🎯 人脸数据后台加载与热更新
  // ==========================================
  Future<void> _loadFaceDataAsync() async {
    try {
      // 拿到本地数据库实例
      final _faceBox = ObjectBoxService().store.box<FaceEntity>();

      for (int i = 0; i < _localSections.length; i++) {
        final photo = _localSections[i].photo;

        // 🚀 极速查询：根据 assetId 去 FaceEntity 表里捞出这张照片对应的所有人脸
        final _fq = _faceBox
            .query(FaceEntity_.assetId.equals(photo.id))
            .build();
        final faces = _fq.find();
        _fq.close();

        if (faces.isNotEmpty && mounted) {
          setState(() {
            // 🌟 核心魔法：用带有人脸数据的新 Photo 替换旧的。
            // 此时屏幕如果正在渲染这张照片，Alignment 会瞬间更新，镜头完美对准人脸！
            _localSections[i] = StorySection(
              text: _localSections[i].text,
              photo: photo.copyWith(faces: faces),
            );
          });
        }
      }
      debugPrint("🎯 所有人脸数据加载完毕，智能裁切已全面激活！");
    } catch (e) {
      debugPrint("⚠️ 加载人脸数据失败: $e");
    }
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
      final playableAudioPath = _resolvePlayableAudioPath();
      if (playableAudioPath != null) {
        audioPath = playableAudioPath;
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

  int _currentBeatIndexForPreview = -1; // 记录当前演到第几拍了

  Future<void> _initAudioAndListener() async {
    // ==========================================
    // 🌟 1. 安全降级：获取这首歌的真实时长（修复空指针崩溃！）
    // ==========================================
    try {
      final playableAudioPath = _resolvePlayableAudioPath();
      if (playableAudioPath != null) {
        await _audioPlayer.setSourceDeviceFile(playableAudioPath);
      } else {
        // 队友没生成音乐/网络失败时，也给监听器喂一口本地测试音乐！
        await _audioPlayer.setSourceAsset('audio/sandal_leap.mp3');
      }
    } catch (e) {
      debugPrint('⚠️ 音频源初始化失败，改用默认内置音乐: $e');
      await _audioPlayer.setSourceAsset('audio/sandal_leap.mp3');
    }

    // 给老旧安卓机一点缓冲时间，防止 getDuration 拿不到数据
    await Future.delayed(const Duration(milliseconds: 150));

    Duration? songDuration = await _audioPlayer.getDuration();
    // 🌟 修复：把获取到的时长存进我们刚才定义的全局变量里！
    _singleLoopMs = songDuration?.inMilliseconds ?? 15000;
    int singleLoopMs = _singleLoopMs;

    // ==========================================
    // 🌟 核心修复补丁：填补兜底节拍的“14秒真空期”！
    // ==========================================
    // 如果发现还是最初那 3 个孤零零的节拍（说明云端检测失败了）
    // 那我们就老老实实根据歌曲总时长，按 500ms 一下，铺满整首歌！
    if (_beatData.length <= 3) {
      List<Map<String, dynamic>> denseBeats = [];
      int fallbackInterval = 500; // 默认 120 BPM 的节奏
      for (int i = 0; i < singleLoopMs; i += fallbackInterval) {
        denseBeats.add({
          "ms": i,
          // 顺便模拟个动次打次的起伏：整秒能量高(0.6)，半秒能量低(0.2)
          "energy": (i % 1000 == 0) ? 0.6 : 0.2,
        });
      }
      _beatData = denseBeats;
      _beatIntervalMs = fallbackInterval;
      debugPrint("⚠️ 已触发本地动态兜底：根据音频时长生成 ${_beatData.length} 个密集节拍");
    }

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
        int targetImageIndex = _clampSectionIndex(
          targetBeatIndex ~/ beatsPerImage,
        );

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
      final playableAudioPath = _resolvePlayableAudioPath();
      if (playableAudioPath != null) {
        // 如果是用户手动导入的音乐，使用 DeviceFileSource
        await _audioPlayer.play(DeviceFileSource(playableAudioPath));
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

  // ==========================================
  // 🤖 智能导演：自动分配字幕样式与画面特效
  // ==========================================
  void _autoConfigVFXAndSubtitles() {
    // 若已有用户/已保存参数（非全部默认值），跳过自动配置
    final hasCustomParams =
        widget.shakeIntensity != 0.0 ||
        widget.shakeFrequency != 1.0 ||
        widget.glitchIntensity != 0.0 ||
        widget.textBlurIntensity != 4.0 ||
        widget.textSize != 24.0 ||
        widget.textYPosition != 0.8 ||
        widget.currentTextStyle != 'hero' ||
        widget.enableFlash != true ||
        widget.useVignette ||
        widget.useGrain ||
        widget.useCameraFrame ||
        widget.useGlowRing ||
        widget.useCloudBorder;
    if (hasCustomParams) return;

    // 1. 🎲 盲盒抽取：随机字幕样式
    final subtitleStyles = [
      'standard',
      'hero',
      'cards',
      'layered',
      'outline',
      'typewriter',
    ];
    _currentTextStyle =
        subtitleStyles[math.Random().nextInt(subtitleStyles.length)];

    // 2. 🎬 阅卷打分：根据视频风格选择【唯一】特效
    // 我们把标题和副标题拼起来，转成小写，方便检索
    final combinedText = "${widget.title} ${widget.subtitle}".toLowerCase();

    // 先把所有特效重置为 false（一票否决制）
    _useVignette = false;
    _useGrain = false;
    _useCameraFrame = false;
    _useGlowRing = false;
    _useCloudBorder = false;

    // 根据关键词计算各特效的契合度
    int vignetteScore = [
      '怀旧',
      '老照片',
      '记忆',
      '过去',
      '伤感',
      '历史',
      'nostalgic',
      'memory',
      'sad',
    ].where((w) => combinedText.contains(w)).length;
    int grainScore = [
      '胶片',
      '电影',
      '质感',
      '艺术',
      '故事',
      'film',
      'cinematic',
      'art',
      'story',
    ].where((w) => combinedText.contains(w)).length;
    int cameraScore = [
      '摄影',
      '记录',
      '旅途',
      '游记',
      '拍',
      'vlog',
      'travel',
      'photo',
      'trip',
    ].where((w) => combinedText.contains(w)).length;
    int glowScore = [
      '派对',
      '赛博',
      '夜晚',
      '科技',
      '炫酷',
      'party',
      'night',
      'cyber',
      'cool',
      'neon',
    ].where((w) => combinedText.contains(w)).length;
    int cloudScore = [
      '可爱',
      '治愈',
      '宝宝',
      '宠物',
      '温暖',
      '天空',
      'cute',
      'warm',
      'baby',
      'pet',
      'sweet',
    ].where((w) => combinedText.contains(w)).length;

    Map<String, int> scores = {
      'vignette': vignetteScore,
      'grain': grainScore,
      'camera': cameraScore,
      'glow': glowScore,
      'cloud': cloudScore,
    };

    String topVFX = 'camera'; // 兜底默认值
    int maxScore = 0;

    // 选出得分最高的特效
    scores.forEach((key, score) {
      if (score > maxScore) {
        maxScore = score;
        topVFX = key;
      }
    });

    // 如果标题完全没有命中关键词 (maxScore == 0)，就在适合大众的几个特效里随机抽一个
    if (maxScore == 0) {
      final fallbackVFX = ['vignette', 'grain', 'camera', 'cloud'];
      topVFX = fallbackVFX[math.Random().nextInt(fallbackVFX.length)];
    }

    // 正式激活当选的特效
    switch (topVFX) {
      case 'vignette':
        _useVignette = true;
        debugPrint("🎬 智能分配特效：复古暗角 (vignette)");
        break;
      case 'grain':
        _useGrain = true;
        debugPrint("🎬 智能分配特效：胶片噪点 (grain)");
        break;
      case 'camera':
        _useCameraFrame = true;
        debugPrint("🎬 智能分配特效：相机取景器 (camera)");
        break;
      case 'glow':
        _useGlowRing = true;
        debugPrint("🎬 智能分配特效：霓虹光圈 (glow)");
        break;
      case 'cloud':
        _useCloudBorder = true;
        debugPrint("🎬 智能分配特效：云朵边框 (cloud)");
        break;
    }
    debugPrint("🔤 智能分配字幕：$_currentTextStyle");

    // ==========================================
    // 3. 💥 智能白光闪烁 (Flash) 双重鉴权
    // ==========================================

    // 第一重：计算这首歌的“暴力指数”（平均能量和暴击率）
    double totalEnergy = 0.0;
    int highEnergyBeats = 0;

    if (_beatData.isNotEmpty) {
      for (var beat in _beatData) {
        double e = (beat['energy'] as num?)?.toDouble() ?? 0.0;
        totalEnergy += e;
        if (e > 0.3) highEnergyBeats++; // 记录出现过多少次重击
      }

      double avgEnergy = totalEnergy / _beatData.length;
      double highEnergyRatio = highEnergyBeats / _beatData.length;

      // 综合判断：如果得分偏高，说明是真·动感音乐
      bool isAudioViolent = (avgEnergy > 0.2) || (highEnergyRatio > 0.15);

      // 第二重：语义一票否决权
      bool isVisualViolent = glowScore > 0; // 只要带有赛博/派对/夜晚属性
      bool isVisualPeaceful = cloudScore > 0 || vignetteScore > 0; // 治愈/怀旧属性

      if (isVisualPeaceful) {
        // 如果主题是治愈或怀旧，哪怕配了动感音乐，也绝对不许瞎闪！
        _enableFlash = false;
        debugPrint("💥 智能闪光：强制关闭 (触发治愈/怀旧保护机制)");
      } else if (isVisualViolent || isAudioViolent) {
        // 如果主题是狂欢，或者音乐本身的重低音足够猛，那就闪起来！
        _enableFlash = true;
        debugPrint(
          "💥 智能闪光：开启 (Audio暴力指数: ${avgEnergy.toStringAsFixed(2)}, Visual: $glowScore)",
        );
      } else {
        // 兜底：既不猛烈也不治愈的普通照片，默认不开
        _enableFlash = false;
        debugPrint("💥 智能闪光：关闭 (日常平淡模式)");
      }
    } else {
      _enableFlash = false; // 没拿到音频数据就不开
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sections.isEmpty) {
      return const Scaffold(body: Center(child: Text('无内容')));
    }

    final currentSection = widget.sections[_clampSectionIndex(_currentIndex)];
    final mediaQuery = MediaQuery.of(context);

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
                      child: ColorGradingEffect(
                        // 🌟 给当前图片套上电影级调色
                        saturation: _imageSaturation,
                        filterType: _imageFilterType,
                        child: _buildPureImageLayer(
                          currentSection.photo,
                          subtitleLayer,
                        ),
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
            PhotoImage(photo: currentSection.photo, fit: BoxFit.cover),
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
      // 直接使用设备真实可用尺寸，避免导出时把画面压到 720x1280。
      screenBody = Center(
        child: SizedBox(
          width: mediaQuery.size.width,
          height: mediaQuery.size.height,
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
                  onPressed: _onVideoButtonPressed,
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

  // 🎬 视频按钮：检查缓存 → 分享，否则导出 → 分享
  Future<void> _onVideoButtonPressed() async {
    // 1. 计算当前参数对应的缓存 key
    final sectionsData = widget.sections.map((s) {
      return {
        'photo': {'path': s.photo.path},
        'text': s.text,
      };
    }).toList();
    final dynamicBeatData = _beatData.isNotEmpty
        ? {'data': _beatData, 'bpm': 60000 / _beatIntervalMs}
        : null;
    final cacheKey = VideoCacheService.instance.buildVideoCacheKey(
      title: widget.title,
      subtitle: widget.subtitle,
      sections: sectionsData,
      customMusicPath: widget.customMusicPath,
      dynamicBeatData: dynamicBeatData,
      targetPlatform: widget.targetPlatform,
      isHorizontal: widget.isHorizontal,
      currentTextStyle: _currentTextStyle,
      textYPosition: _textYPosition,
      textSize: _textSize,
      textBlurIntensity: _textBlurIntensity,
      shakeIntensity: _shakeIntensity,
      shakeFrequency: _shakeFrequency,
      glitchIntensity: _glitchIntensity,
      enableFlash: _enableFlash,
      useVignette: _useVignette,
      useGrain: _useGrain,
      useCameraFrame: _useCameraFrame,
      useGlowRing: _useGlowRing,
      useCloudBorder: _useCloudBorder,
    );

    // 2. 检查已有视频（entity + cache + export 目录）
    String? existingPath;
    if (widget.storyEntityId != null) {
      try {
        final storyBox = ObjectBoxService().store.box<StoryEntity>();
        final story = storyBox.get(widget.storyEntityId!);
        if (story?.cachedVideoKey == cacheKey &&
            story?.cachedVideoPath != null &&
            await File(story!.cachedVideoPath!).exists()) {
          existingPath = story.cachedVideoPath;
        }
      } catch (_) {}
    }
    existingPath ??= await VideoCacheService.instance.getCachedVideoPath(
      sections: sectionsData,
      cacheKey: cacheKey,
    );

    if (existingPath != null && await File(existingPath).exists()) {
      // 3a. 缓存命中 → 跳转发布页面（复用已有视频 + 文案）
      if (!mounted) return;
      final path = existingPath;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PublishPage(
            title: widget.title,
            subtitle: widget.subtitle,
            captions: widget.sections.map((s) => s.text).toList(),
            targetPlatform: widget.targetPlatform,
            exportedVideoPath: path,
          ),
        ),
      );
      return;
    }

    // 3b. 无缓存 → 导出，完成后弹出发布页面（含文案 + 4按钮）
    ExportManager.instance.startBackgroundExport(
      context: context,
      title: widget.title,
      subtitle: widget.subtitle,
      sections: widget.sections,
      customMusicPath: widget.customMusicPath,
      dynamicBeatData: dynamicBeatData,
      targetPlatform: widget.targetPlatform,
      isHorizontal: widget.isHorizontal,
      storyEntityId: widget.storyEntityId,
      currentTextStyle: _currentTextStyle,
      textYPosition: _textYPosition,
      textSize: _textSize,
      textBlurIntensity: _textBlurIntensity,
      shakeIntensity: _shakeIntensity,
      shakeFrequency: _shakeFrequency,
      glitchIntensity: _glitchIntensity,
      enableFlash: _enableFlash,
      useVignette: _useVignette,
      useGrain: _useGrain,
      useCameraFrame: _useCameraFrame,
      useGlowRing: _useGlowRing,
      useCloudBorder: _useCloudBorder,
      // 🌟 新增：把用户当前调好的滤镜发往后台！
      imageSaturation: _imageSaturation,
      imageFilterType: _imageFilterType,
    );
    Navigator.pop(context);
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
                              const Divider(color: Colors.white24, height: 32),
                              const Text(
                                '🎨 色彩与滤镜',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // 🌟 新增：滤镜风格下拉框
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '影像风格',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  DropdownButton<String>(
                                    value: _imageFilterType,
                                    dropdownColor: Colors.grey[900],
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    underline: const SizedBox(),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'none',
                                        child: Text('原画 (Original)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'cinematic',
                                        child: Text('青橙电影 (Cinematic)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'vintage',
                                        child: Text('复古胶片 (Vintage)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'cyberpunk',
                                        child: Text('赛博霓虹 (Cyber)'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'bw',
                                        child: Text('黑白往事 (B&W)'),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setModalState(
                                          () => _imageFilterType = val,
                                        );
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),

                              // 🌟 新增：色相饱和度滑块
                              Row(
                                children: [
                                  const Text(
                                    '色彩饱和',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: _imageSaturation,
                                      min: 0.0, // 0 = 纯灰
                                      max: 2.0, // 2 = 色彩爆炸
                                      divisions: 20,
                                      activeColor: Colors.orangeAccent,
                                      onChanged: (val) {
                                        setModalState(
                                          () => _imageSaturation = val,
                                        );
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),

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
                              Material(
                                color: Colors.transparent,
                                child: SwitchListTile(
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
                              const Divider(color: Colors.white24),
                              Material(
                                color: Colors.transparent,
                                child: CheckboxListTile(
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
                              ),
                              Material(
                                color: Colors.transparent,
                                child: CheckboxListTile(
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
                              ),
                              Material(
                                color: Colors.transparent,
                                child: CheckboxListTile(
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
                              ),
                              Material(
                                color: Colors.transparent,
                                child: CheckboxListTile(
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
                              ),
                              Material(
                                color: Colors.transparent,
                                child: CheckboxListTile(
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

  // ==========================================
  // 🎯 智能裁切：基于面积加权的人脸重心计算
  // ==========================================
  Alignment _calculateFaceAlignment(dynamic photo) {
    // ⚠️ 提取数据：这里假设 photo 有 width, height 和关联的人脸列表
    // 根据你的 Isar 模型，如果 photo.faces 是 IsarLinks，你可能需要 photo.faces.toList()
    final int imageWidth = photo.width ?? 0;
    final int imageHeight = photo.height ?? 0;
    final List<dynamic> faces = photo.faces?.toList() ?? [];

    // 1. 如果没有脸、或者图片宽高无效，直接老老实实居中
    if (faces.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
      return Alignment.center;
    }

    double totalWeight = 0.0;
    double weightedX = 0.0;
    double weightedY = 0.0;

    // 2. 遍历所有检测到的人脸
    for (var face in faces) {
      // 算出这张脸的绝对中心坐标 (像素)
      double faceCenterX = face.left + (face.width / 2);
      double faceCenterY = face.top + (face.height / 2);

      // 🌟 核心魔法：使用人脸的面积作为权重 (Area Weighting)
      // 脸越大，对最终重心的牵引力就越强！
      double weight = face.area;
      if (weight <= 0) continue;

      weightedX += faceCenterX * weight;
      weightedY += faceCenterY * weight;
      totalWeight += weight;
    }

    // 防御性判断：如果全是无效面积，退回居中
    if (totalWeight <= 0) {
      return Alignment.center;
    }

    // 3. 计算加权后的“绝对视觉重心”（像素坐标）
    double avgX = weightedX / totalWeight;
    double avgY = weightedY / totalWeight;

    // 4. 归一化：把像素坐标转变成 0.0 ~ 1.0 的相对比例
    double normalizedX = avgX / imageWidth;
    double normalizedY = avgY / imageHeight;

    // 5. 坐标系映射：Flutter 的 Alignment 要求是 -1.0 (左/上) 到 1.0 (右/下)
    double alignX = (normalizedX * 2) - 1.0;
    double alignY = (normalizedY * 2) - 1.0;

    debugPrint(
      "🎯 智能裁切：检测到 ${faces.length} 张脸，加权重心 Alignment(${alignX.toStringAsFixed(2)}, ${alignY.toStringAsFixed(2)})",
    );

    // 钳制在合法范围内 (-1.0 到 1.0)，防止把图片推出黑边
    return Alignment(alignX.clamp(-1.0, 1.0), alignY.clamp(-1.0, 1.0));
  }

  // 🎬 专门给取景器提供纯净画面的层（无黑边）
  // 🌟 修改点 1：把参数里的 String imagePath 改成 var photo (或者 PhotoEntity photo)
  Widget _buildPureImageLayer(var photo, Widget subtitle) {
    // 🌟 修改点 2：从传进来的 photo 对象里提取真正的路径
    // 🎯 呼叫智能裁切雷达
    final Alignment smartAlignment = _calculateFaceAlignment(photo);

    return Stack(
      key: ValueKey<String>(photo.path), // 🌟 这里也要改成 photo.path
      fit: StackFit.expand,
      children: [
        TweenAnimationBuilder(
          tween: Tween<double>(begin: 1.0, end: 1.15),
          duration: const Duration(seconds: 5),
          builder: (context, scale, child) {
            return Transform.scale(
              scale: scale,
              child: PhotoImage(
                photo: photo,
                fit: BoxFit.cover,
                alignment: smartAlignment,
                width: double.infinity,
                height: double.infinity,
                enableSmartCache: false,
              ),
            );
          },
        ),
        subtitle,
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
