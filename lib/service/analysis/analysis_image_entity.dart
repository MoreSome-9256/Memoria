import 'package:objectbox/objectbox.dart';
import 'analysis_types.dart';

@Entity()
class AnalysisImageEntity {
  @Id()
  int id;

  @Index()
  String taskId;

  @Unique()
  String imageId;

  @Index()
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

  AnalysisImageEntity({
    this.id = 0,
    required this.taskId,
    required this.imageId,
    this.status = 0,
    this.sortOrder = 0,
    this.assetId,
    this.filePath,
    this.contentUri,
    this.resultJson,
    this.resultPath,
    this.errorMessage,
    int? createdAtMs,
    int? updatedAtMs,
  })  : createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
        updatedAtMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  ImageJobStatus get jobStatus {
    if (status < 0 || status >= ImageJobStatus.values.length) {
      return ImageJobStatus.pending;
    }
    return ImageJobStatus.values[status];
  }

  set jobStatus(ImageJobStatus value) => status = value.index;
}
