import 'package:objectbox/objectbox.dart';

@Entity()
class FaceEntity {
  @Id()
  int id = 0;

  @Index()
  late int photoId;

  @Index()
  late String assetId;

  late int faceIndex;

  // Bounding box in source image pixels.
  late double left;
  late double top;
  late double right;
  late double bottom;

  double? roll;
  double? yaw;
  double? smilingProbability;
  double? leftEyeOpenProbability;
  double? rightEyeOpenProbability;

  String? debugCropPath;
  List<double>? embedding;
  late String embeddingModelVersion;
  double? qualityScore;

  @Index()
  int? clusterId;

  bool isPrimaryFace = false;
  late int createdAt;
  late int updatedAt;

  double get width => right - left;
  double get height => bottom - top;
  double get area => width <= 0 || height <= 0 ? 0 : width * height;
}
