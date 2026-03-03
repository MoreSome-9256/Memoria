import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../../models/ai_theme.dart';
import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../service/photo_service.dart';
import '../../service/story_service.dart';
import 'story_result_page.dart';

enum StoryLength { short, medium }

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
  StoryLength _selectedLength = StoryLength.medium;
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
      final eventEntityId = int.parse(widget.event.id);
      final eventEntity = await isar.collection<EventEntity>().get(
        eventEntityId,
      );

      if (eventEntity == null) {
        throw Exception('Event not found');
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
      final story = await StoryService().generateStory(
        event: eventEntity,
        selectedPhotos: photoEntities,
        title: _themeController.text.trim(),
        subtitle: _selectedSubtitle ?? '',
        length: _selectedLength,
      );

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

          // Story length selection
          Text(
            '篇幅选择',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<StoryLength>(
            segments: const [
              ButtonSegment(
                value: StoryLength.short,
                label: Text('短篇'),
                icon: Icon(Icons.short_text),
              ),
              ButtonSegment(
                value: StoryLength.medium,
                label: Text('中篇'),
                icon: Icon(Icons.notes),
              ),
            ],
            selected: {_selectedLength},
            onSelectionChanged: (Set<StoryLength> newSelection) {
              setState(() {
                _selectedLength = newSelection.first;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            _selectedLength == StoryLength.short ? '约 150 字' : '约 300 字',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
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
