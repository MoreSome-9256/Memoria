import 'package:flutter/material.dart';
import '../../models/entity/story_entity.dart';
import '../../service/story_service.dart';
import 'story_result_page.dart';

class StoriesPage extends StatefulWidget {
  const StoriesPage({super.key});

  @override
  State<StoriesPage> createState() => _StoriesPageState();
}

class _StoriesPageState extends State<StoriesPage> {
  late Future<List<StoryEntity>> _storiesFuture;

  @override
  void initState() {
    super.initState();
    _storiesFuture = StoryService().getAllStories();
  }

  Future<void> _reload() async {
    setState(() {
      _storiesFuture = StoryService().getAllStories();
    });
  }

  Future<void> _openStory(StoryEntity story) async {
    final photos = await StoryService().loadPhotos(story.photoIds);
    if (!mounted) {
      return;
    }

    if (photos.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该故事缺少可用照片')));
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            StoryResultPage.fromStoryEntity(storyEntity: story, photos: photos),
      ),
    );

    if (!mounted) {
      return;
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('故事'),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新故事列表',
          ),
        ],
      ),
      body: FutureBuilder<List<StoryEntity>>(
        future: _storiesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 12),
                  Text('加载故事失败: ${snapshot.error}'),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            );
          }

          final stories = snapshot.data ?? [];
          if (stories.isEmpty) {
            return const Center(child: Text('暂无故事，先去相册生成一篇吧'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: stories.length,
            itemBuilder: (context, index) {
              final story = stories[index];
              final date = DateTime.fromMillisecondsSinceEpoch(story.createdAt);
              final dateText =
                  '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(story.title),
                  subtitle: Text(
                    '${story.subtitle}\n$dateText · ${story.photoCount} 张照片',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openStory(story),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
