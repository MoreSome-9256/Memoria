import 'package:objectbox/objectbox.dart';
import 'analysis_types.dart';

@Entity()
class AnalysisTaskEntity {
  @Id()
  int id;

  @Unique()
  String taskId;

  @Index()
  int status;

  int totalCount;
  int completedCount;
  int failedCount;

  String? currentItemId;

  double percent;

  String? errorMessage;

  @Index()
  int createdAtMs;

  int updatedAtMs;

  String? resultJson;

  AnalysisTaskEntity({
    this.id = 0,
    required this.taskId,
    this.status = 0,
    this.totalCount = 0,
    this.completedCount = 0,
    this.failedCount = 0,
    this.currentItemId,
    this.percent = 0,
    this.errorMessage,
    int? createdAtMs,
    int? updatedAtMs,
    this.resultJson,
  })  : createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
        updatedAtMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  AnalysisTaskStatus get taskStatus {
    if (status < 0 || status >= AnalysisTaskStatus.values.length) {
      return AnalysisTaskStatus.pending;
    }
    return AnalysisTaskStatus.values[status];
  }

  set taskStatus(AnalysisTaskStatus value) => status = value.index;
}
