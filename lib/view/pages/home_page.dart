import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../../service/photo_service.dart';
import '../../models/entity/photo_entity.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 📸 用于轮播的照片列表
  List<PhotoEntity> _displayPhotos = [];
  int _currentPhotoIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 启动时加载照片数据
    _loadRecentPhotos();
  }

  @override
  void dispose() {
    // ⚠️ 极其重要：销毁页面时必须关闭定时器，防止后台内存泄露
    _timer?.cancel();
    super.dispose();
  }

  /// 1. 时间优先的背景照片加载逻辑
  Future<void> _loadRecentPhotos() async {
    final isar = PhotoService().isar;

    // 🔍 策略 A：先抓取最近拍摄的 100 张照片作为候选池
    // 假设 PhotoEntity 中的时间字段为 time（如果是 startTime 请对应修改）
    var recentCandidates = await isar.photoEntitys
        .where()
        .sortByTimestampDesc() // 🌟 关键：按时间从新到旧排序
        .limit(100) // 取最近的 100 张，基数够大才好选美的
        .findAll();

    // 🔍 策略 B：在候选池中应用“防天塌”过滤器
    var filtered = recentCandidates.where((p) {
      // 1. 物理尺寸过滤（排除截屏）
      if (p.width != null && p.height != null) {
        double ratio = p.width! / p.height!;
        if (ratio < 0.6 || ratio > 1.8) return false;
      }

      // 2. 标签过滤（排除文字、截图等）
      final forbiddenTags = {'Screen', 'Text', 'Document', '屏幕', '文字', '截图'};
      if (p.aiTags != null &&
          p.aiTags!.any((tag) => forbiddenTags.contains(tag))) {
        return false;
      }

      // 3. 质量初筛（如果有 AI 评分，优先选高分的）
      // 如果还没来得及 AI 分析，我们先保留它，以免初期没图显示
      if (p.isAiAnalyzed && (p.joyScore ?? 0) < 0.1) return false;

      return true;
    }).toList();

    // 🔍 策略 C：取过滤后的前 15 张（这 15 张就是最近且最美的）
    // 为了让 10 秒切换不那么单调，我们可以稍微打乱一下顺序
    final selection = filtered.take(15).toList();
    selection.shuffle();

    if (selection.isNotEmpty && mounted) {
      setState(() {
        _displayPhotos = selection;
      });
      _startBackgroundTimer();
    }
  }

  /// 2. 开启背景切换定时器
  void _startBackgroundTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_displayPhotos.isNotEmpty && mounted) {
        setState(() {
          _currentPhotoIndex = (_currentPhotoIndex + 1) % _displayPhotos.length;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.purple.shade50, Colors.white],
            stops: const [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildHeroCard(context), // 🌟 这里现在是动态的了
                const SizedBox(height: 32),
                _buildSectionTitle('发现'),
                const SizedBox(height: 16),
                _buildDiscoverList(),
                const SizedBox(height: 32),
                _buildSectionTitle('我的作品'),
                const SizedBox(height: 16),
                _buildWorksGrid(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- UI 构建方法 ---

  Widget _buildHeader() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 24,
          backgroundColor: Colors.pinkAccent,
          child: Icon(Icons.person, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'User_MoreSome,',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            Text(
              '欢迎使用智能影记！',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  /// 3. 核心改进：带动态淡入淡出背景的 Hero Card
  Widget _buildHeroCard(BuildContext context) {
    final hasPhotos = _displayPhotos.isNotEmpty;
    final currentPhoto = hasPhotos ? _displayPhotos[_currentPhotoIndex] : null;

    return Container(
      width: double.infinity,
      height: 220, // 稍微调高一点，气场更强
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.grey.shade300,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 🖼️ 背景层：使用 AnimatedSwitcher 实现平滑的淡入淡出效果
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 1200), // 1.2秒的平滑过渡
              child: hasPhotos
                  ? Image.file(
                      File(currentPhoto!.path), // 从本地路径读取文件
                      key: ValueKey(currentPhoto.id), // Key 变化时触发切换动画
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      // 💡 关键：添加暗色遮罩，确保白色的文字能看清
                      color: Colors.black.withOpacity(0.35),
                      colorBlendMode: BlendMode.darken,
                    )
                  : const Center(
                      child: Icon(
                        Icons.photo_album,
                        size: 80,
                        color: Colors.white70,
                      ),
                    ),
            ),
          ),

          // ✍️ 文本内容层
          Positioned(
            left: 20,
            bottom: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '我的相册',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '让 AI 生成你的专属故事',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // 跳转逻辑可以根据需要后续添加
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.95),
                    foregroundColor: Colors.purple.shade900,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                  ),
                  child: const Text(
                    '开始创作 >',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildDiscoverList() {
    return Column(
      children: [
        _buildDiscoverCard(
          title: '萌宠心动瞬间',
          subtitle: '检测到15张图片，建议生成视频\n2天前，济南',
          tag: '新回忆',
          bgColor: Colors.blue.shade50,
          tagColor: Colors.blue.shade200,
        ),
        const SizedBox(height: 16),
        _buildDiscoverCard(
          title: '我的2025年度总结',
          subtitle: '查看2025的高光时刻',
          tag: '待生成',
          bgColor: Colors.purple.shade50,
          tagColor: Colors.purple.shade200,
        ),
      ],
    );
  }

  Widget _buildDiscoverCard({
    required String title,
    required String subtitle,
    required String tag,
    required Color bgColor,
    required Color tagColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 80,
              height: 80,
              color: Colors.white54,
              child: const Icon(Icons.auto_awesome, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tagColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorksGrid() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.pink.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: Icon(Icons.image, color: Colors.pink, size: 40),
            ),
          ),
        ),
      ],
    );
  }
}
