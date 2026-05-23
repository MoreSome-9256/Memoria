import 'dart:async';
import 'package:flutter/foundation.dart';
import 'analysis_types.dart';
import 'analysis_repository.dart';
import 'analysis_bridge.dart';
import 'analysis_task_entity.dart';
import 'analysis_image_entity.dart';

class AnalysisManager {
  AnalysisManager._internal();

  static final AnalysisManager _instance = AnalysisManager._internal();
  factory AnalysisManager() => _instance;

  final AnalysisRepository _repository = AnalysisRepository();
  final AnalysisBridge _bridge = AnalysisBridge();

  final ValueNotifier<AnalysisTaskProgress?> currentProgress =
      ValueNotifier<AnalysisTaskProgress?>(null);

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _bridge.onProgress = _onNativeProgress;
    _bridge.startListening();
    _initialized = true;
  }

  void _onNativeProgress(AnalysisTaskProgress progress) {
    currentProgress.value = progress;
    _repository.updateTaskProgress(
      progress.taskId,
      completed: progress.completedCount,
      failed: progress.failedCount,
      currentItem: progress.currentItemId,
    );
  }

  Future<String> enqueueImages(List<Map<String, dynamic>> images) async {
    await initialize();
    final taskId = _generateTaskId();
    final itemIds = images
        .map((img) => img['imageId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    _repository.createTask(taskId, itemIds);

    final success = await _bridge.enqueueImages(taskId, images);
    if (!success) {
      _repository.updateTaskStatus(taskId, AnalysisTaskStatus.failed, error: 'Platform bridge not available');
    }
    return taskId;
  }

  Future<bool> startAnalysis(String taskId) async {
    _repository.updateTaskStatus(taskId, AnalysisTaskStatus.running);
    final success = await _bridge.startAnalysis(taskId);
    if (!success) {
      _repository.updateTaskStatus(taskId, AnalysisTaskStatus.failed, error: 'Failed to start');
    }
    return success;
  }

  Future<bool> pauseAnalysis(String taskId) async {
    _repository.updateTaskStatus(taskId, AnalysisTaskStatus.paused);
    return _bridge.pauseAnalysis(taskId);
  }

  Future<bool> resumeAnalysis(String taskId) async {
    _repository.updateTaskStatus(taskId, AnalysisTaskStatus.running);
    return _bridge.resumeAnalysis(taskId);
  }

  Future<bool> cancelAnalysis(String taskId) async {
    _repository.updateTaskStatus(taskId, AnalysisTaskStatus.cancelled);
    return _bridge.cancelAnalysis(taskId);
  }

  Future<AnalysisTaskProgress?> getCurrentState(String taskId) async {
    final state = await _bridge.getState(taskId);
    if (state != null) {
      return AnalysisTaskProgress(
        taskId: state['taskId'] as String? ?? taskId,
        totalCount: state['totalCount'] as int? ?? 0,
        completedCount: state['completedCount'] as int? ?? 0,
        failedCount: state['failedCount'] as int? ?? 0,
        currentItemId: state['currentItemId'] as String?,
        percent: (state['percent'] as num?)?.toDouble() ?? 0,
        status: _parseStatus(state['status'] as String? ?? 'pending'),
        errorMessage: state['errorMessage'] as String?,
      );
    }
    final task = _repository.getTask(taskId);
    if (task == null) return null;
    return AnalysisTaskProgress(
      taskId: task.taskId,
      totalCount: task.totalCount,
      completedCount: task.completedCount,
      failedCount: task.failedCount,
      currentItemId: task.currentItemId,
      percent: task.percent,
      status: task.taskStatus,
      errorMessage: task.errorMessage,
    );
  }

  Stream<AnalysisTaskProgress> watchProgress(String taskId) {
    return _bridge.onProgress != null
        ? _bridge.onProgress!
            .where((p) => p.taskId == taskId)
        : const Stream.empty();
  }

  Future<List<AnalysisTaskEntity>> recoverUnfinishedTasks() async {
    final local = _repository.getUnfinishedTasks();
    final native = await _bridge.getUnfinishedTasks();
    final running = <AnalysisTaskEntity>[];

    for (final task in local) {
      final nativeInfo = native.where(
        (n) => n['taskId'] == task.taskId,
      );
      if (nativeInfo.isNotEmpty) {
        final status = nativeInfo.first['status'] as String? ?? 'paused';
        if (status == 'running') {
          running.add(task);
        }
      }
    }
    return running;
  }

  String _generateTaskId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'analysis_${now}_${_randomSuffix()}';
  }

  String _randomSuffix() {
    return (DateTime.now().microsecondsSinceEpoch % 10000).toString().padLeft(4, '0');
  }

  AnalysisTaskStatus _parseStatus(String raw) {
    switch (raw) {
      case 'pending': return AnalysisTaskStatus.pending;
      case 'running': return AnalysisTaskStatus.running;
      case 'paused': return AnalysisTaskStatus.paused;
      case 'completed': return AnalysisTaskStatus.completed;
      case 'failed': return AnalysisTaskStatus.failed;
      case 'cancelled': return AnalysisTaskStatus.cancelled;
      default: return AnalysisTaskStatus.pending;
    }
  }

  void dispose() {
    _bridge.dispose();
  }
}
