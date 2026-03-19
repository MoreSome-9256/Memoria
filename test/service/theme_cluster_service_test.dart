import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/models/theme_cluster_models.dart';
import 'package:photo_album/service/theme_cluster_service.dart';
import 'package:photo_album/utils/theme_subclustering.dart';

PhotoEntity _photo({
  required int id,
  required int ts,
  int faceCount = 0,
  List<String>? aiTags,
  int width = 1000,
  int height = 1000,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/$id.jpg'
    ..timestamp = ts
    ..width = width
    ..height = height
    ..faceCount = faceCount
    ..aiTags = aiTags;
}

ThemeDefinition _theme({
  required String id,
  double minSimilarity = 0.0,
}) {
  return ThemeDefinition(
    id: id,
    title: id,
    subtitle: 'sub',
    prototypePrompts: const <String>['p'],
    keywords: const <String>['cat'],
    minSimilarity: minSimilarity,
  );
}

class _RecordingSubclusterer extends ThemeSubclusterer {
  _RecordingSubclusterer(this.name);

  final String name;
  final List<List<ScoredThemePhoto>> calls = <List<ScoredThemePhoto>>[];

  @override
  List<ThemeSubcluster> buildSubclusters({
    required ThemeDefinition definition,
    required List<ScoredThemePhoto> scoredPhotos,
    required int maxPreviewPerGroup,
    required int minPhotosPerSubcluster,
    required bool pureEmbeddingOnly,
  }) {
    calls.add(scoredPhotos);
    final photos = scoredPhotos.map((e) => e.photo).toList(growable: false);
    return <ThemeSubcluster>[
      ThemeSubcluster(
        id: '${definition.id}_$name',
        title: '$name-${definition.id}',
        subtitle: 'stub',
        algorithm: ThemeSubclusterAlgorithm(
          currentLabel: pureEmbeddingOnly ? 'pure' : 'hybrid',
          nextLabel: 'next',
        ),
        cohesion: null,
        totalPhotos: photos.length,
        coverPhotos: photos.take(4).toList(growable: false),
        groups: buildTimelineGroups(
          photos,
          maxPreviewPerGroup: maxPreviewPerGroup,
        ),
      ),
    ];
  }
}

void main() {
  group('ThemeClusterService orchestration', () {
    test('uses injected dependencies and returns sorted clusters', () async {
      final photos = <PhotoEntity>[
        _photo(id: 1, ts: 1, aiTags: const <String>['cat']),
        _photo(id: 2, ts: 2, aiTags: const <String>['cat']),
        _photo(id: 3, ts: 3, aiTags: const <String>['cat']),
      ];

      final peopleSubclusterer = _RecordingSubclusterer('people');
      final genericSubclusterer = _RecordingSubclusterer('generic');

      final service = ThemeClusterService.forTest(
        definitions: <ThemeDefinition>[
          _theme(id: 'people', minSimilarity: 0.0),
          _theme(id: 'pets', minSimilarity: 0.0),
        ],
        photosLoader: () async => photos,
        embeddingPreparer: (items) async => <int, List<double>>{
          for (final p in items) p.id: const <double>[1.0, 0.0],
        },
        prototypeBuilder: () async => <String, List<double>>{
          'people': const <double>[1.0, 0.0],
          'pets': const <double>[1.0, 0.0],
        },
        peopleSubclusterer: peopleSubclusterer,
        genericSubclusterer: genericSubclusterer,
      );

      final clusters = await service.loadClusters(
        minPhotosPerTheme: 1,
        pureEmbeddingOnly: true,
      );

      expect(clusters.length, 2);
      expect(clusters.first.definition.id, 'people');
      expect(clusters.last.definition.id, 'pets');
      expect(peopleSubclusterer.calls.length, 1);
      expect(genericSubclusterer.calls.length, 1);
      expect(peopleSubclusterer.calls.first.length, 3);
      expect(genericSubclusterer.calls.first.length, 3);
    });

    test('hybrid mode keeps people theme face filter, pure mode disables it', () async {
      final photos = <PhotoEntity>[
        _photo(id: 1, ts: 1, faceCount: 0, aiTags: const <String>['cat']),
        _photo(id: 2, ts: 2, faceCount: 2, aiTags: const <String>['cat']),
      ];

      Future<Map<int, List<double>>> embeddingPreparer(List<PhotoEntity> items) async {
        return <int, List<double>>{
          for (final p in items) p.id: const <double>[1.0, 0.0],
        };
      }

      Future<Map<String, List<double>>> prototypeBuilder() async {
        return <String, List<double>>{
          'people': const <double>[1.0, 0.0],
        };
      }

      final peopleHybrid = _RecordingSubclusterer('people');
      final serviceHybrid = ThemeClusterService.forTest(
        definitions: <ThemeDefinition>[_theme(id: 'people', minSimilarity: 0.0)],
        photosLoader: () async => photos,
        embeddingPreparer: embeddingPreparer,
        prototypeBuilder: prototypeBuilder,
        peopleSubclusterer: peopleHybrid,
      );
      await serviceHybrid.loadClusters(minPhotosPerTheme: 1, pureEmbeddingOnly: false);
      expect(peopleHybrid.calls.single.length, 1);
      expect(peopleHybrid.calls.single.single.photo.id, 2);

      final peoplePure = _RecordingSubclusterer('people');
      final servicePure = ThemeClusterService.forTest(
        definitions: <ThemeDefinition>[_theme(id: 'people', minSimilarity: 0.0)],
        photosLoader: () async => photos,
        embeddingPreparer: embeddingPreparer,
        prototypeBuilder: prototypeBuilder,
        peopleSubclusterer: peoplePure,
      );
      await servicePure.loadClusters(minPhotosPerTheme: 1, pureEmbeddingOnly: true);
      expect(peoplePure.calls.single.length, 2);
    });

    test('screenshots are always filtered before scoring', () async {
      final photos = <PhotoEntity>[
        _photo(id: 1, ts: 1, width: 3000, height: 1000), // screenshot-like
        _photo(id: 2, ts: 2, width: 1000, height: 1000),
      ];

      final generic = _RecordingSubclusterer('generic');
      final service = ThemeClusterService.forTest(
        definitions: <ThemeDefinition>[_theme(id: 'pets', minSimilarity: 0.0)],
        photosLoader: () async => photos,
        embeddingPreparer: (items) async => <int, List<double>>{
          for (final p in items) p.id: const <double>[1.0, 0.0],
        },
        prototypeBuilder: () async => <String, List<double>>{
          'pets': const <double>[1.0, 0.0],
        },
        genericSubclusterer: generic,
      );

      await service.loadClusters(minPhotosPerTheme: 1, pureEmbeddingOnly: true);

      expect(generic.calls.single.length, 1);
      expect(generic.calls.single.single.photo.id, 2);
    });
  });
}
