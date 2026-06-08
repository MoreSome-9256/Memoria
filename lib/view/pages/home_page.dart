/// 首页，展示精选事件、最近照片和推荐入口。

import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui';
import '../../service/photo_service.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../../models/ai_theme.dart';
import '../../utils/media_type_helper.dart';
import '../../utils/tag_sanitizer.dart';
import '../widgets/media_thumbnail.dart';
import 'create_hub_page.dart';
import 'event_detail_page.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import '../../objectbox.g.dart';
import '../../storage/objectbox/objectbox_service.dart';

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

  // 💡 用于动态发现模块的卡片数据
  List<Map<String, dynamic>> _discoverCards = [];

  @override
  void initState() {
    super.initState();
    // 启动时加载照片数据
    _loadRecentPhotos();
    // 🌟 启动本地推荐引擎
    _generateDiscoverCards();
  }

  @override
  void dispose() {
    // ⚠️ 极其重要：销毁页面时必须关闭定时器，防止后台内存泄露
    _timer?.cancel();
    super.dispose();
  }

  // ==========================================
  // 📸 Hero Card 轮播逻辑 (保持不变)
  // ==========================================
  Future<void> _loadRecentPhotos() async {
    final _pb = ObjectBoxService().store.box<PhotoEntity>();
    final _q = _pb
        .query()
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    _q.limit = 100;
    var recentCandidates = _q.find();
    _q.close();

    var filtered = recentCandidates.where((p) {
      final ratio = p.width / p.height;
      if (ratio < 0.6 || ratio > 1.8) return false;
      final forbiddenTags = {'Screen', 'Text', 'Document', '屏幕', '文字', '截图'};
      if (p.aiTags != null &&
          p.aiTags!.any((tag) => forbiddenTags.contains(tag))) {
        return false;
      }
      if (p.isAiAnalyzed && (p.joyScore ?? 0) < 0.1) return false;
      return true;
    }).toList();

    final selection = filtered.take(15).toList()..shuffle();
    final reconciledSelection = await PhotoService().reconcileAccessiblePhotos(
      selection,
    );
    // ==========================================
    // 🌟 新增：修复缓存路径失效问题
    // 遍历选中的照片，用永远不变的 assetId 换取最新有效路径
    // ==========================================
    if (reconciledSelection.isNotEmpty && mounted) {
      setState(() {
        _displayPhotos = reconciledSelection;
      });
      _startBackgroundTimer();
    }
  }

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

  // ==========================================
  // 🧠 核心：本地智能回忆推荐引擎
  // ==========================================
  Future<void> _generateDiscoverCards() async {
    final now = DateTime.now();
    final List<Map<String, dynamic>> finalCards = [];
    const int maxCards = 2; // 页面最多展示 2 张卡片

    // 🥇 规则 1：时间策略（动态感知 年底/月底/往年今日）
    final timeCard = await _buildTimeRuleCard(now);
    if (timeCard != null) {
      finalCards.add(timeCard);
    }

    // 🥈 规则 2：内容画像策略（按照片数量降序）
    if (finalCards.length < maxCards) {
      final contentCards = await _buildContentRuleCards();
      for (var card in contentCards) {
        if (finalCards.length >= maxCards) break;
        finalCards.add(card);
      }
    }
    // ==========================================
    // 🌟 新增：修复发现卡片封面图路径失效问题
    // 只更新每张卡片第一张图（封面）的路径即可，节省性能
    // ==========================================
    // 🥉 规则 3：地点保底策略
    if (finalCards.length < maxCards) {
      final locationCards = await _buildLocationRuleCards();
      for (var card in locationCards) {
        if (finalCards.length >= maxCards) break;
        finalCards.add(card);
      }
    }

    final reconciledCards = <Map<String, dynamic>>[];
    for (final card in finalCards) {
      final photos =
          (card['photos'] as List<PhotoEntity>?) ?? const <PhotoEntity>[];
      final reconciledPhotos = await PhotoService().reconcileAccessiblePhotos(
        photos,
      );
      if (reconciledPhotos.isEmpty) {
        continue;
      }
      reconciledCards.add(<String, dynamic>{
        ...card,
        'photos': reconciledPhotos,
      });
      if (reconciledCards.length >= maxCards) {
        break;
      }
    }

    if (mounted) {
      setState(() {
        _discoverCards = reconciledCards;
      });
    }
  }

  Future<Map<String, dynamic>?> _buildTimeRuleCard(DateTime now) async {
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    // 1. 年度总结 (12.20 - 1.10)
    if ((now.month == 12 && now.day >= 20) ||
        (now.month == 1 && now.day <= 10)) {
      final targetYear = now.month == 12 ? now.year : now.year - 1;
      final start = DateTime(targetYear, 1, 1).millisecondsSinceEpoch;
      final end = DateTime(
        targetYear,
        12,
        31,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;
      final _tq = photoBox
          .query(PhotoEntity_.timestamp.between(start, end))
          .build();
      final photos = _tq.find();
      _tq.close();

      if (photos.length >= 10) {
        return _createCard(
          '我的 $targetYear 年度总结',
          '回眸这一年的 ${photos.length} 个瞬间',
          '年度大片',
          Colors.purple.shade50,
          Colors.purple.shade200,
          Icons.auto_awesome,
          photos.take(20).toList(),
        );
      }
    }

    // 2. 月度总结 (每月 25 号之后)
    if (now.day >= 25) {
      final start = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
      final end = DateTime(
        now.year,
        now.month + 1,
        0,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;
      final _tq = photoBox
          .query(PhotoEntity_.timestamp.between(start, end))
          .build();
      final photos = _tq.find();
      _tq.close();

      if (photos.length >= 8) {
        return _createCard(
          '${now.month}月碎片',
          '把 ${now.month} 月的温柔收集成册',
          '月度回顾',
          Colors.blue.shade50,
          Colors.blue.shade300,
          Icons.calendar_month,
          photos.take(20).toList(),
        );
      }
    }

    // 3. 往年今日
    List<PhotoEntity> historyPhotos = [];
    int historyYear = now.year;
    for (int i = 1; i <= 5; i++) {
      final start = DateTime(
        now.year - i,
        now.month,
        now.day,
      ).millisecondsSinceEpoch;
      final end = DateTime(
        now.year - i,
        now.month,
        now.day,
        23,
        59,
        59,
      ).millisecondsSinceEpoch;
      final _tq = photoBox
          .query(PhotoEntity_.timestamp.between(start, end))
          .build();
      final photos = _tq.find();
      _tq.close();
      if (photos.isNotEmpty) {
        historyPhotos.addAll(photos);
        if (historyYear == now.year) historyYear = now.year - i;
      }
    }
    if (historyPhotos.length >= 3) {
      return _createCard(
        '那年今日',
        '梦回 $historyYear 年的今天',
        '时光机',
        Colors.orange.shade50,
        Colors.orange.shade300,
        Icons.history,
        historyPhotos.take(20).toList(),
      );
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> _buildContentRuleCards() async {
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final _cq = photoBox
        .query()
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    _cq.limit = 500;
    final recentPhotos = _cq.find();
    _cq.close();
    List<PhotoEntity> pets = [], scenery = [], foods = [], happy = [];

    for (var p in recentPhotos) {
      final tagsStr = TagSanitizer.sanitizeVisualTags(
        p.aiTags ?? const <String>[],
      ).join(' ').toLowerCase();
      if (tagsStr.contains('猫') ||
          tagsStr.contains('狗') ||
          tagsStr.contains('宠物') ||
          tagsStr.contains('cat')) {
        pets.add(p);
      } else if (tagsStr.contains('风景') ||
          tagsStr.contains('山') ||
          tagsStr.contains('海') ||
          tagsStr.contains('自然') ||
          tagsStr.contains('出游'))
        scenery.add(p);
      else if (tagsStr.contains('美食') ||
          tagsStr.contains('饭') ||
          tagsStr.contains('菜') ||
          tagsStr.contains('餐厅') ||
          tagsStr.contains('甜点'))
        foods.add(p);
      if (p.joyScore != null && p.joyScore! > 0.6) happy.add(p);
    }

    List<Map<String, dynamic>> candidates = [];
    if (pets.length >= 5) {
      candidates.add(
        _createCard(
          '萌宠心动瞬间',
          '抓拍到 ${pets.length} 个可爱瞬间',
          '毛孩子',
          Colors.cyan.shade50,
          Colors.cyan.shade300,
          Icons.pets,
          pets.take(20).toList(),
        ),
      );
    }
    if (scenery.length >= 8) {
      candidates.add(
        _createCard(
          '出游回忆',
          '吹过的风和看过的风景',
          '在路上',
          Colors.teal.shade50,
          Colors.teal.shade300,
          Icons.landscape,
          scenery.take(20).toList(),
        ),
      );
    }
    if (foods.length >= 6) {
      candidates.add(
        _createCard(
          '我的美食日记',
          '唯有爱与美食不可辜负',
          '吃货必看',
          Colors.red.shade50,
          Colors.red.shade200,
          Icons.restaurant,
          foods.take(20).toList(),
        ),
      );
    }
    if (happy.length >= 5) {
      candidates.add(
        _createCard(
          '愉快回忆',
          '保存了 ${happy.length} 张灿烂笑脸',
          '治愈系',
          Colors.yellow.shade50,
          Colors.orange.shade300,
          Icons.sentiment_very_satisfied,
          happy.take(20).toList(),
        ),
      );
    }

    candidates.sort(
      (a, b) =>
          (b['photos'] as List).length.compareTo((a['photos'] as List).length),
    );
    return candidates;
  }

  Future<AuthUser?> _loadUser() async {
    try {
      // 🌟 直接呼叫底层的 AuthSession，不需要管队友的 _auth 变量叫啥
      final session = await Amplify.Auth.fetchAuthSession();
      if (!session.isSignedIn) {
        return null;
      }
      return await Amplify.Auth.getCurrentUser();
    } catch (_) {
      // 如果没登录或者没配好网络，安静地返回 null
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _buildLocationRuleCards() async {
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final _lq = photoBox
        .query()
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    _lq.limit = 1000;
    final recentPhotos = _lq.find();
    _lq.close();
    Map<String, List<PhotoEntity>> locationGroups = {};
    for (var p in recentPhotos) {
      final loc = p.city ?? p.province;
      if (loc != null && loc.isNotEmpty) {
        locationGroups.putIfAbsent(loc, () => []).add(p);
      }
    }

    List<Map<String, dynamic>> candidates = [];
    locationGroups.forEach((loc, photos) {
      if (photos.length >= 10) {
        candidates.add(
          _createCard(
            '$loc·漫游记',
            '在 $loc 留下的 ${photos.length} 个足迹',
            '城市印记',
            Colors.indigo.shade50,
            Colors.indigo.shade300,
            Icons.place,
            photos.take(20).toList(),
          ),
        );
      }
    });
    candidates.sort(
      (a, b) =>
          (b['photos'] as List).length.compareTo((a['photos'] as List).length),
    );
    return candidates;
  }

  Map<String, dynamic> _createCard(
    String title,
    String subtitle,
    String tag,
    Color bgColor,
    Color tagColor,
    IconData icon,
    List<PhotoEntity> photos,
  ) {
    return {
      'title': title,
      'subtitle': subtitle,
      'tag': tag,
      'bgColor': bgColor,
      'tagColor': tagColor,
      'icon': icon,
      'photos': photos,
    };
  }

  // ==========================================
  // 🎨 页面主 UI 结构 (完美复刻极光晕染与装饰 Logo)
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA), // 极浅的灰白色打底
      body: Stack(
        children: [
          // 1. 🌌 极光晕染背景层 (固定在底部)
          _buildAmbientBackground(),

          // 2. 📜 滚动内容层
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Stack(
                clipBehavior: Clip.none, // 允许装饰元素稍微溢出边界
                children: [
                  // 🌟 3. 装饰 Logo 层 (定位在 Hero 卡片后方偏右)
                  // 它被放在 Column 前面，所以会被 Hero 卡片遮挡一半
                  Positioned(
                    top: 20, // 调整到刚好在欢迎语下方、卡片后方
                    right: -20, // 稍微偏出屏幕右侧一点，更有设计感
                    child: Opacity(
                      opacity: 0.6, // 透明度，别让它抢了卡片的风头
                    ),
                  ),

                  // 4. 实际的 UI 内容层
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),
                      _buildHeroCard(context),
                      const SizedBox(height: 32),
                      _buildSectionTitle('发现'),
                      const SizedBox(height: 16),
                      _buildDiscoverList(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 🌌 极光晕染背景生成器
  Widget _buildAmbientBackground() {
    return Container(
      color: const Color(0xFFFAFAFA), // 浅灰白底色
      child: ImageFiltered(
        // 🌟 换成绝对安全的 ImageFiltered
        imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              left: -50,
              child: Container(
                width: 250,
                height: 250,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x88E0B0FF), // 稍微加深一点透明度
                ),
              ),
            ),
            Positioned(
              top: -20,
              right: -80,
              child: Container(
                width: 300,
                height: 300,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x7787CEEB), // 稍微加深一点天蓝色
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundColor: Colors.pinkAccent,
              child: Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🌟 核心修改：用 FutureBuilder 替换写死的用户名
                FutureBuilder<AuthUser?>(
                  future: _loadUser(), // 调用获取用户的方法
                  builder: (context, snapshot) {
                    // 提取用户名，如果还没加载出来或者没登录，就用个默认称呼兜底
                    final userName = snapshot.data?.username ?? '探索者';

                    return Text(
                      '$userName,',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    );
                  },
                ),
                const Text(
                  '欢迎使用智能影记！',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    final hasPhotos = _displayPhotos.isNotEmpty;
    final currentPhoto = hasPhotos ? _displayPhotos[_currentPhotoIndex] : null;

    return Container(
      width: double.infinity,
      height: 220,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.grey.shade300,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 1200),
              child: hasPhotos && currentPhoto != null
                  ? Stack(
                      key: ValueKey(currentPhoto.id),
                      fit: StackFit.expand,
                      children: [
                        MediaThumbnail(
                          path: currentPhoto.path,
                          assetId: currentPhoto.assetId,
                          kind: MediaTypeHelper.fromStorageValue(
                            currentPhoto.mediaKind,
                            path: currentPhoto.path,
                          ),
                          thumbnailBytes: currentPhoto.thumbnailBytes,
                          fit: BoxFit.cover,
                        ),
                        Container(color: Colors.black.withValues(alpha: 0.35)),
                      ],
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateHubPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.95),
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

  // 🌟 动态渲染发现列表
  Widget _buildDiscoverList() {
    if (_discoverCards.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(
              Icons.bubble_chart_outlined,
              size: 48,
              color: Colors.purple.shade100,
            ),
            const SizedBox(height: 12),
            const Text(
              '正在浩瀚相册里寻找美好回忆...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _discoverCards.map((cardData) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: _buildDiscoverCard(cardData),
        );
      }).toList(),
    );
  }

  // 🌟 动态构建单张发现卡片，并绑定点击跳转事件
  Widget _buildDiscoverCard(Map<String, dynamic> cardData) {
    final List<PhotoEntity> photos = cardData['photos'];
    final firstPhoto = photos.isNotEmpty ? photos.first : null;

    return GestureDetector(
      onTap: () async {
        if (photos.isEmpty) return;
        final reconciledPhotos = await PhotoService().reconcileAccessiblePhotos(
          photos,
        );
        if (!context.mounted || reconciledPhotos.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('这些照片已经在系统相册中删除，已从应用中移除。'),
              ),
            );
          }
          return;
        }

        // 1. 组装合法的 UI 模型 Photo 列表
        final mappedPhotos = reconciledPhotos
            .map(
              (p) => Photo(
                id: p.assetId,
                location: p.city ?? p.province ?? '未知地点',
                path: p.path,
                dateTaken: DateTime.fromMillisecondsSinceEpoch(p.timestamp),
                isSelected: true,
                mediaKind: p.mediaKind,
                thumbnailBytes: p.thumbnailBytes,
              ),
            )
            .toList();

        // 2. 推算时间范围
        final sortedDates = mappedPhotos.map((p) => p.dateTaken).toList()
          ..sort();

        // 3. 构造虚拟 AI 推荐主题
        final virtualTheme = AITheme(
          id: 'discover_theme',
          emoji: '✨',
          title: cardData['title'],
          subtitle: cardData['tag'],
        );

        // 4. 构造穿透底层的虚拟 Event
        final virtualEvent = Event(
          id: '-1',
          title: cardData['title'],
          season: '智能推荐',
          year: sortedDates.first.year,
          location: '精选回忆',
          startDate: sortedDates.first,
          endDate: sortedDates.last,
          photos: mappedPhotos,
          aiThemes: [virtualTheme],
        );

        // ==========================================
        // 🌟 5. 核心修改：先去详情页确认/筛选照片！
        // ==========================================
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EventDetailPage(
              event: virtualEvent, // 直接把虚拟事件丢给它
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardData['bgColor'],
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // 左侧缩略图（优先展示照片，没有则展示图标）
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 80,
                height: 80,
                color: Colors.white54,
                child: firstPhoto != null
                    ? MediaThumbnail(
                        path: firstPhoto.path,
                        assetId: firstPhoto.assetId,
                        kind: MediaTypeHelper.fromStorageValue(
                          firstPhoto.mediaKind,
                          path: firstPhoto.path,
                        ),
                        thumbnailBytes: firstPhoto.thumbnailBytes,
                        fit: BoxFit.cover,
                      )
                    : Icon(
                        cardData['icon'] as IconData,
                        color: Colors.grey.shade600,
                        size: 32,
                      ),
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
                      color: cardData['tagColor'],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      cardData['tag'],
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cardData['title'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cardData['subtitle'],
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
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
