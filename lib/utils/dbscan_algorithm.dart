import 'dart:math' as math;

import '../models/theme_cluster_models.dart';

class DbscanClusterResult {
  const DbscanClusterResult({
    required this.clusters,
    required this.leftovers,
  });

  final List<List<ScoredThemePhoto>> clusters;
  final List<ScoredThemePhoto> leftovers;
}

class DbscanAlgorithm {
  const DbscanAlgorithm._();

  static const int _dbscanUnassigned = -2;
  static const int _dbscanNoise = -1;

  static DbscanClusterResult clusterScoredPhotos({
    required List<ScoredThemePhoto> scoredPhotos,
    required int minPhotosPerSubcluster,
    required double epsilon,
  }) {
    if (scoredPhotos.length < 2) {
      return DbscanClusterResult(
        clusters: const <List<ScoredThemePhoto>>[],
        leftovers: scoredPhotos,
      );
    }

    final embedded = <_EmbeddedScoredThemePhoto>[];
    final noEmbedding = <ScoredThemePhoto>[];
    var dimension = 0;
    for (final item in scoredPhotos) {
      final embedding = item.embedding;
      if (embedding.isEmpty) {
        noEmbedding.add(item);
        continue;
      }
      if (dimension == 0) {
        dimension = embedding.length;
      }
      if (embedding.length != dimension) {
        noEmbedding.add(item);
        continue;
      }
      embedded.add(_EmbeddedScoredThemePhoto(item: item, embedding: embedding));
    }

    if (embedded.length < minPhotosPerSubcluster || dimension == 0) {
      return DbscanClusterResult(
        clusters: const <List<ScoredThemePhoto>>[],
        leftovers: scoredPhotos,
      );
    }

    final minPoints = math.max(2, math.min(4, minPhotosPerSubcluster - 1));
    final assignments = List<int>.filled(embedded.length, _dbscanUnassigned);
    final visited = List<bool>.filled(embedded.length, false);
    var clusterId = 0;

    for (var index = 0; index < embedded.length; index++) {
      if (visited[index]) {
        continue;
      }
      visited[index] = true;
      final neighbors = _regionQuery(embedded, index, epsilon);
      if (neighbors.length < minPoints) {
        assignments[index] = _dbscanNoise;
        continue;
      }

      _expandCluster(
        points: embedded,
        assignments: assignments,
        visited: visited,
        seedIndex: index,
        neighbors: neighbors,
        clusterId: clusterId,
        epsilon: epsilon,
        minPoints: minPoints,
      );
      clusterId++;
    }

    final clusters = <List<ScoredThemePhoto>>[];
    final leftovers = <ScoredThemePhoto>[...noEmbedding];
    for (var id = 0; id < clusterId; id++) {
      final members = <ScoredThemePhoto>[];
      for (var index = 0; index < embedded.length; index++) {
        if (assignments[index] == id) {
          members.add(embedded[index].item);
        }
      }

      if (members.length >= minPhotosPerSubcluster) {
        members.sort((a, b) {
          final scoreCompare = b.score.compareTo(a.score);
          if (scoreCompare != 0) {
            return scoreCompare;
          }
          return b.photo.timestamp.compareTo(a.photo.timestamp);
        });
        clusters.add(members);
      } else {
        leftovers.addAll(members);
      }
    }

    for (var index = 0; index < embedded.length; index++) {
      if (assignments[index] == _dbscanNoise) {
        leftovers.add(embedded[index].item);
      }
    }

    return DbscanClusterResult(clusters: clusters, leftovers: leftovers);
  }

  static void _expandCluster({
    required List<_EmbeddedScoredThemePhoto> points,
    required List<int> assignments,
    required List<bool> visited,
    required int seedIndex,
    required List<int> neighbors,
    required int clusterId,
    required double epsilon,
    required int minPoints,
  }) {
    assignments[seedIndex] = clusterId;
    final queue = List<int>.from(neighbors);
    final seen = queue.toSet();

    while (queue.isNotEmpty) {
      final currentIndex = queue.removeLast();
      if (!visited[currentIndex]) {
        visited[currentIndex] = true;
        final currentNeighbors = _regionQuery(points, currentIndex, epsilon);
        if (currentNeighbors.length >= minPoints) {
          for (final neighbor in currentNeighbors) {
            if (seen.add(neighbor)) {
              queue.add(neighbor);
            }
          }
        }
      }

      if (assignments[currentIndex] == _dbscanUnassigned ||
          assignments[currentIndex] == _dbscanNoise) {
        assignments[currentIndex] = clusterId;
      }
    }
  }

  static List<int> _regionQuery(
    List<_EmbeddedScoredThemePhoto> points,
    int centerIndex,
    double epsilon,
  ) {
    final neighbors = <int>[];
    for (var index = 0; index < points.length; index++) {
      final distance = _cosineDistance(
        points[centerIndex].embedding,
        points[index].embedding,
      );
      if (distance <= epsilon) {
        neighbors.add(index);
      }
    }
    return neighbors;
  }

  static double _cosineDistance(List<double> left, List<double> right) {
    final similarity = _cosineSimilarity(left, right);
    return 1 - similarity;
  }

  static double _cosineSimilarity(List<double> left, List<double> right) {
    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;

    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftNorm += left[index] * left[index];
      rightNorm += right[index] * right[index];
    }

    if (leftNorm <= 0 || rightNorm <= 0) {
      return 0;
    }

    return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }
}

class _EmbeddedScoredThemePhoto {
  const _EmbeddedScoredThemePhoto({
    required this.item,
    required this.embedding,
  });

  final ScoredThemePhoto item;
  final List<double> embedding;
}
