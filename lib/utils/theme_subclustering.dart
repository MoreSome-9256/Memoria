import 'dart:math' as math;

import '../models/entity/photo_entity.dart';
import '../models/theme_cluster_models.dart';
import 'dbscan_algorithm.dart';

abstract class ThemeSubclusterer {
  const ThemeSubclusterer();

  List<ThemeSubcluster> buildSubclusters({
    required ThemeDefinition definition,
    required List<ScoredThemePhoto> scoredPhotos,
    required int maxPreviewPerGroup,
    required int minPhotosPerSubcluster,
    required bool pureEmbeddingOnly,
  });
}

class PeopleThemeSubclusterer extends ThemeSubclusterer {
  const PeopleThemeSubclusterer();

  @override
  List<ThemeSubcluster> buildSubclusters({
    required ThemeDefinition definition,
    required List<ScoredThemePhoto> scoredPhotos,
    required int maxPreviewPerGroup,
    required int minPhotosPerSubcluster,
    required bool pureEmbeddingOnly,
  }) {
    if (pureEmbeddingOnly) {
      return const GenericThemeSubclusterer().buildSubclusters(
        definition: definition,
        scoredPhotos: scoredPhotos,
        maxPreviewPerGroup: maxPreviewPerGroup,
        minPhotosPerSubcluster: minPhotosPerSubcluster,
        pureEmbeddingOnly: true,
      );
    }

    final base = const HeuristicThemeSubclusterer().buildSubclusters(
      definition: definition,
      scoredPhotos: scoredPhotos,
      maxPreviewPerGroup: maxPreviewPerGroup,
      minPhotosPerSubcluster: minPhotosPerSubcluster,
      pureEmbeddingOnly: false,
    );

    const algorithm = ThemeSubclusterAlgorithm(
      currentLabel: '当前：MobileCLIP2(512) 主题召回 + 人脸规则细分',
      nextLabel: '后续：人脸向量/HDBSCAN 细分身份簇',
    );

    return base
        .map((item) => item.copyWith(algorithm: algorithm))
        .toList(growable: false);
  }
}

class GenericThemeSubclusterer extends ThemeSubclusterer {
  const GenericThemeSubclusterer();

  static const int _embeddingDim = 512;

  @override
  List<ThemeSubcluster> buildSubclusters({
    required ThemeDefinition definition,
    required List<ScoredThemePhoto> scoredPhotos,
    required int maxPreviewPerGroup,
    required int minPhotosPerSubcluster,
    required bool pureEmbeddingOnly,
  }) {
    final dbscanResult = DbscanAlgorithm.clusterScoredPhotos(
      scoredPhotos: scoredPhotos,
      minPhotosPerSubcluster: minPhotosPerSubcluster,
      epsilon: _epsilonForTheme(definition.id),
    );

    final embeddingReadyCount = scoredPhotos
        .where((item) => item.embedding.length == _embeddingDim)
        .length;
    final algorithm = pureEmbeddingOnly
        ? ThemeSubclusterAlgorithm(
            currentLabel:
                '当前：纯 MobileCLIP2(512) + DBSCAN（$embeddingReadyCount/${scoredPhotos.length}，${dbscanResult.clusters.length} 簇）',
            nextLabel: '后续：纯向量 HDBSCAN / 自动命名 / 原型图提炼',
          )
        : ThemeSubclusterAlgorithm(
            currentLabel:
                '当前：MobileCLIP2(512) + DBSCAN（$embeddingReadyCount/${scoredPhotos.length}，${dbscanResult.clusters.length} 簇）',
            nextLabel: '后续：簇内 HDBSCAN / 自动命名 / 原型图提炼',
          );

    final subclusters = <ThemeSubcluster>[];
    for (var index = 0; index < dbscanResult.clusters.length; index++) {
      final clusterPhotos = dbscanResult.clusters[index];
      final descriptor = _describeDbscanCluster(
        definition: definition,
        clusterIndex: index,
        clusterPhotos: clusterPhotos,
      );
      subclusters.add(
        _buildDbscanSubcluster(
          id: '${definition.id}_dbscan_$index',
          title: descriptor.title,
          subtitle: descriptor.subtitle,
          algorithm: algorithm,
          scoredPhotos: clusterPhotos,
          maxPreviewPerGroup: maxPreviewPerGroup,
        ),
      );
    }

    if (dbscanResult.leftovers.isNotEmpty && pureEmbeddingOnly) {
      subclusters.add(
        _buildDbscanSubcluster(
          id: '${definition.id}_dbscan_leftovers',
          title: '向量边界样本',
          subtitle: '仅基于向量距离，未形成稳定 DBSCAN 簇',
          algorithm: algorithm,
          scoredPhotos: dbscanResult.leftovers,
          maxPreviewPerGroup: maxPreviewPerGroup,
        ),
      );
    }

    if (dbscanResult.leftovers.isNotEmpty && !pureEmbeddingOnly) {
      final fallback = const HeuristicThemeSubclusterer().buildSubclusters(
        definition: definition,
        scoredPhotos: dbscanResult.leftovers,
        maxPreviewPerGroup: maxPreviewPerGroup,
        minPhotosPerSubcluster: minPhotosPerSubcluster,
        pureEmbeddingOnly: false,
      );
      subclusters.addAll(
        fallback.map((item) => item.copyWith(algorithm: algorithm)),
      );
    }

    if (subclusters.isEmpty) {
      if (pureEmbeddingOnly) {
        return <ThemeSubcluster>[
          _buildDbscanSubcluster(
            id: '${definition.id}_vector_all',
            title: '纯向量簇',
            subtitle: '仅依赖 MobileCLIP2 512 维向量的主题集合',
            algorithm: algorithm,
            scoredPhotos: scoredPhotos,
            maxPreviewPerGroup: maxPreviewPerGroup,
          ),
        ];
      }

      final fallback = const HeuristicThemeSubclusterer().buildSubclusters(
        definition: definition,
        scoredPhotos: scoredPhotos,
        maxPreviewPerGroup: maxPreviewPerGroup,
        minPhotosPerSubcluster: minPhotosPerSubcluster,
        pureEmbeddingOnly: false,
      );
      return fallback
          .map((item) => item.copyWith(algorithm: algorithm))
          .toList(growable: false);
    }

    subclusters.sort((a, b) => b.totalPhotos.compareTo(a.totalPhotos));

    return subclusters;
  }

  ThemeSubcluster _buildDbscanSubcluster({
    required String id,
    required String title,
    required String subtitle,
    required ThemeSubclusterAlgorithm algorithm,
    required List<ScoredThemePhoto> scoredPhotos,
    required int maxPreviewPerGroup,
  }) {
    final sorted = List<ScoredThemePhoto>.from(scoredPhotos)
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return b.photo.timestamp.compareTo(a.photo.timestamp);
      });
    final photos = sorted.map((item) => item.photo).toList(growable: false);

    return ThemeSubcluster(
      id: id,
      title: title,
      subtitle: subtitle,
      algorithm: algorithm,
      cohesion: _computeCohesion(scoredPhotos),
      totalPhotos: photos.length,
      coverPhotos: photos.take(4).toList(growable: false),
      groups: buildTimelineGroups(
        photos,
        maxPreviewPerGroup: maxPreviewPerGroup,
      ),
    );
  }

  _ClusterDescriptor _describeDbscanCluster({
    required ThemeDefinition definition,
    required int clusterIndex,
    required List<ScoredThemePhoto> clusterPhotos,
  }) {
    final photos = clusterPhotos.map((item) => item.photo).toList(growable: false);
    if (definition.id == 'books') {
      final slides = photos.where(HeuristicThemeSubclusterer.looksLikeSlidePhoto).length;
      final docs = photos.where(HeuristicThemeSubclusterer.looksLikeDocumentPhoto).length;
      if (slides >= docs && slides >= 2) {
        return const _ClusterDescriptor(
          title: '投影课件簇',
          subtitle: 'DBSCAN 聚到一起的课堂投影与讲解画面',
        );
      }
      if (docs >= 2) {
        return const _ClusterDescriptor(
          title: '笔记文档簇',
          subtitle: 'DBSCAN 聚到一起的文档、试卷与笔记资料',
        );
      }
    }

    if (definition.id == 'food') {
      final drinks = photos.where(HeuristicThemeSubclusterer.looksLikeDrinkPhoto).length;
      final meals = photos.where(HeuristicThemeSubclusterer.looksLikeMealPhoto).length;
      if (drinks >= meals && drinks >= 2) {
        return const _ClusterDescriptor(
          title: '饮料甜点簇',
          subtitle: 'DBSCAN 聚到一起的饮品、甜点与咖啡瞬间',
        );
      }
      if (meals >= 2) {
        return const _ClusterDescriptor(
          title: '正餐热食簇',
          subtitle: 'DBSCAN 聚到一起的火锅、烧烤与正餐场景',
        );
      }
    }

    final preferredToken = _pickRepresentativeToken(photos);
    if (preferredToken != null) {
      return _ClusterDescriptor(
        title: '$preferredToken 簇',
        subtitle: 'DBSCAN 聚到一起的相似视觉主题',
      );
    }

    return _ClusterDescriptor(
      title: '语义簇 ${clusterIndex + 1}',
      subtitle: 'DBSCAN 聚到一起的相似视觉内容',
    );
  }

  String? _pickRepresentativeToken(List<PhotoEntity> photos) {
    final counts = <String, int>{};

    void addToken(String token) {
      final normalized = token.trim().toLowerCase();
      if (normalized.isEmpty || normalized.length <= 1) {
        return;
      }
      if (_genericStopTokens.contains(normalized)) {
        return;
      }
      counts.update(normalized, (value) => value + 1, ifAbsent: () => 1);
    }

    for (final photo in photos) {
      for (final tag in photo.aiTags ?? const <String>[]) {
        addToken(tag);
      }
      for (final tag in photo.ocrTags ?? const <String>[]) {
        addToken(tag);
      }
    }

    if (counts.isEmpty) {
      return null;
    }

    final sorted = counts.entries.toList(growable: false)
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        if (countCompare != 0) {
          return countCompare;
        }
        return a.key.length.compareTo(b.key.length);
      });
    return sorted.first.key;
  }

  double _epsilonForTheme(String themeId) {
    switch (themeId) {
      case 'scenery':
        return 0.16;
      case 'food':
      case 'books':
      case 'pets':
        return 0.14;
      case 'cars':
        return 0.15;
      default:
        return 0.15;
    }
  }

  ThemeSubclusterCohesion? _computeCohesion(
    List<ScoredThemePhoto> scoredPhotos,
  ) {
    final embeddings = <List<double>>[];
    var dimension = 0;
    for (final item in scoredPhotos) {
      final embedding = item.embedding;
      if (embedding.isEmpty) {
        continue;
      }
      if (dimension == 0) {
        dimension = embedding.length;
      }
      if (embedding.length != dimension) {
        continue;
      }
      embeddings.add(embedding);
    }

    if (embeddings.length < 2) {
      return null;
    }

    var pairCount = 0;
    var totalDistance = 0.0;
    for (var i = 0; i < embeddings.length; i++) {
      for (var j = i + 1; j < embeddings.length; j++) {
        totalDistance += 1 - _cosineSimilarity(embeddings[i], embeddings[j]);
        pairCount++;
      }
    }

    if (pairCount == 0) {
      return null;
    }

    return ThemeSubclusterCohesion(
      meanDistance: totalDistance / pairCount,
      sampleCount: embeddings.length,
    );
  }

  double _cosineSimilarity(List<double> left, List<double> right) {
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

  static const Set<String> _genericStopTokens = <String>{
    '风景',
    '景色',
    '自然',
    '食物',
    '美食',
    '餐',
    '饭',
    '书',
    '书本',
    '文字',
    '课堂',
    '车',
    '汽车',
    '道路',
    '宠物',
    '猫',
    '狗',
  };
}

class _ClusterDescriptor {
  const _ClusterDescriptor({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;
}

class HeuristicThemeSubclusterer extends ThemeSubclusterer {
  const HeuristicThemeSubclusterer();

  @override
  List<ThemeSubcluster> buildSubclusters({
    required ThemeDefinition definition,
    required List<ScoredThemePhoto> scoredPhotos,
    required int maxPreviewPerGroup,
    required int minPhotosPerSubcluster,
    required bool pureEmbeddingOnly,
  }) {
    final rules = _rulesByTheme[definition.id] ?? const <_SubclusterRule>[];
    if (rules.isEmpty) {
      return <ThemeSubcluster>[
        _buildSingleSubcluster(
          id: '${definition.id}_all',
          title: '全部',
          subtitle: '当前主题下的全部照片',
          algorithm: _algorithmForTheme(definition.id),
          scoredPhotos: scoredPhotos,
          maxPreviewPerGroup: maxPreviewPerGroup,
        ),
      ];
    }

    final remaining = List<ScoredThemePhoto>.from(scoredPhotos);
    final subclusters = <ThemeSubcluster>[];

    for (final rule in rules) {
      final matched = remaining.where((item) => rule.matcher(item.photo)).toList(growable: false);
      if (matched.length < minPhotosPerSubcluster) {
        continue;
      }

      remaining.removeWhere((candidate) =>
          matched.any((item) => identical(item.photo, candidate.photo)));
      subclusters.add(
        _buildSingleSubcluster(
          id: '${definition.id}_${rule.id}',
          title: rule.title,
          subtitle: rule.subtitle,
          algorithm: _algorithmForTheme(definition.id),
          scoredPhotos: matched,
          maxPreviewPerGroup: maxPreviewPerGroup,
        ),
      );
    }

    if (remaining.length >= minPhotosPerSubcluster) {
      subclusters.add(
        _buildSingleSubcluster(
          id: '${definition.id}_others',
          title: '其他',
          subtitle: '暂时未归入更细子簇的照片',
          algorithm: _algorithmForTheme(definition.id),
          scoredPhotos: remaining,
          maxPreviewPerGroup: maxPreviewPerGroup,
        ),
      );
    }

    if (subclusters.isEmpty) {
      return <ThemeSubcluster>[
        _buildSingleSubcluster(
          id: '${definition.id}_all',
          title: '全部',
          subtitle: '当前主题下的全部照片',
          algorithm: _algorithmForTheme(definition.id),
          scoredPhotos: scoredPhotos,
          maxPreviewPerGroup: maxPreviewPerGroup,
        ),
      ];
    }

    subclusters.sort((a, b) => b.totalPhotos.compareTo(a.totalPhotos));
    return subclusters;
  }

  ThemeSubcluster _buildSingleSubcluster({
    required String id,
    required String title,
    required String subtitle,
    required ThemeSubclusterAlgorithm algorithm,
    required List<ScoredThemePhoto> scoredPhotos,
    required int maxPreviewPerGroup,
  }) {
    final sorted = List<ScoredThemePhoto>.from(scoredPhotos)
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return b.photo.timestamp.compareTo(a.photo.timestamp);
      });
    final photos = sorted.map((item) => item.photo).toList(growable: false);

    return ThemeSubcluster(
      id: id,
      title: title,
      subtitle: subtitle,
      algorithm: algorithm,
      cohesion: null,
      totalPhotos: photos.length,
      coverPhotos: photos.take(4).toList(growable: false),
      groups: buildTimelineGroups(
        photos,
        maxPreviewPerGroup: maxPreviewPerGroup,
      ),
    );
  }

  ThemeSubclusterAlgorithm _algorithmForTheme(String themeId) {
    if (themeId == 'people') {
      return const ThemeSubclusterAlgorithm(
        currentLabel: '当前：规则分桶 + faceCount',
        nextLabel: '未来：人脸 Embedding + DBSCAN',
      );
    }

    return const ThemeSubclusterAlgorithm(
      currentLabel: '当前：标签/OCR 规则分桶',
      nextLabel: '未来：图像 Embedding + DBSCAN',
    );
  }

  static final Map<String, List<_SubclusterRule>> _rulesByTheme =
      <String, List<_SubclusterRule>>{
    'people': <_SubclusterRule>[
      _SubclusterRule(
        id: 'group',
        title: '合影',
        subtitle: '更接近未来的人物关系簇入口',
        matcher: _isGroupPeoplePhoto,
      ),
      _SubclusterRule(
        id: 'solo',
        title: '单人',
        subtitle: '未来可继续细分到具体人物身份',
        matcher: _isSoloPeoplePhoto,
      ),
    ],
    'books': <_SubclusterRule>[
      _SubclusterRule(
        id: 'slides',
        title: '投影课件',
        subtitle: 'PPT、投影和课堂讲解画面',
        matcher: looksLikeSlidePhoto,
      ),
      _SubclusterRule(
        id: 'notes',
        title: '笔记文档',
        subtitle: '文字密集、试卷和文档资料',
        matcher: looksLikeDocumentPhoto,
      ),
    ],
    'food': <_SubclusterRule>[
      _SubclusterRule(
        id: 'drinks',
        title: '饮料甜点',
        subtitle: '咖啡、饮品和甜口瞬间',
        matcher: looksLikeDrinkPhoto,
      ),
      _SubclusterRule(
        id: 'meals',
        title: '正餐热食',
        subtitle: '火锅、烧烤、面饭与聚餐',
        matcher: looksLikeMealPhoto,
      ),
    ],
  };

  static bool _isSoloPeoplePhoto(PhotoEntity photo) => photo.faceCount == 1;

  static bool _isGroupPeoplePhoto(PhotoEntity photo) => photo.faceCount >= 2;

  static bool looksLikeSlidePhoto(PhotoEntity photo) {
    final bag = _tokenBag(photo);
    return bag.any(<String>{'课件', 'ppt', '讲座', '投影', '黑板', '教室'}.contains);
  }

  static bool looksLikeDocumentPhoto(PhotoEntity photo) {
    if (photo.ocrTags?.isNotEmpty ?? false) {
      return true;
    }
    final bag = _tokenBag(photo);
    return bag.any(
      <String>{'笔记', '文档', '试卷', '作业', '文件', '手抄本', '文字'}.contains,
    );
  }

  static bool looksLikeDrinkPhoto(PhotoEntity photo) {
    final bag = _tokenBag(photo);
    return bag.any(<String>{'咖啡', '饮料', '奶茶', '果汁', '甜点', '蛋糕', '茶'}.contains);
  }

  static bool looksLikeMealPhoto(PhotoEntity photo) {
    final bag = _tokenBag(photo);
    return bag.any(<String>{'火锅', '烧烤', '美食', '饭', '面', '菜', '食物', '餐'}.contains);
  }

  static Set<String> _tokenBag(PhotoEntity photo) {
    final tokens = <String>{};

    void addText(String? text) {
      final normalized = text?.trim().toLowerCase();
      if (normalized == null || normalized.isEmpty) {
        return;
      }
      tokens.add(normalized);
      for (final piece in normalized.split(RegExp(r'[\s,，。；：、|/\\()\[\]{}_-]+'))) {
        final value = piece.trim();
        if (value.isNotEmpty) {
          tokens.add(value);
        }
      }
    }

    for (final tag in photo.aiTags ?? const <String>[]) {
      addText(tag);
    }
    for (final tag in photo.ocrTags ?? const <String>[]) {
      addText(tag);
    }
    addText(photo.ocrText);
    return tokens;
  }
}

class _SubclusterRule {
  const _SubclusterRule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.matcher,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool Function(PhotoEntity photo) matcher;
}

List<ThemeTimelineGroup> buildTimelineGroups(
  List<PhotoEntity> photos, {
  required int maxPreviewPerGroup,
}) {
  final buckets = <String, List<PhotoEntity>>{};
  for (final photo in photos) {
    final date = DateTime.fromMillisecondsSinceEpoch(photo.timestamp);
    final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    buckets.putIfAbsent(key, () => <PhotoEntity>[]).add(photo);
  }

  final groups = buckets.entries.map((entry) {
    final parts = entry.key.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final groupPhotos = entry.value
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return ThemeTimelineGroup(
      key: entry.key,
      title: '$year年$month月',
      monthStart: DateTime(year, month),
      photos: groupPhotos.take(maxPreviewPerGroup).toList(growable: false),
      totalPhotos: groupPhotos.length,
    );
  }).toList(growable: false)
    ..sort((a, b) => b.monthStart.compareTo(a.monthStart));

  return groups;
}
