import 'package:objectbox/objectbox.dart';

@Entity()
class AnalysisTaskEntity {
  AnalysisTaskEntity({
    this.id = 0,
    required this.taskId,
    required this.status,
    required this.totalCount,
    required this.completedCount,
    required this.failedCount,
    this.currentItemId,
    required this.percent,
    this.errorMessage,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.resultJson,
  });

  @Id()
  int id;
  String taskId;
  int status;
  int totalCount;
  int completedCount;
  int failedCount;
  String? currentItemId;
  double percent;
  String? errorMessage;
  int createdAtMs;
  int updatedAtMs;
  String? resultJson;
}
