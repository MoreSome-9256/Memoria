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
  /*Future<void> _refreshData({bool clearCacheFirst = false}) async {
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
  }*/
  // 🔄 刷新数据：极速扫描相册 + 后台静默 AI
  Future<void> _refreshData({bool clearCacheFirst = false}) async {
    if (_isRefreshing) return; // 防止重复点击

    setState(() => _isRefreshing = true);

    try {
      if (clearCacheFirst) {
        await PhotoService().clearAllCachedData();
      }

      // 1. ⚡ 极速操作：扫描相册（仅入库原始可用数据）
      final scanSummary = await PhotoService().scanAndSyncPhotos();

      // 2. ⚡ 极速操作：运行聚类算法（通过时间/GPS聚合成 Event）
      await EventService().runClustering();

      // ==========================================
      // 🚀 核心改动：到这里基础数据已经搞定，立刻关闭加载动画！
      // ==========================================
      setState(() => _isRefreshing = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // 🌟 让提示框悬浮，不再挤压底部栏
            behavior: SnackBarBehavior.floating,
            content: Text(
              clearCacheFirst
                  ? '✅ 已清空重扫，发现${scanSummary.totalAfter}张照片。AI正在后台悄悄打标...'
                  : '✅ 相册已极速更新，发现${scanSummary.totalAfter}张照片。AI正在后台悄悄打标...',
            ),
            duration: const Duration(seconds: 3), // 提示稍长一点
          ),
        );
      }

      // 3. 🤫 静默操作：剥离主线程，让 AI 在后台慢慢抠图打标签
      // ⚠️ 注意：这里去掉了 await，它不会再阻塞后续代码和 UI 了！
      AIService()
          .analyzePhotosInBackground()
          .then((_) {
            print("🎉 [后台任务] 所有照片的 AI 标签已静默添加完毕！");
            // 你可以随时在这里发送广播，或者静默更新部分特定 UI
          })
          .catchError((e) {
            print("❌ [后台任务] AI 分析出错: $e");
          });
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
      // 兜底逻辑：如果前面的极速操作抛出异常，确保能关掉加载动画
      if (_isRefreshing && mounted) {
        setState(() => _isRefreshing = false);
      }
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
          // 1. 🌟 优化后的加载判断逻辑
          // 只有在“还在连接”且“完全没有历史数据”时，才显示大转圈
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // 2. 错误处理 (保持原样)
          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          // 获取实体列表
          final eventEntities = snapshot.data ?? [];

          // 3. 🌟 空状态：如果数据库返回了空列表，立刻显示空提示，不再转圈
          if (eventEntities.isEmpty) {
            return _buildEmptyState();
          }

          // 4. 有数据时的处理逻辑
          return FutureBuilder<Map<String, List<Event>>>(
            // 🚀 这里使用了我们刚才优化的 Future.wait 并行处理方法
            future: _groupEvents(eventEntities),
            builder: (context, groupSnapshot) {
              // 错误捕获：防止转换 UI 模型时崩溃导致无限转圈
              if (groupSnapshot.hasError) {
                return Center(child: Text('数据转换错误: ${groupSnapshot.error}'));
              }

              // 正在进行并行转换时的小转圈
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
  // 🎨 1. 构建空状态界面
  Widget _buildEmptyState() {
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
          const Text('暂无照片', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          const Text('点击右上角刷新按钮扫描相册', style: TextStyle(color: Colors.grey)),
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

  // 🎨 2. 构建错误提示界面
  Widget _buildErrorState(String errorMessage) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('加载失败: $errorMessage'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _refreshData, child: const Text('重试')),
        ],
      ),
    );
  }

  // 将 EventEntity 列表转换为分组的 Event 列表
  Future<Map<String, List<Event>>> _groupEvents(
    List<EventEntity> eventEntities,
  ) async {
    final grouped = <String, List<Event>>{};
    final isar = PhotoService().isar;

    // 1. 🚀 关键改动：使用 Future.wait 并行处理所有事件转换，不再一个一个等
    final List<Event> allEvents = await Future.wait(
      eventEntities.map((entity) => entity.toUIModel(isar)),
    );

    // 2. 快速分组
    for (final event in allEvents) {
      final key = '${event.year} · ${event.season}';
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(event);
    }

    return grouped;
  }
}
