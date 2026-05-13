import 'package:objectbox/objectbox.dart';

import '../../vector_index/vector_index_constants.dart';

@Entity()
class FaceEmbeddingIndexEntity {
  FaceEmbeddingIndexEntity({
    this.id = 0,
    required this.lookupKey,
    required this.faceId,
    required this.photoId,
    required this.modelVersion,
    required this.updatedAtMillis,
    this.isStale = false,
    this.qualityScore,
    this.vector,
  });

  @Id()
  int id;

  @Unique(onConflict: ConflictStrategy.replace)
  String lookupKey;

  @Index()
  int faceId;

  @Index()
  int photoId;

  @Index()
  String modelVersion;

  int updatedAtMillis;
  bool isStale;
  double? qualityScore;

  @HnswIndex(
    dimensions: kFaceEmbeddingVectorDimensions,
    distanceType: VectorDistanceType.cosine,
  )
  @Property(type: PropertyType.floatVector)
  List<double>? vector;

  static String buildLookupKey(int faceId, String modelVersion) {
    return '$faceId::$modelVersion';
  }
}
