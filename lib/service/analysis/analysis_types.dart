enum AnalysisTaskStatus {
  pending,
  running,
  paused,
  completed,
  failed,
  cancelled,
}

enum ImageJobStatus {
  pending,
  processing,
  completed,
  failed,
  cancelled,
}

class AnalysisTaskProgress {
  final String taskId;
  final int totalCount;
  final int completedCount;
  final int failedCount;
  final String? currentItemId;
  final double percent;
  final AnalysisTaskStatus status;
  final String? errorMessage;

  const AnalysisTaskProgress({
    required this.taskId,
    required this.totalCount,
    required this.completedCount,
    required this.failedCount,
    this.currentItemId,
    required this.percent,
    required this.status,
    this.errorMessage,
  });

  AnalysisTaskProgress copyWith({
    String? taskId,
    int? totalCount,
    int? completedCount,
    int? failedCount,
    String? currentItemId,
    double? percent,
    AnalysisTaskStatus? status,
    String? errorMessage,
  }) {
    return AnalysisTaskProgress(
      taskId: taskId ?? this.taskId,
      totalCount: totalCount ?? this.totalCount,
      completedCount: completedCount ?? this.completedCount,
      failedCount: failedCount ?? this.failedCount,
      currentItemId: currentItemId ?? this.currentItemId,
      percent: percent ?? this.percent,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ImageAnalysisResult {
  final String imageId;
  final ImageJobStatus status;
  final String? resultJson;
  final String? resultPath;
  final String? errorMessage;

  const ImageAnalysisResult({
    required this.imageId,
    required this.status,
    this.resultJson,
    this.resultPath,
    this.errorMessage,
  });
}
