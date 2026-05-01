import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:collection';
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
import '../../service/story_queue_service.dart';
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
Future<List<PhotoEntity>> _loadAlbumTagBrowserSourcePhotos() {
  return PhotoService().isar.photoEntitys
      .where()
      .sortByTimestampDesc()
      .limit(_albumTagBrowserPhotoSoftLimit)
      .findAll()
      .then(PhotoService().reconcileAccessiblePhotos);
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

  // 馃専 1. 鏀逛负鐩存帴鐩戝惉鏈€缁?UI 鏁版嵁缁撴瀯鐨?Stream
  late Stream<Map<String, List<Event>>> _uiEventsStream;
  late Stream<_AlbumTagBrowserData> _albumTagBrowserStream;

  static const int _fullRefreshOption = -1;
  static const List<int> _refreshPhotoOptions = <int>[
    100,
    300,
    500,
    _fullRefreshOption,
  ];

  // 馃攧 鍒锋柊鏁版嵁锛氭壂鎻忕浉鍐?+ 杩愯鑱氱被
  /*Future<void> _refreshData({bool clearCacheFirst = false}) async {
    if (_isRefreshing) return; // 闃叉閲嶅鐐瑰嚮

    setState(() => _isRefreshing = true);

    try {
      if (clearCacheFirst) {
        await PhotoService().clearAllCachedData();
      }

      // 1. 鎵弿鐩稿唽锛堜粎鍏ュ簱鍘熷鍙敤鏁版嵁锛?
      final scanSummary = await PhotoService().scanAndSyncPhotos();

      // 2. 杩愯鑱氱被绠楁硶锛堜細鑷姩瑙﹀彂鍦板潃瑙ｆ瀽锛?
      await EventService().runClustering();

      // 3. 鑱氱被瀹屾垚鍚庡啀鍋?AI 鍒嗘瀽锛岀‘淇?eventId 宸插缓绔?
      await AIService().analyzePhotosInBackground();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              clearCacheFirst
                  ? '鉁?宸叉竻绌虹紦瀛樺苟瀹屾垚閲嶆壂锛氭柊澧?{scanSummary.insertedCount}寮狅紝鍙敤鎬绘暟${scanSummary.totalAfter}寮?
                  : '鉁?鏁版嵁宸叉洿鏂帮細鏂板${scanSummary.insertedCount}寮狅紝鍙敤鎬绘暟${scanSummary.totalAfter}寮?,
            ),
          ),
        );
      }
    } on PhotoScanException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('鈿狅笍 ${e.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('鉂?鏇存柊澶辫触: $e')));
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
            '将清空本 app 的本地数据库缓存（Isar + ObjectBox，包括照片、事件、故事、已扫描结果与向量索引），'
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
                  // 杩欓噷鍋囪浣犵殑浠ｇ爜閲屽畾涔変簡 _fullRefreshOption锛屽鏋滄病鏈夎鏇挎崲涓轰綘瀹為檯鐨勫€?
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
              PhotoService().isar.collection<PhotoEntity>().watchLazy(
                fireImmediately: true,
              ),
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
    // 浠呭姞杞芥渶杩戜竴娈垫暟鎹紝閬垮厤澶у浘搴撴瘡娆″彉鏇撮兘瑙﹀彂鍏ㄩ噺鎺掑簭銆?
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

  // 馃帹 1. 鏋勫缓绌虹姸鎬佺晫闈?
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

  // 馃帹 2. 鏋勫缓閿欒鎻愮ず鐣岄潰
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
    final isar = PhotoService().isar;

    // 閫愭潯寮傛杞崲锛岄伩鍏嶅ぇ鎵归噺骞跺彂瀵艰嚧涓荤嚎绋嬬灛鏃跺帇鍔涜繃楂樸€?
    final allEvents = <Event>[];
    for (var i = 0; i < eventEntities.length; i++) {
      final event = await eventEntities[i].toPreviewModel(isar);
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
