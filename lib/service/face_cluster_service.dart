/// 人脸聚类服务，计算人脸向量分组并输出聚类结果。

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/entity/face_entity.dart';
import '../models/entity/photo_entity.dart';
import '../models/face_cluster_models.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../storage/vector_index/face_embedding_index_repository.dart';
import '../utils/tag_sanitizer.dart';

typedef FaceEntitiesLoader = Future<List<FaceEntity>> Function();
typedef PhotoEntitiesLoader = Future<List<PhotoEntity>> Function();

class FaceClusterService {
  FaceClusterService._internal({
    FaceEntitiesLoader? facesLoader,
    PhotoEntitiesLoader? photosLoader,
  }) : _facesLoader = facesLoader,
       _photosLoader = photosLoader;

  static final FaceClusterService _instance = FaceClusterService._internal();

  factory FaceClusterService() => _instance;

  factory FaceClusterService.forTest({
    required FaceEntitiesLoader facesLoader,
    PhotoEntitiesLoader? photosLoader,
  }) {
    return FaceClusterService._internal(
      facesLoader: facesLoader,
      photosLoader: photosLoader,
    );
  }

  static const double defaultMinQualityScore = 0.03;
  static const double defaultSeedQualityScore = 0.10;
  static const double defaultMinAttachFaceAreaRatio = 0.008;
  static const double defaultMinSeedFaceAreaRatio = 0.015;
  static const int defaultMinClusterSize = 2;
  static const double defaultSeedToCentroidThreshold = 0.83;
  static const double defaultSeedToCoverThreshold = 0.85;
  static const double defaultSmallClusterCentroidMergeThreshold = 0.75;
  static const double defaultSmallClusterCoverMergeThreshold = 0.72;
  static const double defaultSmallClusterPairMergeThreshold = 0.74;
  static const int defaultSmallClusterMergeMaxSize = 4;
  static const double defaultMergeSmallClusterThreshold = 0.78;
  static const double defaultAttachToClusterThreshold = 0.76;
  static const double defaultAttachToCoverThreshold = 0.74;
  static const double defaultClusterCentroidMergeThreshold = 0.86;
  static const double defaultClusterCoverMergeThreshold = 0.84;
  static const int defaultMaxClusterSize = 12;

  static const Set<String> _nonHumanPhotoTags = <String>{
    '宠物',
    '动物',
    '狗',
    '猫',
    '二次元/动漫',
    '表情包/梗图',
    '文档截图',
    '屏幕/代码',
    '海报/图表',
  };

  static const Set<String> _nonHumanLooseTokens = <String>{
    '宠物',
    '动物',
    '狗',
    '猫',
    '狗头',
    '表情包',
    '梗图',
    '动漫',
    '二次元',
    '截图',
    '海报',
    '图表',
    '屏幕',
    '代码',
  };

  final FaceEntitiesLoader? _facesLoader;
  final PhotoEntitiesLoader? _photosLoader;
  final FaceEmbeddingIndexRepository _faceEmbeddingIndexRepository =
      FaceEmbeddingIndexRepository();

  Future<FaceClusterRunSummary> reclusterAllFaces({
    double minQualityScore = defaultMinQualityScore,
    double seedQualityScore = defaultSeedQualityScore,
    double minAttachFaceAreaRatio = defaultMinAttachFaceAreaRatio,
    double minSeedFaceAreaRatio = defaultMinSeedFaceAreaRatio,
    int minClusterSize = defaultMinClusterSize,
    double seedToCentroidThreshold = defaultSeedToCentroidThreshold,
    double seedToCoverThreshold = defaultSeedToCoverThreshold,
    double smallClusterCentroidMergeThreshold =
        defaultSmallClusterCentroidMergeThreshold,
    double smallClusterCoverMergeThreshold =
        defaultSmallClusterCoverMergeThreshold,
    double smallClusterPairMergeThreshold =
        defaultSmallClusterPairMergeThreshold,
    int smallClusterMergeMaxSize = defaultSmallClusterMergeMaxSize,
    double mergeSmallClusterThreshold = defaultMergeSmallClusterThreshold,
    double attachToClusterThreshold = defaultAttachToClusterThreshold,
    double attachToCoverThreshold = defaultAttachToCoverThreshold,
    double clusterCentroidMergeThreshold = defaultClusterCentroidMergeThreshold,
    double clusterCoverMergeThreshold = defaultClusterCoverMergeThreshold,
    int maxClusterSize = defaultMaxClusterSize,
  }) async {
    final allFaces = await _loadAllFaces();
    final indexedEmbeddings = _faceEmbeddingIndexRepository
        .readEmbeddingsForFaces(allFaces);
    for (final face in allFaces) {
      final embedding = indexedEmbeddings[face.id];
      if (embedding != null) {
        face.embedding = embedding;
      }
    }
    if (allFaces.isEmpty) {
      return const FaceClusterRunSummary(
        candidateFaceCount: 0,
        clusteredFaceCount: 0,
        leftoverFaceCount: 0,
        clusterCount: 0,
        clusters: <FaceCluster>[],
      );
    }

    final allPhotos = await _loadPhotosForFaces(allFaces);
    final photoById = <int, PhotoEntity>{
      for (final photo in allPhotos) photo.id: photo,
    };

    final candidateFaces = allFaces
        .where((face) {
          final photo = photoById[face.photoId];
          return _isAttachCandidateFace(
            face,
            photo: photo,
            minQualityScore: minQualityScore,
            minFaceAreaRatio: minAttachFaceAreaRatio,
          );
        })
        .toList(growable: false);
    final representativeFaceIds = _selectRepresentativeFaceIds(
      candidateFaces,
      photoById: photoById,
    );
    final seedFaces = candidateFaces
        .where((face) {
          if (!representativeFaceIds.contains(face.id)) {
            return false;
          }
          final photo = photoById[face.photoId];
          return _isSeedCandidateFace(
            face,
            photo: photo,
            minQualityScore: minQualityScore,
            seedQualityScore: seedQualityScore,
            minSeedFaceAreaRatio: minSeedFaceAreaRatio,
          );
        })
        .toList(growable: false);
    final seedFaceIds = seedFaces.map((face) => face.id).toSet();

    final clusters = <FaceCluster>[];
    final assignedClusterByFaceId = <int, int?>{};
    final versionBuckets = <String, List<FaceEntity>>{};

    for (final face in seedFaces) {
      versionBuckets
          .putIfAbsent(face.embeddingModelVersion, () => <FaceEntity>[])
          .add(face);
    }

    var nextClusterId = 1;
    for (final entry in versionBuckets.entries) {
      final version = entry.key;
      final faces = entry.value;
      final rawClusters = _buildSeedClusters(
        faces,
        seedToCentroidThreshold: seedToCentroidThreshold,
        seedToCoverThreshold: seedToCoverThreshold,
        maxClusterSize: maxClusterSize,
      );
      final grownClusters = rawClusters
          .map((cluster) => List<FaceEntity>.from(cluster))
          .toList(growable: true);

      _mergeSmallRepresentativeClusters(
        grownClusters,
        centroidThreshold: smallClusterCentroidMergeThreshold,
        coverThreshold: smallClusterCoverMergeThreshold,
        pairThreshold: smallClusterPairMergeThreshold,
        maxClusterSize: maxClusterSize,
        smallClusterMaxSize: smallClusterMergeMaxSize,
      );

      final stableClusters = <List<FaceEntity>>[];
      final smallClusters = <List<FaceEntity>>[];
      for (final cluster in grownClusters) {
        if (cluster.length >= minClusterSize) {
          stableClusters.add(cluster);
        } else {
          smallClusters.add(cluster);
        }
      }

      for (final smallCluster in smallClusters) {
        final bestIndex = _bestStableClusterIndex(
          smallCluster,
          stableClusters,
          minSimilarity: mergeSmallClusterThreshold,
        );
        if (bestIndex >= 0) {
          stableClusters[bestIndex].addAll(smallCluster);
        } else {
          for (final face in smallCluster) {
            assignedClusterByFaceId[face.id] = null;
          }
        }
      }

      _mergeStableClusters(
        stableClusters,
        centroidThreshold: clusterCentroidMergeThreshold,
        coverThreshold: clusterCoverMergeThreshold,
        maxClusterSize: maxClusterSize,
      );

      stableClusters.sort((left, right) {
        final sizeCompare = right.length.compareTo(left.length);
        if (sizeCompare != 0) {
          return sizeCompare;
        }
        return _averageQuality(right).compareTo(_averageQuality(left));
      });

      final attachCandidates = candidateFaces
          .where(
            (face) =>
                face.embeddingModelVersion == version &&
                !seedFaceIds.contains(face.id),
          )
          .toList(growable: false);

      for (final face in attachCandidates) {
        final bestIndex = _bestStableClusterIndex(
          <FaceEntity>[face],
          stableClusters,
          minSimilarity: attachToClusterThreshold,
          coverThreshold: attachToCoverThreshold,
        );
        if (bestIndex >= 0 &&
            stableClusters[bestIndex].length < maxClusterSize) {
          stableClusters[bestIndex].add(face);
        } else {
          assignedClusterByFaceId[face.id] = null;
        }
      }

      for (final members in stableClusters) {
        final sortedMembers = List<FaceEntity>.from(members)
          ..sort((left, right) {
            final primaryCompare = (right.isPrimaryFace ? 1 : 0).compareTo(
              left.isPrimaryFace ? 1 : 0,
            );
            if (primaryCompare != 0) {
              return primaryCompare;
            }
            return (right.qualityScore ?? 0).compareTo(left.qualityScore ?? 0);
          });

        final clusterId = nextClusterId++;
        for (final face in sortedMembers) {
          assignedClusterByFaceId[face.id] = clusterId;
        }

        clusters.add(
          FaceCluster(
            clusterId: clusterId,
            memberFaceIds: sortedMembers
                .map((face) => face.id)
                .toList(growable: false),
            members: sortedMembers
                .map(
                  (face) => FaceClusterMember(
                    faceId: face.id,
                    photoId: face.photoId,
                    qualityScore: face.qualityScore ?? 0.0,
                    isPrimaryFace: face.isPrimaryFace,
                  ),
                )
                .toList(growable: false),
            coverFaceId: sortedMembers.first.id,
            averageQuality: _averageQuality(sortedMembers),
            embeddingModelVersion: version,
          ),
        );
      }
    }

    for (final face in candidateFaces) {
      assignedClusterByFaceId.putIfAbsent(face.id, () => null);
    }

    final clusteredFaceCount = assignedClusterByFaceId.values
        .whereType<int>()
        .length;
    final leftoverFaceCount = candidateFaces.length - clusteredFaceCount;

    _logClusterPairDiagnostics(
      allFaces: allFaces,
      assignedClusterByFaceId: assignedClusterByFaceId,
    );

    await _persistAssignments(
      allFaces: allFaces,
      assignedClusterByFaceId: assignedClusterByFaceId,
    );

    return FaceClusterRunSummary(
      candidateFaceCount: candidateFaces.length,
      clusteredFaceCount: clusteredFaceCount,
      leftoverFaceCount: leftoverFaceCount,
      clusterCount: clusters.length,
      clusters: clusters,
    );
  }

  Future<List<FaceEntity>> _loadAllFaces() async {
    if (_facesLoader != null) {
      return _facesLoader();
    }
    return ObjectBoxService().store.box<FaceEntity>().getAll();
  }

  Future<List<PhotoEntity>> _loadPhotosForFaces(List<FaceEntity> faces) async {
    if (_photosLoader != null) {
      return _photosLoader();
    }
    if (_facesLoader != null) {
      return const <PhotoEntity>[];
    }
    final photoIds = faces
        .map((face) => face.photoId)
        .toSet()
        .toList(growable: false);
    if (photoIds.isEmpty) {
      return const <PhotoEntity>[];
    }
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    return photoBox.getMany(photoIds).whereType<PhotoEntity>().toList(growable: false);
  }

  bool _isAttachCandidateFace(
    FaceEntity face, {
    required double minQualityScore,
    required double minFaceAreaRatio,
    required PhotoEntity? photo,
  }) {
    final embedding = face.embedding;
    if (embedding == null || embedding.isEmpty) {
      return false;
    }
    if (_isRejectedPhoto(photo)) {
      return false;
    }
    if (photo != null && _faceAreaRatio(face, photo) < minFaceAreaRatio) {
      return false;
    }
    return (face.qualityScore ?? 0.0) >= minQualityScore;
  }

  bool isAttachCandidateFaceForDebug(
    FaceEntity face, {
    required PhotoEntity? photo,
    double minQualityScore = defaultMinQualityScore,
    double minFaceAreaRatio = defaultMinAttachFaceAreaRatio,
  }) {
    return _isAttachCandidateFace(
      face,
      photo: photo,
      minQualityScore: minQualityScore,
      minFaceAreaRatio: minFaceAreaRatio,
    );
  }

  bool _isSeedCandidateFace(
    FaceEntity face, {
    required double minQualityScore,
    required double seedQualityScore,
    required double minSeedFaceAreaRatio,
    required PhotoEntity? photo,
  }) {
    if (!_isAttachCandidateFace(
      face,
      photo: photo,
      minQualityScore: minQualityScore,
      minFaceAreaRatio: minSeedFaceAreaRatio,
    )) {
      return false;
    }

    return face.isPrimaryFace || (face.qualityScore ?? 0.0) >= seedQualityScore;
  }

  bool _isRejectedPhoto(PhotoEntity? photo) {
    if (photo == null) {
      return false;
    }
    if (photo.isProbablyScreenshot) {
      return true;
    }
    final tags = TagSanitizer.sanitizeVisualTags(
      photo.aiTags ?? const <String>[],
    );
    if (tags.any(_nonHumanPhotoTags.contains)) {
      return true;
    }

    return tags.any((tag) {
      final normalized = tag.trim().toLowerCase();
      return _nonHumanLooseTokens.any(
        (token) => normalized.contains(token.toLowerCase()),
      );
    });
  }

  bool isRejectedPhotoForDebug(PhotoEntity? photo) => _isRejectedPhoto(photo);

  Set<int> _selectRepresentativeFaceIds(
    List<FaceEntity> faces, {
    required Map<int, PhotoEntity> photoById,
  }) {
    final bestFaceByPhotoId = <int, FaceEntity>{};

    for (final face in faces) {
      final existing = bestFaceByPhotoId[face.photoId];
      if (existing == null) {
        bestFaceByPhotoId[face.photoId] = face;
        continue;
      }

      final currentScore = _representativeScore(face, photoById[face.photoId]);
      final existingScore = _representativeScore(
        existing,
        photoById[existing.photoId],
      );
      if (currentScore > existingScore) {
        bestFaceByPhotoId[face.photoId] = face;
      }
    }

    return bestFaceByPhotoId.values.map((face) => face.id).toSet();
  }

  List<List<FaceEntity>> _buildSeedClusters(
    List<FaceEntity> faces, {
    required double seedToCentroidThreshold,
    required double seedToCoverThreshold,
    required int maxClusterSize,
  }) {
    final sortedFaces = List<FaceEntity>.from(faces)
      ..sort((left, right) {
        final primaryCompare = (right.isPrimaryFace ? 1 : 0).compareTo(
          left.isPrimaryFace ? 1 : 0,
        );
        if (primaryCompare != 0) {
          return primaryCompare;
        }
        return (right.qualityScore ?? 0.0).compareTo(left.qualityScore ?? 0.0);
      });

    final clusters = <List<FaceEntity>>[];
    for (final face in sortedFaces) {
      var bestIndex = -1;
      var bestScore = -double.infinity;

      for (var index = 0; index < clusters.length; index++) {
        final cluster = clusters[index];
        if (cluster.length >= maxClusterSize) {
          continue;
        }

        final centroid = _centroid(cluster);
        if (centroid.isEmpty) {
          continue;
        }
        final centroidSimilarity = _cosineSimilarity(face.embedding!, centroid);
        if (centroidSimilarity < seedToCentroidThreshold) {
          continue;
        }

        final coverFace = _coverFace(cluster);
        final coverSimilarity = _cosineSimilarity(
          face.embedding!,
          coverFace.embedding!,
        );
        if (coverSimilarity < seedToCoverThreshold) {
          continue;
        }

        final score = (centroidSimilarity + coverSimilarity) / 2;
        if (score > bestScore) {
          bestScore = score;
          bestIndex = index;
        }
      }

      if (bestIndex >= 0) {
        clusters[bestIndex].add(face);
        continue;
      }

      clusters.add(<FaceEntity>[face]);
    }

    return clusters;
  }

  int _bestStableClusterIndex(
    List<FaceEntity> smallCluster,
    List<List<FaceEntity>> stableClusters, {
    required double minSimilarity,
    double? coverThreshold,
  }) {
    if (stableClusters.isEmpty) {
      return -1;
    }

    final smallCentroid = _centroid(smallCluster);
    if (smallCentroid.isEmpty) {
      return -1;
    }

    var bestIndex = -1;
    var bestSimilarity = -double.infinity;
    for (var index = 0; index < stableClusters.length; index++) {
      final stableCluster = stableClusters[index];
      final stableCentroid = _centroid(stableCluster);
      if (stableCentroid.isEmpty) {
        continue;
      }
      final similarity = _cosineSimilarity(smallCentroid, stableCentroid);
      if (coverThreshold != null) {
        final stableCover = _coverFace(stableCluster);
        final smallCover = _coverFace(smallCluster);
        final coverSimilarity = _cosineSimilarity(
          smallCover.embedding!,
          stableCover.embedding!,
        );
        if (coverSimilarity < coverThreshold) {
          continue;
        }
      }
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestIndex = index;
      }
    }

    if (bestSimilarity < minSimilarity) {
      return -1;
    }
    return bestIndex;
  }

  void _mergeStableClusters(
    List<List<FaceEntity>> stableClusters, {
    required double centroidThreshold,
    required double coverThreshold,
    required int maxClusterSize,
  }) {
    _mergeClustersInPlace(
      stableClusters,
      centroidThreshold: centroidThreshold,
      coverThreshold: coverThreshold,
      maxClusterSize: maxClusterSize,
    );
  }

  void _mergeSmallRepresentativeClusters(
    List<List<FaceEntity>> clusters, {
    required double centroidThreshold,
    required double coverThreshold,
    required double pairThreshold,
    required int maxClusterSize,
    required int smallClusterMaxSize,
  }) {
    if (clusters.length < 2) {
      return;
    }

    while (true) {
      var bestLeft = -1;
      var bestRight = -1;
      var bestScore = -double.infinity;

      for (var left = 0; left < clusters.length; left++) {
        for (var right = left + 1; right < clusters.length; right++) {
          final leftCluster = clusters[left];
          final rightCluster = clusters[right];
          if (leftCluster.length > smallClusterMaxSize ||
              rightCluster.length > smallClusterMaxSize) {
            continue;
          }
          if (leftCluster.length + rightCluster.length > maxClusterSize) {
            continue;
          }

          final centroidSimilarity = _cosineSimilarity(
            _centroid(leftCluster),
            _centroid(rightCluster),
          );
          if (centroidSimilarity < centroidThreshold) {
            continue;
          }

          final coverSimilarity = _cosineSimilarity(
            _coverFace(leftCluster).embedding!,
            _coverFace(rightCluster).embedding!,
          );
          if (coverSimilarity < coverThreshold) {
            continue;
          }

          final maxPairSimilarity = _maxPairSimilarity(
            leftCluster,
            rightCluster,
          );
          if (maxPairSimilarity < pairThreshold) {
            continue;
          }

          final score =
              (centroidSimilarity + coverSimilarity + maxPairSimilarity) / 3;
          if (score > bestScore) {
            bestScore = score;
            bestLeft = left;
            bestRight = right;
          }
        }
      }

      if (bestLeft < 0 || bestRight < 0) {
        break;
      }

      clusters[bestLeft].addAll(clusters[bestRight]);
      clusters.removeAt(bestRight);
    }
  }

  void _mergeClustersInPlace(
    List<List<FaceEntity>> clusters, {
    required double centroidThreshold,
    required double coverThreshold,
    required int maxClusterSize,
  }) {
    if (clusters.length < 2) {
      return;
    }

    while (true) {
      var bestLeft = -1;
      var bestRight = -1;
      var bestScore = -double.infinity;

      for (var left = 0; left < clusters.length; left++) {
        for (var right = left + 1; right < clusters.length; right++) {
          final leftCluster = clusters[left];
          final rightCluster = clusters[right];
          if (leftCluster.length + rightCluster.length > maxClusterSize) {
            continue;
          }

          final centroidSimilarity = _cosineSimilarity(
            _centroid(leftCluster),
            _centroid(rightCluster),
          );
          if (centroidSimilarity < centroidThreshold) {
            continue;
          }

          final coverSimilarity = _cosineSimilarity(
            _coverFace(leftCluster).embedding!,
            _coverFace(rightCluster).embedding!,
          );
          if (coverSimilarity < coverThreshold) {
            continue;
          }

          final score = (centroidSimilarity + coverSimilarity) / 2;
          if (score > bestScore) {
            bestScore = score;
            bestLeft = left;
            bestRight = right;
          }
        }
      }

      if (bestLeft < 0 || bestRight < 0) {
        break;
      }

      clusters[bestLeft].addAll(clusters[bestRight]);
      clusters.removeAt(bestRight);
    }
  }

  List<double> _centroid(List<FaceEntity> faces) {
    if (faces.isEmpty) {
      return const <double>[];
    }

    final embeddings = faces
        .map((face) => face.embedding)
        .whereType<List<double>>()
        .where((embedding) => embedding.isNotEmpty)
        .toList(growable: false);
    if (embeddings.isEmpty) {
      return const <double>[];
    }

    final dimension = embeddings.first.length;
    if (embeddings.any((embedding) => embedding.length != dimension)) {
      return const <double>[];
    }

    final centroid = List<double>.filled(dimension, 0.0);
    for (final embedding in embeddings) {
      for (var index = 0; index < dimension; index++) {
        centroid[index] += embedding[index];
      }
    }
    for (var index = 0; index < dimension; index++) {
      centroid[index] /= embeddings.length;
    }

    final norm = math.sqrt(
      centroid.fold<double>(0.0, (sum, value) => sum + value * value),
    );
    if (norm <= 0) {
      return centroid;
    }
    return centroid.map((value) => value / norm).toList(growable: false);
  }

  double _averageQuality(List<FaceEntity> faces) {
    if (faces.isEmpty) {
      return 0.0;
    }
    final total = faces.fold<double>(
      0.0,
      (sum, face) => sum + (face.qualityScore ?? 0.0),
    );
    return total / faces.length;
  }

  FaceEntity _coverFace(List<FaceEntity> faces) {
    final sorted = List<FaceEntity>.from(faces)
      ..sort((left, right) {
        final primaryCompare = (right.isPrimaryFace ? 1 : 0).compareTo(
          left.isPrimaryFace ? 1 : 0,
        );
        if (primaryCompare != 0) {
          return primaryCompare;
        }
        return (right.qualityScore ?? 0.0).compareTo(left.qualityScore ?? 0.0);
      });
    return sorted.first;
  }

  double _faceAreaRatio(FaceEntity face, PhotoEntity? photo) {
    if (photo == null || photo.width <= 0 || photo.height <= 0) {
      return 0.0;
    }
    return face.area / (photo.width * photo.height);
  }

  double _representativeScore(FaceEntity face, PhotoEntity? photo) {
    final primaryBonus = face.isPrimaryFace ? 1000.0 : 0.0;
    final qualityScore = (face.qualityScore ?? 0.0) * 100;
    final areaScore = _faceAreaRatio(face, photo) * 50;
    final yawPenalty = (face.yaw?.abs() ?? 0.0) * 0.5;
    final rollPenalty = (face.roll?.abs() ?? 0.0) * 0.5;

    return primaryBonus + qualityScore + areaScore - yawPenalty - rollPenalty;
  }

  double _cosineSimilarity(List<double> left, List<double> right) {
    if (left.isEmpty || right.isEmpty || left.length != right.length) {
      return 0.0;
    }

    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftNorm += left[index] * left[index];
      rightNorm += right[index] * right[index];
    }

    if (leftNorm <= 0 || rightNorm <= 0) {
      return 0.0;
    }

    return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }

  double _maxPairSimilarity(List<FaceEntity> left, List<FaceEntity> right) {
    var best = -double.infinity;
    for (final leftFace in left) {
      for (final rightFace in right) {
        final similarity = _cosineSimilarity(
          leftFace.embedding!,
          rightFace.embedding!,
        );
        if (similarity > best) {
          best = similarity;
        }
      }
    }
    return best;
  }

  Future<void> _persistAssignments({
    required List<FaceEntity> allFaces,
    required Map<int, int?> assignedClusterByFaceId,
  }) async {
    if (_facesLoader != null) {
      return;
    }

    for (final face in allFaces) {
      face.clusterId = assignedClusterByFaceId[face.id];
      face.updatedAt = DateTime.now().millisecondsSinceEpoch;
    }

    final store = ObjectBoxService().store;
    store.runInTransaction(TxMode.write, () {
      store.box<FaceEntity>().putMany(allFaces);
    });
  }

  void _logClusterPairDiagnostics({
    required List<FaceEntity> allFaces,
    required Map<int, int?> assignedClusterByFaceId,
  }) {
    if (!kDebugMode) {
      return;
    }

    final grouped = <int, List<FaceEntity>>{};
    for (final face in allFaces) {
      final clusterId = assignedClusterByFaceId[face.id];
      if (clusterId == null) {
        continue;
      }
      grouped.putIfAbsent(clusterId, () => <FaceEntity>[]).add(face);
    }

    final entries = grouped.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    if (entries.length < 2) {
      return;
    }

    for (var left = 0; left < entries.length; left++) {
      for (var right = left + 1; right < entries.length; right++) {
        final leftCluster = entries[left].value;
        final rightCluster = entries[right].value;
        final centroidSim = _cosineSimilarity(
          _centroid(leftCluster),
          _centroid(rightCluster),
        );
        final leftCover = _coverFace(leftCluster);
        final rightCover = _coverFace(rightCluster);
        final coverSim = _cosineSimilarity(
          leftCover.embedding!,
          rightCover.embedding!,
        );

        var bestPairSim = -double.infinity;
        var bestLeftFaceId = -1;
        var bestRightFaceId = -1;
        for (final leftFace in leftCluster) {
          for (final rightFace in rightCluster) {
            final similarity = _cosineSimilarity(
              leftFace.embedding!,
              rightFace.embedding!,
            );
            if (similarity > bestPairSim) {
              bestPairSim = similarity;
              bestLeftFaceId = leftFace.id;
              bestRightFaceId = rightFace.id;
            }
          }
        }

        debugPrint(
          '🧩 [FaceClusterPair] ${entries[left].key}<->${entries[right].key} '
          'size=${leftCluster.length}/${rightCluster.length} '
          'coverFaces=${leftCover.id}/${rightCover.id} '
          'centroid=${centroidSim.toStringAsFixed(4)} '
          'cover=${coverSim.toStringAsFixed(4)} '
          'maxPair=${bestPairSim.toStringAsFixed(4)} '
          'bestFaces=$bestLeftFaceId/$bestRightFaceId',
        );
      }
    }
  }
}
