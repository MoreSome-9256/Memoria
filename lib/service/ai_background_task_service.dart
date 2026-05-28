// AI 前台任务处理器 — Spool 模式。
//
// 主进程写 manifest 到 spool → 启动前台服务 → 本 isolate 只做纯计算
// → result/embedding/progress 写入 spool → done.marker → 主进程消费写库。

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analysis_spool_service.dart';

import '../storage/objectbox/objectbox_service.dart';
import 'spool_analysis_worker.dart';
import 'unified_analysis_pipeline_service.dart';

/// 前台任务回调入口，在后台 isolate 中运行。
@pragma('vm:entry-point')
void foregroundTaskCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_SpoolTaskHandler());
}

@pragma('vm:entry-point')
void albumCacheForegroundTaskCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_AlbumCacheTaskHandler());
}

class _AlbumCacheTaskHandler extends TaskHandler {
  bool _started = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    if (_started) return;
    _started = true;
    unawaited(_runPipeline());
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    UnifiedAnalysisPipelineService().stopPipeline();
  }

  Future<void> _runPipeline() async {
    try {
      final request = await AiBackgroundTaskService.instance
          .takePendingUnifiedPipelineRequest();
      if (request == null) {
        debugPrint('[foreground-pipeline] 没有待执行的缓存/AI 任务');
        return;
      }
      await UnifiedAnalysisPipelineService().runInsideForegroundService(
        clearCacheFirst: request.clearCacheFirst,
        analyzeWithAi: request.analyzeWithAi,
        storeReferenceBytes: request.storeReferenceBytes,
        rootIsolateToken: RootIsolateToken.instance,
      );
    } catch (error, stackTrace) {
      debugPrint('[foreground-pipeline] 执行失败: $error');
      debugPrint('[foreground-pipeline] 堆栈: $stackTrace');
    } finally {
      await AiBackgroundTaskService.instance.clearPendingUnifiedPipelineRequest();
      // Do not stop the foreground service from inside its own task isolate.
      // flutter_foreground_task answers stopService over a MethodChannel; if
      // that call races with FlutterEngine teardown, Flutter can abort with
      // platform_message_response_dart_port.cc did_send.
    }
  }
}

class _SpoolTaskHandler extends TaskHandler {
  SpoolAnalysisWorker? _worker;
  bool _started = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    if (_started) return;
    _started = true;
    unawaited(_runWorker());
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  Future<void> _runWorker() async {
    try {
      // 从 spool 读取最新未完成的 manifest
      final manifest = await AiBackgroundTaskService.instance
          .takePendingManifest();
      if (manifest == null) {
        debugPrint('[spool-worker] 没有待处理的 manifest');
        return;
      }

      _worker = SpoolAnalysisWorker();
      await _worker!.run(manifest);
    } catch (error) {
      debugPrint('❌ Spool worker 执行失败: $error');
    } finally {
      // See _AlbumCacheTaskHandler._runPipeline: stopping from the foreground
      // task isolate can race with the MethodChannel response port teardown.
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _worker?.requestStop();
  }
}

/// 前台服务生命周期管理。
class AiBackgroundTaskService {
  AiBackgroundTaskService._();
  static final AiBackgroundTaskService instance = AiBackgroundTaskService._();

  static bool _initialized = false;
  static const _pendingManifestJobIdKey = 'spool_pending_manifest_job_id';
  static const _pendingUnifiedPipelineKey =
      'foreground_pending_unified_pipeline';
  static const _pendingUnifiedClearCacheKey =
      'foreground_pending_unified_clear_cache';
  static const _pendingUnifiedAnalyzeKey =
      'foreground_pending_unified_analyze_ai';
  static const _pendingUnifiedStoreReferenceKey =
      'foreground_pending_unified_store_reference';

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'memoria_ai_foreground_task',
        channelName: 'Memoria AI 分析',
        channelDescription: '展示 AI 打标任务的前台服务通知',
        onlyAlertOnce: true,
        priority: NotificationPriority.LOW,
        channelImportance: NotificationChannelImportance.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
  }

  /// 写入 manifest → 启动前台服务。
  Future<void> startAnalysisWorker({
    AnalysisJobManifest? manifest,
  }) async {
    if (manifest != null) {
      await AnalysisSpoolService.instance.writeManifest(manifest);
      await AnalysisSpoolService.instance.writeControl(
        AnalysisJobControl.running(manifest.jobId),
      );
      await _recordPendingJobId(manifest.jobId);
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint('[spool] 非 Android/iOS 平台暂不支持前台服务');
      return;
    }
    await startService(title: 'Memoria 正在分析媒体', text: '只处理你加入分析队列的照片和视频');
  }

  /// 获取并认领下一个待处理的 manifest。
  ///
  /// 检查 SharedPreferences 中记录的 pending jobId，
  /// 如果 spool 中存在且没有 done.marker，则认领并返回。
  Future<AnalysisJobManifest?> takePendingManifest() async {
    final prefs = await SharedPreferences.getInstance();
    final jobId = prefs.getString(_pendingManifestJobIdKey);
    if (jobId == null || jobId.isEmpty) return null;

    final spool = AnalysisSpoolService.instance;
    if (await spool.hasDoneMarker(jobId)) {
      debugPrint('[spool-worker] job $jobId 已有 done.marker，跳过');
      return null;
    }
    final manifest = await spool.readManifest(jobId);
    if (manifest == null) {
      debugPrint('[spool-worker] manifest 不存在 jobId=$jobId');
      return null;
    }
    return manifest;
  }

  Future<void> _recordPendingJobId(String jobId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingManifestJobIdKey, jobId);
  }

  // ── 前台服务生命周期 ──

  Future<void> startService({
    required String title,
    required String text,
    void Function()? callback,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await _ensureInitialized();
    if (await FlutterForegroundTask.isRunningService) {
      await updateNotification(title: title, text: text);
      return;
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: 43021,
      serviceTypes: const <ForegroundServiceTypes>[
        ForegroundServiceTypes.dataSync,
        ForegroundServiceTypes.mediaProcessing,
      ],
      notificationTitle: title,
      notificationText: text,
      notificationIcon: null,
      callback: callback ?? foregroundTaskCallback,
    );
    if (result is ServiceRequestFailure) {
      debugPrint('[foreground] startService failed: ${result.error}');
    }
  }

  Future<bool> startAlbumCacheForeground({required String text}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    await _ensureInitialized();
    final wasRunning = await FlutterForegroundTask.isRunningService;
    await startService(
      title: 'Memoria 正在更新相册缓存',
      text: text,
      callback: albumCacheForegroundTaskCallback,
    );
    return !wasRunning;
  }

  Future<void> startUnifiedPipelineWorker({
    required bool clearCacheFirst,
    required bool analyzeWithAi,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pendingUnifiedPipelineKey, true);
    await prefs.setBool(_pendingUnifiedClearCacheKey, clearCacheFirst);
    await prefs.setBool(_pendingUnifiedAnalyzeKey, analyzeWithAi);
    await prefs.setString(
      _pendingUnifiedStoreReferenceKey,
      base64Encode(ObjectBoxService().storeReferenceBytes),
    );
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await startService(
      title: analyzeWithAi ? 'Memoria 正在缓存并分析媒体' : 'Memoria 正在更新相册缓存',
      text: analyzeWithAi ? '正在读取授权范围，并串行执行本地 AI 分析' : '正在读取授权范围并更新相册缓存',
      callback: albumCacheForegroundTaskCallback,
    );
  }

  Future<_UnifiedPipelineForegroundRequest?>
      takePendingUnifiedPipelineRequest() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_pendingUnifiedPipelineKey) ?? false;
    if (!pending) return null;
    final encodedReference = prefs.getString(_pendingUnifiedStoreReferenceKey);
    if (encodedReference == null || encodedReference.isEmpty) {
      throw StateError('Foreground pipeline missing ObjectBox store reference');
    }
    return _UnifiedPipelineForegroundRequest(
      clearCacheFirst: prefs.getBool(_pendingUnifiedClearCacheKey) ?? false,
      analyzeWithAi: prefs.getBool(_pendingUnifiedAnalyzeKey) ?? true,
      storeReferenceBytes: Uint8List.fromList(base64Decode(encodedReference)),
    );
  }

  Future<void> clearPendingUnifiedPipelineRequest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingUnifiedPipelineKey);
    await prefs.remove(_pendingUnifiedClearCacheKey);
    await prefs.remove(_pendingUnifiedAnalyzeKey);
    await prefs.remove(_pendingUnifiedStoreReferenceKey);
  }

  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  Future<bool> get isRunning async {
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    await _ensureInitialized();
    return FlutterForegroundTask.isRunningService;
  }

  Future<void> stop() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await FlutterForegroundTask.stopService();
  }
}

class _UnifiedPipelineForegroundRequest {
  const _UnifiedPipelineForegroundRequest({
    required this.clearCacheFirst,
    required this.analyzeWithAi,
    required this.storeReferenceBytes,
  });

  final bool clearCacheFirst;
  final bool analyzeWithAi;
  final Uint8List storeReferenceBytes;
}
