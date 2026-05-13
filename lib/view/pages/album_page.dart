/// 相册页面，负责照片浏览、事件查看和标签筛选。

import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:collection';
import 'package:objectbox/objectbox.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../data/tag_taxonomy_v2.dart';
import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/event.dart';
import '../../objectbox.g.dart';
import '../../service/ai_service.dart';
import '../../service/album_refresh_service.dart';
import '../../service/album_tag_browser_service.dart';
import '../../service/event_service.dart';
import '../../service/junk_photo_cleanup_service.dart';
import '../../service/junk_photo_filter_service.dart';
import '../../service/photo_service.dart';
import '../../service/story_queue_service.dart';
import '../../storage/objectbox/objectbox_service.dart';
import '../widgets/event_card.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import '../widgets/junk_photo_cleanup_banner.dart';
import '../widgets/junk_photo_cleanup_dialog.dart';
import '../widgets/path_image.dart';
import 'album_search_page.dart';
import 'story_queue_page.dart';

part 'album_page_tag_browser.dart';
part 'album_page_deferred_image.dart';

const int _albumTagBrowserPhotoSoftLimit = 1200;

// Keep the tag overview and detail sheet on the same snapshot window so a
// fireImmediately refresh cannot overwrite a non-empty cluster with a narrower query.
Future<List<PhotoEntity>> _loadAlbumTagBrowserSourcePhotos() async {
  final photoBox = ObjectBoxService().store.box<PhotoEntity>();
  final q = photoBox.query()
      .order(PhotoEntity_.timestamp, flags: Order.descending)
      .build();
  final photos = q
      .find()
      .take(_albumTagBrowserPhotoSoftLimit)
      .toList(growable: false);
  q.close();
  return PhotoService().reconcileAccessiblePhotos(photos);
}

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key});

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

enum _AlbumViewMode { tags, moments }

class _AlbumPageState extends State<AlbumPage> {
  static const double _contentBottomInset = 118;
  static const int _tagBrowserYieldChunk = 120;
  bool _isClearingCache = false;
  bool _tagBrowserAiRecoveryTriggered = false;
  String? _lastPromptedJunkCleanupReportId;
  final TextEditingController _semanticSearchController =
      TextEditingController();
  final FocusNode _semanticSearchFocusNode = FocusNode();
  final AlbumTagBrowserService _albumTagBrowserService =
      AlbumTagBrowserService();
  final ScrollController _momentsScrollController = ScrollController();
  final Map<String, GlobalKey> _momentSectionKeys = <String, GlobalKey>{};
  final GlobalKey _momentsFastScrollerTrackKey = GlobalKey();
  _AlbumViewMode _viewMode = _AlbumViewMode.tags;
  Timer? _momentsFastScrollerHideTimer;
  bool _showMomentsFastScroller = false;
  bool _draggingMomentsFastScroller = false;
  String? _momentsFastScrollerLabel;

  // UI streams for moments and tag browser data.
  late Stream<Map<String, List<Event>>> _uiEventsStream;
  late Stream<_AlbumTagBrowserData> _albumTagBrowserStream;

  // Keep this in sync with _fullRefreshOption.
  static const List<int> _refreshPhotoOptions = <int>[
    100,
    300,
    500,
    // Keep this in sync with _fullRefreshOption.
  ];

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
            final scannedCount = scanSummary.scannedCount;
            final insertedCount = scanSummary.insertedCount;
            final nonInsertedCount = scannedCount > insertedCount
                ? (scannedCount - insertedCount)
                : 0;
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
                      : nonInsertedCount > 0
                      ? '已扫描下一批 ${result.recentPhotoLimit} 张照片，实际新增入库 $insertedCount 张，并将其中 ${result.requeuedCount} 张加入中文打标队列；其余 $nonInsertedCount 张未入库。'
                      : '已扫描下一批 ${result.recentPhotoLimit} 张照片，并将新增入库的 ${result.requeuedCount} 张加入中文打标队列。'
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
                content: Text('更新失败: $error'),
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
            '将清空本 app 的本地数据库缓存（ObjectBox，包括照片、事件、故事、已扫描结果与向量索引），'
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
      AlbumRefreshService().resetScanOffsets();
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
                  // Keep this in sync with _fullRefreshOption.
                  final isFull = option == -1;
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
                // 鐣欏嚭搴曢儴瀹夊叏璺濈
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
      // Keep this in sync with _fullRefreshOption.
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
      if (!mounted) {
        return;
      }
      AIService().clearPendingJunkCleanupReport();
      final keptCount = remainingCandidates.length;
      final message = removedCount <= 0
          ? keptCount > 0
                ? '未删除本地记录，已保留 $keptCount 张低质量候选，不会自动重新打标。'
                : '没有删除任何本地数据库记录。'
          : keptCount > 0
          ? '已删除 $removedCount 张低质量图片记录，并保留其余 $keptCount 张候选，不会自动重新打标。'
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
    AIService().clearPendingJunkCleanupReport();
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

    _albumTagBrowserStream =
        _debounceStream<void>(
              ObjectBoxService().store.box<PhotoEntity>().query().watch(triggerImmediately: true).map((_) => null),
              const Duration(milliseconds: 700),
            )
            .asyncMap((_) => _loadAllPhotosForTagBrowser())
            .asyncMap(_buildAlbumTagBrowserData)
            .asBroadcastStream();
  }

  Future<_AlbumTagBrowserData> _buildAlbumTagBrowserData(
    List<PhotoEntity> photos,
  ) async {
    var analyzedPhotoCount = 0;
    final taggedPhotos = <PhotoEntity>[];

    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      if (photo.isAiAnalyzed) {
        analyzedPhotoCount += 1;
      }
      if (_albumTagBrowserService.hasBrowsableCategory(photo)) {
        taggedPhotos.add(photo);
      }

      if (i % _tagBrowserYieldChunk == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    taggedPhotos.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    await Future<void>.delayed(Duration.zero);

    final clusters = _albumTagBrowserService.buildCoarseClusters(
      taggedPhotos,
      fineTopK: memoriaFineTopK,
    );

    return _AlbumTagBrowserData(
      totalPhotoCount: photos.length,
      analyzedPhotoCount: analyzedPhotoCount,
      taggedPhotoCount: taggedPhotos.length,
      photos: taggedPhotos,
      clusters: clusters,
    );
  }

  @override
  void dispose() {
    AIService().junkCleanupReportListenable.removeListener(
      _onJunkCleanupReportChanged,
    );
    _momentsFastScrollerHideTimer?.cancel();
    _momentsScrollController.dispose();
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
    // Load a bounded recent window to avoid full-library resorting on every change.
    return _loadAlbumTagBrowserSourcePhotos();
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
              ValueListenableBuilder<int>(
                valueListenable:
                    _DeferredImageLoadScheduler.pendingCountListenable,
                builder: (context, pendingCount, _) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: pendingCount > 0
                        ? const LinearProgressIndicator(
                            key: ValueKey<String>('deferred-images-loading'),
                            minHeight: 2.5,
                          )
                        : const SizedBox.shrink(),
                  );
                },
              ),
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
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.34,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: progress.isVisible
                            ? _buildAnalysisProgressBanner(progress)
                            : const SizedBox.shrink(),
                      ),
                      ValueListenableBuilder<JunkPhotoCleanupReport?>(
                        valueListenable:
                            AIService().junkCleanupReportListenable,
                        builder: (context, report, _) {
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: report == null || !report.hasCandidates
                                ? const SizedBox.shrink()
                                : JunkPhotoCleanupBanner(
                                    key: ValueKey<String>(report.reportId),
                                    report: report,
                                    onReview: () =>
                                        _showJunkCleanupDialog(report),
                                    onDismiss: _dismissJunkCleanupBanner,
                                  ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _viewMode == _AlbumViewMode.tags ? 0 : 1,
                  children: [_buildAlbumTagBrowserView(), _buildMomentsView()],
                ),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
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

  // Empty state.
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
        final totalPhotoCount = browserData?.totalPhotoCount ?? 0;
        final analyzedPhotoCount = browserData?.analyzedPhotoCount ?? 0;
        if (totalPhotoCount > 0 &&
            analyzedPhotoCount <= 0 &&
            !AIService().isAnalyzing &&
            !_tagBrowserAiRecoveryTriggered) {
          _tagBrowserAiRecoveryTriggered = true;
          unawaited(AIService().analyzePhotosInBackground());
        } else if (analyzedPhotoCount > 0 || AIService().isAnalyzing) {
          _tagBrowserAiRecoveryTriggered = false;
        }
        if (clusters.isEmpty) {
          return _buildTagBrowserEmptyState(browserData);
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
          return _buildTopIndeterminateLoading();
        }

        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString());
        }

        final groupedEvents = snapshot.data ?? {};
        if (groupedEvents.isEmpty) {
          return _buildEmptyState();
        }

        final items = <Object>[];
        final sectionKeys = <String, GlobalKey>{};
        for (final entry in groupedEvents.entries) {
          items.add(entry.key);
          items.addAll(entry.value);
          sectionKeys[entry.key] = _momentSectionKeys[entry.key] ?? GlobalKey();
        }
        _momentSectionKeys
          ..clear()
          ..addAll(sectionKeys);

        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification ||
                    notification is UserScrollNotification) {
                  _handleMomentsScrollActivity();
                }
                return false;
              },
              child: ListView.builder(
                controller: _momentsScrollController,
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  _contentBottomInset + MediaQuery.of(context).padding.bottom,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item is String) {
                    return Padding(
                      key: _momentSectionKeys[item],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        item,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }
                  return EventCard(event: item as Event);
                },
              ),
            ),
            _buildMomentsFastScroller(
              groupedEvents.keys.toList(growable: false),
            ),
          ],
        );
      },
    );
  }

  void _handleMomentsScrollActivity() {
    _updateMomentsFastScrollerLabel();
    if (!_showMomentsFastScroller && mounted) {
      setState(() {
        _showMomentsFastScroller = true;
      });
    }
    _momentsFastScrollerHideTimer?.cancel();
    _momentsFastScrollerHideTimer = Timer(
      const Duration(milliseconds: 900),
      () {
        if (!mounted || _draggingMomentsFastScroller) {
          return;
        }
        setState(() {
          _showMomentsFastScroller = false;
          _momentsFastScrollerLabel = null;
        });
      },
    );
  }

  void _updateMomentsFastScrollerLabel() {
    if (_momentSectionKeys.isEmpty) {
      return;
    }
    String? currentLabel;
    for (final entry in _momentSectionKeys.entries) {
      final context = entry.value.currentContext;
      if (context == null) {
        continue;
      }
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) {
        continue;
      }
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy <= 180) {
        currentLabel = entry.key;
      } else {
        break;
      }
    }
    if (currentLabel != null &&
        currentLabel != _momentsFastScrollerLabel &&
        mounted) {
      setState(() {
        _momentsFastScrollerLabel = currentLabel;
      });
    }
  }

  void _jumpToMomentSection(String label) {
    final context = _momentSectionKeys[label]?.currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      alignment: 0.04,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  Widget _buildMomentsFastScroller(List<String> labels) {
    if (labels.length <= 1) {
      return const SizedBox.shrink();
    }
    final visible = _showMomentsFastScroller || _draggingMomentsFastScroller;
    final bubbleLabel = _momentsFastScrollerLabel;
    return Positioned(
      right: 8,
      top: 110,
      bottom: 140,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: visible ? 1 : 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (bubbleLabel != null)
                Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    bubbleLabel,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) {
                  setState(() {
                    _draggingMomentsFastScroller = true;
                    _showMomentsFastScroller = true;
                  });
                },
                onVerticalDragUpdate: (details) {
                  final box =
                      _momentsFastScrollerTrackKey.currentContext
                              ?.findRenderObject()
                          as RenderBox?;
                  if (box == null || labels.isEmpty) {
                    return;
                  }
                  final local = box.globalToLocal(details.globalPosition);
                  final height = box.size.height;
                  final ratio = (local.dy / height).clamp(0.0, 0.999);
                  final index = (ratio * labels.length).floor().clamp(
                    0,
                    labels.length - 1,
                  );
                  final label = labels[index];
                  if (label != _momentsFastScrollerLabel && mounted) {
                    setState(() {
                      _momentsFastScrollerLabel = label;
                    });
                  }
                  _jumpToMomentSection(label);
                },
                onVerticalDragEnd: (_) {
                  _momentsFastScrollerHideTimer?.cancel();
                  setState(() {
                    _draggingMomentsFastScroller = false;
                  });
                  _handleMomentsScrollActivity();
                },
                child: Container(
                  key: _momentsFastScrollerTrackKey,
                  width: 28,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.unfold_more_rounded,
                    size: 18,
                    color: Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagBrowserEmptyState(_AlbumTagBrowserData? browserData) {
    final totalPhotoCount = browserData?.totalPhotoCount ?? 0;
    final analyzedPhotoCount = browserData?.analyzedPhotoCount ?? 0;
    final taggedPhotoCount = browserData?.taggedPhotoCount ?? 0;
    final aiProgress = AIService().progressListenable.value;

    String title;
    String subtitle;
    IconData icon;

    if (totalPhotoCount <= 0) {
      title = '暂时还没有可浏览的标签聚类';
      subtitle = '先点击右上角 + 扫描相册，系统再按粗粒度标签自动整理相册。';
      icon = Icons.sell_outlined;
    } else if (analyzedPhotoCount <= 0 || aiProgress.isVisible) {
      title = '照片已入库，正在后台打标';
      final completedText = aiProgress.total > 0
          ? '${aiProgress.completed}/${aiProgress.total}'
          : '$analyzedPhotoCount/$totalPhotoCount';
      subtitle =
          '当前已有 $totalPhotoCount 张照片，AI 正在补充标签与文案（$completedText）。打标完成后，这里会自动出现标签预览。';
      icon = Icons.auto_awesome_outlined;
    } else if (taggedPhotoCount <= 0) {
      title = '已完成分析，但暂未形成标签预览';
      subtitle =
          '当前已有 $analyzedPhotoCount 张照片完成分析，但还没有可用于标签浏览的分类结果。可以稍后再看，或继续补扫、补打标。';
      icon = Icons.label_outline;
    } else {
      title = '暂时还没有可浏览的标签分类';
      subtitle = '标签结果正在整理中，请稍候再试。';
      icon = Icons.sell_outlined;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(title),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // Error state.
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

  Widget _buildTopIndeterminateLoading() {
    return Column(
      children: [
        const LinearProgressIndicator(minHeight: 2.5),
        Expanded(
          child: Center(
            child: Text('正在加载相册...', style: TextStyle(color: Colors.grey[600])),
          ),
        ),
      ],
    );
  }

  // 灏?EventEntity 鍒楄〃杞崲涓哄垎缁勭殑 Event 鍒楄〃
  Future<Map<String, List<Event>>> _groupEvents(
    List<EventEntity> eventEntities,
  ) async {
    final grouped = <String, List<Event>>{};
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    Future<List<PhotoEntity>> loadPhotos(List<int> ids) async =>
        photoBox.getMany(ids).whereType<PhotoEntity>().toList(growable: false);

    // 閫愭潯寮傛杞崲锛岄伩鍏嶅ぇ鎵归噺骞跺彂瀵艰嚧涓荤嚎绋嬬灛鏃跺帇鍔涜繃楂樸€?
    final allEvents = <Event>[];
    for (var i = 0; i < eventEntities.length; i++) {
      final event = await eventEntities[i].toPreviewModel(loadPhotoEntities: loadPhotos);
      allEvents.add(event);
      if (i % 8 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    // 2. 一级标题按年份和季节分组，具体到日的信息保留在卡片内部。
    for (final event in allEvents) {
      final key = _seasonGroupKey(event.startDate);
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
      }
      grouped[key]!.add(event);
    }

    return grouped;
  }

  String _seasonGroupKey(DateTime date) {
    final season = switch (date.month) {
      3 || 4 || 5 => '春',
      6 || 7 || 8 => '夏',
      9 || 10 || 11 => '秋',
      _ => '冬',
    };
    return '${date.year}年 · $season';
  }
}

/*
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

enum _ClusterSelectionMenuAction { selectAll, clear, cancel }
enum _ClusterActionMode { none, story, delete }

class _AlbumTagClusterSheetState extends State<_AlbumTagClusterSheet> {
  final AlbumTagBrowserService _browserService = AlbumTagBrowserService();
  String? _selectedFineTag;
  static const int _secondaryFilterTopK = 12;
  static const double _sheetBottomInset = 168;
  late final Stream<List<PhotoEntity>> _photosStream;
  _ClusterActionMode _actionMode = _ClusterActionMode.none;
  final Set<int> _selectedPhotoIds = <int>{};

  bool get _isSelectionMode => _actionMode != _ClusterActionMode.none;
  bool get _isDeleteMode => _actionMode == _ClusterActionMode.delete;

  @override
  void initState() {
    super.initState();
    _photosStream = _debounceStream<void>(
      ObjectBoxService().store.box<PhotoEntity>().query().watch(triggerImmediately: true).map((_) => null),
      const Duration(milliseconds: 650),
    ).asyncMap((_) => _loadCurrentPhotos());
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

        return Stack(
          children: [
            SizedBox(
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
                                  final photo = group.photos[index];
                                  return _AlbumTagPhotoTile(
                                    photo: photo,
                                    selectionMode: _isSelectionMode,
                                    deleteMode: _isDeleteMode,
                                    selected: _selectedPhotoIds.contains(photo.id),
                                    onTap: () {
                                      if (_isSelectionMode) {
                                        _toggleSelection(photo.id);
                                        return;
                                      }
                                      showFullscreenPhotoViewer(
                                        context,
                                        path: photo.path,
                                        heroTag: 'album-tag-photo-${photo.id}',
                                      );
                                    },
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
            ),
            Positioned(
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: _buildFloatingActions(clusterPhotos),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFloatingActions(List<PhotoEntity> clusterPhotos) {
    return ValueListenableBuilder<List<StoryQueueItem>>(
      valueListenable: StoryQueueService().queueListenable,
      builder: (context, items, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (items.isNotEmpty) ...[
              FloatingActionButton.extended(
                heroTag: 'tag-cluster-queue',
                onPressed: _openStoryQueuePage,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text('队列 ${items.length}'),
              ),
              const SizedBox(height: 10),
            ],
            if (_isSelectionMode)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSelectionMenuButton(
                    enableSelectAll: clusterPhotos.isNotEmpty,
                    onSelected: (action) {
                      switch (action) {
                        case _ClusterSelectionMenuAction.selectAll:
                          setState(() {
                            _selectedPhotoIds.addAll(
                              clusterPhotos.map((photo) => photo.id),
                            );
                          });
                          break;
                        case _ClusterSelectionMenuAction.clear:
                          setState(() {
                            _selectedPhotoIds.clear();
                          });
                          break;
                        case _ClusterSelectionMenuAction.cancel:
                          setState(() {
                            _actionMode = _ClusterActionMode.none;
                            _selectedPhotoIds.clear();
                          });
                          break;
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton.extended(
                    heroTag: 'tag-cluster-story',
                    onPressed: _isDeleteMode
                        ? () => _deleteSelectionFromLocalIndex(clusterPhotos)
                        : () => _addSelectionToQueue(clusterPhotos),
                    icon: Icon(
                      _isDeleteMode
                          ? Icons.delete_outline_rounded
                          : Icons.playlist_add_rounded,
                    ),
                    label: Text(
                      _selectedPhotoIds.isEmpty
                          ? (_isDeleteMode ? '删除本地记录' : '加入故事队列')
                          : (_isDeleteMode
                              ? '删除本地记录 ${_selectedPhotoIds.length}'
                              : '加入故事队列 ${_selectedPhotoIds.length}'),
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'tag-cluster-delete',
                    onPressed: () {
                      setState(() {
                        _actionMode = _ClusterActionMode.delete;
                        _selectedPhotoIds.clear();
                      });
                    },
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  const SizedBox(width: 10),
                  FloatingActionButton.extended(
                    heroTag: 'tag-cluster-story',
                    onPressed: () {
                      setState(() {
                        _actionMode = _ClusterActionMode.story;
                        _selectedPhotoIds.clear();
                      });
                    },
                    icon: const Icon(Icons.auto_stories_rounded),
                    label: const Text('生成故事'),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildSelectionMenuButton({
    required ValueChanged<_ClusterSelectionMenuAction> onSelected,
    required bool enableSelectAll,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: const CircleBorder(),
      child: PopupMenuButton<_ClusterSelectionMenuAction>(
        tooltip: '选图操作',
        onSelected: onSelected,
        itemBuilder: (context) => <PopupMenuEntry<_ClusterSelectionMenuAction>>[
          PopupMenuItem<_ClusterSelectionMenuAction>(
            value: _ClusterSelectionMenuAction.selectAll,
            enabled: enableSelectAll,
            child: const Text('全选'),
          ),
          const PopupMenuItem<_ClusterSelectionMenuAction>(
            value: _ClusterSelectionMenuAction.clear,
            child: Text('清空'),
          ),
          const PopupMenuItem<_ClusterSelectionMenuAction>(
            value: _ClusterSelectionMenuAction.cancel,
            child: Text('取消'),
          ),
        ],
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.more_horiz_rounded),
        ),
      ),
    );
  }

  void _toggleSelection(int photoId) {
    setState(() {
      if (_selectedPhotoIds.contains(photoId)) {
        _selectedPhotoIds.remove(photoId);
      } else {
        _selectedPhotoIds.add(photoId);
      }
    });
  }

  void _addSelectionToQueue(List<PhotoEntity> clusterPhotos) {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一张照片加入故事队列')),
      );
      return;
    }

    final selected = clusterPhotos
        .where((photo) => _selectedPhotoIds.contains(photo.id))
        .map(StoryQueueService.mapPhotoEntityToQueuePhoto)
        .toList(growable: false);
    final addedCount = StoryQueueService().addPhotos(selected);

    setState(() {
      _actionMode = _ClusterActionMode.none;
      _selectedPhotoIds.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          addedCount > 0 ? '已加入故事队列 $addedCount 张' : '这些照片已经在故事队列里了',
        ),
      ),
    );
    _openStoryQueuePage();
  }

  Future<void> _deleteSelectionFromLocalIndex(
    List<PhotoEntity> clusterPhotos,
  ) async {
    if (_selectedPhotoIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一张照片再删除')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除本地记录'),
          content: Text(
            '将从 App 本地数据库中删除 ${_selectedPhotoIds.length} 张照片记录，不会删除手机系统相册中的原图。是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final selected = clusterPhotos
        .where((photo) => _selectedPhotoIds.contains(photo.id))
        .toList(growable: false);

    var removedCount = 0;
    for (final entity in selected) {
      await JunkPhotoCleanupService().removeFromLocalIndex(entity);
      StoryQueueService().removePhoto(entity.assetId);
      removedCount += 1;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _actionMode = _ClusterActionMode.none;
      _selectedPhotoIds.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          removedCount > 0 ? '已删除 $removedCount 条本地记录' : '没有删除任何本地记录',
        ),
      ),
    );
  }

  void _openStoryQueuePage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const StoryQueuePage(),
      ),
    );
  }

  Future<List<PhotoEntity>> _loadCurrentPhotos() async {
    if (AIService().isAnalyzing) {
      // 打标高峰期避免每次写库都触发重查，减少 UI 抢占。
      return widget.allPhotos;
    }

    return _loadAlbumTagBrowserSourcePhotos();
  }

  List<_AlbumPhotoMonthGroup> _groupPhotosByMonth(List<PhotoEntity> photos) {
    final grouped = <String, List<PhotoEntity>>{};
    for (final photo in photos) {
      final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
    if (parts.length != 3) {
      return key;
    }
    return '${parts[0]}年${parts[1]}月${parts[2]}日';
  }
}

class _AlbumPhotoMonthGroup {
  const _AlbumPhotoMonthGroup({required this.title, required this.photos});

  final String title;
  final List<PhotoEntity> photos;
}

class _DeferredImageTicket {
  _DeferredImageTicket();

  bool started = false;
  bool completed = false;
}

class _DeferredImageLoadScheduler {
  static const int _maxConcurrent = 4;
  static final ValueNotifier<int> pendingCountListenable = ValueNotifier<int>(
    0,
  );
  static final Queue<(_DeferredImageTicket, VoidCallback)> _queue =
      Queue<(_DeferredImageTicket, VoidCallback)>();
  static int _active = 0;
  static int _pendingCount = 0;
  static bool _flushScheduled = false;

  static void enqueue(_DeferredImageTicket ticket, VoidCallback starter) {
    if (ticket.completed) {
      return;
    }
    _setPendingCount(_pendingCount + 1);
    _queue.add((ticket, starter));
    _pump();
  }

  static void complete(_DeferredImageTicket ticket) {
    if (ticket.completed) {
      return;
    }
    ticket.completed = true;

    if (ticket.started && _active > 0) {
      _active -= 1;
    } else {
      _queue.removeWhere((entry) => identical(entry.$1, ticket));
    }

    final next = _pendingCount - 1;
    _setPendingCount(next < 0 ? 0 : next);
    _pump();
  }

  static void _setPendingCount(int value) {
    _pendingCount = value;
    _scheduleFlush();
  }

  static void _scheduleFlush() {
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (pendingCountListenable.value != _pendingCount) {
        pendingCountListenable.value = _pendingCount;
      }
    });
  }

  static void _pump() {
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final (ticket, starter) = _queue.removeFirst();
      if (ticket.completed) {
        continue;
      }
      ticket.started = true;
      _active += 1;
      starter();
    }
  }
}

class _AlbumTagPhotoTile extends StatelessWidget {
  const _AlbumTagPhotoTile({
    required this.photo,
    required this.selectionMode,
    required this.deleteMode,
    required this.selected,
    required this.onTap,
  });

  final PhotoEntity photo;
  final bool selectionMode;
  final bool deleteMode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final heroTag = 'album-tag-photo-${photo.id}';
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: _DeferredPathImage(path: photo.path, fit: BoxFit.cover),
              ),
              if (selectionMode && !selected)
                Container(color: Colors.black.withValues(alpha: 0.32)),
              if (selectionMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: selected
                          ? (deleteMode
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary)
                          : Colors.white.withValues(alpha: 0.88),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Icon(
                      selected
                          ? (deleteMode
                              ? Icons.delete_rounded
                              : Icons.check_rounded)
                          : Icons.add_rounded,
                      size: 16,
                      color: selected
                          ? Colors.white
                          : (deleteMode
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
            ],
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
  final _DeferredImageTicket _ticket = _DeferredImageTicket();
  bool _ready = false;
  bool _firstFrameReported = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _DeferredImageLoadScheduler.enqueue(_ticket, _startDeferredLoad);
  }

  void _startDeferredLoad() {
    // 鎸夎矾寰勫搱甯岄敊宄?+ 骞跺彂闄愭祦锛岄伩鍏嶇煭鏃堕棿瑙﹀彂澶ч噺鍥剧墖瑙ｇ爜銆?
    final delayMs = 30 + (widget.path.hashCode.abs() % 11) * 28;
    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || _ticket.completed) {
        return;
      }
      setState(() {
        _ready = true;
      });
    });
  }

  void _onFirstFrame() {
    if (_firstFrameReported) {
      return;
    }
    _firstFrameReported = true;
    _DeferredImageLoadScheduler.complete(_ticket);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _DeferredImageLoadScheduler.complete(_ticket);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return PathImage(
        path: widget.path,
        fit: widget.fit,
        onFirstFrame: _onFirstFrame,
      );
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
*/
