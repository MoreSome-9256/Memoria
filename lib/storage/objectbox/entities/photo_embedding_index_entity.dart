import 'package:objectbox/objectbox.dart';

import '../../vector_index/vector_index_constants.dart';

@Entity()
class PhotoEmbeddingIndexEntity {
  PhotoEmbeddingIndexEntity({
    this.id = 0,
    required this.lookupKey,
    required this.photoId,
    required this.modelVersion,
    required this.updatedAtMillis,
    this.isStale = false,
    this.vector,
  });

  @Id()
  int id;

  @Unique(onConflict: ConflictStrategy.replace)
  String lookupKey;

  @Index()
  int photoId;

  @Index()
  String modelVersion;

  int updatedAtMillis;
  bool isStale;

  @HnswIndex(
    dimensions: kPhotoEmbeddingVectorDimensions,
    distanceType: VectorDistanceType.cosine,
  )
  @Property(type: PropertyType.floatVector)
  List<double>? vector;

  static String buildLookupKey(int photoId, String modelVersion) {
    return '$photoId::$modelVersion';
  }
}
