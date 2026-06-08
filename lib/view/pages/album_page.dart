// 相册页面，负责照片浏览、事件查看和标签筛选。

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../../service/unified_analysis_pipeline_service.dart';
import '../../service/unified_analysis_progress.dart';
import '../../service/unified_analysis_progress_store.dart';
import '../../storage/objectbox/objectbox_service.dart';
import '../../utils/media_type_helper.dart';
import '../widgets/event_card.dart';
import 'media_access_range_page.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import '../widgets/junk_photo_cleanup_banner.dart';
import '../widgets/junk_photo_cleanup_dialog.dart';
import '../widgets/media_thumbnail.dart';
import 'album_search_page.dart';
import 'story_queue_page.dart';

part 'album_page_tag_browser.dart';
part 'album_page_deferred_image.dart';

const int _albumTagBrowserPhotoSoftLimit = 1200;

enum _ImportAction {
  importAllNew,
  updateCacheOnly,
  rebuildAll,
  addMorePhotos,
  requestFullAccess,
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
  bool _isStartingImport = false;
  bool _isDeletingCurrentTask = false;
  bool _tagBrowserAiRecoveryTriggered = false;
  bool _hiddenPendingAnalysisPromptForSession = false;
  bool _autoResumePendingStarted = false;
  int _pendingAnalysisCandidateCount = 0;
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
  Timer? _foregroundCardElapsedTimer;
  DateTime? _foregroundCardStartedAt;
  bool _showMomentsFastScroller = false;
  bool _draggingMomentsFastScroller = false;
  String? _momentsFastScrollerLabel;

  // UI streams for moments and tag browser data.
  late Stream<Map<String, List<Event>>> _uiEventsStream;
  late Stream<_AlbumTagBrowserData> _albumTagBrowserStream;
  StreamSubscription<void>? _pendingAnalysisSubscription;

  void _startRefresh({
    bool clearCacheFirst = false,
    bool analyzeWithAi = true,
  }) {
    final foregroundProgress =
        UnifiedAnalysisProgressStore.instance.progress.value;
    if (_isStartingImport ||
        AlbumRefreshService().isRunning ||
        foregroundProgress.isRunning ||
        AIService().isAnalyzing) {
      return;
    }
    setState(() => _isStartingImport = true);

    final scopeLabel = analyzeWithAi ? '全部新的图片和视频' : '相册缓存';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('已开始后台扫描 $scopeLabel，可随时切换页面继续使用。'),
      ),
    );

    final refreshFuture = AlbumRefreshService()
        .startRefresh(
          clearCacheFirst: clearCacheFirst,
          analyzeWithAi: analyzeWithAi,
        )
        .then((result) {
          if (result == null || !mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                analyzeWithAi
                    ? '前台任务已启动，扫描和 AI 进度会在上方更新。'
                    : '前台缓存任务已启动，进度会在上方更新。',
              ),
              duration: const Duration(seconds: 2),
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

  void _handleScanButtonPressed() {
    if (_isStartingImport ||
        AlbumRefreshService().isRunning ||
        UnifiedAnalysisProgressStore.instance.progress.value.isRunning ||
        AIService().isAnalyzing) {
      return;
    }
    _showRefreshOptions();
  }

  Future<void> _refreshPendingAnalysisPrompt() async {
    final count = PhotoService().countPendingAnalysisCandidates();
    if (!mounted) {
      return;
    }
    if (count != _pendingAnalysisCandidateCount) {
      setState(() {
        _pendingAnalysisCandidateCount = count;
        if (count == 0) {
          _hiddenPendingAnalysisPromptForSession = false;
        }
      });
    }

    if (count > 0 &&
        !_autoResumePendingStarted &&
        !AlbumRefreshService().isRunning &&
        !UnifiedAnalysisProgressStore.instance.progress.value.isRunning) {
      final settings = await AppAiSettingsService.instance.load();
      if (!mounted) {
        return;
      }
      if (settings.autoResumeAnalysis) {
        _autoResumePendingStarted = true;
        unawaited(_resumePendingAnalysisCandidates());
      }
    }
  }

  Future<void> _resumePendingAnalysisCandidates() async {
    final count = PhotoService().countPendingAnalysisCandidates();
    if (count <= 0) {
      await _refreshPendingAnalysisPrompt();
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('正在继续分析 $count 个未完成图片。'),
      ),
    );
    try {
      await UnifiedAnalysisPipelineService().startPendingAnalysisCandidates();
    } finally {
      await AIService().refreshJunkCleanupReportFromDatabase(
        replaceExisting: false,
      );
      if (mounted) {
        await _refreshPendingAnalysisPrompt();
      }
    }
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

  Future<void> _deleteCurrentAnalysisTask() async {
    if (_isDeletingCurrentTask) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除当前任务'),
        content: const Text(
          '将中断当前前台任务，并清空本地数据库中的 AI 分析结果、候选队列、事件聚类、向量索引和低价值标记。照片记录和系统相册原图不会删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('删除任务'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isDeletingCurrentTask = true);
    try {
      final clearedCount = await UnifiedAnalysisPipelineService()
          .deleteCurrentTaskAndClearAnalysisData();
      AIService().clearPendingJunkCleanupReport();
      _DeferredImageLoadScheduler.reset();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await _refreshPendingAnalysisPrompt();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('已删除当前任务，并清空 $clearedCount 张照片的 AI 分析字段。'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('删除当前任务失败: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingCurrentTask = false);
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
                  androidPermission: AndroidPermission(
                    type: type,
                    mediaLocation: false,
                  ),
                ),
              );
              if (ctx.mounted) {
                Navigator.pop(ctx, s.hasAccess);
              }
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
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('仅更新相册缓存'),
                  subtitle: const Text('只扫描并写入数据库，不预热 AI，不移交打标任务'),
                  onTap: () =>
                      Navigator.pop(context, _ImportAction.updateCacheOnly),
                ),
                if (isLimited)
                  ListTile(
                    leading: const Icon(Icons.add_photo_alternate_outlined),
                    title: const Text('添加更多可分析照片'),
                    subtitle: const Text('从系统相册中选择更多照片'),
                    onTap: () =>
                        Navigator.pop(context, _ImportAction.addMorePhotos),
                  ),
                if (isLimited)
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('重新申请全部照片访问'),
                    subtitle: const Text('让系统再次尝试授权完整照片与视频范围'),
                    onTap: () =>
                        Navigator.pop(context, _ImportAction.requestFullAccess),
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
        _startRefresh();
      case _ImportAction.updateCacheOnly:
        _startRefresh(analyzeWithAi: false);
      case _ImportAction.rebuildAll:
        await _confirmAndRebuildAnalysis();
      case _ImportAction.addMorePhotos:
        await MediaAccessGrantService.instance.presentLimitedLibraryPicker();
      case _ImportAction.requestFullAccess:
        final state = await MediaAccessGrantService.instance
            .requestFullLibraryAccess();
        if (!mounted) return;
        final text = state.isAuth
            ? '已获得完整照片访问权限。'
            : state.isLimited
            ? '系统仍处于部分授权；可继续添加照片，或在系统设置改为全部照片。'
            : '未获得照片访问权限。';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(text),
            action: state.isLimited
                ? SnackBarAction(
                    label: '系统设置',
                    onPressed: () {
                      unawaited(PhotoManager.openSetting());
                    },
                  )
                : null,
          ),
        );
      case _ImportAction.managePermissions:
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const MediaAccessRangePage()),
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
    await _markSelectedJunkRecords(report, selectedPhotoIds ?? const <int>[]);
  }

  Future<void> _markSelectedJunkRecords(
    JunkPhotoCleanupReport report,
    List<int> selectedPhotoIds,
  ) async {
    try {
      final selectedCandidates = report.candidates
          .where((candidate) => selectedPhotoIds.contains(candidate.photoId))
          .toList(growable: false);
      final markedCount = await JunkPhotoCleanupService()
          .markCandidatesAsLowValue(selectedCandidates);
      final remainingCandidates = report.candidates
          .where((candidate) => !selectedPhotoIds.contains(candidate.photoId))
          .toList(growable: false);
      if (remainingCandidates.isNotEmpty) {
        await JunkPhotoCleanupService().markCandidatesAsKept(
          remainingCandidates,
        );
        AIService().markJunkCandidatesAsKept(
          remainingCandidates.map((candidate) => candidate.photoId),
        );
      }
      if (!mounted) {
        return;
      }
      AIService().clearPendingJunkCleanupReport();
      final keptCount = remainingCandidates.length;
      final message = markedCount <= 0
          ? keptCount > 0
                ? '未标记新的低价值照片，已保留 $keptCount 张候选，不会自动重新打标。'
                : '没有标记新的低价值照片。'
          : keptCount > 0
          ? '已标记 $markedCount 张低价值照片，并保留其余 $keptCount 张候选，不会自动重新打标。'
          : '已标记 $markedCount 张低价值照片，可在低价值照片回收站查看。';
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
          content: Text('标记低价值照片失败: $error'),
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
    UnifiedAnalysisProgressStore.instance.progress.addListener(
      _onForegroundProgressForCardChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _onForegroundProgressForCardChanged();
      }
    });
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
    _pendingAnalysisSubscription =
        _debounceStream<void>(
          ObjectBoxService().store
              .box<PhotoEntity>()
              .query(
                PhotoEntity_.isAiAnalysisCandidate
                    .equals(true)
                    .and(PhotoEntity_.isAiAnalyzed.equals(false)),
              )
              .watch(triggerImmediately: true)
              .map((_) {}),
          const Duration(milliseconds: 600),
        ).listen((_) {
          unawaited(_refreshPendingAnalysisPrompt());
        });
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
    UnifiedAnalysisProgressStore.instance.progress.removeListener(
      _onForegroundProgressForCardChanged,
    );
    _pendingAnalysisSubscription?.cancel();
    _momentsFastScrollerHideTimer?.cancel();
    _foregroundCardElapsedTimer?.cancel();
    _momentsScrollController.dispose();
    _semanticSearchController.dispose();
    _semanticSearchFocusNode.dispose();
    super.dispose();
  }

  void _onForegroundProgressForCardChanged() {
    final progress = UnifiedAnalysisProgressStore.instance.progress.value;
    final syncedElapsed = Duration(milliseconds: progress.elapsedMs);
    if (!progress.isVisible) {
      _foregroundCardElapsedTimer?.cancel();
      _foregroundCardElapsedTimer = null;
      if (_foregroundCardStartedAt != null && mounted) {
        setState(() => _foregroundCardStartedAt = null);
      }
      return;
    }

    final syncedStartedAt = progress.startedAtMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(progress.startedAtMs)
        : DateTime.now().subtract(syncedElapsed);
    final shouldResetStart =
        _foregroundCardStartedAt == null ||
        _foregroundCardStartedAt!.difference(syncedStartedAt).abs() >
            const Duration(seconds: 2);
    if (shouldResetStart) {
      if (mounted) {
        setState(() => _foregroundCardStartedAt = syncedStartedAt);
      } else {
        _foregroundCardStartedAt = syncedStartedAt;
      }
    }

    if (progress.isRunning) {
      _foregroundCardElapsedTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) {
          if (!mounted) {
            return;
          }
          setState(() {});
        },
      );
    } else {
      _foregroundCardElapsedTimer?.cancel();
      _foregroundCardElapsedTimer = null;
    }
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
          ValueListenableBuilder<UnifiedAnalysisProgress>(
            valueListenable: UnifiedAnalysisProgressStore.instance.progress,
            builder: (context, foregroundProgress, _) {
              final isBusy =
                  _isStartingImport || AlbumRefreshService().isRunning;
              final isLaunching =
                  _isStartingImport || AlbumRefreshService().isRunning;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: _isDeletingCurrentTask
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cleaning_services),
                    onPressed: _isDeletingCurrentTask
                        ? null
                        : () => unawaited(_deleteCurrentAnalysisTask()),
                    tooltip: '删除当前任务并清空 AI 分析字段',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton.filledTonal(
                      icon: isLaunching
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add, size: 22),
                      onPressed: isBusy ? null : _handleScanButtonPressed,
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
                hintText: '自然语言搜索，例如：去年夏天青岛海边',
                suffixIcon: IconButton(
                  onPressed: _submitSemanticSearch,
                  icon: const Icon(Icons.search),
                  tooltip: '开始搜索',
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
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
                  _buildForegroundWorkCardSection(),
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
                ],
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _viewMode == _AlbumViewMode.tags
                  ? KeyedSubtree(
                      key: const ValueKey<String>('album-tags-view'),
                      child: _buildAlbumTagBrowserView(),
                    )
                  : KeyedSubtree(
                      key: const ValueKey<String>('album-moments-view'),
                      child: _buildMomentsView(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForegroundWorkCardSection() {
    return ValueListenableBuilder<UnifiedAnalysisProgress>(
      valueListenable: UnifiedAnalysisProgressStore.instance.progress,
      builder: (context, progress, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: progress.isVisible
              ? _buildUnifiedWorkProgressBanner(progress)
              : _buildPendingAnalysisPromptSection(),
        );
      },
    );
  }

  Widget _buildPendingAnalysisPromptSection() {
    final count = _pendingAnalysisCandidateCount;
    final isBusy =
        AlbumRefreshService().isRunning ||
        UnifiedAnalysisProgressStore.instance.progress.value.isRunning ||
        AIService().isAnalyzing;
    if (count <= 0 || _hiddenPendingAnalysisPromptForSession || isBusy) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pending_actions_outlined, color: Colors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '还有$count个图片没有分析，是否继续分析',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _hiddenPendingAnalysisPromptForSession = true;
              });
            },
            child: const Text('隐藏'),
          ),
          FilledButton(
            onPressed: () => unawaited(_resumePendingAnalysisCandidates()),
            child: const Text('是'),
          ),
        ],
      ),
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

  Widget _buildUnifiedWorkProgressBanner(UnifiedAnalysisProgress progress) {
    final cacheFraction = progress.scanFraction;
    final aiFraction = progress.aiFraction;
    final startedAt =
        _foregroundCardStartedAt ??
        (progress.startedAtMs > 0
            ? DateTime.fromMillisecondsSinceEpoch(progress.startedAtMs)
            : null);
    final displayedElapsed = startedAt != null && progress.isRunning
        ? DateTime.now().difference(startedAt)
        : Duration(milliseconds: progress.elapsedMs);
    final elapsedLabel = _formatDurationCompact(displayedElapsed);
    final syncedElapsed = Duration(milliseconds: progress.elapsedMs);
    final localTickDelta = displayedElapsed > syncedElapsed
        ? displayedElapsed - syncedElapsed
        : Duration.zero;
    final estimatedRemaining = progress.estimatedRemainingDuration;
    final displayedRemaining =
        estimatedRemaining != null && estimatedRemaining > localTickDelta
        ? estimatedRemaining - localTickDelta
        : estimatedRemaining != null
        ? Duration.zero
        : null;
    final remainingLabel = displayedRemaining != null
        ? _formatDurationCompact(displayedRemaining)
        : null;

    final isWarmingUp = progress.stage == UnifiedAnalysisStage.warmingUp;

    final cacheTitle = progress.scanDone
        ? '相册缓存已更新 ${progress.scanCompleted}/${progress.scanTotal}'
        : progress.scanStopped
        ? '已停止扫描 ${progress.scanCompleted}/${progress.scanTotal}'
        : '正在更新相册缓存 ${progress.scanCompleted}/${progress.scanTotal}';
    final hasAiWork = progress.analysisEnabled && progress.aiTotal > 0;
    final aiTitle = !progress.analysisEnabled
        ? 'AI 打标签未启动'
        : progress.scanStopped
        ? 'AI 打标签已停止 ${progress.aiCompleted}/${progress.aiTotal}'
        : isWarmingUp
        ? 'AI 模型正在预热'
        : hasAiWork
        ? 'AI 正在打标签 ${progress.aiCompleted}/${progress.aiTotal}'
        : '尚未发现待分析图片';
    final aiDetail = !progress.analysisEnabled
        ? '仅更新缓存，不预热模型，不移交任务'
        : progress.scanStopped
        ? '未完成候选保留在本地，后续可自动恢复'
        : isWarmingUp
        ? '首次处理需要加载模型，请稍候…'
        : hasAiWork
        ? '队列 ${progress.queueSize} · 失败 ${progress.aiFailed}'
        : '扫描完成后如果有新图片，会自动移交到这里处理';
    final cacheDetail = progress.scanDone
        ? '缓存索引构建完成'
        : progress.scanStopped
        ? '已停止继续扫描；不会再产生新的缓存'
        : '生产者正在更新相册缓存 ${progress.scanCompleted}/${progress.scanTotal}';
    final canStop =
        progress.isRunning &&
        progress.stage != UnifiedAnalysisStage.completed &&
        !progress.scanStopped;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sync, size: 18, color: Colors.indigo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  progress.analysisEnabled ? '相册缓存与 AI 打标' : '相册缓存更新',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (remainingLabel != null && !isWarmingUp)
                Text(
                  '剩余 $remainingLabel',
                  style: TextStyle(
                    color: Colors.indigo[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Text(
                  '已耗时 $elapsedLabel',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildProgressRow(
            icon: Icons.inventory_2_outlined,
            title: cacheTitle,
            detail: cacheDetail,
            value: progress.scanTotal > 0 ? cacheFraction : null,
            color: Colors.pinkAccent,
          ),
          if (progress.analysisEnabled) ...[
            const SizedBox(height: 12),
            _buildProgressRow(
              icon: isWarmingUp ? Icons.whatshot : Icons.auto_awesome,
              title: aiTitle,
              detail: aiDetail,
              value: isWarmingUp
                  ? null
                  : (progress.aiTotal > 0 ? aiFraction : null),
              color: Colors.teal,
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: canStop
                  ? () => unawaited(AlbumRefreshService().stopScanningOnly())
                  : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('停止任务'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow({
    required IconData icon,
    required String title,
    required String detail,
    required double? value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (value != null)
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(fontWeight: FontWeight.w700, color: color),
              ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: value,
          minHeight: 8,
          borderRadius: BorderRadius.circular(999),
          backgroundColor: color.withValues(alpha: 0.12),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
        const SizedBox(height: 6),
        Text(detail, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
      ],
    );
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
            !AlbumRefreshService().isRunning &&
            !UnifiedAnalysisProgressStore.instance.progress.value.isRunning &&
            !_tagBrowserAiRecoveryTriggered) {
          _tagBrowserAiRecoveryTriggered = true;
          unawaited(_refreshPendingAnalysisPrompt());
        } else if (analyzedPhotoCount > 0 || AIService().isAnalyzing) {
          _tagBrowserAiRecoveryTriggered = false;
        }
        if (clusters.isEmpty) {
          return _buildTagBrowserEmptyState(browserData);
        }

        return CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(700),
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
    final foregroundProgress =
        UnifiedAnalysisProgressStore.instance.progress.value;

    String title;
    String subtitle;
    IconData icon;

    if (totalPhotoCount <= 0) {
      title = '暂时还没有可浏览的标签聚类';
      subtitle = '先点击右上角 + 扫描相册，系统再按粗粒度标签自动整理相册。';
      icon = Icons.sell_outlined;
    } else if (analyzedPhotoCount <= 0 || foregroundProgress.isVisible) {
      final isActive = foregroundProgress.isRunning;
      title = isActive ? '照片已入库，正在后台打标' : '照片已入库，等待 AI 打标';
      final completedText = foregroundProgress.aiTotal > 0
          ? '${foregroundProgress.aiCompleted}/${foregroundProgress.aiTotal}'
          : '$analyzedPhotoCount/$totalPhotoCount';
      subtitle = isActive
          ? '当前已有 $totalPhotoCount 张照片，AI 正在补充标签与文案（$completedText）。打标完成后，这里会自动出现标签预览。'
          : '当前已有 $totalPhotoCount 张照片，但还没有完成标签分析。可使用上方任务卡继续处理。';
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
