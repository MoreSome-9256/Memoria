import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../../models/ai_theme.dart';
import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/entity/story_entity.dart';
import '../../service/photo_service.dart';
import '../../service/story_service.dart';
import 'story_result_page.dart';

// 🌟 新增：视频长宽比枚举
enum VideoAspectRatio { vertical, horizontal }

// 🌟 新增：发布平台枚举
enum PublishingPlatform { moments, xiaohongshu, bilibili, tiktok }

class ConfigPage extends StatefulWidget {
  final Event event;
  final List<Photo> selectedPhotos;
  final AITheme selectedTheme;

  const ConfigPage({
    super.key,
    required this.event,
    required this.selectedPhotos,
    required this.selectedTheme,
  });

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  late TextEditingController _themeController;
  String? _selectedSubtitle;

  // 🌟 替换掉原来的 StoryLength，改为新的配置项并给默认值
  VideoAspectRatio _selectedAspectRatio = VideoAspectRatio.vertical;
  PublishingPlatform _selectedPlatform = PublishingPlatform.xiaohongshu;

  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _themeController = TextEditingController(text: widget.selectedTheme.title);
    _selectedSubtitle = widget.selectedTheme.subtitle;
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  Future<void> _generateStory() async {
    if (_themeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入故事主题')));
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      // 1. 获取 EventEntity（通过 Event.id 查询）
      final isar = PhotoService().isar;
      EventEntity? eventEntity;

      if (widget.event.id == '-1') {
        // 🕵️‍♂️ 拦截到虚拟 Event！直接在内存中捏一个对象
        eventEntity = EventEntity()
          ..id = -1
          ..title = widget.event.title
          ..startTime = widget.event.startDate.millisecondsSinceEpoch
          ..endTime = widget.event.endDate.millisecondsSinceEpoch
          ..photoCount = widget.selectedPhotos.length;
      } else {
        // 正常走系统自动聚类的相册逻辑
        final eventEntityId = int.parse(widget.event.id);
        eventEntity = await isar.collection<EventEntity>().get(eventEntityId);
      }

      if (eventEntity == null) {
        throw Exception('未找到或创建事件档案失败');
      }

      // 2. 严格按用户选择的照片生成故事
      final selectedAssetIds = widget.selectedPhotos
          .map((photo) => photo.id)
          .toList();
      final List<PhotoEntity> photoEntities = await isar
          .collection<PhotoEntity>()
          .filter()
          .anyOf(selectedAssetIds, (q, assetId) => q.assetIdEqualTo(assetId))
          .sortByTimestamp()
          .findAll();

      if (photoEntities.isEmpty) {
        throw Exception('No photos found');
      }

      // 3. 调用 StoryService 生成故事
      // ⚠️ 注意：你需要去 StoryService 里把原来的 length 参数改成接收 aspectRatio 和 platform！
      /*final story = await StoryService().generateStory(
        event: eventEntity,
        selectedPhotos: photoEntities,
        title: _themeController.text.trim(),
        subtitle: _selectedSubtitle ?? '',
        // 🌟 传入新增的两个配置项 (传字符串给后端/AI更方便解析)
        aspectRatio: _selectedAspectRatio.name,
        platform: _selectedPlatform.name,
      );*/ // 暂时注释掉！后期一定记得改回来！

      // 🌟 【测试专用】手动捏一个极其逼真的假 StoryEntity
      // 🌟 修复点：从 photoEntities (List<PhotoEntity>) 里提取 int 类型的 id
      final databaseIds = photoEntities.map((e) => e.id).toList();
      final now = DateTime.now().millisecondsSinceEpoch;
      final story = StoryEntity()
        ..title = _themeController.text.trim().isEmpty
            ? '测试视频生成'
            : _themeController.text.trim()
        ..subtitle = _selectedSubtitle ?? '沙盒测试'
        ..createdAt = now
        ..updatedAt = now
        ..eventId = eventEntity
            .id // 👈 必须传：否则存数据库时会报错
        ..photoIds =
            databaseIds // 👈 必须传：绑定的照片ID列表
        ..photoCount = selectedAssetIds.length
        ..isLlmGenerated = false
        // ⚠️ 最最最关键的 content：必须带有 ![img](x) 占位符，否则 UI 无法切图！
        ..content =
            '''
测试

![img](0)

Sandal Leap

![img](1)
'''
                .trim();

      if (!mounted) return;

      setState(() {
        _isGenerating = false;
      });

      if (story != null) {
        // 4. 导航到 StoryResultPage.fromStoryEntity
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => StoryResultPage.fromStoryEntity(
              storyEntity: story,
              photos: photoEntities,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('故事生成失败，请重试')));
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('生成异常: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('配置故事')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Event info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.event.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.event.dateRangeText} · ${widget.event.location}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.selectedPhotos.length} 张照片',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Core theme input
          Text(
            '核心主题',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _themeController,
            decoration: InputDecoration(
              hintText: '输入故事主题',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: Text(
                widget.selectedTheme.emoji,
                style: const TextStyle(fontSize: 24),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 50),
            ),
          ),
          const SizedBox(height: 24),

          // Subtitle chips
          Text(
            '副标题 / 切入点',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [widget.selectedTheme.subtitle, '难忘的回忆', '美好时光', '特别的日子']
                .map((subtitle) {
                  final isSelected = subtitle == _selectedSubtitle;
                  return ChoiceChip(
                    label: Text(subtitle),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedSubtitle = selected ? subtitle : null;
                      });
                    },
                  );
                })
                .toList(),
          ),
          const SizedBox(height: 24),

          // 🎬 删除了原来的“篇幅选择”，换成“视频长宽比”
          Text(
            '画面比例',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<VideoAspectRatio>(
            segments: const [
              ButtonSegment(
                value: VideoAspectRatio.vertical,
                label: Text('竖屏 9:16'),
                icon: Icon(Icons.phone_android),
              ),
              ButtonSegment(
                value: VideoAspectRatio.horizontal,
                label: Text('横屏 16:9'),
                icon: Icon(Icons.stay_current_landscape),
              ),
            ],
            selected: {_selectedAspectRatio},
            onSelectionChanged: (Set<VideoAspectRatio> newSelection) {
              setState(() {
                _selectedAspectRatio = newSelection.first;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            _selectedAspectRatio == VideoAspectRatio.vertical
                ? '适合抖音、朋友圈、小红书等移动端观看'
                : '适合 B站、大屏沉浸式观看',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          // 📱 新增：发布平台选择
          Text(
            '发布平台 (影响生成风格)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('✨ 小红书'),
                selected: _selectedPlatform == PublishingPlatform.xiaohongshu,
                onSelected: (selected) {
                  if (selected)
                    setState(
                      () => _selectedPlatform = PublishingPlatform.xiaohongshu,
                    );
                },
              ),
              ChoiceChip(
                label: const Text('💬 朋友圈'),
                selected: _selectedPlatform == PublishingPlatform.moments,
                onSelected: (selected) {
                  if (selected)
                    setState(
                      () => _selectedPlatform = PublishingPlatform.moments,
                    );
                },
              ),
              ChoiceChip(
                label: const Text('📺 B站'),
                selected: _selectedPlatform == PublishingPlatform.bilibili,
                onSelected: (selected) {
                  if (selected)
                    setState(
                      () => _selectedPlatform = PublishingPlatform.bilibili,
                    );
                },
              ),
              ChoiceChip(
                label: const Text('🔥 短视频'),
                selected: _selectedPlatform == PublishingPlatform.tiktok,
                onSelected: (selected) {
                  if (selected)
                    setState(
                      () => _selectedPlatform = PublishingPlatform.tiktok,
                    );
                },
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Generate button
          FilledButton(
            onPressed: _isGenerating ? null : _generateStory,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isGenerating
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('开始生成'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
