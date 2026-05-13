import 'package:objectbox/objectbox.dart';

import '../../vector_index/vector_index_constants.dart';

enum MediaAssetStatus {
  pending,
  ready,
  dirty,
  failed,
}

@Entity()
class MediaAssetEntity {
  MediaAssetEntity({
    this.id = 0,
    required this.assetId,
    this.status = 0,
    this.width = 0,
    this.height = 0,
    this.createTimeMs = 0,
    this.modifiedTimeMs = 0,
    this.durationMs = 0,
    this.subtype = 0,
    this.contentHash,
    this.modelVersion,
    this.embeddingUpdatedAtMs,
    this.errorMessage,
    this.embedding,
  });

  @Id()
  int id;

  @Unique(onConflict: ConflictStrategy.replace)
  String assetId;

  @Index()
  int status;

  int width;
  int height;

  @Index()
  int createTimeMs;

  int modifiedTimeMs;
  int durationMs;
  int subtype;

  String? contentHash;

  @Index()
  String? modelVersion;

  int? embeddingUpdatedAtMs;
  String? errorMessage;

  @HnswIndex(
    dimensions: kPhotoEmbeddingVectorDimensions,
    distanceType: VectorDistanceType.cosine,
  )
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;

  MediaAssetStatus get statusEnum {
    if (status < 0 || status >= MediaAssetStatus.values.length) {
      return MediaAssetStatus.pending;
    }
    return MediaAssetStatus.values[status];
  }

  set statusEnum(MediaAssetStatus value) {
    status = value.index;
  }
}
