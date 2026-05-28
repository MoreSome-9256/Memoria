// AI 前台任务处理器 — Spool 模式。
//
// 主进程写 manifest 到 spool → 启动前台服务 → 本 isolate 只做纯计算
// → result/embedding/progress 写入 spool → done.marker → 主进程消费写库。

import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analysis_spool_service.dart';

import 'spool_analysis_worker.dart';

/// 前台任务回调入口，在后台 isolate 中运行。
@pragma('vm:entry-point')
void foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_SpoolTaskHandler());
}

@pragma('vm:entry-point')
void albumCacheForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_AlbumCacheTaskHandler());
}

class _AlbumCacheTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
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
      await AiBackgroundTaskService.instance.stop();
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
