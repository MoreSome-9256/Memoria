import 'package:flutter/material.dart';
import '../../models/entity/event_entity.dart';
import '../../models/event.dart';
import '../../service/ai_service.dart';
import '../../service/event_service.dart';
import '../../service/photo_service.dart';
import '../widgets/event_card.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  bool _isRefreshing = false;

  late Stream<List<EventEntity>> _eventsStream;

  // 🔄 刷新数据：扫描相册 + 运行聚类
  Future<void> _refreshData({bool clearCacheFirst = false}) async {
    if (_isRefreshing) return; // 防止重复点击

    setState(() => _isRefreshing = true);

    try {
      if (clearCacheFirst) {
        await PhotoService().clearAllCachedData();
      }

      // 1. 扫描相册（仅入库原始可用数据）
      final scanSummary = await PhotoService().scanAndSyncPhotos();

      // 2. 运行聚类算法（会自动触发地址解析）
      await EventService().runClustering();

      // 3. 聚类完成后再做 AI 分析，确保 eventId 已建立
      await AIService().analyzePhotosInBackground();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              clearCacheFirst
                  ? '✅ 已清空缓存并完成重扫：新增${scanSummary.insertedCount}张，可用总数${scanSummary.totalAfter}张'
                  : '✅ 数据已更新：新增${scanSummary.insertedCount}张，可用总数${scanSummary.totalAfter}张',
            ),
          ),
        );
      }
    } on PhotoScanException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('⚠️ ${e.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ 更新失败: $e')));
      }
    } finally {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _resetCacheAndRescan() async {
    if (_isRefreshing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('刷新缓存并重扫'),
          content: const Text('将清空 Isar 中的照片、事件、故事数据，并重新扫描相册。是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _refreshData(clearCacheFirst: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _eventsStream = EventService().watchEvents();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('相册'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services),
            onPressed: _isRefreshing ? null : _resetCacheAndRescan,
            tooltip: '清空缓存并重扫',
          ),
          // 刷新按钮
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isRefreshing ? null : _refreshData,
            tooltip: '扫描相册并聚类',
          ),
        ],
      ),
      body: StreamBuilder<List<EventEntity>>(
        stream: _eventsStream,
        builder: (context, snapshot) {
          // 加载中
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // 错误处理
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('加载失败: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _refreshData,
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }

          final eventEntities = snapshot.data ?? [];

          // 空状态
          if (eventEntities.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text('暂无事件', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text(
                    '点击右上角刷新按钮扫描相册',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _refreshData,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text('扫描相册'),
                  ),
                ],
              ),
            );
          }

          // 将 EventEntity 转为 Event 并按年份/季节分组
          return FutureBuilder<Map<String, List<Event>>>(
            future: _groupEvents(eventEntities),
            builder: (context, groupSnapshot) {
              if (!groupSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final groupedEvents = groupSnapshot.data!;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: groupedEvents.entries.map((entry) {
                  final seasonTitle = entry.key;
                  final events = entry.value;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          seasonTitle,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...events.map((event) => EventCard(event: event)),
                      const SizedBox(height: 0),
                    ],
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }

  // 将 EventEntity 列表转换为分组的 Event 列表
  Future<Map<String, List<Event>>> _groupEvents(
    List<EventEntity> eventEntities,
  ) async {
    final grouped = <String, List<Event>>{};
    final isar = PhotoService().isar;

    for (final entity in eventEntities) {
      // 转换为 UI 模型
      final event = await entity.toUIModel(isar);

      // 分组键：年份 · 季节
      final key = '${event.year} · ${event.season}';

      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(event);
    }

    return grouped;
  }
}
