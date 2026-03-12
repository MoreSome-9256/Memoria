import 'dart:math' as math;

import 'package:isar/isar.dart';

import '../models/entity/photo_entity.dart';
import 'photo_service.dart';

class ThemeClusterService {
  ThemeClusterService._internal();

  static final ThemeClusterService _instance = ThemeClusterService._internal();
  final ThemeSubclusterer _peopleSubclusterer =
      const PeopleThemeSubclusterer(
        faceEmbeddingSource: NoopFaceThemeEmbeddingSource(),
      );
  final ThemeSubclusterer _genericSubclusterer =
      const GenericThemeSubclusterer(
        imageEmbeddingSource: PersistedImageThemeEmbeddingSource(),
      );

  factory ThemeClusterService() => _instance;

  static const List<ThemeDefinition> _definitions = <ThemeDefinition>[
    ThemeDefinition(
      id: 'people',
      title: '人物时刻',
      subtitle: '把同一个阶段的人和笑脸串起来看',
      keywords: <String>[
        '人',
        '人物',
        '同学',
        '朋友',
        '家人',
        '孩子',
        '儿童',
        '男孩',
        '女孩',
        '自拍',
        '合影',
        '老师',
        '学生',
      ],
      minScore: 1.2,
    ),
    ThemeDefinition(
      id: 'food',
      title: '食物地图',
      subtitle: '看看这段时间你都吃了什么',
      keywords: <String>[
        '美食',
        '食物',
        '饭',
        '餐',
        '面',
        '火锅',
        '烧烤',
        '甜点',
        '咖啡',
        '蛋糕',
        '饮料',
        '水果',
        '菜',
      ],
      minScore: 1.0,
    ),
    ThemeDefinition(
      id: 'books',
      title: '书与课堂',
      subtitle: '书本、课件、笔记和学习场景会串成一条线',
      keywords: <String>[
        '书',
        '书本',
        '书页',
        '教材',
        '课件',
        '课堂',
        '教室',
        '笔记',
        '文档',
        '文字',
        '试卷',
        '作业',
        '黑板',
      ],
      minScore: 1.0,
    ),
    ThemeDefinition(
      id: 'cars',
      title: '车与出行',
      subtitle: '车、路、旅程和移动中的生活片段',
      keywords: <String>[
        '车',
        '汽车',
        '轿车',
        '卡车',
        '公交',
        '地铁',
        '火车',
        '高铁',
        '摩托车',
        '自行车',
        '道路',
        '公路',
        '车站',
      ],
      minScore: 1.0,
    ),
    ThemeDefinition(
      id: 'scenery',
      title: '风景与远方',
      subtitle: '山海、公园、日落和路上的风景',
      keywords: <String>[
        '风景',
        '景色',
        '自然',
        '山',
        '海',
        '湖',
        '天空',
        '公园',
        '日落',
        '夕阳',
        '草地',
        '森林',
        '花',
      ],
      minScore: 1.0,
    ),
    ThemeDefinition(
      id: 'pets',
      title: '宠物日常',
      subtitle: '猫猫狗狗和它们的日常瞬间',
      keywords: <String>['猫', '狗', '宠物', '小猫', '小狗', '鸟', '兔子'],
      minScore: 1.0,
    ),
  ];

  Future<List<ThemeCluster>> loadClusters({
    int maxThemes = 6,
    int minPhotosPerTheme = 6,
    int maxPreviewPerGroup = 18,
    int minPhotosPerSubcluster = 4,
  }) async {
    final photos = await PhotoService().isar
        .collection<PhotoEntity>()
        .where()
        .findAll();
    if (photos.isEmpty) {
      return const <ThemeCluster>[];
    }

    final clusters = <ThemeCluster>[];
    for (final definition in _definitions) {
      final matches = <ScoredThemePhoto>[];
      for (final photo in photos) {
        final score = _scorePhoto(photo, definition);
        if (score >= definition.minScore) {
          matches.add(ScoredThemePhoto(photo: photo, score: score));
        }
      }

      if (matches.length < minPhotosPerTheme) {
        continue;
      }

      matches.sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return b.photo.timestamp.compareTo(a.photo.timestamp);
      });
      final subclusterer = _resolveSubclusterer(definition);
      final subclusters = subclusterer.buildSubclusters(
        definition: definition,
        scoredPhotos: matches,
        maxPreviewPerGroup: maxPreviewPerGroup,
        minPhotosPerSubcluster: minPhotosPerSubcluster,
      );
      if (subclusters.isEmpty) {
        continue;
      }

      clusters.add(
        ThemeCluster(
          definition: definition,
          subclusters: subclusters,
        ),
      );
    }

    clusters.sort((a, b) => b.totalPhotos.compareTo(a.totalPhotos));
    return clusters.take(maxThemes).toList(growable: false);
  }

  ThemeSubclusterer _resolveSubclusterer(ThemeDefinition definition) {
    return definition.id == 'people'
        ? _peopleSubclusterer
        : _genericSubclusterer;
  }

  static List<ThemeTimelineGroup> buildTimelineGroups(
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

  double _scorePhoto(PhotoEntity photo, ThemeDefinition definition) {
    final bag = _buildTokenBag(photo);
    var score = 0.0;
    for (final keyword in definition.keywords) {
      if (bag.contains(keyword.toLowerCase())) {
        score += 1.0;
      }
    }

    if (definition.id == 'people') {
      if (photo.faceCount > 0) {
        score += 1.2;
      }
      if ((photo.joyScore ?? 0) >= 0.45) {
        score += 0.4;
      }
    }

    if (definition.id == 'books' && (photo.ocrTags?.isNotEmpty ?? false)) {
      score += 0.6;
    }

    return score;
  }

  Set<String> _buildTokenBag(PhotoEntity photo) {
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
    addText(photo.locationName);
    addText(photo.district);
    addText(photo.city);

    return tokens;
  }
}

class ThemeDefinition {
  const ThemeDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.keywords,
    required this.minScore,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<String> keywords;
  final double minScore;
}

class ThemeCluster {
  const ThemeCluster({
    required this.definition,
    required this.subclusters,
  });

  final ThemeDefinition definition;
  final List<ThemeSubcluster> subclusters;

  int get totalPhotos => subclusters.fold<int>(0, (sum, item) => sum + item.totalPhotos);

  List<PhotoEntity> get coverPhotos => subclusters
      .expand((item) => item.coverPhotos)
      .take(4)
      .toList(growable: false);

  int get totalTimelineGroups => subclusters.fold<int>(0, (sum, item) => sum + item.groups.length);

  ThemeSubcluster get primarySubcluster => subclusters.first;
}

class ThemeSubcluster {
  const ThemeSubcluster({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.algorithm,
    required this.cohesion,
    required this.totalPhotos,
    required this.coverPhotos,
    required this.groups,
  });

  final String id;
  final String title;
  final String subtitle;
  final ThemeSubclusterAlgorithm algorithm;
  final ThemeSubclusterCohesion? cohesion;
  final int totalPhotos;
  final List<PhotoEntity> coverPhotos;
  final List<ThemeTimelineGroup> groups;

  ThemeSubcluster copyWith({
    String? id,
    String? title,
    String? subtitle,
    ThemeSubclusterAlgorithm? algorithm,
    ThemeSubclusterCohesion? cohesion,
    int? totalPhotos,
    List<PhotoEntity>? coverPhotos,
    List<ThemeTimelineGroup>? groups,
  }) {
    return ThemeSubcluster(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      algorithm: algorithm ?? this.algorithm,
      cohesion: cohesion ?? this.cohesion,
      totalPhotos: totalPhotos ?? this.totalPhotos,
      coverPhotos: coverPhotos ?? this.coverPhotos,
      groups: groups ?? this.groups,
    );
  }
}

class ThemeSubclusterCohesion {
  const ThemeSubclusterCohesion({
    required this.meanDistance,
    required this.sampleCount,
  });

  final double meanDistance;
  final int sampleCount;

  String get levelLabel {
    if (meanDistance <= 0.08) {
      return '精选';
    }
    if (meanDistance <= 0.14) {
      return '中等';
    }
    return '松散';
  }

  String get summaryLabel => '$levelLabel · 均距 ${meanDistance.toStringAsFixed(3)}';

  String get detailLabel {
    if (meanDistance <= 0.08) {
      return '簇内非常紧密，适合折叠成精选簇';
    }
    if (meanDistance <= 0.14) {
      return '簇内有一定变化，适合保留分组浏览';
    }
    return '簇内跨度较大，更适合平铺展示';
  }
}

class ThemeSubclusterAlgorithm {
  const ThemeSubclusterAlgorithm({
    required this.currentLabel,
    required this.nextLabel,
  });

  final String currentLabel;
  final String nextLabel;
}

class ScoredThemePhoto {
  const ScoredThemePhoto({required this.photo, required this.score});

  final PhotoEntity photo;
  final double score;

  ScoredThemePhoto copyWith({
    PhotoEntity? photo,
    double? score,
  }) {
    return ScoredThemePhoto(
      photo: photo ?? this.photo,
      score: score ?? this.score,
    );
  }
}

class ThemeTimelineGroup {
  const ThemeTimelineGroup({
    required this.key,
    required this.title,
    required this.monthStart,
    required this.photos,
    required this.totalPhotos,
  });

  final String key;
  final String title;
  final DateTime monthStart;
  final List<PhotoEntity> photos;
  final int totalPhotos;
}

abstract class ThemeSubclusterer {
  const ThemeSubclusterer();

  List<ThemeSubcluster> buildSubclusters({
    required ThemeDefinition definition,
    required List<ScoredThemePhoto> scoredPhotos,
    required int maxPreviewPerGroup,
    required int minPhotosPerSubcluster,
  });
}

abstract class ThemeEmbeddingSource {
  const ThemeEmbeddingSource();

  bool get isReady;
  String get sourceName;

  List<double>? readEmbedding(PhotoEntity photo);

  bool hasEmbedding(PhotoEntity photo) {
    final embedding = readEmbedding(photo);
    return embedding != null && embedding.isNotEmpty;
  }
}

abstract class FaceThemeEmbeddingSource extends ThemeEmbeddingSource {
  const FaceThemeEmbeddingSource();
}

abstract class ImageThemeEmbeddingSource extends ThemeEmbeddingSource {
  const ImageThemeEmbeddingSource();
}

class NoopFaceThemeEmbeddingSource extends FaceThemeEmbeddingSource {
  const NoopFaceThemeEmbeddingSource();

  @override
  bool get isReady => false;

  @override
  String get sourceName => 'face-embedding:not-ready';

  @override
  List<double>? readEmbedding(PhotoEntity photo) => null;
}

class NoopImageThemeEmbeddingSource extends ImageThemeEmbeddingSource {
  const NoopImageThemeEmbeddingSource();

  @override
  bool get isReady => false;

  @override
  String get sourceName => 'image-embedding:not-ready';

  @override
  List<double>? readEmbedding(PhotoEntity photo) => null;
}

class PersistedImageThemeEmbeddingSource extends ImageThemeEmbeddingSource {
  const PersistedImageThemeEmbeddingSource();

  @override
  bool get isReady => true;

  @override
  String get sourceName => 'Isar.imageEmbedding';

  @override
  List<double>? readEmbedding(PhotoEntity photo) => photo.imageEmbedding;
}

class PeopleThemeSubclusterer extends ThemeSubclusterer {
  const PeopleThemeSubclusterer({required this.faceEmbeddingSource});

  final FaceThemeEmbeddingSource faceEmbeddingSource;

  @override
  List<ThemeSubcluster> buildSubclusters({
    required ThemeDefinition definition,
    required List<ScoredThemePhoto> scoredPhotos,
    required int maxPreviewPerGroup,
    required int minPhotosPerSubcluster,
  }) {
    final base = const HeuristicThemeSubclusterer().buildSubclusters(
      definition: definition,
      scoredPhotos: scoredPhotos,
      maxPreviewPerGroup: maxPreviewPerGroup,
      minPhotosPerSubcluster: minPhotosPerSubcluster,
    );

    final algorithm = faceEmbeddingSource.isReady
        ? ThemeSubclusterAlgorithm(
            currentLabel: '当前：${faceEmbeddingSource.sourceName}',
            nextLabel: '后续：DBSCAN / HDBSCAN 细分身份簇',
          )
        : const ThemeSubclusterAlgorithm(
            currentLabel: '当前：规则分桶 + faceCount',
            nextLabel: '未来：人脸 Embedding + DBSCAN',
          );

    return base
        .map((item) => item.copyWith(algorithm: algorithm))
        .toList(growable: false);
  }
}

class GenericThemeSubclusterer extends ThemeSubclusterer {
  const GenericThemeSubclusterer({required this.imageEmbeddingSource});

  final ImageThemeEmbeddingSource imageEmbeddingSource;

  @override
  List<ThemeSubcluster> buildSubclusters({
    required ThemeDefinition definition,
    required List<ScoredThemePhoto> scoredPhotos,
    required int maxPreviewPerGroup,
    required int minPhotosPerSubcluster,
  }) {
    final embeddingReadyCount = scoredPhotos
        .where((item) => imageEmbeddingSource.hasEmbedding(item.photo))
        .length;
    final dbscanResult = _clusterWithDbscan(
      definition: definition,
      scoredPhotos: scoredPhotos,
      minPhotosPerSubcluster: minPhotosPerSubcluster,
    );

    final algorithm = imageEmbeddingSource.isReady && embeddingReadyCount > 0
        ? ThemeSubclusterAlgorithm(
            currentLabel:
                '当前：${imageEmbeddingSource.sourceName} + DBSCAN（$embeddingReadyCount/${scoredPhotos.length} 已落库，${dbscanResult.clusters.length} 簇）',
            nextLabel: '后续：簇内 HDBSCAN / 自动命名 / 原型图提炼',
          )
        : const ThemeSubclusterAlgorithm(
            currentLabel: '当前：标签/OCR 规则分桶',
            nextLabel: '未来：图像 Embedding + DBSCAN',
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

    if (dbscanResult.leftovers.isNotEmpty) {
      final fallback = const HeuristicThemeSubclusterer().buildSubclusters(
        definition: definition,
        scoredPhotos: dbscanResult.leftovers,
        maxPreviewPerGroup: maxPreviewPerGroup,
        minPhotosPerSubcluster: minPhotosPerSubcluster,
      );
      subclusters.addAll(
        fallback.map((item) => item.copyWith(algorithm: algorithm)),
      );
    }

    if (subclusters.isEmpty) {
      final fallback = const HeuristicThemeSubclusterer().buildSubclusters(
        definition: definition,
        scoredPhotos: scoredPhotos,
        maxPreviewPerGroup: maxPreviewPerGroup,
        minPhotosPerSubcluster: minPhotosPerSubcluster,
      );
      return fallback
          .map((item) => item.copyWith(algorithm: algorithm))
          .toList(growable: false);
    }

    subclusters.sort((a, b) => b.totalPhotos.compareTo(a.totalPhotos));

    return subclusters;
  }

  _DbscanClusterResult _clusterWithDbscan({
    required ThemeDefinition definition,
    required List<ScoredThemePhoto> scoredPhotos,
    required int minPhotosPerSubcluster,
  }) {
    if (!imageEmbeddingSource.isReady || scoredPhotos.length < 2) {
      return _DbscanClusterResult(
        clusters: const <List<ScoredThemePhoto>>[],
        leftovers: scoredPhotos,
      );
    }

    final embedded = <_EmbeddedScoredThemePhoto>[];
    final noEmbedding = <ScoredThemePhoto>[];
    var dimension = 0;
    for (final item in scoredPhotos) {
      final embedding = imageEmbeddingSource.readEmbedding(item.photo);
      if (embedding == null || embedding.isEmpty) {
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
      return _DbscanClusterResult(
        clusters: const <List<ScoredThemePhoto>>[],
        leftovers: scoredPhotos,
      );
    }

    final epsilon = _epsilonForTheme(definition.id);
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

    return _DbscanClusterResult(clusters: clusters, leftovers: leftovers);
  }

  void _expandCluster({
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

  List<int> _regionQuery(
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
      groups: ThemeClusterService.buildTimelineGroups(
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
      final slides = photos.where(HeuristicThemeSubclusterer._looksLikeSlidePhoto).length;
      final docs = photos.where(HeuristicThemeSubclusterer._looksLikeDocumentPhoto).length;
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
      final drinks = photos.where(HeuristicThemeSubclusterer._looksLikeDrinkPhoto).length;
      final meals = photos.where(HeuristicThemeSubclusterer._looksLikeMealPhoto).length;
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

  double _cosineDistance(List<double> left, List<double> right) {
    final similarity = _cosineSimilarity(left, right);
    return 1 - similarity;
  }

  ThemeSubclusterCohesion? _computeCohesion(
    List<ScoredThemePhoto> scoredPhotos,
  ) {
    final embeddings = <List<double>>[];
    var dimension = 0;
    for (final item in scoredPhotos) {
      final embedding = imageEmbeddingSource.readEmbedding(item.photo);
      if (embedding == null || embedding.isEmpty) {
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
        totalDistance += _cosineDistance(embeddings[i], embeddings[j]);
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

  static const int _dbscanUnassigned = -2;
  static const int _dbscanNoise = -1;
}

class _EmbeddedScoredThemePhoto {
  const _EmbeddedScoredThemePhoto({
    required this.item,
    required this.embedding,
  });

  final ScoredThemePhoto item;
  final List<double> embedding;
}

class _DbscanClusterResult {
  const _DbscanClusterResult({
    required this.clusters,
    required this.leftovers,
  });

  final List<List<ScoredThemePhoto>> clusters;
  final List<ScoredThemePhoto> leftovers;
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

      remaining.removeWhere((candidate) => matched.any((item) => identical(item.photo, candidate.photo)));
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
      groups: ThemeClusterService.buildTimelineGroups(
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
            matcher: _looksLikeSlidePhoto,
          ),
          _SubclusterRule(
            id: 'notes',
            title: '笔记文档',
            subtitle: '文字密集、试卷和文档资料',
            matcher: _looksLikeDocumentPhoto,
          ),
        ],
        'food': <_SubclusterRule>[
          _SubclusterRule(
            id: 'drinks',
            title: '饮料甜点',
            subtitle: '咖啡、饮品和甜口瞬间',
            matcher: _looksLikeDrinkPhoto,
          ),
          _SubclusterRule(
            id: 'meals',
            title: '正餐热食',
            subtitle: '火锅、烧烤、面饭与聚餐',
            matcher: _looksLikeMealPhoto,
          ),
        ],
      };

  static bool _isSoloPeoplePhoto(PhotoEntity photo) => photo.faceCount == 1;

  static bool _isGroupPeoplePhoto(PhotoEntity photo) => photo.faceCount >= 2;

  static bool _looksLikeSlidePhoto(PhotoEntity photo) {
    final bag = _tokenBag(photo);
    return bag.any(<String>{'课件', 'ppt', '讲座', '投影', '黑板', '教室'}.contains);
  }

  static bool _looksLikeDocumentPhoto(PhotoEntity photo) {
    if (photo.ocrTags?.isNotEmpty ?? false) {
      return true;
    }
    final bag = _tokenBag(photo);
    return bag.any(<String>{'笔记', '文档', '试卷', '作业', '文件', '手抄本', '文字'}.contains);
  }

  static bool _looksLikeDrinkPhoto(PhotoEntity photo) {
    final bag = _tokenBag(photo);
    return bag.any(<String>{'咖啡', '饮料', '奶茶', '果汁', '甜点', '蛋糕', '茶'}.contains);
  }

  static bool _looksLikeMealPhoto(PhotoEntity photo) {
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