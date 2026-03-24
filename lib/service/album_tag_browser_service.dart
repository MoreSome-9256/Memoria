import 'dart:io';

import '../data/tag_taxonomy_v2.dart';
import '../models/entity/photo_entity.dart';
import '../utils/tag_sanitizer.dart';

class AlbumFineTagSummary {
  const AlbumFineTagSummary({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;
}

class AlbumCoarseTagCluster {
  const AlbumCoarseTagCluster({
    required this.coarseId,
    required this.label,
    required this.photoCount,
    required this.coverPhotos,
    required this.topFineTags,
  });

  final String coarseId;
  final String label;
  final int photoCount;
  final List<PhotoEntity> coverPhotos;
  final List<AlbumFineTagSummary> topFineTags;
}

class AlbumTagBrowserService {
  AlbumTagBrowserService._internal();

  static final AlbumTagBrowserService _instance =
      AlbumTagBrowserService._internal();

  factory AlbumTagBrowserService() => _instance;

  List<AlbumCoarseTagCluster> buildCoarseClusters(
    List<PhotoEntity> photos, {
    int fineTopK = 5,
    int coverLimit = 4,
  }) {
    final clusterPhotos = <String, List<PhotoEntity>>{};
    final fineCountsByCoarse = <String, Map<String, int>>{};
    final fineScoresByCoarse = <String, Map<String, double>>{};

    for (final photo in photos) {
      if (!_hasRenderableFile(photo)) {
        continue;
      }
      final tags = clusterableTagsForPhoto(photo);
      if (tags.isEmpty) {
        continue;
      }

      final coarseIds = tags
          .map((tag) => memoriaAlbumTagLabelToCoarseId[tag])
          .whereType<String>()
          .toSet();
      for (final coarseId in coarseIds) {
        clusterPhotos.putIfAbsent(coarseId, () => <PhotoEntity>[]).add(photo);
        final fineCounts = fineCountsByCoarse.putIfAbsent(
          coarseId,
          () => <String, int>{},
        );
        final fineScores = fineScoresByCoarse.putIfAbsent(
          coarseId,
          () => <String, double>{},
        );
        for (var i = 0; i < tags.length; i++) {
          final tag = tags[i];
          if (memoriaAlbumTagLabelToCoarseId[tag] != coarseId) {
            continue;
          }
          fineCounts[tag] = (fineCounts[tag] ?? 0) + 1;
          fineScores[tag] = (fineScores[tag] ?? 0) + _weightForRank(i);
        }
      }
    }

    final clusters = <AlbumCoarseTagCluster>[];
    for (final definition in memoriaCoarseTagDefinitions) {
      final photosInCluster = clusterPhotos[definition.id];
      if (photosInCluster == null || photosInCluster.isEmpty) {
        continue;
      }
      photosInCluster.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final fineCounts = fineCountsByCoarse[definition.id] ?? const <String, int>{};
      final fineScores = fineScoresByCoarse[definition.id] ?? const <String, double>{};
      final topFineTags = fineCounts.entries.toList(growable: false)
        ..sort((a, b) {
          final scoreCompare = (fineScores[b.key] ?? 0).compareTo(
            fineScores[a.key] ?? 0,
          );
          if (scoreCompare != 0) {
            return scoreCompare;
          }
          return b.value.compareTo(a.value);
        });

      clusters.add(
        AlbumCoarseTagCluster(
          coarseId: definition.id,
          label: definition.label,
          photoCount: photosInCluster.length,
          coverPhotos: photosInCluster.take(coverLimit).toList(growable: false),
          topFineTags: topFineTags
              .take(fineTopK)
              .map(
                (entry) => AlbumFineTagSummary(
                  label: entry.key,
                  count: entry.value,
                ),
              )
              .toList(growable: false),
        ),
      );
    }

    clusters.sort((a, b) {
      final aIsOther = a.coarseId == memoriaOtherCoarseId;
      final bIsOther = b.coarseId == memoriaOtherCoarseId;
      if (aIsOther != bIsOther) {
        return aIsOther ? 1 : -1;
      }
      return b.photoCount.compareTo(a.photoCount);
    });
    return clusters;
  }

  bool hasClassifiableTag(PhotoEntity photo) {
    return _hasRenderableFile(photo) && clusterableTagsForPhoto(photo).isNotEmpty;
  }

  List<PhotoEntity> photosForCoarseCluster(
    List<PhotoEntity> photos,
    String coarseId,
  ) {
    final filtered = photos.where((photo) {
      if (!_hasRenderableFile(photo)) {
        return false;
      }
      final tags = clusterableTagsForPhoto(photo);
      return tags.any((tag) => memoriaAlbumTagLabelToCoarseId[tag] == coarseId);
    }).toList(growable: false);
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return filtered;
  }

  List<AlbumFineTagSummary> topFineTagsForCoarseCluster(
    List<PhotoEntity> photos,
    String coarseId, {
    int topK = 5,
    bool includeCrossCoarseTags = false,
  }) {
    final counts = <String, int>{};
    final scores = <String, double>{};
    for (final photo in photos) {
      final tags = clusterableTagsForPhoto(photo);
      for (var i = 0; i < tags.length; i++) {
        final tag = tags[i];
        final tagCoarseId = memoriaAlbumTagLabelToCoarseId[tag];
        if (!includeCrossCoarseTags && tagCoarseId != coarseId) {
          continue;
        }
        counts[tag] = (counts[tag] ?? 0) + 1;
        final score = _weightForRank(i) * (tagCoarseId == coarseId ? 1.15 : 1.0);
        scores[tag] = (scores[tag] ?? 0) + score;
      }
    }
    final sorted = counts.entries.toList(growable: false)
      ..sort((a, b) {
        final scoreCompare = (scores[b.key] ?? 0).compareTo(scores[a.key] ?? 0);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return b.value.compareTo(a.value);
      });
    return sorted
        .take(topK)
        .map((entry) => AlbumFineTagSummary(label: entry.key, count: entry.value))
        .toList(growable: false);
  }

  List<PhotoEntity> filterPhotosByFineTag(
    List<PhotoEntity> photos, {
    required String coarseId,
    String? fineTag,
  }) {
    final filtered = photos.where((photo) {
      if (!_hasRenderableFile(photo)) {
        return false;
      }
      final tags = clusterableTagsForPhoto(photo);
      final inCoarse = tags.any(
        (tag) => memoriaAlbumTagLabelToCoarseId[tag] == coarseId,
      );
      if (!inCoarse) {
        return false;
      }
      if (fineTag == null || fineTag.trim().isEmpty) {
        return true;
      }
      return tags.contains(fineTag);
    }).toList(growable: false);
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return filtered;
  }

  List<String> coarseLabelsForPhoto(PhotoEntity photo) {
    final coarseIds = clusterableTagsForPhoto(photo)
        .map((tag) => memoriaAlbumTagLabelToCoarseId[tag])
        .whereType<String>()
        .toSet();
    return coarseIds
        .map((id) => memoriaCoarseIdToDefinition[id]?.label)
        .whereType<String>()
        .toList(growable: false);
  }

  bool _hasRenderableFile(PhotoEntity photo) {
    final path = photo.path.trim();
    if (path.isEmpty) {
      return false;
    }
    return File(path).existsSync();
  }

  List<String> clusterableTagsForPhoto(PhotoEntity photo) {
    final raw = TagSanitizer.sanitizeVisualTags(photo.aiTags ?? const <String>[]);
    return raw
        .where((tag) => memoriaAlbumTagLabelToCoarseId.containsKey(tag))
        .toList(growable: false);
  }

  double _weightForRank(int rank) {
    switch (rank) {
      case 0:
        return 1.0;
      case 1:
        return 0.9;
      case 2:
        return 0.82;
      case 3:
        return 0.74;
      default:
        return 0.66;
    }
  }
}
