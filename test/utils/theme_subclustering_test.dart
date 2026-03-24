import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/models/theme_cluster_models.dart';
import 'package:photo_album/utils/theme_subclustering.dart';

ThemeDefinition _theme(String id) {
  return ThemeDefinition(
    id: id,
    title: id,
    subtitle: 'sub',
    prototypePrompts: const <String>['p'],
    keywords: const <String>[],
    minSimilarity: 0.0,
  );
}

PhotoEntity _photo({
  required int id,
  required DateTime t,
  int faceCount = 0,
  List<String>? aiTags,
  List<String>? ocrTags,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/$id.jpg'
    ..timestamp = t.millisecondsSinceEpoch
    ..width = 1000
    ..height = 1000
    ..faceCount = faceCount
    ..aiTags = aiTags
    ..ocrTags = ocrTags;
}

ScoredThemePhoto _scored({
  required PhotoEntity photo,
  required List<double> embedding,
  double score = 0.5,
}) {
  return ScoredThemePhoto(photo: photo, score: score, embedding: embedding);
}

void main() {
  group('theme_subclustering core', () {
    test('people hybrid mode splits different solo identities and keeps group photos', () {
      final now = DateTime(2026, 1, 1, 10);
      final scored = <ScoredThemePhoto>[
        _scored(photo: _photo(id: 1, t: now, faceCount: 1), embedding: const [1.0, 0.0], score: 0.9),
        _scored(photo: _photo(id: 2, t: now.add(const Duration(minutes: 1)), faceCount: 1), embedding: const [0.999, 0.001], score: 0.8),
        _scored(photo: _photo(id: 3, t: now.add(const Duration(minutes: 2)), faceCount: 1), embedding: const [-1.0, 0.0], score: 0.7),
        _scored(photo: _photo(id: 4, t: now.add(const Duration(minutes: 3)), faceCount: 1), embedding: const [-0.999, -0.001], score: 0.6),
        _scored(photo: _photo(id: 5, t: now.add(const Duration(minutes: 4)), faceCount: 2), embedding: const [0.0, 1.0], score: 0.7),
        _scored(photo: _photo(id: 6, t: now.add(const Duration(minutes: 5)), faceCount: 2), embedding: const [0.001, 0.999], score: 0.6),
      ];

      final subclusters = const PeopleThemeSubclusterer().buildSubclusters(
        definition: _theme('people'),
        scoredPhotos: scored,
        maxPreviewPerGroup: 10,
        minPhotosPerSubcluster: 2,
        pureEmbeddingOnly: false,
      );

      expect(subclusters.length, 3);
      final identityClusters = subclusters
          .where((item) => item.title.startsWith('人物簇 '))
          .toList(growable: false);
      expect(identityClusters.length, 2);
      expect(subclusters.any((item) => item.title == '多人合影'), isTrue);
    });

    test('people hybrid mode respects minPhotosPerSubcluster and avoids tiny identity shards', () {
      final now = DateTime(2026, 1, 1, 10);
      final scored = <ScoredThemePhoto>[
        _scored(photo: _photo(id: 1, t: now, faceCount: 1), embedding: const [1.0, 0.0], score: 0.9),
        _scored(photo: _photo(id: 2, t: now.add(const Duration(minutes: 1)), faceCount: 1), embedding: const [0.999, 0.001], score: 0.8),
        _scored(photo: _photo(id: 3, t: now.add(const Duration(minutes: 2)), faceCount: 1), embedding: const [-1.0, 0.0], score: 0.7),
        _scored(photo: _photo(id: 4, t: now.add(const Duration(minutes: 3)), faceCount: 1), embedding: const [-0.999, -0.001], score: 0.6),
      ];

      final subclusters = const PeopleThemeSubclusterer().buildSubclusters(
        definition: _theme('people'),
        scoredPhotos: scored,
        maxPreviewPerGroup: 10,
        minPhotosPerSubcluster: 4,
        pureEmbeddingOnly: false,
      );

      expect(subclusters.length, 1);
      expect(subclusters.first.title, '单人照片');
      expect(subclusters.first.totalPhotos, 4);
    });

    test('people hybrid mode absorbs nearby leftovers back into a stable identity cluster', () {
      final now = DateTime(2026, 1, 1, 10);
      final scored = <ScoredThemePhoto>[
        _scored(photo: _photo(id: 1, t: now, faceCount: 1), embedding: const [1.0, 0.0], score: 0.9),
        _scored(photo: _photo(id: 2, t: now.add(const Duration(minutes: 1)), faceCount: 1), embedding: const [0.995, 0.005], score: 0.88),
        _scored(photo: _photo(id: 3, t: now.add(const Duration(minutes: 2)), faceCount: 1), embedding: const [0.99, 0.01], score: 0.86),
        _scored(photo: _photo(id: 4, t: now.add(const Duration(minutes: 3)), faceCount: 1), embedding: const [0.985, 0.015], score: 0.84),
        _scored(photo: _photo(id: 5, t: now.add(const Duration(minutes: 4)), faceCount: 1), embedding: const [0.97, 0.03], score: 0.82),
      ];

      final subclusters = const PeopleThemeSubclusterer().buildSubclusters(
        definition: _theme('people'),
        scoredPhotos: scored,
        maxPreviewPerGroup: 10,
        minPhotosPerSubcluster: 4,
        pureEmbeddingOnly: false,
      );

      expect(subclusters.length, 1);
      expect(subclusters.first.title, '人物簇 1');
      expect(subclusters.first.totalPhotos, 5);
    });

    test('people pure embedding mode delegates to DBSCAN path', () {
      final now = DateTime(2026, 1, 1, 10);
      final scored = <ScoredThemePhoto>[
        _scored(photo: _photo(id: 1, t: now, faceCount: 0), embedding: const [1.0, 0.0], score: 0.9),
        _scored(photo: _photo(id: 2, t: now.add(const Duration(minutes: 1)), faceCount: 0), embedding: const [0.999, 0.001], score: 0.8),
      ];

      final subclusters = const PeopleThemeSubclusterer().buildSubclusters(
        definition: _theme('people'),
        scoredPhotos: scored,
        maxPreviewPerGroup: 10,
        minPhotosPerSubcluster: 2,
        pureEmbeddingOnly: true,
      );

      expect(subclusters, isNotEmpty);
      expect(subclusters.first.algorithm.currentLabel.contains('DBSCAN'), isTrue);
    });

    test('buildTimelineGroups groups by month in descending order and limits preview', () {
      final photos = <PhotoEntity>[
        _photo(id: 1, t: DateTime(2026, 1, 5)),
        _photo(id: 2, t: DateTime(2026, 1, 6)),
        _photo(id: 3, t: DateTime(2026, 2, 7)),
      ];

      final groups = buildTimelineGroups(photos, maxPreviewPerGroup: 1);

      expect(groups.length, 2);
      expect(groups.first.title, '2026年2月');
      expect(groups.first.photos.length, 1);
      expect(groups.last.title, '2026年1月');
      expect(groups.last.totalPhotos, 2);
    });

    test('generic pure embedding keeps boundary samples as dedicated subcluster', () {
      final now = DateTime(2026, 1, 1, 10);
      final scored = <ScoredThemePhoto>[
        _scored(photo: _photo(id: 1, t: now), embedding: const [1.0, 0.0], score: 0.9),
        _scored(photo: _photo(id: 2, t: now.add(const Duration(minutes: 1))), embedding: const [0.999, 0.001], score: 0.8),
        _scored(photo: _photo(id: 3, t: now.add(const Duration(minutes: 2))), embedding: const [-1.0, 0.0], score: 0.7),
      ];

      final subclusters = const GenericThemeSubclusterer().buildSubclusters(
        definition: _theme('scenery'),
        scoredPhotos: scored,
        maxPreviewPerGroup: 10,
        minPhotosPerSubcluster: 2,
        pureEmbeddingOnly: true,
      );

      expect(subclusters.length, 2);
      expect(subclusters.any((item) => item.title == '向量边界样本'), isTrue);
    });

    test('heuristic fallback returns single all-subcluster for themes without rules', () {
      final now = DateTime(2026, 1, 1, 10);
      final scored = <ScoredThemePhoto>[
        _scored(photo: _photo(id: 1, t: now), embedding: const [1.0, 0.0], score: 0.9),
        _scored(photo: _photo(id: 2, t: now.add(const Duration(minutes: 1))), embedding: const [0.9, 0.1], score: 0.7),
      ];

      final subclusters = const HeuristicThemeSubclusterer().buildSubclusters(
        definition: _theme('scenery'),
        scoredPhotos: scored,
        maxPreviewPerGroup: 10,
        minPhotosPerSubcluster: 2,
        pureEmbeddingOnly: false,
      );

      expect(subclusters.length, 1);
      expect(subclusters.first.id, 'scenery_all');
      expect(subclusters.first.totalPhotos, 2);
    });
  });
}
