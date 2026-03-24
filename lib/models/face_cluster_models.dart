class FaceClusterMember {
  const FaceClusterMember({
    required this.faceId,
    required this.photoId,
    required this.qualityScore,
    required this.isPrimaryFace,
  });

  final int faceId;
  final int photoId;
  final double qualityScore;
  final bool isPrimaryFace;
}

class FaceCluster {
  const FaceCluster({
    required this.clusterId,
    required this.memberFaceIds,
    required this.members,
    required this.coverFaceId,
    required this.averageQuality,
    required this.embeddingModelVersion,
  });

  final int clusterId;
  final List<int> memberFaceIds;
  final List<FaceClusterMember> members;
  final int coverFaceId;
  final double averageQuality;
  final String embeddingModelVersion;

  int get size => memberFaceIds.length;
}

class FaceClusterRunSummary {
  const FaceClusterRunSummary({
    required this.candidateFaceCount,
    required this.clusteredFaceCount,
    required this.leftoverFaceCount,
    required this.clusterCount,
    required this.clusters,
  });

  final int candidateFaceCount;
  final int clusteredFaceCount;
  final int leftoverFaceCount;
  final int clusterCount;
  final List<FaceCluster> clusters;
}
