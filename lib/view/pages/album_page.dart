import 'dart:async';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../data/tag_taxonomy_v2.dart';
import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/event.dart';
import '../../service/ai_service.dart';
import '../../service/album_refresh_service.dart';
import '../../service/album_tag_browser_service.dart';
import '../../service/event_service.dart';
import '../../service/junk_photo_cleanup_service.dart';
import '../../service/junk_photo_filter_service.dart';
import '../../service/photo_service.dart';
import '../widgets/event_card.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import '../widgets/junk_photo_cleanup_banner.dart';
import '../widgets/junk_photo_cleanup_dialog.dart';
import '../widgets/path_image.dart';
import 'album_search_page.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

enum _AlbumViewMode { tags, moments }

class _AlbumPageState extends State<AlbumPage> {
  static const double _contentBottomInset = 118;
  static const int _tagBrowserPhotoSoftLimit = 1200;
  bool _isClearingCache = false;
  String? _lastPromptedJunkCleanupReportId;
  final TextEditingController _semanticSearchController =
      TextEditingController();
  final FocusNode _semanticSearchFocusNode = FocusNode();
  final AlbumTagBrowserService _albumTagBrowserService =
      AlbumTagBrowserService();
  _AlbumViewMode _viewMode = _AlbumViewMode.tags;

  // 🌟 1. 改为直接监听最终 UI 数据结构的 Stream
  late Stream<Map<String, List<Event>>> _uiEventsStream;
  late Stream<_AlbumTagBrowserData> _albumTagBrowserStream;

  static const int _fullRefreshOption = -1;
  static const List<int> _refreshPhotoOptions = <int>[
    100,
    300,
    500,
    _fullRefreshOption,
  ];

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
  void _startRefresh({bool clearCacheFirst = false, int? recentPhotoLimit}) {
    if (_isClearingCache || AlbumRefreshService().isRunning) {
      return;
    }

    final scopeLabel = recentPhotoLimit == null
        ? '全部照片'
      : '下一批 $recentPhotoLimit 张';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('已开始后台扫描 $scopeLabel，可随时切换页面继续使用。'),
      ),
    );

    unawaited(
      AlbumRefreshService()
          .startRefresh(
            clearCacheFirst: clearCacheFirst,
            recentPhotoLimit: recentPhotoLimit,
          )
          .then((result) {
            if (result == null || !mounted) {
              return;
            }
            final scanSummary = result.scanSummary;
            final handoffText = result.aiAlreadyRunning
                ? '后台 AI 已在运行，新照片已并入当前队列。'
                : 'AI 已转入后台继续打标。';
            final message = result.clearCacheFirst
                ? result.recentPhotoLimit == null
                      ? '已安全重建缓存，恢复 ${scanSummary.totalAfter} 张照片。$handoffText'
                      : '已安全重建最近 ${result.recentPhotoLimit} 张照片缓存，恢复 ${scanSummary.totalAfter} 张照片。$handoffText'
                : result.requeuedCount > 0
                ? result.recentPhotoLimit == null
                      ? '相册已更新，并将 ${result.requeuedCount} 张旧照片重新加入中文打标队列。'
                  : '已刷新下一批 ${result.recentPhotoLimit} 张照片，并将新增的 ${result.requeuedCount} 张加入中文打标队列。'
                : result.recentPhotoLimit == null
                ? '相册已更新。$handoffText'
                : '下一批 ${result.recentPhotoLimit} 张照片已刷新。$handoffText';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(message),
                duration: const Duration(seconds: 3),
              ),
            );
          })
          .catchError((error) async {
            if (!mounted) {
              return;
            }
            if (error is PhotoScanException &&
                error.code == PhotoScanError.permissionDenied) {
              await _showPhotoPermissionGuide(error.message);
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('❌ 更新失败: $error'),
              ),
            );
          }),
    );
  }

  Future<void> _showPhotoPermissionGuide(String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('需要完整照片权限'),
          content: Text(
            '$message\n\n当前系统不会再次弹出照片选择器，请手动进入系统设置，将“照片与视频”权限改为“允许所有照片”。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('稍后处理'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await PhotoManager.openSetting();
              },
              child: const Text('去系统设置'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _clearLocalCacheOnly() async {
    if (_isClearingCache || AlbumRefreshService().isRunning) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('清空本地缓存'),
          content: const Text(
            '将只清空本 app 的 Isar 本地缓存（照片、事件、故事、已扫描结果），'
            '不会删除或修改手机系统相册中的任何图片。是否继续？',
          ),
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

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isClearingCache = true);
    try {
      await AIService().stopAnalysisAndWait();
      await PhotoService().clearAllCachedData();
      AIService().clearPendingJunkCleanupReport();
      _lastPromptedJunkCleanupReportId = null;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('已清空本地缓存。系统相册原图未受影响，可点击右上角 + 重新扫描。'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('清空本地缓存失败: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isClearingCache = false);
      }
    }
  }

  Future<void> _showRefreshOptions() async {
    if (_isClearingCache || AlbumRefreshService().isRunning) {
      return;
    }

    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text('选择刷新范围'),
                  subtitle: Text('先只跑最近一部分照片，或者全量运行'),
                ),
                ..._refreshPhotoOptions.map((option) {
                  // 这里假设你的代码里定义了 _fullRefreshOption，如果没有请替换为你实际的值
                  final isFull = option == -1; // 假设 -1 代表全部，请根据你的代码调整
                  final label = isFull ? '全部运行' : '跑下一批 $option 张';
                  final subtitle = isFull
                      ? '扫描全部照片并对全部待处理照片后台打标'
                    : '按窗口滚动扫描下一批，并仅重排本批新增照片的 AI 打标';
                  return ListTile(
                    leading: Icon(
                      isFull ? Icons.all_inclusive : Icons.flash_on,
                    ),
                    title: Text(label),
                    subtitle: Text(subtitle),
                    onTap: () => Navigator.pop(context, option),
                  );
                }),
                // 留出底部安全距离
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }

    _startRefresh(
      recentPhotoLimit: selected == _fullRefreshOption ? null : selected,
    );
  }

  Future<void> _handleJunkCleanupReportChanged() async {
    if (!mounted) {
      return;
    }

    final report = AIService().latestJunkCleanupReport;
    if (report == null || !report.hasCandidates) {
      return;
    }

    if (_lastPromptedJunkCleanupReportId == report.reportId) {
      return;
    }
    _lastPromptedJunkCleanupReportId = report.reportId;

    await _showJunkCleanupDialog(report);
  }

  Future<void> _showJunkCleanupDialog(JunkPhotoCleanupReport report) async {
    final selectedPhotoIds = await showDialog<List<int>>(
      context: context,
      builder: (context) => JunkPhotoCleanupDialog(report: report),
    );
    if (!mounted) {
      return;
    }
    await _deleteSelectedJunkRecords(report, selectedPhotoIds ?? const <int>[]);
  }

  Future<void> _deleteSelectedJunkRecords(
    JunkPhotoCleanupReport report,
    List<int> selectedPhotoIds,
  ) async {
    try {
      final selectedCandidates = report.candidates
          .where((candidate) => selectedPhotoIds.contains(candidate.photoId))
          .toList(growable: false);
      final removedCount = await JunkPhotoCleanupService()
          .removeCandidatesFromLocalIndex(selectedCandidates);
      final remainingCandidates = report.candidates
          .where((candidate) => !selectedPhotoIds.contains(candidate.photoId))
          .toList(growable: false);
      if (remainingCandidates.isNotEmpty) {
        AIService().markJunkCandidatesAsKept(
          remainingCandidates.map((candidate) => candidate.photoId),
        );
      }
      final retriedCount = remainingCandidates.isEmpty
          ? 0
          : await PhotoService().requeuePhotosForAiByIds(
              remainingCandidates.map((candidate) => candidate.photoId),
            );
      if (retriedCount > 0 && !AIService().isAnalyzing) {
        unawaited(
          AIService().analyzePhotosInBackground(maxPhotos: retriedCount),
        );
      }
      if (!mounted) {
        return;
      }
      AIService().clearPendingJunkCleanupReport();
      final message = removedCount <= 0
          ? retriedCount > 0
                ? '未删除本地记录，已将 $retriedCount 张候选重新加入正常打标队列。'
                : '没有删除任何本地数据库记录。'
          : retriedCount > 0
          ? '已删除 $removedCount 张低质量图片记录，其余 $retriedCount 张已重新尝试正常打标。'
          : '已从本地数据库删除 $removedCount 张低质量图片记录，系统相册原图未受影响。';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('删除本地数据库记录失败: $error'),
        ),
      );
    }
  }

  void _dismissJunkCleanupBanner() {
    final report = AIService().latestJunkCleanupReport;
    AIService().clearPendingJunkCleanupReport();
    if (report == null || report.candidates.isEmpty) {
      return;
    }
    unawaited(_requeueRemainingJunkCandidates(report.candidates));
  }

  Future<void> _requeueRemainingJunkCandidates(
    List<JunkPhotoCleanupCandidate> candidates,
  ) async {
    AIService().markJunkCandidatesAsKept(
      candidates.map((candidate) => candidate.photoId),
    );
    final retriedCount = await PhotoService().requeuePhotosForAiByIds(
      candidates.map((candidate) => candidate.photoId),
    );
    if (retriedCount > 0 && !AIService().isAnalyzing) {
      unawaited(AIService().analyzePhotosInBackground(maxPhotos: retriedCount));
    }
  }

  @override
  void initState() {
    super.initState();
    AIService().junkCleanupReportListenable.addListener(
      _onJunkCleanupReportChanged,
    );
    final uiEventsSource = _debounceStream<List<EventEntity>>(
      EventService().watchEvents(),
      const Duration(milliseconds: 420),
    );
    _uiEventsStream = uiEventsSource
        .asyncMap((eventEntities) => _groupEvents(eventEntities))
        .asBroadcastStream();

    _albumTagBrowserStream = _debounceStream<void>(
          PhotoService().isar.collection<PhotoEntity>().watchLazy(fireImmediately: true),
          const Duration(milliseconds: 700),
        )
        .asyncMap((_) => _loadAllPhotosForTagBrowser())
        .asyncMap((photos) async {
          // 主动让出一帧，降低同帧内计算尖峰。
          await Future<void>.delayed(Duration.zero);
          final taggedPhotos =
              photos
                  .where(_albumTagBrowserService.hasClassifiableTag)
                  .toList(growable: false)
                ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
          final clusters = _albumTagBrowserService.buildCoarseClusters(
            taggedPhotos,
            fineTopK: memoriaFineTopK,
          );
          return _AlbumTagBrowserData(
            totalPhotoCount: photos.length,
            analyzedPhotoCount: photos
                .where((photo) => photo.isAiAnalyzed)
                .length,
            taggedPhotoCount: taggedPhotos.length,
            photos: taggedPhotos,
            clusters: clusters,
          );
        })
        .asBroadcastStream();
  }

  @override
  void dispose() {
    AIService().junkCleanupReportListenable.removeListener(
      _onJunkCleanupReportChanged,
    );
    _semanticSearchController.dispose();
    _semanticSearchFocusNode.dispose();
    super.dispose();
  }

  void _onJunkCleanupReportChanged() {
    unawaited(_handleJunkCleanupReportChanged());
  }

  void _submitSemanticSearch() {
    final query = _semanticSearchController.text.trim();
    _semanticSearchFocusNode.unfocus();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('请输入自然语言描述后再搜索。'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AlbumSearchPage(initialQuery: query)),
    );
  }

  Future<List<PhotoEntity>> _loadAllPhotosForTagBrowser() async {
    // 仅加载最近一段数据，避免大图库每次变更都触发全量排序。
    return PhotoService().isar.photoEntitys
        .where()
        .sortByTimestampDesc()
        .limit(_tagBrowserPhotoSoftLimit)
        .findAll();
  }

  Stream<T> _debounceStream<T>(Stream<T> source, Duration delay) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    Timer? timer;
    T? pending;
    var hasPending = false;

    void emitPending() {
      if (!hasPending) {
        return;
      }
      controller.add(pending as T);
      hasPending = false;
      pending = null;
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = source.listen(
          (event) {
            pending = event;
            hasPending = true;
            timer?.cancel();
            timer = Timer(delay, emitPending);
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            emitPending();
            controller.close();
          },
          cancelOnError: false,
        );
      },
      onCancel: () {
        timer?.cancel();
        subscription?.cancel();
      },
    );

    return controller.stream;
  }

  Future<void> _openTagClusterBrowser(
    AlbumCoarseTagCluster cluster,
    List<PhotoEntity> allPhotos,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return _AlbumTagClusterSheet(cluster: cluster, allPhotos: allPhotos);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('相册'),
        elevation: 0,
        actions: [
          ValueListenableBuilder<AlbumRefreshProgress>(
            valueListenable: AlbumRefreshService().progressListenable,
            builder: (context, refreshProgress, _) {
              final isRefreshRunning = refreshProgress.isRunning;
              final isBusy = _isClearingCache || isRefreshRunning;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.cleaning_services),
                    onPressed: isBusy ? null : _clearLocalCacheOnly,
                    tooltip: '清空本地缓存',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton.filledTonal(
                      icon: isRefreshRunning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add, size: 22),
                      onPressed: isBusy ? null : _showRefreshOptions,
                      tooltip: '选择刷新范围',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<AIAnalysisProgress>(
        valueListenable: AIService().progressListenable,
        builder: (context, progress, _) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _semanticSearchController,
                  focusNode: _semanticSearchFocusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submitSemanticSearch(),
                  decoration: InputDecoration(
                    hintText: '语义搜索',
                    suffixIcon: IconButton(
                      onPressed: _submitSemanticSearch,
                      icon: const Icon(Icons.search),
                      tooltip: '开始搜索',
                    ),
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SegmentedButton<_AlbumViewMode>(
                  segments: const <ButtonSegment<_AlbumViewMode>>[
                    ButtonSegment<_AlbumViewMode>(
                      value: _AlbumViewMode.tags,
                      icon: Icon(Icons.sell_outlined),
                      label: Text('标签浏览'),
                    ),
                    ButtonSegment<_AlbumViewMode>(
                      value: _AlbumViewMode.moments,
                      icon: Icon(Icons.auto_awesome_mosaic_outlined),
                      label: Text('时刻分组'),
                    ),
                  ],
                  selected: <_AlbumViewMode>{_viewMode},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) {
                      return;
                    }
                    setState(() {
                      _viewMode = selection.first;
                    });
                  },
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: progress.isVisible
                    ? _buildAnalysisProgressBanner(progress)
                    : const SizedBox.shrink(),
              ),
              ValueListenableBuilder<JunkPhotoCleanupReport?>(
                valueListenable: AIService().junkCleanupReportListenable,
                builder: (context, report, _) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: report == null || !report.hasCandidates
                        ? const SizedBox.shrink()
                        : JunkPhotoCleanupBanner(
                            key: ValueKey<String>(report.reportId),
                            report: report,
                            onReview: () => _showJunkCleanupDialog(report),
                            onDismiss: _dismissJunkCleanupBanner,
                          ),
                  );
                },
              ),
              Expanded(
                child: _viewMode == _AlbumViewMode.tags
                    ? _buildAlbumTagBrowserView()
                    : _buildMomentsView(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnalysisProgressBanner(AIAnalysisProgress progress) {
    final completedText = '${progress.completed}/${progress.total}';
    final failedSuffix = progress.failed > 0 ? '，失败 ${progress.failed}' : '';
    final title = progress.isPaused
        ? 'AI 打标已暂停 $completedText$failedSuffix'
        : progress.isStopping
        ? 'AI 正在结束本轮打标 $completedText$failedSuffix'
        : 'AI 正在后台打标 $completedText$failedSuffix';
    final aiService = AIService();
    final elapsedLabel = _formatDurationCompact(progress.elapsed);
    final avgSeconds = progress.averageSecondsPerItem;
    final avgLabel = avgSeconds == null
        ? '--'
        : '${avgSeconds.toStringAsFixed(1)} 秒/张';
    final etaLabel = progress.estimatedRemainingDuration == null
        ? '--'
        : _formatDurationCompact(progress.estimatedRemainingDuration!);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${(progress.fraction * 100).round()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: Colors.teal.withValues(alpha: 0.12),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
          ),
          const SizedBox(height: 8),
          Text(
            progress.currentStep,
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            '已耗时 $elapsedLabel · 平均 $avgLabel · 预计剩余 $etaLabel',
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: progress.isStopping
                    ? null
                    : progress.isPaused
                    ? aiService.resumeAnalysis
                    : aiService.pauseAnalysis,
                icon: Icon(progress.isPaused ? Icons.play_arrow : Icons.pause),
                label: Text(progress.isPaused ? '继续' : '暂停'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: progress.isStopping ? null : aiService.stopAnalysis,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('结束本轮'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDurationCompact(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours小时${minutes.toString().padLeft(2, '0')}分';
    }
    if (minutes > 0) {
      return '$minutes分${seconds.toString().padLeft(2, '0')}秒';
    }
    return '${duration.inSeconds}秒';
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
          const Text('点击右上角 + 按钮扫描相册', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showRefreshOptions,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('扫描相册'),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumTagBrowserView() {
    return StreamBuilder<_AlbumTagBrowserData>(
      stream: _albumTagBrowserStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString());
        }

        final browserData = snapshot.data;
        final clusters =
            browserData?.clusters ?? const <AlbumCoarseTagCluster>[];
        if (clusters.isEmpty) {
          return _buildTagBrowserEmptyState();
        }

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                _contentBottomInset + MediaQuery.of(context).padding.bottom,
              ),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final cluster = clusters[index];
                  return _AlbumTagClusterTile(
                    cluster: cluster,
                    onTap: () =>
                        _openTagClusterBrowser(cluster, browserData!.photos),
                  );
                }, childCount: clusters.length),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMomentsView() {
    return StreamBuilder<Map<String, List<Event>>>(
      stream: _uiEventsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString());
        }

        final groupedEvents = snapshot.data ?? {};
        if (groupedEvents.isEmpty) {
          return _buildEmptyState();
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            _contentBottomInset + MediaQuery.of(context).padding.bottom,
          ),
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...events.map((event) => EventCard(event: event)),
              ],
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildTagBrowserEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sell_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('暂时还没有可浏览的标签聚类'),
            const SizedBox(height: 8),
            Text(
              '先点击右上角 + 扫描并完成一轮 AI 打标，系统就会按粗粒度标签自动整理相册。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.5),
            ),
          ],
        ),
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
          ElevatedButton(
            onPressed: _showRefreshOptions,
            child: const Text('重新扫描'),
          ),
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

    // 逐条异步转换，避免大批量并发导致主线程瞬时压力过高。
    final allEvents = <Event>[];
    for (var i = 0; i < eventEntities.length; i++) {
      final event = await eventEntities[i].toUIModel(isar);
      allEvents.add(event);
      if (i % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

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

class _AlbumTagBrowserData {
  const _AlbumTagBrowserData({
    required this.totalPhotoCount,
    required this.analyzedPhotoCount,
    required this.taggedPhotoCount,
    required this.photos,
    required this.clusters,
  });

  final int totalPhotoCount;
  final int analyzedPhotoCount;
  final int taggedPhotoCount;
  final List<PhotoEntity> photos;
  final List<AlbumCoarseTagCluster> clusters;
}

class _AlbumTagClusterTile extends StatelessWidget {
  const _AlbumTagClusterTile({required this.cluster, required this.onTap});

  final AlbumCoarseTagCluster cluster;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: _AlbumTagClusterCoverMosaic(photos: cluster.coverPhotos),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            cluster.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            cluster.photoCount.toString(),
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _AlbumTagClusterCoverMosaic extends StatelessWidget {
  const _AlbumTagClusterCoverMosaic({required this.photos});

  final List<PhotoEntity> photos;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return ColoredBox(
        color: Colors.grey.shade300,
        child: const Center(child: Icon(Icons.photo_library_outlined)),
      );
    }

    if (photos.length <= 2) {
      return _DeferredPathImage(path: photos.first.path, fit: BoxFit.cover);
    }

    final visible = photos.take(4).toList(growable: false);
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: visible.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        return _DeferredPathImage(path: visible[index].path, fit: BoxFit.cover);
      },
    );
  }
}

class _AlbumTagClusterSheet extends StatefulWidget {
  const _AlbumTagClusterSheet({required this.cluster, required this.allPhotos});

  final AlbumCoarseTagCluster cluster;
  final List<PhotoEntity> allPhotos;

  @override
  State<_AlbumTagClusterSheet> createState() => _AlbumTagClusterSheetState();
}

class _AlbumTagClusterSheetState extends State<_AlbumTagClusterSheet> {
  final AlbumTagBrowserService _browserService = AlbumTagBrowserService();
  String? _selectedFineTag;
  static const int _secondaryFilterTopK = 12;
  static const double _sheetBottomInset = 110;
  static const int _sheetPhotoSoftLimit = 800;
  late final Stream<List<PhotoEntity>> _photosStream;

  @override
  void initState() {
    super.initState();
    _photosStream = _debounceStream<void>(
          PhotoService().isar
              .collection<PhotoEntity>()
              .watchLazy(fireImmediately: true),
          const Duration(milliseconds: 650),
        )
        .asyncMap((_) => _loadCurrentPhotos());
  }

  Stream<T> _debounceStream<T>(Stream<T> source, Duration delay) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    Timer? timer;
    T? pending;
    var hasPending = false;

    void emitPending() {
      if (!hasPending) {
        return;
      }
      controller.add(pending as T);
      hasPending = false;
      pending = null;
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = source.listen(
          (event) {
            pending = event;
            hasPending = true;
            timer?.cancel();
            timer = Timer(delay, emitPending);
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            emitPending();
            controller.close();
          },
          cancelOnError: false,
        );
      },
      onCancel: () {
        timer?.cancel();
        subscription?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PhotoEntity>>(
      stream: _photosStream,
      initialData: widget.allPhotos,
      builder: (context, snapshot) {
        final allPhotos = snapshot.data ?? widget.allPhotos;
        final baseClusterPhotos = _browserService.photosForCoarseCluster(
          allPhotos,
          widget.cluster.coarseId,
        );
        final secondaryFilters = _browserService.topFineTagsForCoarseCluster(
          baseClusterPhotos,
          widget.cluster.coarseId,
          topK: _secondaryFilterTopK,
          includeCrossCoarseTags: true,
        );
        final clusterPhotos = _browserService.filterPhotosByFineTag(
          baseClusterPhotos,
          coarseId: widget.cluster.coarseId,
          fineTag: _selectedFineTag,
        );
        final monthGroups = _groupPhotosByMonth(clusterPhotos);

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.cluster.label,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selectedFineTag == null
                          ? '共 ${clusterPhotos.length} 张，按 ${secondaryFilters.length} 个相关标签筛选'
                          : '当前筛选：$_selectedFineTag · ${clusterPhotos.length} 张',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: const Text('全部'),
                              selected: _selectedFineTag == null,
                              onSelected: (_) {
                                setState(() {
                                  _selectedFineTag = null;
                                });
                              },
                            ),
                          ),
                          ...secondaryFilters.map(
                            (tag) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('${tag.label} ${tag.count}'),
                                selected: _selectedFineTag == tag.label,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedFineTag = tag.label;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: clusterPhotos.isEmpty
                    ? Center(
                        child: Text(
                          '当前筛选下暂无图片',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      )
                    : CustomScrollView(
                        slivers: [
                          for (final group in monthGroups) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Text(
                                  group.title,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      mainAxisSpacing: 8,
                                      crossAxisSpacing: 8,
                                      childAspectRatio: 0.82,
                                    ),
                                delegate: SliverChildBuilderDelegate((
                                  context,
                                  index,
                                ) {
                                  return _AlbumTagPhotoTile(
                                    photo: group.photos[index],
                                  );
                                }, childCount: group.photos.length),
                              ),
                            ),
                          ],
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height:
                                  _sheetBottomInset +
                                  MediaQuery.of(context).padding.bottom,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<PhotoEntity>> _loadCurrentPhotos() async {
    if (AIService().isAnalyzing) {
      // 打标高峰期避免每次写库都触发重查，减少 UI 抢占。
      return widget.allPhotos;
    }

    return PhotoService().isar.photoEntitys
        .where()
        .sortByTimestampDesc()
        .limit(_sheetPhotoSoftLimit)
        .findAll();
  }

  List<_AlbumPhotoMonthGroup> _groupPhotosByMonth(List<PhotoEntity> photos) {
    final grouped = <String, List<PhotoEntity>>{};
    for (final photo in photos) {
      final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => <PhotoEntity>[]).add(photo);
    }
    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return keys
        .map(
          (key) => _AlbumPhotoMonthGroup(
            title: _formatMonthTitle(key),
            photos: grouped[key]!
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
          ),
        )
        .toList(growable: false);
  }

  String _formatMonthTitle(String key) {
    final parts = key.split('-');
    if (parts.length != 2) {
      return key;
    }
    return '${parts[0]}年${parts[1]}月';
  }
}

class _AlbumPhotoMonthGroup {
  const _AlbumPhotoMonthGroup({required this.title, required this.photos});

  final String title;
  final List<PhotoEntity> photos;
}

class _AlbumTagPhotoTile extends StatelessWidget {
  const _AlbumTagPhotoTile({required this.photo});

  final PhotoEntity photo;

  @override
  Widget build(BuildContext context) {
    final heroTag = 'album-tag-photo-${photo.id}';
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => showFullscreenPhotoViewer(
          context,
          path: photo.path,
          heroTag: heroTag,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Hero(
            tag: heroTag,
            child: _DeferredPathImage(path: photo.path, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

class _DeferredPathImage extends StatefulWidget {
  const _DeferredPathImage({required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  State<_DeferredPathImage> createState() => _DeferredPathImageState();
}

class _DeferredPathImageState extends State<_DeferredPathImage> {
  bool _ready = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 按路径哈希做轻微错峰，避免同一帧触发大量解码。
    final delayMs = 30 + (widget.path.hashCode.abs() % 9) * 35;
    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return PathImage(path: widget.path, fit: widget.fit);
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.grey.shade200),
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
