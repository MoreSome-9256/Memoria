import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/entity/photo_entity.dart';
import '../models/theme_cluster_models.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../utils/ocr_policy.dart';
import '../utils/theme_subclustering.dart';
import 'mobileclip_embedding_service.dart';
import 'semantic_matching_service.dart';
import 'theme_cluster_compute_helpers.dart';

typedef ThemePhotosLoader = Future<List<PhotoEntity>> Function();
typedef ThemeEmbeddingPreparer =
    Future<Map<int, List<double>>> Function(List<PhotoEntity> photos);
typedef ThemePrototypeBuilder = Future<Map<String, List<double>>> Function();

enum ThemeClusteringStage {
  idle,
  loadingPhotos,
  preparingEmbeddings,
  buildingPrototypes,
  scoringThemes,
  done,
}

class ThemeClusteringProgress {
  const ThemeClusteringProgress({
    required this.stage,
    required this.processed,
    required this.total,
    this.newEmbeddings = 0,
    this.cachedEmbeddings = 0,
    this.themeProcessed = 0,
    this.themeTotal = 0,
    this.message,
  });

  final ThemeClusteringStage stage;
  final int processed;
  final int total;
  final int newEmbeddings;
  final int cachedEmbeddings;
  final int themeProcessed;
  final int themeTotal;
  final String? message;

  double get ratio {
    if (total <= 0) {
      return 0;
    }
    final value = processed / total;
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }

  static const ThemeClusteringProgress idle = ThemeClusteringProgress(
    stage: ThemeClusteringStage.idle,
    processed: 0,
    total: 0,
  );
}

class ThemeClusterService {
  ThemeClusterService._internal({
    ThemeSubclusterer? peopleSubclusterer,
    ThemeSubclusterer? genericSubclusterer,
    SemanticMatchingService? semanticService,
    MobileClipEmbeddingService? embeddingService,
    List<ThemeDefinition>? definitions,
    ThemePhotosLoader? photosLoader,
    ThemeEmbeddingPreparer? embeddingPreparer,
    ThemePrototypeBuilder? prototypeBuilder,
  }) : _peopleSubclusterer =
           peopleSubclusterer ?? const PeopleThemeSubclusterer(),
       _genericSubclusterer =
           genericSubclusterer ?? const GenericThemeSubclusterer(),
       _semanticService = semanticService ?? SemanticMatchingService(),
       _embeddingService = embeddingService ?? MobileClipEmbeddingService(),
       _definitions = definitions ?? _defaultDefinitions,
       _photosLoader = photosLoader,
       _embeddingPreparer = embeddingPreparer,
       _prototypeBuilder = prototypeBuilder;

  static final ThemeClusterService _instance = ThemeClusterService._internal();
  final ThemeSubclusterer _peopleSubclusterer;
  final ThemeSubclusterer _genericSubclusterer;
  final SemanticMatchingService _semanticService;
  final MobileClipEmbeddingService _embeddingService;
  final List<ThemeDefinition> _definitions;
  final ThemePhotosLoader? _photosLoader;
  final ThemeEmbeddingPreparer? _embeddingPreparer;
  final ThemePrototypeBuilder? _prototypeBuilder;
  final ValueNotifier<ThemeClusteringProgress> _progressNotifier =
      ValueNotifier<ThemeClusteringProgress>(ThemeClusteringProgress.idle);

  factory ThemeClusterService() => _instance;
  factory ThemeClusterService.forTest({
    ThemeSubclusterer? peopleSubclusterer,
    ThemeSubclusterer? genericSubclusterer,
    List<ThemeDefinition>? definitions,
    ThemePhotosLoader? photosLoader,
    ThemeEmbeddingPreparer? embeddingPreparer,
    ThemePrototypeBuilder? prototypeBuilder,
  }) {
    return ThemeClusterService._internal(
      peopleSubclusterer: peopleSubclusterer,
      genericSubclusterer: genericSubclusterer,
      definitions: definitions,
      photosLoader: photosLoader,
      embeddingPreparer: embeddingPreparer,
      prototypeBuilder: prototypeBuilder,
    );
  }

  static const int _embeddingDim =
      MobileClipEmbeddingService.expectedEmbeddingDim;
  static const int _defaultMaxNewEmbeddingsPerRun = 400;
  static const int _defaultMaxPhotosToScan = 2400;
  static const int _yieldEveryEmbeddingItems = 24;
  static const int _yieldEveryScoringItems = 80;
  static const Duration _embeddingTimeout = Duration(seconds: 10);
  static const Duration _prototypeWarmUpTimeout = Duration(seconds: 15);
  static const Duration _prototypePromptTimeout = Duration(seconds: 8);

  ValueListenable<ThemeClusteringProgress> get progressListenable =>
      _progressNotifier;

  static const List<ThemeDefinition> _defaultDefinitions = <ThemeDefinition>[
    ThemeDefinition(
      id: 'people',
      title: '人物时刻',
      subtitle: '把同一个阶段的人和笑脸串起来看',
      prototypePrompts: <String>[
        'a photo of people, person, portrait, selfie, friends, family',
        'a photo of a smiling face, group photo, classmates and teachers',
      ],
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
      minSimilarity: 0.18,
    ),
    ThemeDefinition(
      id: 'food',
      title: '食物地图',
      subtitle: '看看这段时间你都吃了什么',
      prototypePrompts: <String>[
        'a photo of food, meal, restaurant dish, dessert, coffee',
        'a photo of hotpot, barbecue, noodles, drinks and snacks',
      ],
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
      minSimilarity: 0.18,
    ),
    ThemeDefinition(
      id: 'books',
      title: '书与课堂',
      subtitle: '书本、课件、笔记和学习场景会串成一条线',
      prototypePrompts: <String>[
        'a photo of books, classroom, slides, notes, documents, study',
        'a photo of textbook, worksheet, lecture, blackboard and paper',
      ],
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
      minSimilarity: 0.16,
    ),
    ThemeDefinition(
      id: 'cars',
      title: '车与出行',
      subtitle: '车、路、旅程和移动中的生活片段',
      prototypePrompts: <String>[
        'a photo of car, road, street, train, subway, travel transport',
        'a photo of vehicle, station, highway, driving and commute',
      ],
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
      minSimilarity: 0.16,
    ),
    ThemeDefinition(
      id: 'scenery',
      title: '风景与远方',
      subtitle: '山海、公园、日落和路上的风景',
      prototypePrompts: <String>[
        'a photo of landscape, mountain, sea, lake, sunset, sky, nature',
        'a photo of park, forest, flowers, outdoor travel scenery',
      ],
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
      minSimilarity: 0.15,
    ),
    ThemeDefinition(
      id: 'pets',
      title: '宠物日常',
      subtitle: '猫猫狗狗和它们的日常瞬间',
      prototypePrompts: <String>[
        'a photo of pet, cat, dog, puppy, kitten, animal at home',
        'a photo of cute pets playing and daily moments',
      ],
      keywords: <String>['猫', '狗', '宠物', '小猫', '小狗', '鸟', '兔子'],
      minSimilarity: 0.18,
    ),
  ];

  Future<List<ThemeCluster>> loadClusters({
    int maxThemes = 6,
    int minPhotosPerTheme = 6,
    int maxPreviewPerGroup = 18,
    int minPhotosPerSubcluster = 4,
    bool pureEmbeddingOnly = false,
    int maxNewEmbeddingsPerRun = _defaultMaxNewEmbeddingsPerRun,
    int maxPhotosToScan = _defaultMaxPhotosToScan,
  }) async {
    _updateProgress(
      const ThemeClusteringProgress(
        stage: ThemeClusteringStage.loadingPhotos,
        processed: 0,
        total: 1,
        message: '正在加载照片',
      ),
    );
    final photos = await _loadPhotos(maxPhotosToScan: maxPhotosToScan);
    if (photos.isEmpty) {
      _updateProgress(
        const ThemeClusteringProgress(
          stage: ThemeClusteringStage.done,
          processed: 1,
          total: 1,
          message: '没有可用于聚类的照片',
        ),
      );
      return const <ThemeCluster>[];
    }

    final embeddingByPhotoId = await _prepareMobileClip2Embeddings(
      photos,
      maxNewEmbeddingsPerRun: maxNewEmbeddingsPerRun,
    );
    if (embeddingByPhotoId.isEmpty) {
      _updateProgress(
        const ThemeClusteringProgress(
          stage: ThemeClusteringStage.done,
          processed: 1,
          total: 1,
          message: '没有可用向量，聚类中止',
        ),
      );
      return const <ThemeCluster>[];
    }

    _updateProgress(
      const ThemeClusteringProgress(
        stage: ThemeClusteringStage.buildingPrototypes,
        processed: 0,
        total: 1,
        message: '正在构建主题原型向量',
      ),
    );
    final prototypeByThemeId = await _buildThemePrototypeVectors();
    if (prototypeByThemeId.isEmpty) {
      _updateProgress(
        const ThemeClusteringProgress(
          stage: ThemeClusteringStage.done,
          processed: 1,
          total: 1,
          message: '原型向量为空，聚类中止',
        ),
      );
      return const <ThemeCluster>[];
    }

    _updateProgress(
      ThemeClusteringProgress(
        stage: ThemeClusteringStage.scoringThemes,
        processed: 0,
        total: _definitions.length,
        message: '正在计算主题得分',
        themeProcessed: 0,
        themeTotal: _definitions.length,
      ),
    );

    final clusters = <ThemeCluster>[];
    for (var i = 0; i < _definitions.length; i++) {
      final definition = _definitions[i];
      _updateProgress(
        ThemeClusteringProgress(
          stage: ThemeClusteringStage.scoringThemes,
          processed: i,
          total: _definitions.length,
          message: '正在评估主题: ${definition.title}',
          themeProcessed: i,
          themeTotal: _definitions.length,
        ),
      );

      final prototype = prototypeByThemeId[definition.id];
      if (prototype == null) {
        continue;
      }

      final matches = <ScoredThemePhoto>[];
      for (var photoIndex = 0; photoIndex < photos.length; photoIndex++) {
        final photo = photos[photoIndex];
        if (_shouldSkipPhotoForTheme(
          photo,
          definition,
          pureEmbeddingOnly: pureEmbeddingOnly,
        )) {
          if (photoIndex % _yieldEveryScoringItems == 0) {
            await Future<void>.delayed(Duration.zero);
          }
          continue;
        }

        final embedding = embeddingByPhotoId[photo.id];
        if (embedding == null) {
          if (photoIndex % _yieldEveryScoringItems == 0) {
            await Future<void>.delayed(Duration.zero);
          }
          continue;
        }

        final score = _scorePhoto(
          photo,
          definition,
          embedding: embedding,
          prototype: prototype,
          pureEmbeddingOnly: pureEmbeddingOnly,
        );
        if (score >= definition.minSimilarity) {
          matches.add(
            ScoredThemePhoto(photo: photo, score: score, embedding: embedding),
          );
        }

        if (photoIndex % _yieldEveryScoringItems == 0) {
          await Future<void>.delayed(Duration.zero);
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
        pureEmbeddingOnly: pureEmbeddingOnly,
      );
      if (subclusters.isEmpty) {
        continue;
      }

      clusters.add(
        ThemeCluster(definition: definition, subclusters: subclusters),
      );

      _updateProgress(
        ThemeClusteringProgress(
          stage: ThemeClusteringStage.scoringThemes,
          processed: i + 1,
          total: _definitions.length,
          message: '已完成主题: ${definition.title}',
          themeProcessed: i + 1,
          themeTotal: _definitions.length,
        ),
      );
    }

    clusters.sort((a, b) => b.totalPhotos.compareTo(a.totalPhotos));
    _updateProgress(
      ThemeClusteringProgress(
        stage: ThemeClusteringStage.done,
        processed: clusters.length,
        total: math.max(1, clusters.length),
        message: '主题聚类完成，共 ${clusters.length} 个主题',
      ),
    );
    return clusters.take(maxThemes).toList(growable: false);
  }

  Future<List<PhotoEntity>> _loadPhotos({required int maxPhotosToScan}) async {
    if (_photosLoader != null) {
      return _photosLoader();
    }
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final q = photoBox.query()
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    q.limit = maxPhotosToScan;
    final photos = q.find();
    q.close();
    return photos;
  }

  ThemeSubclusterer _resolveSubclusterer(ThemeDefinition definition) {
    return definition.id == 'people'
        ? _peopleSubclusterer
        : _genericSubclusterer;
  }

  Future<Map<int, List<double>>> _prepareMobileClip2Embeddings(
    List<PhotoEntity> photos, {
    required int maxNewEmbeddingsPerRun,
  }) async {
    if (_embeddingPreparer != null) {
      return _embeddingPreparer(photos);
    }

    final cached = <int, List<double>>{};
    final updated = <PhotoEntity>[];

    final total = photos.length;
    var processed = 0;
    var newEmbeddings = 0;
    var cachedEmbeddings = 0;
    var skippedScreenshots = 0;
    var skippedMissingFiles = 0;

    _updateProgress(
      ThemeClusteringProgress(
        stage: ThemeClusteringStage.preparingEmbeddings,
        processed: 0,
        total: total,
        message: '正在准备图像向量',
        newEmbeddings: 0,
        cachedEmbeddings: 0,
      ),
    );

    await _embeddingService.beginWorkflowSession();
    try {
      final activeModelVersion = await _embeddingService
          .getSelectedModelVersion();
      for (final photo in photos) {
        processed++;

        // Keep screenshot-like UI captures out of visual-theme retrieval.
        if (photo.isProbablyScreenshot) {
          skippedScreenshots++;
          _emitEmbeddingProgress(
            processed: processed,
            total: total,
            newEmbeddings: newEmbeddings,
            cachedEmbeddings: cachedEmbeddings,
          );
          continue;
        }

        final indexedEmbedding = _embeddingService.readIndexedEmbeddingForPhoto(
          photo: photo,
          modelVersion: activeModelVersion,
        );
        if (indexedEmbedding != null) {
          cached[photo.id] = indexedEmbedding;
          cachedEmbeddings++;
          _emitEmbeddingProgress(
            processed: processed,
            total: total,
            newEmbeddings: newEmbeddings,
            cachedEmbeddings: cachedEmbeddings,
          );
          continue;
        }

        if (newEmbeddings >= maxNewEmbeddingsPerRun) {
          _emitEmbeddingProgress(
            processed: processed,
            total: total,
            newEmbeddings: newEmbeddings,
            cachedEmbeddings: cachedEmbeddings,
            hitLimit: true,
            force: true,
          );
          continue;
        }

        final file = File(photo.path);
        if (!await file.exists()) {
          skippedMissingFiles++;
          _emitEmbeddingProgress(
            processed: processed,
            total: total,
            newEmbeddings: newEmbeddings,
            cachedEmbeddings: cachedEmbeddings,
          );
          continue;
        }

        try {
          final resolution = await _embeddingService
              .resolvePhotoEmbedding(photo: photo)
              .timeout(_embeddingTimeout);
          final embedding = photo.imageEmbedding;
          if (embedding == null || embedding.length != _embeddingDim) {
            _emitEmbeddingProgress(
              processed: processed,
              total: total,
              newEmbeddings: newEmbeddings,
              cachedEmbeddings: cachedEmbeddings,
            );
            continue;
          }

          cached[photo.id] = embedding;
          if (resolution.reusedCache) {
            cachedEmbeddings++;
          } else {
            updated.add(photo);
            newEmbeddings++;
          }
        } on TimeoutException {
          _emitEmbeddingProgress(
            processed: processed,
            total: total,
            newEmbeddings: newEmbeddings,
            cachedEmbeddings: cachedEmbeddings,
            force: true,
          );
          continue;
        } catch (_) {
          _emitEmbeddingProgress(
            processed: processed,
            total: total,
            newEmbeddings: newEmbeddings,
            cachedEmbeddings: cachedEmbeddings,
          );
          continue;
        }

        _emitEmbeddingProgress(
          processed: processed,
          total: total,
          newEmbeddings: newEmbeddings,
          cachedEmbeddings: cachedEmbeddings,
        );

        if (processed % _yieldEveryEmbeddingItems == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      await _embeddingService.endWorkflowSession();
    }

    if (updated.isNotEmpty) {
      final store = ObjectBoxService().store;
      store.runInTransaction(TxMode.write, () => store.box<PhotoEntity>().putMany(updated));
    }

    debugPrint(
      '🧠 [主题聚类向量] 复用=$cachedEmbeddings 新算=$newEmbeddings '
      '截图跳过=$skippedScreenshots 文件缺失=$skippedMissingFiles '
      '总可用=${cached.length}',
    );

    return cached;
  }

  void _emitEmbeddingProgress({
    required int processed,
    required int total,
    required int newEmbeddings,
    required int cachedEmbeddings,
    bool hitLimit = false,
    bool force = false,
  }) {
    final shouldEmit =
        force || processed == total || processed == 1 || processed % 20 == 0;
    if (!shouldEmit) {
      return;
    }

    final suffix = hitLimit ? '（本轮新算已达上限）' : '';
    _updateProgress(
      ThemeClusteringProgress(
        stage: ThemeClusteringStage.preparingEmbeddings,
        processed: processed,
        total: total,
        newEmbeddings: newEmbeddings,
        cachedEmbeddings: cachedEmbeddings,
        message: '向量准备中 $processed/$total$suffix',
      ),
    );
  }

  void _updateProgress(ThemeClusteringProgress progress) {
    _progressNotifier.value = progress;
  }

  bool _shouldSkipPhotoForTheme(
    PhotoEntity photo,
    ThemeDefinition definition, {
    required bool pureEmbeddingOnly,
  }) {
    if (photo.isProbablyScreenshot) {
      return true;
    }

    if (!pureEmbeddingOnly &&
        definition.id == 'people' &&
        photo.faceCount <= 0) {
      return true;
    }

    return false;
  }

  Future<Map<String, List<double>>> _buildThemePrototypeVectors() async {
    if (_prototypeBuilder != null) {
      return _prototypeBuilder();
    }

    try {
      await _semanticService.warmUp().timeout(_prototypeWarmUpTimeout);
    } on TimeoutException {
      debugPrint('⚠️ [主题聚类] 语义模型 warmUp 超时，跳过本轮聚类');
      return const <String, List<double>>{};
    }
    final result = <String, List<double>>{};

    for (final definition in _definitions) {
      if (definition.prototypePrompts.isEmpty) {
        continue;
      }

      final promptVectors = <List<double>>[];
      for (final prompt in definition.prototypePrompts) {
        try {
          final vector = await _semanticService
              .embedText(prompt)
              .timeout(_prototypePromptTimeout);
          promptVectors.add(vector);
        } on TimeoutException {
          continue;
        } catch (_) {
          continue;
        }
      }
      final merged = ThemeClusterComputeHelpers.meanAndNormalize(promptVectors);
      if (merged.length == _embeddingDim) {
        result[definition.id] = merged;
      }

      await Future<void>.delayed(Duration.zero);
    }

    return result;
  }

  double _scorePhoto(
    PhotoEntity photo,
    ThemeDefinition definition, {
    required List<double> embedding,
    required List<double> prototype,
    required bool pureEmbeddingOnly,
  }) {
    var score = ThemeClusterComputeHelpers.cosineSimilarity(
      embedding,
      prototype,
    );

    if (pureEmbeddingOnly) {
      return score;
    }

    final bag = ThemeClusterComputeHelpers.buildTokenBag(photo);
    final lexicalHits = definition.keywords
        .where((keyword) => bag.contains(keyword.toLowerCase()))
        .length;
    if (lexicalHits > 0) {
      // Small lexical bonus to stabilize near-threshold Chinese terms.
      score += math.min(0.06, lexicalHits * 0.015);
    }

    if (definition.id == 'people') {
      if (photo.faceCount > 0) {
        score += 0.08;
      }
      if ((photo.joyScore ?? 0) >= 0.45) {
        score += 0.03;
      }
    }

    if (definition.id == 'books' &&
        OcrPolicy.effectiveTags(photo.ocrTags ?? const <String>[]).isNotEmpty) {
      score += 0.04;
    }

    return score;
  }
}
