import 'package:flutter/material.dart';
import 'dart:io'; // 🌟 加上这行，File 类就活过来了！
import 'package:isar/isar.dart';
import '../../data/tag_dictionary.dart';
import '../../models/entity/photo_entity.dart';
import '../../service/photo_service.dart';
import '../../service/semantic_matching_service.dart';
import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../../models/ai_theme.dart';
import 'config_page.dart';
import 'dart:ui';
// 如果有封装好的图片显示组件可以替换这里的 Image.file

class CreatePage extends StatefulWidget {
  const CreatePage({super.key});

  @override
  State<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends State<CreatePage> {
  final TextEditingController _searchController = TextEditingController();
  final SemanticMatchingService _semanticService = SemanticMatchingService();
  bool _isSearching = false;
  static const double _minSemanticSimilarity = 0.22;
  static const int _maxSemanticResults = 300;

  // 搜索结果
  List<PhotoEntity> _searchResults = [];
  // 用户勾选的照片集合（存 ID）
  final Set<int> _selectedPhotoIds = {};

  List<String> get _candidateLabels {
    final input = _searchController.text.trim();
    if (input.isEmpty) {
      return memoriaMasterLabels.take(6).toList(growable: false);
    }

    final normalizedInput = input.toLowerCase();
    final matched = memoriaMasterLabels
        .where(
          (label) =>
              label.toLowerCase().contains(normalizedInput) ||
              normalizedInput.contains(label.toLowerCase()),
        )
        .toList(growable: false);

    if (matched.isNotEmpty) {
      return matched.take(6).toList(growable: false);
    }

    return memoriaMasterLabels.take(6).toList(growable: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 🧠 语义检索版：本地实体截流 (时间/地点) + Text Embedding 余弦排序
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchResults.clear();
      _selectedPhotoIds.clear();
    });

    final isar = PhotoService().isar;

    // 1. 获取所有已分析的照片
    final allAnalyzedPhotos = await isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .sortByTimestampDesc()
        .findAll();

    if (allAnalyzedPhotos.isEmpty) {
      setState(() => _isSearching = false);
      return;
    }

    // ==========================================
    // 💡 阶段一：建立地点知识库（用于 NER）
    // ==========================================
    final Set<String> allLocations = {};

    for (var photo in allAnalyzedPhotos) {
      final rawLocs = [photo.province, photo.city, photo.district];
      for (var loc in rawLocs) {
        if (loc == null || loc.trim().isEmpty) continue;

        final cleanLoc = loc.trim();
        allLocations.add(cleanLoc); // 保留完整版，例如 "济南市"

        // 🌟 终极暴力脱水：无视位置，只要带有这些字，全部剔除！
        final strippedLoc = cleanLoc
            .replaceAll(RegExp(r'[省市自治区县盟旗]'), '')
            .trim();
        if (strippedLoc.length >= 2) {
          allLocations.add(strippedLoc); // 将 "济南" 也加入字典
        }
      }
    }

    // ==========================================
    // 💡 阶段二：本地命名实体识别 (NER)
    // ==========================================
    String remainingQuery = query.trim();
    String? targetYear;
    List<String> matchedLocsInQuery = [];

    // 1. 提取年份 (正则匹配 20xx 年)
    final yearMatch = RegExp(r'(20\d{2})').firstMatch(remainingQuery);
    if (yearMatch != null) {
      targetYear = yearMatch.group(0);
      remainingQuery = remainingQuery.replaceAll(targetYear!, '');
    }

    // 2. 提取地点 (按长度降序，优先匹配长地名防止截断)
    final sortedLocations = allLocations.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (var loc in sortedLocations) {
      if (remainingQuery.contains(loc)) {
        matchedLocsInQuery.add(loc);
        // 🌟 从查询词中精准抠掉地点
        remainingQuery = remainingQuery.replaceAll(loc, '');
      }
    }

    // 3. 擦除无意义的停止词（Stop Words），防止残留“的”、“在”导致 AI 疑惑
    remainingQuery = remainingQuery.replaceAll(RegExp(r'[的在]'), '').trim();

    print(
      "🔍 [意图分析] 提取年份: ${targetYear ?? '无'}, 提取地点: $matchedLocsInQuery, 剩余需AI解析的语义词: '${remainingQuery.isEmpty ? '无' : remainingQuery}'",
    );

    // ==========================================
    // 💡 阶段三：先做时空过滤，缩小候选集合
    // ==========================================
    final List<PhotoEntity> candidates = [];

    for (var photo in allAnalyzedPhotos) {
      if (photo.isProbablyScreenshot) {
        continue;
      }

      bool isMatch = true; // 采取 AND 淘汰制：必须同时满足被提取出的条件

      // 判定 A: 时间拦截
      if (targetYear != null) {
        final photoYear = DateTime.fromMillisecondsSinceEpoch(
          photo.timestamp,
        ).year.toString();
        if (photoYear != targetYear) isMatch = false;
      }

      // 判定 B: 地点拦截
      if (isMatch && matchedLocsInQuery.isNotEmpty) {
        final locationText =
            '${photo.province ?? ''} ${photo.city ?? ''} ${photo.district ?? ''}';
        bool hitLoc = false;
        for (var loc in matchedLocsInQuery) {
          if (locationText.contains(loc)) {
            hitLoc = true;
            break;
          }
        }
        if (!hitLoc) isMatch = false;
      }

      if (isMatch) {
        candidates.add(photo);
      }
    }

    if (candidates.isEmpty) {
      print('🎯 [综合过滤] 时空过滤后候选为 0');
      if (mounted) {
        setState(() {
          _searchResults = const <PhotoEntity>[];
          _isSearching = false;
        });
      }
      return;
    }

    // ==========================================
    // 💡 阶段四：文本向量检索（语义排序）
    // ==========================================
    final semanticQuery = remainingQuery.isNotEmpty ? remainingQuery : query.trim();
    final semanticPrompt = _resolveSemanticPrompt(semanticQuery);
    List<PhotoEntity> matchedPhotos;

    // 纯时空查询：直接返回候选集合（已是时间倒序）
    if (semanticQuery.replaceAll(RegExp(r'\s+'), '').isEmpty) {
      matchedPhotos = List<PhotoEntity>.from(candidates);
    } else {
      try {
        await _semanticService.warmUp();
        final textVector = await _semanticService.embedText(semanticPrompt);

        final scored = <MapEntry<PhotoEntity, double>>[];
        for (final photo in candidates) {
          final imageEmbedding = photo.imageEmbedding;
          if (imageEmbedding == null || imageEmbedding.isEmpty) {
            continue;
          }
          if (imageEmbedding.length != textVector.length) {
            continue;
          }
          final score = _semanticService.calculateSimilarity(
            textVector,
            imageEmbedding,
          );
          scored.add(MapEntry<PhotoEntity, double>(photo, score));
        }

        if (scored.isEmpty) {
          print('⚠️ [语义检索] 候选集中没有可用图像向量，返回 0 条');
          matchedPhotos = const <PhotoEntity>[];
        } else {
          scored.sort((a, b) => b.value.compareTo(a.value));

          final filtered = scored
              .where((entry) => entry.value >= _minSemanticSimilarity)
              .take(_maxSemanticResults)
              .toList(growable: false);

          matchedPhotos = filtered.map((e) => e.key).toList(growable: false);

          if (filtered.isEmpty) {
            print(
              '⚠️ [语义检索] 全部低于阈值 $_minSemanticSimilarity，返回 0 条，避免弱相关噪声',
            );
          }

          final preview = scored
              .take(5)
              .map((e) => '${e.value.toStringAsFixed(4)}#${e.key.id}')
              .join(', ');
          print(
            '🧠 [语义检索] raw="$semanticQuery" prompt="$semanticPrompt" '
            'top5=[$preview] threshold=$_minSemanticSimilarity '
            'filtered=${filtered.length}/${scored.length}',
          );
        }
      } catch (e) {
        print('⚠️ 语义检索失败，降级为时空过滤结果: $e');
        matchedPhotos = List<PhotoEntity>.from(candidates);
      }
    }

    print("🎯 [综合过滤] 最终命中照片数: ${matchedPhotos.length}");

    if (mounted) {
      setState(() {
        _searchResults = matchedPhotos;
        _isSearching = false;
      });
    }
  }

  String _resolveSemanticPrompt(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final mapped = memoriaMasterTaxonomy[trimmed];
    if (mapped != null && mapped.isNotEmpty) {
      return mapped;
    }

    // 优先匹配推荐词，避免把中文短语直接喂给英文主训练的 Text Encoder。
    for (final entry in memoriaMasterTaxonomy.entries) {
      if (trimmed.contains(entry.key) || entry.key.contains(trimmed)) {
        return entry.value;
      }
    }

    return trimmed;
  }

  // 👆 勾选/取消勾选照片
  void _toggleSelection(int photoId) {
    setState(() {
      if (_selectedPhotoIds.contains(photoId)) {
        _selectedPhotoIds.remove(photoId);
      } else {
        _selectedPhotoIds.add(photoId);
      }
    });
  }
  // 🌟 新增：全选
  void _selectAll() {
    setState(() {
      _selectedPhotoIds.addAll(_searchResults.map((p) => p.id));
    });
  }

  // 🌟 新增：全不选
  void _deselectAll() {
    setState(() {
      _selectedPhotoIds.clear();
    });
  }

  // 🚀 生成故事（跳转到配置页）
  void _generateStory() {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一张照片哦')));
      return;
    }

    // 获取选中的真实照片实体
    final selectedEntities = _searchResults
        .where((p) => _selectedPhotoIds.contains(p.id))
        .toList();

    // 🌟 1. 组装 Photo 列表 (严格适配你的 Photo 类)
    final mappedPhotos = selectedEntities.map((p) {
      return Photo(
        id: p.assetId, // 使用 assetId 确保和底层对应
        location: p.city ?? p.province ?? '未知地点',
        path: p.path,
        dateTaken: DateTime.fromMillisecondsSinceEpoch(p.timestamp),
        tags: p.aiTags ?? [],
        isSelected: true,
      );
    }).toList();

    // 🌟 2. 动态计算时间范围 (提取选出照片的最早和最晚时间)
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    if (mappedPhotos.isNotEmpty) {
      final sortedDates = mappedPhotos.map((p) => p.dateTaken).toList()..sort();
      startDate = sortedDates.first;
      endDate = sortedDates.last;
    }

    final themeTitle = _searchController.text.trim().isNotEmpty
        ? _searchController.text.trim()
        : '我的专属回忆';

    // 🌟 3. 构造虚拟的 AI 推荐主题 (严格适配 AITheme)
    final virtualTheme = AITheme(
      id: 'manual_theme',
      emoji: '✨',
      title: themeTitle,
      subtitle: '自定义回忆',
    );

    // 🌟 4. 构造虚拟 Event (严格适配你的 Event 类构造函数)
    final virtualEvent = Event(
      id: '-1',
      title: themeTitle,
      season: '精选', // 既然是手动跨时空选的，就叫精选
      year: startDate.year,
      location: '多地精选',
      startDate: startDate,
      endDate: endDate,
      photos: mappedPhotos,
      aiThemes: [virtualTheme], // 直接把刚刚建好的主题塞进去
    );

    // 🌟 5. 携带合规的虚拟数据，正式起飞前往配置页！
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConfigPage(
          event: virtualEvent,
          selectedPhotos: virtualEvent.photos,
          selectedTheme: virtualTheme,
        ),
      ),
    );
  }

  // ==========================================
  // 🎨 页面主 UI 结构
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          // 🌌 1. 极光晕染背景层
          _buildAmbientBackground(),

          // 📜 2. 主体滚动内容层
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部返回按钮
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.black87,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),

                // 搜索完成后的头部信息
                if (!_isSearching && _searchResults.isNotEmpty) _buildHeader(),

                // 全选/全不选操作条
                if (!_isSearching && _searchResults.isNotEmpty)
                  _buildSelectionBar(),

                // 核心：瀑布流/网格照片展示
                Expanded(
                  child: _isSearching
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFD17EAD),
                          ),
                        )
                      : _searchResults.isEmpty
                      ? _buildEmptyState()
                      : _buildPhotoGrid(),
                ),

                // 底部留白，防止网格被底部悬浮搜索框彻底挡住
                // const SizedBox(height: 140),
              ],
            ),
          ),

          // 🔎 3. 底部悬浮巨型搜索框
          Positioned(
            left: 0,
            right: 0,
            bottom: 0, // 距离底部有点呼吸感
            child: _buildBottomSearchBar(),
          ),
        ],
      ),
    );
  }
  // 🌌 极光晕染背景生成器 (终极防黑屏版)
  Widget _buildAmbientBackground() {
    return Container(
      color: const Color(0xFFFAFAFA), // 垫一层底色
      // 🌟 核心修改：使用 ImageFiltered 替代 BackdropFilter
      // 它只模糊内部的两个圆块，绝不干扰页面滑动退出的底层图层！
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              left: -50,
              child: Container(
                width: 300,
                height: 300,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x88FFB6C1), // 稍微加深一点粉色，因为 ImageFiltered 效果更纯粹
                ),
              ),
            ),
            Positioned(
              top: -20,
              right: -80,
              child: Container(
                width: 250,
                height: 250,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x77E0B0FF), // 紫罗兰色
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // 🏆 顶部 Header：大大的图标 + 搜索结果文案 + 继续按钮
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
      child: Row(
        children: [
          // 左侧花哨的播放渐变方块
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFA07A), Color(0xFFD17EAD)], // 橙粉渐变
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD17EAD).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(width: 16),
          // 中间文字
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '搜索完成',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '为您搜集到${_searchResults.length}张相关照片',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          // 右侧“继续”按钮
          ElevatedButton(
            onPressed: _generateStory,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD17EAD), // 粉紫色
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              '继续',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ✨ 全选/全不选操作条
  Widget _buildSelectionBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        children: [
          // 全选按钮 (实心粉)
          ElevatedButton(
            onPressed: _selectAll,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD17EAD),
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size(60, 32),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('全选', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 12),
          // 全不选按钮 (空心边框)
          OutlinedButton(
            onPressed: _deselectAll,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFD17EAD),
              side: const BorderSide(color: Color(0xFFD17EAD), width: 1.5),
              minimumSize: const Size(60, 32),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('全不选', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
  // 🖼️ 构建无黑罩的照片网格
  Widget _buildPhotoGrid() {
    return GridView.builder(
      padding: const EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: 140, // 👈 留出足够的高度，让最后一行照片能滚上来
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.0,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final photo = _searchResults[index];
        final isSelected = _selectedPhotoIds.contains(photo.id);
        final file = File(photo.path);

        return GestureDetector(
          onTap: () => _toggleSelection(photo.id),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. 照片本身 (大圆角)
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: file.existsSync()
                    ? Image.file(file, fit: BoxFit.cover)
                    : Container(color: Colors.grey.shade300),
              ),

              // 2. 右上角的选择指示器 (无黑罩，还原设计图的清爽感)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFD17EAD)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFD17EAD)
                          : Colors.white,
                      width: 2.5,
                    ),
                    boxShadow: [
                      if (!isSelected) // 给白圈加点阴影防止在白背景图片上看不见
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                        ),
                    ],
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  // 🔎 底部巨型悬浮搜索框 (带渐变遮罩)
  Widget _buildBottomSearchBar() {
    return Container(
      // 🌟 1. 外层渐变遮罩：给顶部留出 40 像素的渐变过渡区，其他边距还原原来的位置
      padding: const EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            // 顶部完全透明
            const Color(0xFFFAFAFA).withValues(alpha: 0.0),
            // 中间半透明过渡
            const Color(0xFFFAFAFA).withValues(alpha: 0.7),
            // 到底部变成实色 (与你的 Scaffold 背景色一致)
            const Color(0xFFFAFAFA),
          ],
          stops: const [0.0, 0.4, 1.0], // 控制渐变的节奏，让透明部分多一点
        ),
      ),
      // 🌟 2. 里层：真正的白色搜索框 (完全保持你原来的绝美设计)
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFD17EAD).withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD17EAD).withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.only(
            left: 20,
            right: 12,
            top: 12,
            bottom: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 多行输入框
              TextField(
                controller: _searchController,
                maxLines: 3,
                minLines: 1,
                textInputAction: TextInputAction.search,
                onSubmitted: _performSearch,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '想看什么？比如 "去年的日本之旅"...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _candidateLabels
                    .map(
                      (label) => ActionChip(
                        label: Text(label),
                        onPressed: () {
                          _searchController.text = label;
                          _searchController.selection = TextSelection.fromPosition(
                            TextPosition(offset: label.length),
                          );
                          FocusScope.of(context).unfocus();
                          _performSearch(label);
                        },
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 8),
              // 右下角的粉色搜索按钮
              Align(
                alignment: Alignment.bottomRight,
                child: GestureDetector(
                  onTap: () {
                    FocusScope.of(context).unfocus(); // 收起键盘
                    _performSearch(_searchController.text);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD17EAD),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.search, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.travel_explore,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isEmpty
                ? '输入主题，AI帮你找出回忆'
                : '没有找到匹配的照片，换个词试试？',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
          ),
        ],
      ),
    );
  }

}
