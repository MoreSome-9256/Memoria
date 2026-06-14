// 专辑标签浏览服务，负责按标签组织和筛选照片集合。

import '../data/tag_taxonomy_v2.dart';
import '../models/entity/photo_entity.dart';
import '../utils/tag_sanitizer.dart';
import 'junk_photo_filter_service.dart';

class AlbumFineTagSummary {
  const AlbumFineTagSummary({required this.label, required this.count});

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
  static const Set<String> _genericLowInformationTags = <String>{
    '人物',
    '美食',
    '风景',
  };

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
      if (_isJunkQuarantined(photo) || !_hasRenderableFile(photo)) {
        continue;
      }
      final tags = browsableTagsForPhoto(photo);
      final coarseIds = browsableCoarseIdsForPhoto(photo);
      if (coarseIds.isEmpty) {
        continue;
      }
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

      final fineCounts =
          fineCountsByCoarse[definition.id] ?? const <String, int>{};
      final fineScores =
          fineScoresByCoarse[definition.id] ?? const <String, double>{};
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
                (entry) =>
                    AlbumFineTagSummary(label: entry.key, count: entry.value),
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

  bool hasBrowsableCategory(PhotoEntity photo) {
    return !_isJunkQuarantined(photo) &&
        _hasRenderableFile(photo) &&
        browsableCoarseIdsForPhoto(photo).isNotEmpty;
  }

  List<PhotoEntity> photosForCoarseCluster(
    List<PhotoEntity> photos,
    String coarseId,
  ) {
    final filtered = photos
        .where((photo) {
          if (!_hasRenderableFile(photo)) {
            return false;
          }
          if (_isJunkQuarantined(photo)) {
            return false;
          }
          return browsableCoarseIdsForPhoto(photo).contains(coarseId);
        })
        .toList(growable: false);
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
      final tags = browsableTagsForPhoto(photo);
      for (var i = 0; i < tags.length; i++) {
        final tag = tags[i];
        final tagCoarseId = memoriaAlbumTagLabelToCoarseId[tag];
        if (!includeCrossCoarseTags && tagCoarseId != coarseId) {
          continue;
        }
        counts[tag] = (counts[tag] ?? 0) + 1;
        final score =
            _weightForRank(i) * (tagCoarseId == coarseId ? 1.15 : 1.0);
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
        .map(
          (entry) => AlbumFineTagSummary(label: entry.key, count: entry.value),
        )
        .toList(growable: false);
  }

  List<PhotoEntity> filterPhotosByFineTag(
    List<PhotoEntity> photos, {
    required String coarseId,
    String? fineTag,
  }) {
    final filtered = photos
        .where((photo) {
          if (!_hasRenderableFile(photo)) {
            return false;
          }
          final tags = browsableTagsForPhoto(photo);
          final inCoarse = browsableCoarseIdsForPhoto(photo).contains(coarseId);
          if (!inCoarse) {
            return false;
          }
          if (fineTag == null || fineTag.trim().isEmpty) {
            return true;
          }
          return tags.contains(fineTag);
        })
        .toList(growable: false);
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return filtered;
  }

  List<String> coarseLabelsForPhoto(PhotoEntity photo) {
    final coarseIds = browsableCoarseIdsForPhoto(photo);
    return coarseIds
        .map((id) => memoriaCoarseIdToDefinition[id]?.label)
        .whereType<String>()
        .toList(growable: false);
  }

  bool _hasRenderableFile(PhotoEntity photo) {
    return photo.assetId.trim().isNotEmpty ||
        (photo.thumbnailBytes?.isNotEmpty ?? false) ||
        photo.path.trim().isNotEmpty;
  }

  bool _isJunkQuarantined(PhotoEntity photo) {
    return JunkPhotoFilterService.isQuarantined(photo.aiTags);
  }

  List<String> browsableTagsForPhoto(PhotoEntity photo) {
    final raw = TagSanitizer.sanitizeVisualTags(
      photo.aiTags ?? const <String>[],
    );
    final localFallback = _localSignalFallbackTags(photo, raw);
    final effectiveTags = localFallback.isNotEmpty ? localFallback : raw;
    final mapped = effectiveTags
        .where((tag) => memoriaAlbumTagLabelToCoarseId.containsKey(tag))
        .toSet()
        .toList(growable: false);
    return _collapsePureLowInformationTags(mapped);
  }

  List<String> _collapsePureLowInformationTags(List<String> tags) {
    if (tags.length <= 1) {
      return tags;
    }
    if (!tags.every(_isLowInformationTag)) {
      return tags;
    }
    final primary = tags.firstWhere(
      (tag) => tag != memoriaOtherLabel,
      orElse: () => tags.first,
    );
    return <String>[primary];
  }

  Set<String> browsableCoarseIdsForPhoto(PhotoEntity photo) {
    final coarseIds = <String>{};
    for (final tag in browsableTagsForPhoto(photo)) {
      final coarseId = memoriaAlbumTagLabelToCoarseId[tag];
      if (coarseId != null && coarseId.isNotEmpty) {
        coarseIds.add(coarseId);
      }
    }
    return coarseIds;
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

  List<String> _localSignalFallbackTags(
    PhotoEntity photo,
    List<String> rawTags,
  ) {
    if (!_hasLowInformationTags(rawTags) && !photo.isProbablyScreenshot) {
      return const <String>[];
    }

    final text = _localSignalText(photo);
    final tags = <String>[];
    if (_looksLikeReceipt(text)) {
      tags.add('收据小票');
    } else if (_looksLikeDocumentOrCoursework(photo, text)) {
      tags.add('文档');
    }

    if (_looksLikeCodeOrScreenTool(text)) {
      tags.add('屏幕代码');
    }

    if (_looksLikeFoodOrder(text)) {
      tags.add('美食');
    }

    return tags
        .where((tag) => memoriaAlbumTagLabelToCoarseId.containsKey(tag))
        .toSet()
        .toList(growable: false);
  }

  bool _hasLowInformationTags(List<String> rawTags) {
    if (rawTags.isEmpty) {
      return true;
    }
    final mapped = rawTags
        .where((tag) => memoriaAlbumTagLabelToCoarseId.containsKey(tag))
        .toList(growable: false);
    if (mapped.isEmpty) {
      return true;
    }
    return mapped.every(_isLowInformationTag);
  }

  bool _isLowInformationTag(String tag) {
    return tag == memoriaOtherLabel ||
        memoriaLegacyCoarseLabelToCoarseId.containsKey(tag) ||
        _genericLowInformationTags.contains(tag);
  }

  String _localSignalText(PhotoEntity photo) {
    return <String>[
      photo.path,
      photo.ocrText ?? '',
      ...(photo.ocrTags ?? const <String>[]),
    ].join(' ').toLowerCase();
  }

  bool _looksLikeDocumentOrCoursework(PhotoEntity photo, String text) {
    if (photo.isProbablyScreenshot) {
      return true;
    }
    return RegExp(
      r'(ppt|pdf|doc|word|excel|课件|课程|作业|试卷|题目|答案|讲义|论文|研究|表格|成绩|录取|报名|申请|通知|群聊|聊天|二维码|扫码|证件)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  bool _looksLikeCodeOrScreenTool(String text) {
    return RegExp(
      r'(代码|编程|github|terminal|console|debug|error|exception|flutter|dart|python|javascript|java|kotlin|ide|vscode)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  bool _looksLikeReceipt(String text) {
    return RegExp(
      r'(发票|账单|小票|收据|订单|付款|支付|合计|总计|¥|￥)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  bool _looksLikeFoodOrder(String text) {
    return RegExp(
      r'(外卖|菜单|菜品|美团|饿了么|奶茶|咖啡|早餐|午餐|晚餐|餐厅|饭店|火锅|烧烤)',
      caseSensitive: false,
    ).hasMatch(text);
  }
}
