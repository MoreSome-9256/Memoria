// 相册页面，负责照片浏览、事件查看和标签筛选。

import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:collection';
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
import '../../service/app_ai_settings_service.dart';
import '../../service/media_access_grant_service.dart';
import '../../service/photo_service.dart';
import '../../service/story_queue_service.dart';
import '../../storage/objectbox/objectbox_service.dart';
import '../widgets/event_card.dart';
import 'media_access_range_page.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import '../widgets/junk_photo_cleanup_banner.dart';
import '../widgets/junk_photo_cleanup_dialog.dart';
import '../widgets/path_image.dart';
import 'album_search_page.dart';
import 'story_queue_page.dart';

part 'album_page_tag_browser.dart';
part 'album_page_deferred_image.dart';

const int _albumTagBrowserPhotoSoftLimit = 1200;
const int _importAllNewMediaLimit = 0x7fffffff;

enum _ImportAction {
  importAllNew,
  importLatest100,
  rebuildAll,
  addMorePhotos,
  managePermissions,
}

// Keep the tag overview and detail sheet on the same snapshot window so a
// fireImmediately refresh cannot overwrite a non-empty cluster with a narrower query.
Future<List<PhotoEntity>> _loadAlbumTagBrowserSourcePhotos() async {
  final photoBox = ObjectBoxService().store.box<PhotoEntity>();
  final q = photoBox
      .query()
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
  bool _isStartingImport = false;
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

  void _startRefresh({bool clearCacheFirst = false, int? recentPhotoLimit}) {
    if (_isClearingCache) {
      return;
    }
    setState(() => _isStartingImport = true);

    final scopeLabel =
        recentPhotoLimit == null || recentPhotoLimit == _importAllNewMediaLimit
        ? '全部新的图片和视频'
        : '最新的 $recentPhotoLimit 个未分析项目';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('已开始后台扫描 $scopeLabel，可随时切换页面继续使用。'),
      ),
    );

    final refreshFuture = AlbumRefreshService()
        .startRefresh(
          clearCacheFirst: clearCacheFirst,
          recentPhotoLimit: recentPhotoLimit,
        )
        .then((result) {
          if (result == null || !mounted) {
            return;
          }
          final scan = result.scanSummary;
          final handoffText = result.aiAlreadyRunning
              ? '后台 AI 已在运行，新照片已并入当前队列。'
              : 'AI 已转入后台继续打标。';

          final String message;
          if (result.clearCacheFirst) {
            message = result.recentPhotoLimit == null
                ? '已安全重建缓存，恢复 ${scan.totalAfter} 张照片。$handoffText'
                : '已安全重建最近 ${result.recentPhotoLimit} 张照片缓存。$handoffText';
          } else if (result.requeuedCount > 0) {
            message = '新增 ${result.requeuedCount} 张可入库照片，已加入打标队列。$handoffText';
          } else {
            message = '从最新往前检查了 ${scan.scannedCount} 张，本轮没有可入库新照片。$handoffText';
          }

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
        });
    unawaited(
      refreshFuture.whenComplete(() {
        if (mounted) {
          setState(() => _isStartingImport = false);
        }
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
      await AIService().endCurrentRoundSafely();
      await PhotoService().clearAllCachedData();
      AIService().clearPendingJunkCleanupReport();
      _lastPromptedJunkCleanupReportId = null;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('已清空本地缓存。系统相册原图未受影响，可点击右上角 + 重新导入。'),
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

  Future<PermissionState> _requestPhotoPermission({
    required String title,
    required String message,
    required RequestType type,
  }) async {
    var state = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(type: type, mediaLocation: false),
      ),
    );
    if (state.hasAccess) return state;

    if (!mounted) return state;

    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final s = await PhotoManager.requestPermissionExtend(
                requestOption: PermissionRequestOption(
                  androidPermission:
                      AndroidPermission(type: type, mediaLocation: false),
                ),
              );
              Navigator.pop(ctx, s.hasAccess);
            },
            child: const Text('授予权限'),
          ),
        ],
      ),
    );

    if (retry != true || !mounted) return state;

    state = await PhotoManager.requestPermissionExtend(
      requestOption: PermissionRequestOption(
        androidPermission: AndroidPermission(type: type, mediaLocation: false),
      ),
    );

    if (!state.hasAccess && mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('权限被拒绝'),
          content: const Text('请在系统设置中手动开启相册访问权限。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }

    return state;
  }

  Future<void> _showRefreshOptions() async {
    if (_isClearingCache) {
      return;
    }

    // ── 确保有相册权限 ──
    // 先申请图片权限
    final imageState = await _requestPhotoPermission(
      title: '需要图片访问权限',
      message: 'Memoria 需要读取您的照片，才能进行分析和管理。',
      type: RequestType.image,
    );
    if (!imageState.hasAccess || !mounted) return;

    // 如果用户开启了「包含视频」，额外申请视频权限
    final settings = await AppAiSettingsService.instance.load();
    if (settings.includeVideos) {
      final videoState = await _requestPhotoPermission(
        title: '需要视频访问权限',
        message: 'Memoria 需要读取您的视频，才能进行分析和管理。',
        type: RequestType.video,
      );
      if (!videoState.hasAccess || !mounted) return;
    }

    final permState = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.common,
          mediaLocation: false,
        ),
      ),
    );
    final isLimited = permState.isLimited;

    if (!mounted) return;

    final selected = await showModalBottomSheet<_ImportAction>(
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
                  title: Text('导入/更新'),
                  subtitle: Text('从系统相册中查找未分析的图片和视频'),
                ),
                ListTile(
                  leading: const Icon(Icons.done_all_outlined),
                  title: const Text('导入已授权范围内的新图片'),
                  subtitle: const Text('按相册时间倒序加入全部未分析项目'),
                  onTap: () =>
                      Navigator.pop(context, _ImportAction.importAllNew),
                ),
                ListTile(
                  leading: const Icon(Icons.flash_on_outlined),
                  title: const Text('导入最新 100 张未分析图片'),
                  subtitle: const Text('按创建时间或修改时间倒序加入最新一批'),
                  onTap: () =>
                      Navigator.pop(context, _ImportAction.importLatest100),
                ),
                if (isLimited)
                  ListTile(
                    leading: const Icon(Icons.add_photo_alternate_outlined),
                    title: const Text('添加更多可分析照片'),
                    subtitle: const Text('从系统相册中选择更多照片'),
                    onTap: () =>
                        Navigator.pop(context, _ImportAction.addMorePhotos),
                  ),
                if (isLimited) const Divider(),
                ListTile(
                  leading: const Icon(Icons.restart_alt_outlined),
                  title: const Text('重新分析全部'),
                  subtitle: const Text('删除缓存和分析结果后按系统相册重建'),
                  onTap: () => Navigator.pop(context, _ImportAction.rebuildAll),
                ),
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('管理照片访问权限'),
                  subtitle: const Text('修改授权范围、选择分析相册'),
                  onTap: () =>
                      Navigator.pop(context, _ImportAction.managePermissions),
                ),
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

    switch (selected) {
      case _ImportAction.importAllNew:
        _startRefresh(recentPhotoLimit: _importAllNewMediaLimit);
      case _ImportAction.importLatest100:
        _startRefresh(recentPhotoLimit: 100);
      case _ImportAction.rebuildAll:
        await _confirmAndRebuildAnalysis();
      case _ImportAction.addMorePhotos:
        await MediaAccessGrantService.instance.presentLimitedLibraryPicker();
      case _ImportAction.managePermissions:
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const MediaAccessRangePage(),
          ),
        );
    }
  }

  Future<void> _confirmAndRebuildAnalysis() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重新分析全部'),
          content: const Text('这会删除当前缓存和分析结果，并从系统相册重新开始分析。原始图片和视频不会被删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除缓存并重新分析'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      _startRefresh(clearCacheFirst: true);
    }
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
              ObjectBoxService().store
                  .box<PhotoEntity>()
                  .query()
                  .watch(triggerImmediately: true)
                  .map((_) {}),
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
              final isBusy =
                  _isClearingCache ||
                  _isStartingImport ||
                  refreshProgress.isRunning;
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
                      icon: isBusy
                          ? const SizedBox.square(
                              dimension: 20,
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
      body: Column(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: _DeferredImageLoadScheduler.pendingCountListenable,
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
                  _buildAnalysisProgressSection(),
                  ValueListenableBuilder<AlbumRefreshProgress>(
                    valueListenable: AlbumRefreshService().progressListenable,
                    builder: (context, refreshProgress, _) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: refreshProgress.isVisible
                            ? _buildImportProgressBanner(refreshProgress)
                            : const SizedBox.shrink(),
                      );
                    },
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
      ),
    );
  }

  Widget _buildAnalysisProgressSection() {
    return ValueListenableBuilder<AIAnalysisProgress>(
      valueListenable: AIService().progressListenable,
      builder: (context, progress, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: progress.isVisible
              ? _buildAnalysisProgressBanner(progress)
              : const SizedBox.shrink(),
        );
      },
    );
  }

  String _formatDurationCompact(Duration duration) {
    final totalSeconds = duration.inSeconds;
    if (totalSeconds <= 0) {
      return '0秒';
    }
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours小时$minutes分';
    }
    if (minutes > 0) {
      return '$minutes分$seconds秒';
    }
    return '$seconds秒';
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
    final avgSeconds = progress.averageSecondsPerItem;
    final avgLabel = avgSeconds == null
        ? '--'
        : '${avgSeconds.toStringAsFixed(1)} 秒/张';
    final eta = progress.estimatedRemainingDuration;
    final etaLabel = eta == null ? '--' : _formatDurationCompact(eta);
    final elapsedLabel = _formatDurationCompact(progress.elapsed);

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
          if (avgSeconds != null) ...[
            const SizedBox(height: 6),
            Text(
              '已耗时 $elapsedLabel · 预计剩余 $etaLabel · 平均 $avgLabel',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ],
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
                onPressed: progress.isStopping
                    ? null
                    : () => unawaited(_endCurrentAnalysisRound()),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('结束本轮'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImportProgressBanner(AlbumRefreshProgress progress) {
    final color = switch (progress.stage) {
      AlbumRefreshStage.failed => Colors.redAccent,
      AlbumRefreshStage.handoff => Colors.indigo,
      AlbumRefreshStage.queueing => Colors.blue,
      AlbumRefreshStage.clustering => Colors.deepPurple,
      _ => Colors.pinkAccent,
    };
    final icon = switch (progress.stage) {
      AlbumRefreshStage.queueing => Icons.playlist_add_check,
      AlbumRefreshStage.clustering => Icons.hub_outlined,
      AlbumRefreshStage.handoff => Icons.rocket_launch_outlined,
      AlbumRefreshStage.failed => Icons.error_outline,
      _ => Icons.photo_library_outlined,
    };

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  progress.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${(progress.progress * 100).round()}%',
                style: TextStyle(fontWeight: FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress.progress <= 0 ? null : progress.progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          const SizedBox(height: 8),
          Text(
            progress.message,
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _endCurrentAnalysisRound() async {
    try {
      await AIService().endCurrentRoundSafely();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('已安全结束当前 AI 任务队列。'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('结束当前任务失败: $error'),
        ),
      );
    }
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
          cacheExtent: 700,
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

  Future<Map<String, List<Event>>> _groupEvents(
    List<EventEntity> eventEntities,
  ) async {
    final grouped = <String, List<Event>>{};
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final coverIds = eventEntities
        .expand((event) => event.photoIds.take(3))
        .toSet()
        .toList(growable: false);
    final coverEntities = photoBox
        .getMany(coverIds)
        .whereType<PhotoEntity>()
        .toList(growable: false);
    final coverById = {for (final photo in coverEntities) photo.id: photo};
    Future<List<PhotoEntity>> loadPhotos(List<int> ids) async => ids
        .map((id) => coverById[id])
        .whereType<PhotoEntity>()
        .toList(growable: false);

    // 封面照片已批量加载，这里只做轻量模型转换并定期让出 UI 线程。
    final allEvents = <Event>[];
    for (var i = 0; i < eventEntities.length; i++) {
      final event = await eventEntities[i].toPreviewModel(
        loadPhotoEntities: loadPhotos,
      );
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
