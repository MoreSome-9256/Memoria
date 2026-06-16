import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/objectbox/objectbox_service.dart';
import 'amplify_auth_bootstrap_service.dart';
import 'media_permission_service.dart';
import 'unified_analysis_pipeline_service.dart';

@pragma('vm:entry-point')
void albumCacheForegroundTaskCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_AlbumCacheTaskHandler());
}

class _AlbumCacheTaskHandler extends TaskHandler {
  bool _started = false;
  String _runId = '';

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
    if (await AiBackgroundTaskService.instance.isCurrentUnifiedRun(_runId)) {
      UnifiedAnalysisPipelineService().stopPipeline();
    } else {
      debugPrint(
        '[foreground-pipeline] 忽略旧 foreground task destroy runId=$_runId',
      );
    }
  }

  Future<void> _runPipeline() async {
    try {
      final request = await AiBackgroundTaskService.instance
          ._takePendingUnifiedPipelineRequest();
      if (request == null) {
        debugPrint('[foreground-pipeline] 没有待执行的缓存/AI 任务');
        return;
      }
      _runId = request.runId;
      debugPrint('[foreground-pipeline] 启动 runId=$_runId');
      final authConfigured =
          await AmplifyAuthBootstrapService.ensureConfigured();
      if (!authConfigured) {
        throw StateError('前台服务无法配置 Cognito Auth，云端代理不可用。');
      }
      if (request.junkCleanupOnly) {
        await UnifiedAnalysisPipelineService()
            .runJunkCleanupInsideForegroundService(
              storeReferenceBytes: request.storeReferenceBytes,
            );
      } else {
        await UnifiedAnalysisPipelineService().runInsideForegroundService(
          clearCacheFirst: request.clearCacheFirst,
          analyzeWithAi: request.analyzeWithAi,
          storeReferenceBytes: request.storeReferenceBytes,
          permissionState: request.permissionState,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[foreground-pipeline] 执行失败: $error');
      debugPrint('[foreground-pipeline] 堆栈: $stackTrace');
    } finally {
      await AiBackgroundTaskService.instance
          .clearPendingUnifiedPipelineRequest();
      // Do not stop the foreground service from inside its own task isolate.
      // flutter_foreground_task answers stopService over a MethodChannel; if
      // that call races with FlutterEngine teardown, Flutter can abort with
      // platform_message_response_dart_port.cc did_send.
    }
  }
}

/// 前台服务生命周期管理。
class AiBackgroundTaskService {
  AiBackgroundTaskService._();
  static final AiBackgroundTaskService instance = AiBackgroundTaskService._();

  static bool _initialized = false;
  static const _pendingUnifiedPipelineKey =
      'foreground_pending_unified_pipeline';
  static const _pendingUnifiedClearCacheKey =
      'foreground_pending_unified_clear_cache';
  static const _pendingUnifiedAnalyzeKey =
      'foreground_pending_unified_analyze_ai';
  static const _pendingUnifiedStoreReferenceKey =
      'foreground_pending_unified_store_reference';
  static const _pendingUnifiedRunIdKey = 'foreground_pending_unified_run_id';
  static const _pendingUnifiedPermissionStateKey =
      'foreground_pending_unified_permission_state';
  static const _pendingJunkCleanupOnlyKey =
      'foreground_pending_junk_cleanup_only';

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'memoria_ai_foreground_task_v2',
        channelName: 'Memoria AI 分析',
        channelDescription: '展示 AI 打标任务的前台服务通知',
        onlyAlertOnce: true,
        priority: NotificationPriority.DEFAULT,
        channelImportance: NotificationChannelImportance.DEFAULT,
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
      callback: callback ?? albumCacheForegroundTaskCallback,
    );
    if (result is ServiceRequestFailure) {
      debugPrint('[foreground] startService failed: ${result.error}');
    } else {
      debugPrint('[foreground] startService requested: $result');
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
    final permissionState =
        await MediaPermissionService.readLivePermissionState();
    if (!permissionState.hasAccess) {
      throw StateError('没有可用的照片访问权限，请先在应用内授权。');
    }
    final prefs = await SharedPreferences.getInstance();
    final runId = DateTime.now().microsecondsSinceEpoch.toString();
    await prefs.setString(_pendingUnifiedRunIdKey, 'starting:$runId');
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
      for (var i = 0; i < 20; i++) {
        if (!await FlutterForegroundTask.isRunningService) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (await FlutterForegroundTask.isRunningService) {
        throw StateError(
          'Foreground service did not stop before unified pipeline restart.',
        );
      }
    }
    await prefs.setBool(_pendingUnifiedPipelineKey, true);
    await prefs.setBool(_pendingUnifiedClearCacheKey, clearCacheFirst);
    await prefs.setBool(_pendingUnifiedAnalyzeKey, analyzeWithAi);
    await prefs.setBool(_pendingJunkCleanupOnlyKey, false);
    await prefs.setString(_pendingUnifiedRunIdKey, runId);
    await prefs.setString(
      _pendingUnifiedPermissionStateKey,
      permissionState.name,
    );
    await prefs.setBool('foreground_unified_pipeline_stop_requested', false);
    await ObjectBoxService().ensureInitialized();
    await prefs.setString(
      _pendingUnifiedStoreReferenceKey,
      base64Encode(ObjectBoxService().storeReferenceBytes),
    );
    await startService(
      title: analyzeWithAi ? 'Memoria 正在缓存并分析媒体' : 'Memoria 正在更新相册缓存',
      text: analyzeWithAi ? '正在读取授权范围，并串行执行本地 AI 分析' : '正在读取授权范围并更新相册缓存',
      callback: albumCacheForegroundTaskCallback,
    );
  }

  Future<void> startJunkCleanupWorker() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    await _ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final runId = 'junk:${DateTime.now().microsecondsSinceEpoch}';
    if (await FlutterForegroundTask.isRunningService) {
      throw StateError('当前已有扫描或分析任务，请等待完成后再清理低价值图片。');
    }
    await prefs.setString(_pendingUnifiedRunIdKey, 'starting:$runId');
    await prefs.setBool(_pendingUnifiedPipelineKey, true);
    await prefs.setBool(_pendingUnifiedClearCacheKey, false);
    await prefs.setBool(_pendingUnifiedAnalyzeKey, false);
    await prefs.setBool(_pendingJunkCleanupOnlyKey, true);
    await prefs.setString(_pendingUnifiedRunIdKey, runId);
    await prefs.setString(
      _pendingUnifiedPermissionStateKey,
      PermissionState.notDetermined.name,
    );
    await ObjectBoxService().ensureInitialized();
    await prefs.setString(
      _pendingUnifiedStoreReferenceKey,
      base64Encode(ObjectBoxService().storeReferenceBytes),
    );
    await startService(
      title: 'Memoria 正在整理低价值图片',
      text: '正在后台分批检查已分析照片',
      callback: albumCacheForegroundTaskCallback,
    );
  }

  Future<_UnifiedPipelineForegroundRequest?>
  _takePendingUnifiedPipelineRequest() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(_pendingUnifiedPipelineKey) ?? false;
    if (!pending) return null;
    final encodedReference = prefs.getString(_pendingUnifiedStoreReferenceKey);
    if (encodedReference == null || encodedReference.isEmpty) {
      throw StateError('Foreground pipeline missing ObjectBox store reference');
    }
    return _UnifiedPipelineForegroundRequest(
      runId: prefs.getString(_pendingUnifiedRunIdKey) ?? '',
      clearCacheFirst: prefs.getBool(_pendingUnifiedClearCacheKey) ?? false,
      analyzeWithAi: prefs.getBool(_pendingUnifiedAnalyzeKey) ?? true,
      storeReferenceBytes: Uint8List.fromList(base64Decode(encodedReference)),
      permissionState: PermissionState.values.firstWhere(
        (state) =>
            state.name == prefs.getString(_pendingUnifiedPermissionStateKey),
        orElse: () => PermissionState.notDetermined,
      ),
      junkCleanupOnly: prefs.getBool(_pendingJunkCleanupOnlyKey) ?? false,
    );
  }

  Future<void> clearPendingUnifiedPipelineRequest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingUnifiedPipelineKey);
    await prefs.remove(_pendingUnifiedClearCacheKey);
    await prefs.remove(_pendingUnifiedAnalyzeKey);
    await prefs.remove(_pendingUnifiedStoreReferenceKey);
    await prefs.remove(_pendingUnifiedRunIdKey);
    await prefs.remove(_pendingUnifiedPermissionStateKey);
    await prefs.remove(_pendingJunkCleanupOnlyKey);
  }

  Future<bool> isCurrentUnifiedRun(String runId) async {
    if (runId.isEmpty) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingUnifiedRunIdKey) == runId;
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
    required this.runId,
    required this.clearCacheFirst,
    required this.analyzeWithAi,
    required this.storeReferenceBytes,
    required this.permissionState,
    required this.junkCleanupOnly,
  });

  final String runId;
  final bool clearCacheFirst;
  final bool analyzeWithAi;
  final Uint8List storeReferenceBytes;
  final PermissionState permissionState;
  final bool junkCleanupOnly;
}
