import 'package:objectbox/objectbox.dart';

@Entity()
class AnalysisImageEntity {
  AnalysisImageEntity({
    this.id = 0,
    required this.taskId,
    required this.imageId,
    required this.status,
    required this.sortOrder,
    this.assetId,
    this.filePath,
    this.contentUri,
    this.resultJson,
    this.resultPath,
    this.errorMessage,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  @Id()
  int id;
  String taskId;
  String imageId;
  int status;
  int sortOrder;
  String? assetId;
  String? filePath;
  String? contentUri;
  String? resultJson;
  String? resultPath;
  String? errorMessage;
  int createdAtMs;
  int updatedAtMs;
}
