import 'dart:async';
import 'package:flutter/services.dart';
import 'analysis_types.dart';

class AnalysisBridge {
  static const String _channelName = 'memoria/analysis';
  static const String _eventChannelName = 'memoria/analysis_progress';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  StreamSubscription<dynamic>? _progressSubscription;
  void Function(AnalysisTaskProgress)? onProgress;

  AnalysisBridge()
    : _methodChannel = const MethodChannel(_channelName),
      _eventChannel = const EventChannel(_eventChannelName);

  void startListening() {
    _progressSubscription?.cancel();
    _progressSubscription = _eventChannel
        .receiveBroadcastStream()
        .listen(_handleProgressEvent);
  }

  void stopListening() {
    _progressSubscription?.cancel();
    _progressSubscription = null;
  }

  void _handleProgressEvent(dynamic event) {
    if (event is Map && onProgress != null) {
      final data = Map<String, dynamic>.from(event);
      onProgress!(AnalysisTaskProgress(
        taskId: data['taskId'] as String? ?? '',
        totalCount: data['totalCount'] as int? ?? 0,
        completedCount: data['completedCount'] as int? ?? 0,
        failedCount: data['failedCount'] as int? ?? 0,
        currentItemId: data['currentItemId'] as String?,
        percent: (data['percent'] as num?)?.toDouble() ?? 0,
        status: _parseStatus(data['status'] as String? ?? 'pending'),
        errorMessage: data['errorMessage'] as String?,
      ));
    }
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

  Future<bool> enqueueImages(String taskId, List<Map<String, dynamic>> images) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('enqueueImages', {
        'taskId': taskId,
        'images': images,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> startAnalysis(String taskId) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('startAnalysis', {
        'taskId': taskId,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> pauseAnalysis(String taskId) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('pauseAnalysis', {
        'taskId': taskId,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> resumeAnalysis(String taskId) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('resumeAnalysis', {
        'taskId': taskId,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> cancelAnalysis(String taskId) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('cancelAnalysis', {
        'taskId': taskId,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getState(String taskId) async {
    try {
      return await _methodChannel.invokeMethod<Map<String, dynamic>>('getState', {
        'taskId': taskId,
      });
    } on MissingPluginException {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getUnfinishedTasks() async {
    try {
      final result = await _methodChannel
          .invokeMethod<List<dynamic>>('getUnfinishedTasks');
      if (result == null) return [];
      return result.cast<Map<String, dynamic>>();
    } on MissingPluginException {
      return [];
    }
  }

  void dispose() {
    stopListening();
  }
}
