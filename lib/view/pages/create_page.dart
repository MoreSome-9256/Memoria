import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../../models/entity/photo_entity.dart';
import '../../service/photo_service.dart';
// 如果有封装好的图片显示组件可以替换这里的 Image.file

class CreatePage extends StatefulWidget {
  const CreatePage({super.key});

  @override
  State<CreatePage> createState() => _CreatePageState();
}

class _CreatePageState extends State<CreatePage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // 搜索结果
  List<PhotoEntity> _searchResults = [];
  // 用户勾选的照片集合（存 ID）
  final Set<int> _selectedPhotoIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 🧠 终极版：本地实体截流 (NER) + LLM 语义扩展
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
    // 💡 阶段一：建立本地知识库 (暴力脱水版)
    // ==========================================
    final Set<String> allUniqueTags = {};
    final Set<String> allLocations = {};

    for (var photo in allAnalyzedPhotos) {
      if (photo.aiTags != null) allUniqueTags.addAll(photo.aiTags!);

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
    // 💡 阶段三：AI 查询扩展 (仅在需要时调用)
    // ==========================================
    List<String> targetTags = [];

    if (remainingQuery.isNotEmpty) {
      try {
        const baseUrl = String.fromEnvironment('LLM_BASE_URL');
        const apiPath = String.fromEnvironment('LLM_API_PATH');
        const model = String.fromEnvironment('LLM_MODEL');
        const apiKey = String.fromEnvironment('LLM_API_KEY');

        final prompt =
            """
你是一个相册搜索助手。用户想要搜索的核心内容是：“$remainingQuery”。
当前相册的标签库有：${allUniqueTags.join(', ')}。
请挑选出所有与“$remainingQuery”在语义上相关的标签。只返回标签名，用英文逗号分隔，不要解释。如果没有相关标签，返回“无”。
""";

        print("🤖 [大模型] 正在向 DeepSeek 请求扩展查询词...");
        final request = await HttpClient().postUrl(
          Uri.parse('$baseUrl$apiPath'),
        );
        request.headers.set('Authorization', 'Bearer $apiKey');
        request.headers.set('Content-Type', 'application/json; charset=utf-8');
        request.write(
          jsonEncode({
            "model": model,
            "messages": [
              {"role": "user", "content": prompt},
            ],
            "temperature": 0.1,
          }),
        );

        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        final aiReply = jsonDecode(
          responseBody,
        )['choices'][0]['message']['content'].toString().trim();

        print("💡 [大模型] 关联到的标签有: $aiReply");
        if (aiReply != '无' && aiReply.isNotEmpty) {
          targetTags = aiReply
              .split(',')
              .map((e) => e.trim().toLowerCase())
              .toList();
        }
      } catch (e) {
        print("⚠️ AI 请求失败，降级处理: $e");
        targetTags = [remainingQuery.toLowerCase()];
      }
    } else {
      print("⚡ [急速直达] 纯时空查询，跳过 AI 网络请求！");
      // 模拟极速查找的视觉缓冲
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // ==========================================
    // 💡 阶段四：本地多模态综合交叉过滤
    // ==========================================
    final List<PhotoEntity> matchedPhotos = [];

    for (var photo in allAnalyzedPhotos) {
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

      // 判定 C: 语义/标签拦截 (当且仅当存在剩余语义词时)
      if (isMatch && remainingQuery.isNotEmpty) {
        bool hitTag = false;
        // 🌟 如果提取阶段不小心漏掉了（比如用户搜了个奇葩缩写），在这里做最后的地址兜底匹配
        final locationText =
            '${photo.province ?? ''} ${photo.city ?? ''} ${photo.district ?? ''}'
                .replaceAll(RegExp(r'[省市区县]'), '');
        if (locationText.contains(remainingQuery) ||
            remainingQuery.contains(
              locationText.isNotEmpty ? locationText : '无极',
            )) {
          hitTag = true;
        }
        if (!hitTag && photo.aiTags != null) {
          final photoTagsLower = photo.aiTags!
              .map((t) => t.toLowerCase())
              .toSet();
          // AI 提供目标标签时
          if (targetTags.isNotEmpty) {
            if (targetTags.any(
              (target) =>
                  photoTagsLower.contains(target) ||
                  target.contains(photoTagsLower.firstOrNull ?? '无极'),
            )) {
              hitTag = true;
            }
          }
          // AI 降级或查无结果时，用剩余词暴力兜底
          if (!hitTag) {
            if (photo.aiTags!.any(
              (tag) =>
                  tag.toLowerCase().contains(remainingQuery) ||
                  remainingQuery.contains(tag.toLowerCase()),
            )) {
              hitTag = true;
            }
          }
        }
        if (!hitTag) isMatch = false;
      }

      if (isMatch) {
        matchedPhotos.add(photo);
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

  // 🚀 生成故事（下一步操作）
  void _generateStory() {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一张照片哦')));
      return;
    }

    // 获取选中的真实照片对象
    final selectedPhotos = _searchResults
        .where((p) => _selectedPhotoIds.contains(p.id))
        .toList();

    print(
      "✅ 准备使用 ${selectedPhotos.length} 张图片生成故事，主题是: ${_searchController.text}",
    );

    // TODO: 在这里带着 selectedPhotos 和 _searchController.text 跳转到 DeepSeek 故事生成页面
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('即将根据选中的 ${_selectedPhotoIds.length} 张照片生成故事...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('唤醒记忆'),
        elevation: 0,
        actions: [
          // 当有选中的图片时，右上角显示“下一步”按钮
          if (_selectedPhotoIds.isNotEmpty)
            FilledButton.tonal(
              onPressed: _generateStory,
              child: Text('生成 (${_selectedPhotoIds.length})'),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // 🔍 搜索输入区域
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: _performSearch,
              decoration: InputDecoration(
                hintText: '想看什么？比如 "2024夏天的海边"、"我的馋嘴猫猫"...',
                prefixIcon: const Icon(Icons.auto_awesome),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _performSearch(_searchController.text),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),

          // 🖼️ 结果展示区域
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                ? _buildEmptyState()
                : _buildPhotoGrid(),
          ),
        ],
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

  // 构建照片网格
  Widget _buildPhotoGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
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
              // 1. 照片本身
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: file.existsSync()
                    ? Image.file(file, fit: BoxFit.cover)
                    : Container(color: Colors.grey[300]),
              ),

              // 2. 选中时的蒙层遮罩
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),

              // 3. 右上角的勾选框
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white,
                      width: 2,
                    ),
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
}
