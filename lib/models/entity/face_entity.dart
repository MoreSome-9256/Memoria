import 'package:isar/isar.dart';

part 'face_entity.g.dart';

@Collection()
class FaceEntity {
  Id id = Isar.autoIncrement;

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
