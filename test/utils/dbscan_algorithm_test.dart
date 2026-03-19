import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/models/theme_cluster_models.dart';
import 'package:photo_album/utils/dbscan_algorithm.dart';

PhotoEntity _photo({
  required int id,
  required int ts,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/$id.jpg'
    ..timestamp = ts
    ..width = 1000
    ..height = 1000;
}

ScoredThemePhoto _scored({
  required int id,
  required List<double> embedding,
  double score = 0.5,
}) {
  return ScoredThemePhoto(
    photo: _photo(id: id, ts: id),
    score: score,
    embedding: embedding,
  );
}

void main() {
  group('DbscanAlgorithm', () {
    test('clusters nearby vectors and leaves far point as leftover', () {
      final samples = <ScoredThemePhoto>[
        _scored(id: 1, embedding: const [1.0, 0.0], score: 0.9),
        _scored(id: 2, embedding: const [0.999, 0.001], score: 0.8),
        _scored(id: 3, embedding: const [-1.0, 0.0], score: 0.7),
      ];

      final result = DbscanAlgorithm.clusterScoredPhotos(
        scoredPhotos: samples,
        minPhotosPerSubcluster: 2,
        epsilon: 0.01,
      );

      expect(result.clusters.length, 1);
      expect(result.clusters.first.length, 2);
      expect(result.leftovers.length, 1);
      expect(result.leftovers.first.photo.id, 3);
    });

    test('treats dimension mismatch as leftovers', () {
      final samples = <ScoredThemePhoto>[
        _scored(id: 1, embedding: const [1.0, 0.0]),
        _scored(id: 2, embedding: const [1.0, 0.0, 0.0]),
      ];

      final result = DbscanAlgorithm.clusterScoredPhotos(
        scoredPhotos: samples,
        minPhotosPerSubcluster: 2,
        epsilon: 0.05,
      );

      expect(result.clusters, isEmpty);
      expect(result.leftovers.length, 2);
    });

    test('returns all leftovers when not enough dense points', () {
      final samples = <ScoredThemePhoto>[
        _scored(id: 1, embedding: const [1.0, 0.0]),
        _scored(id: 2, embedding: const [0.0, 1.0]),
        _scored(id: 3, embedding: const [-1.0, 0.0]),
      ];

      final result = DbscanAlgorithm.clusterScoredPhotos(
        scoredPhotos: samples,
        minPhotosPerSubcluster: 3,
        epsilon: 0.02,
      );

      expect(result.clusters, isEmpty);
      expect(result.leftovers.length, 3);
    });

    test('sorts cluster members by score desc then timestamp desc', () {
      final samples = <ScoredThemePhoto>[
        _scored(id: 1, embedding: const [1.0, 0.0], score: 0.8),
        _scored(id: 3, embedding: const [0.999, 0.001], score: 0.8),
        _scored(id: 2, embedding: const [0.998, 0.002], score: 0.95),
      ];

      final result = DbscanAlgorithm.clusterScoredPhotos(
        scoredPhotos: samples,
        minPhotosPerSubcluster: 2,
        epsilon: 0.01,
      );

      expect(result.clusters.length, 1);
      final ids = result.clusters.first.map((e) => e.photo.id).toList(growable: false);
      expect(ids, <int>[2, 3, 1]);
    });

    test('keeps empty-embedding items as leftovers', () {
      final samples = <ScoredThemePhoto>[
        _scored(id: 1, embedding: const [1.0, 0.0], score: 0.8),
        _scored(id: 2, embedding: const [0.999, 0.001], score: 0.7),
        _scored(id: 99, embedding: const <double>[], score: 0.1),
      ];

      final result = DbscanAlgorithm.clusterScoredPhotos(
        scoredPhotos: samples,
        minPhotosPerSubcluster: 2,
        epsilon: 0.01,
      );

      expect(result.clusters.length, 1);
      expect(result.leftovers.any((item) => item.photo.id == 99), isTrue);
    });
  });
}
