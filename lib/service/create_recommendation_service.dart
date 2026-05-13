/// 推荐生成服务，负责把查询条件转换为可展示的精选集合。

import '../models/entity/create_recommendation_entity.dart';
import '../models/entity/photo_entity.dart';
import '../models/vo/semantic_search_models.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import 'photo_service.dart';
import 'recommendation_query_template_service.dart';
import 'semantic_photo_search_service.dart';
import 'semantic_query_parser_service.dart';

class CreateRecommendationService {
  CreateRecommendationService._internal();

  static final CreateRecommendationService _instance =
      CreateRecommendationService._internal();

  factory CreateRecommendationService() => _instance;

  static const Duration refreshInterval = Duration(days: 3);
  static const int featuredMinimumRecommendedPhotos = 1;
  static const int thematicMinimumRecommendedPhotos = 2;
  static const int timeAndLocationMinimumRecommendedPhotos = 9;
  static const int _maxLocationPresets = 2;
  static const int _maxCards = 16;
  static const int _normalRefreshBudget = 4;
  static const int _forceRefreshBudget = 8;

  final RecommendationQueryTemplateService _templateService =
      RecommendationQueryTemplateService();
  final SemanticQueryParserService _queryParser = SemanticQueryParserService();
  final SemanticPhotoSearchService _semanticPhotoSearchService =
      SemanticPhotoSearchService();

  Future<CreateRecommendationRefreshResult> refreshRecommendationsIfNeeded({
    bool force = false,
    Set<String> excludeRecommendationKeys = const <String>{},
  }) async {
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    final recBox = store.box<CreateRecommendationEntity>();
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final photos = photoBox.getAll();
    final presets = _buildPresets(now, photos);
    final presetKeys = presets.map((item) => item.recommendationKey).toSet();
    final existing = recBox.getAll();
    final existingByKey = <String, CreateRecommendationEntity>{
      for (final entity in existing) entity.recommendationKey: entity,
    };
    final locationDictionary = _buildLocationDictionary(photos);
    final updates = <CreateRecommendationEntity>[];
    final duePresets = _selectPresetsToRefresh(
      presets,
      existingByKey,
      nowMs,
      force: force,
      excludeRecommendationKeys: excludeRecommendationKeys,
    );
    final processedKeys = duePresets
        .map((preset) => preset.recommendationKey)
        .toList(growable: false);

    for (final preset in duePresets) {
      final current = existingByKey[preset.recommendationKey];
      final result = await _searchPreset(
        preset,
        now: now,
        locationDictionary: locationDictionary,
      );
      final matchedPhotos = _mergeRecommendationPhotos(result);
      final matchedCount = matchedPhotos.length;
      final fingerprint = _buildFingerprint(matchedPhotos);
      final representativeCover = _pickRepresentativeCover(matchedPhotos);
      final entity = current ?? CreateRecommendationEntity();
      final sameQuery = current?.query == preset.query;
      final sameFingerprint = current?.resultFingerprint == fingerprint;

      entity
        ..recommendationKey = preset.recommendationKey
        ..presetId = preset.presetId
        ..group = preset.group
        ..label = preset.label
        ..title = preset.title
        ..subtitle = preset.subtitleBuilder(matchedCount)
        ..query = preset.query
        ..photoIds = matchedPhotos.map((photo) => photo.id).toList(growable: false)
        ..coverPhotoIds = representativeCover == null
            ? const <int>[]
            : <int>[representativeCover.id]
        ..matchedCount = matchedCount
        ..priority = preset.priority
        ..createdAt = current?.createdAt ?? nowMs
        ..updatedAt = nowMs
        ..lastCheckedAt = nowMs
        ..nextCheckAt = nowMs + refreshInterval.inMilliseconds
        ..resultFingerprint = fingerprint;

      if (matchedCount >= preset.minPhotoCount) {
        final keepDismissed =
            !force &&
                current?.status == CreateRecommendationStatus.dismissed &&
                sameQuery &&
                sameFingerprint;
        entity
          ..status = keepDismissed
              ? CreateRecommendationStatus.dismissed
              : CreateRecommendationStatus.active
          ..lastRecommendedAt =
              keepDismissed ? current?.lastRecommendedAt : nowMs;
      } else {
        entity
          ..status = CreateRecommendationStatus.expired
          ..lastRecommendedAt = current?.lastRecommendedAt;
      }

      updates.add(entity);
    }

    for (final entity in existing) {
      if (!entity.presetId.startsWith('auto_')) {
        continue;
      }
      if (presetKeys.contains(entity.recommendationKey)) {
        continue;
      }
      if (entity.status == CreateRecommendationStatus.archived) {
        continue;
      }
      entity
        ..status = CreateRecommendationStatus.archived
        ..updatedAt = nowMs
        ..nextCheckAt = nowMs + refreshInterval.inMilliseconds;
      updates.add(entity);
    }

    if (updates.isNotEmpty) {
      store.runInTransaction(TxMode.write, () => recBox.putMany(updates));
    }

    return CreateRecommendationRefreshResult(
      processedRecommendationKeys: processedKeys,
      remainingCount: _countRemainingRefreshCandidates(
        presets,
        existingByKey,
        nowMs,
        force: force,
        excludeRecommendationKeys: {
          ...excludeRecommendationKeys,
          ...processedKeys,
        },
      ),
    );
  }

  Future<List<CreateRecommendationCardData>> loadActiveRecommendations() async {
    final store = ObjectBoxService().store;
    final recBox = store.box<CreateRecommendationEntity>();
    final photoBox = store.box<PhotoEntity>();

    final q = recBox.query(
      CreateRecommendationEntity_.status.equals(CreateRecommendationStatus.active),
    ).build();
    final entities = q.find();
    q.close();

    entities.sort((left, right) {
      final priority = right.priority.compareTo(left.priority);
      if (priority != 0) return priority;
      return right.updatedAt.compareTo(left.updatedAt);
    });

    final trimmed = entities.take(_maxCards).toList(growable: false);
    if (trimmed.isEmpty) return const <CreateRecommendationCardData>[];

    final coverIds = trimmed
        .expand((entity) => entity.coverPhotoIds.take(1))
        .toSet()
        .toList(growable: false);
    final coverPhotos = photoBox.getMany(coverIds).whereType<PhotoEntity>().toList(growable: false);
    final reconciled = await PhotoService().reconcileAccessiblePhotos(coverPhotos);
    final coverById = <int, PhotoEntity>{
      for (final photo in reconciled) photo.id: photo,
    };

    return trimmed
        .map(
          (entity) => CreateRecommendationCardData(
            entity: entity,
            cover: entity.coverPhotoIds.isEmpty
                ? null
                : coverById[entity.coverPhotoIds.first],
          ),
        )
        .toList(growable: false);
  }

  Future<void> dismissRecommendation(int id) async {
    final store = ObjectBoxService().store;
    final recBox = store.box<CreateRecommendationEntity>();
    final entity = recBox.get(id);
    if (entity == null) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    entity
      ..status = CreateRecommendationStatus.dismissed
      ..updatedAt = nowMs
      ..nextCheckAt = nowMs + refreshInterval.inMilliseconds;

    store.runInTransaction(TxMode.write, () => recBox.put(entity));
  }

  List<_ResolvedRecommendationPreset> _buildPresets(
    DateTime now,
    List<PhotoEntity> photos,
  ) {
    final currentMonth = DateTime(now.year, now.month);
    final previousMonth = DateTime(now.year, now.month - 1);
    final season = _currentSeason(now);
    final presets = <_ResolvedRecommendationPreset>[
      _semanticPreset(
        recommendationKey: 'auto_spring_mood',
        presetId: 'auto_spring_mood',
        group: 'season',
        label: '春日气息',
        title: '春天的气息',
        query: '春天的气息',
        priority: 132,
        alwaysRefresh: true,
        minPhotoCount: featuredMinimumRecommendedPhotos,
        subtitleBuilder: (count) => '找到 $count 张带有花草、微风和春日氛围的照片。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_happy_smiles',
        presetId: 'auto_happy_smiles',
        group: 'people',
        label: '笑脸时刻',
        title: '愉快的笑脸',
        query: '愉快的笑脸',
        priority: 130,
        alwaysRefresh: true,
        minPhotoCount: featuredMinimumRecommendedPhotos,
        subtitleBuilder: (count) => '这些笑容已经攒到 $count 张，很适合直接整理成轻松的回忆。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_food_diary',
        presetId: 'auto_food_diary',
        group: 'food',
        label: '美食日记',
        title: '美食日记',
        query: '美食日记',
        priority: 128,
        alwaysRefresh: true,
        minPhotoCount: featuredMinimumRecommendedPhotos,
        subtitleBuilder: (count) => '找到 $count 张和吃饭、聚餐、甜品有关的照片。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_table_gathering',
        presetId: 'auto_table_gathering',
        group: 'food',
        label: '餐桌烟火',
        title: '热闹的餐桌',
        query: '热闹的餐桌',
        priority: 126,
        minPhotoCount: thematicMinimumRecommendedPhotos,
        subtitleBuilder: (count) => '围坐在一起吃饭的场景已经命中 $count 张，很适合整理成一组生活片段。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_city_walk',
        presetId: 'auto_city_walk',
        group: 'daily',
        label: '城市散步',
        title: '街头走走停停的片刻',
        query: '城市散步',
        priority: 124,
        minPhotoCount: thematicMinimumRecommendedPhotos,
        subtitleBuilder: (count) => '熟悉街角和路上的片刻已经有 $count 张，能很好地代表日常生活感。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_flowers_greenery',
        presetId: 'auto_flowers_greenery',
        group: 'season',
        label: '花与绿意',
        title: '花与树的季节',
        query: '花与树的季节',
        priority: 122,
        minPhotoCount: thematicMinimumRecommendedPhotos,
        subtitleBuilder: (count) => '花草、树影和绿意相关的照片已经找到 $count 张，氛围会很统一。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_sunset_sky',
        presetId: 'auto_sunset_sky',
        group: 'season',
        label: '晚霞天空',
        title: '晚霞和天空',
        query: '晚霞和天空',
        priority: 120,
        minPhotoCount: thematicMinimumRecommendedPhotos,
        subtitleBuilder: (count) => '傍晚天色和日落光线已经命中 $count 张，很适合做成一组轻盈的封面故事。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_family_generations',
        presetId: 'auto_family_generations',
        group: 'people',
        label: '成长陪伴',
        title: '长辈陪伴与孩子成长',
        query: '长辈陪伴的时刻',
        priority: 118,
        subtitleBuilder: (count) => '这组主题已经命中 $count 张，很适合回看陪伴与成长。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_family_gathering',
        presetId: 'auto_family_gathering',
        group: 'people',
        label: '相聚时刻',
        title: '朋友与家人的相聚',
        query: '朋友聚会',
        priority: 116,
        subtitleBuilder: (count) => '聚餐、聊天和热闹的瞬间已经积累到 $count 张。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_travel_journey',
        presetId: 'auto_travel_journey',
        group: 'travel',
        label: '旅途记忆',
        title: '旅行出发与回家的路',
        query: '旅行出发那天',
        priority: 114,
        subtitleBuilder: (count) => '关于出发和归来的 $count 张照片，已经能拼出一段旅程。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_pet_daily',
        presetId: 'auto_pet_daily',
        group: 'pet',
        label: '宠物陪伴',
        title: '宠物陪伴的日常',
        query: '宠物陪伴的日常',
        priority: 112,
        subtitleBuilder: (count) => '这些和宠物有关的 $count 张照片，很适合单独留下来。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_festivals',
        presetId: 'auto_festivals',
        group: 'festival',
        label: '节庆团圆',
        title: '节日与团圆',
        query: '春节',
        priority: 110,
        subtitleBuilder: (count) => '节日气氛、聚会和庆祝场景已经命中 $count 张。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_birthday_anniversary',
        presetId: 'auto_birthday_anniversary',
        group: 'festival',
        label: '纪念日',
        title: '生日与纪念日',
        query: '生日',
        priority: 108,
        subtitleBuilder: (count) => '蛋糕、蜡烛和重要的人，已经找到 $count 张。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_school_milestones',
        presetId: 'auto_school_milestones',
        group: 'school',
        label: '人生节点',
        title: '毕业、入学与新的开始',
        query: '毕业那段时间',
        priority: 106,
        subtitleBuilder: (count) => '这些带着阶段变化的 $count 张照片，很适合讲一个节点故事。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_campus_life',
        presetId: 'auto_campus_life',
        group: 'school',
        label: '校园青春',
        title: '校园里的青春时刻',
        query: '校园里的青春',
        priority: 104,
        subtitleBuilder: (count) => '你已经留下 $count 张校园记忆，足够做成一组青春相册。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_achievement_stage',
        presetId: 'auto_achievement_stage',
        group: 'achievement',
        label: '高光时刻',
        title: '舞台、比赛与高光瞬间',
        query: '舞台表演',
        priority: 102,
        subtitleBuilder: (count) => '这组高光瞬间已经命中 $count 张，值得被单独保留。',
      ),
      if (season.id != 'spring')
        _semanticPreset(
          recommendationKey: 'auto_${season.id}_mood',
          presetId: 'auto_${season.id}_mood',
          group: 'season',
          label: season.label,
          title: season.title,
          query: season.query,
          priority: 100,
          subtitleBuilder: (count) => '和 ${season.label} 有关的照片已经有 $count 张。',
        ),
      _semanticPreset(
        recommendationKey: 'auto_hobbies',
        presetId: 'auto_hobbies',
        group: 'hobby',
        label: '兴趣爱好',
        title: '属于你的兴趣日常',
        query: '兴趣爱好',
        priority: 98,
        subtitleBuilder: (count) => '找到 $count 张和兴趣相关的照片，能看见长期坚持的痕迹。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_home_daily',
        presetId: 'auto_home_daily',
        group: 'home',
        label: '生活日常',
        title: '家里的普通一天',
        query: '家里',
        priority: 96,
        subtitleBuilder: (count) => '看似普通的 $count 张照片，往往最适合留下真实生活感。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_outdoor_activity',
        presetId: 'auto_outdoor_activity',
        group: 'outdoor',
        label: '户外夜晚',
        title: '露营、烟花与路上的风景',
        query: '露营夜晚',
        priority: 94,
        subtitleBuilder: (count) => '夜晚和路上的记忆已经命中 $count 张，氛围感很强。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_old_times',
        presetId: 'auto_old_times',
        group: 'growth',
        label: '旧时光',
        title: '那些想重温的旧时光',
        query: '那些想重温的旧时光',
        priority: 92,
        subtitleBuilder: (count) => '这些带着时间感的 $count 张照片，适合重新翻出来看看。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_aesthetic',
        presetId: 'auto_aesthetic',
        group: 'aesthetic',
        label: '美学精选',
        title: '值得单独留存的美感照片',
        query: '美学精选',
        priority: 90,
        subtitleBuilder: (count) => '画面感很强的照片已经有 $count 张，做成精选会很协调。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_neighborhood_park',
        presetId: 'auto_neighborhood_park',
        group: 'daily',
        label: '熟悉街景',
        title: '小区、公园与熟悉的街角',
        query: '公园',
        priority: 88,
        subtitleBuilder: (count) => '离你最近的生活半径里，已经有 $count 张值得回看的照片。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_relationship',
        presetId: 'auto_relationship',
        group: 'relationship',
        label: '关系纪念',
        title: '第一次见面与重要关系节点',
        query: '第一次见面',
        priority: 86,
        subtitleBuilder: (count) => '和重要关系有关的 $count 张照片，适合整理成更私人的纪念。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_water_mountain',
        presetId: 'auto_water_mountain',
        group: 'nature',
        label: '自然远行',
        title: '海边与山里的风景',
        query: '海边',
        priority: 84,
        subtitleBuilder: (count) => '找到 $count 张自然风景照片，很适合汇成一次远离日常的回忆。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_work_life',
        presetId: 'auto_work_life',
        group: 'work',
        label: '工作日常',
        title: '通勤、办公与忙碌生活',
        query: '通勤路上的日常',
        priority: 82,
        subtitleBuilder: (count) => '属于工作日常的 $count 张照片，也能拼出很真实的生活切面。',
      ),
      _semanticPreset(
        recommendationKey: 'auto_home_change',
        presetId: 'auto_home_change',
        group: 'home',
        label: '新生活',
        title: '搬家与新家的变化',
        query: '搬家的日子',
        priority: 80,
        subtitleBuilder: (count) => '这组与新家有关的 $count 张照片，很适合记录生活阶段变化。',
      ),
      _ResolvedRecommendationPreset(
        recommendationKey:
            'auto_month_${currentMonth.year}_${currentMonth.month}',
        presetId: 'auto_month_current',
        group: 'time',
        label: '本月回顾',
        title: '${currentMonth.year} 年 ${currentMonth.month} 月',
        query: '这个月',
        priority: 70,
        minPhotoCount: timeAndLocationMinimumRecommendedPhotos,
        alwaysRefresh: false,
        subtitleBuilder: (count) => '这个月已经留下 $count 张照片，适合整理最近生活的节奏。',
      ),
      _ResolvedRecommendationPreset(
        recommendationKey:
            'auto_month_${previousMonth.year}_${previousMonth.month}',
        presetId: 'auto_month_previous',
        group: 'time',
        label: '上月回顾',
        title: '${previousMonth.year} 年 ${previousMonth.month} 月',
        query: '上个月',
        priority: 68,
        minPhotoCount: timeAndLocationMinimumRecommendedPhotos,
        alwaysRefresh: false,
        subtitleBuilder: (count) => '上个月的 $count 张照片，已经足够拼出一段完整近况。',
      ),
      _ResolvedRecommendationPreset(
        recommendationKey:
            'auto_anniversary_${now.year - 1}_${now.month}_${now.day}',
        presetId: 'auto_anniversary_last_year',
        group: 'time',
        label: '去年今日',
        title: '${now.year - 1} 年的今天',
        query: '去年的今天',
        priority: 66,
        minPhotoCount: timeAndLocationMinimumRecommendedPhotos,
        alwaysRefresh: false,
        subtitleBuilder: (count) => '去年的今天命中 $count 张照片，很适合重新讲述那一天。',
      ),
      _ResolvedRecommendationPreset(
        recommendationKey: 'auto_year_${now.year}',
        presetId: 'auto_year_current',
        group: 'time',
        label: '年度回顾',
        title: '${now.year} 年度总结',
        query: '今年',
        priority: 64,
        minPhotoCount: timeAndLocationMinimumRecommendedPhotos,
        alwaysRefresh: false,
        subtitleBuilder: (count) => '这一年的 $count 张照片，已经足够组成一份年度回看。',
      ),
      _ResolvedRecommendationPreset(
        recommendationKey: 'auto_year_${now.year - 1}',
        presetId: 'auto_year_previous',
        group: 'time',
        label: '去年回顾',
        title: '${now.year - 1} 年度回顾',
        query: '去年',
        priority: 62,
        minPhotoCount: timeAndLocationMinimumRecommendedPhotos,
        alwaysRefresh: false,
        subtitleBuilder: (count) => '去年留下的 $count 张照片，也许已经能整理成另一种讲述。',
      ),
    ];

    final locations = _topLocations(photos);
    for (var index = 0; index < locations.length; index++) {
      final location = locations[index];
      presets.add(
        _ResolvedRecommendationPreset(
          recommendationKey: 'auto_location_${_slugify(location)}',
          presetId: 'auto_location_$index',
          group: 'location',
          label: '熟悉地点',
          title: '$location 的反复出现',
          query: location,
          priority: 60 - index,
          minPhotoCount: timeAndLocationMinimumRecommendedPhotos,
          alwaysRefresh: false,
          locationText: location,
          subtitleBuilder: (count) => '你在 $location 留下了 $count 张照片，这里已经形成连续回忆。',
        ),
      );
    }

    return presets;
  }

  _ResolvedRecommendationPreset _semanticPreset({
    required String recommendationKey,
    required String presetId,
    required String group,
    required String label,
    required String title,
    required String query,
    required int priority,
    required String Function(int count) subtitleBuilder,
    bool alwaysRefresh = false,
    int minPhotoCount = thematicMinimumRecommendedPhotos,
  }) {
    return _ResolvedRecommendationPreset(
      recommendationKey: recommendationKey,
      presetId: presetId,
      group: group,
      label: label,
      title: title,
      query: query,
      priority: priority,
      minPhotoCount: minPhotoCount,
      alwaysRefresh: alwaysRefresh,
      subtitleBuilder: subtitleBuilder,
    );
  }

  Set<String> _buildLocationDictionary(List<PhotoEntity> photos) {
    final values = <String>{};
    for (final photo in photos) {
      for (final value in <String?>[
        photo.province,
        photo.city,
        photo.district,
        photo.locationName,
        photo.formattedAddress,
      ]) {
        final normalized = _normalizedLocation(value);
        if (normalized != null) {
          values.add(normalized);
        }
      }
    }
    return values;
  }

  List<_ResolvedRecommendationPreset> _selectPresetsToRefresh(
    List<_ResolvedRecommendationPreset> presets,
    Map<String, CreateRecommendationEntity> existingByKey,
    int nowMs, {
    required bool force,
    required Set<String> excludeRecommendationKeys,
  }) {
    final budget = force ? _forceRefreshBudget : _normalRefreshBudget;
    final candidates = _refreshCandidates(
      presets,
      existingByKey,
      nowMs,
      force: force,
      excludeRecommendationKeys: excludeRecommendationKeys,
    );
    if (candidates.length <= budget) {
      return candidates;
    }
    return candidates.take(budget).toList(growable: false);
  }

  int _countRemainingRefreshCandidates(
    List<_ResolvedRecommendationPreset> presets,
    Map<String, CreateRecommendationEntity> existingByKey,
    int nowMs, {
    required bool force,
    required Set<String> excludeRecommendationKeys,
  }) {
    return _refreshCandidates(
      presets,
      existingByKey,
      nowMs,
      force: force,
      excludeRecommendationKeys: excludeRecommendationKeys,
    ).length;
  }

  List<_ResolvedRecommendationPreset> _refreshCandidates(
    List<_ResolvedRecommendationPreset> presets,
    Map<String, CreateRecommendationEntity> existingByKey,
    int nowMs, {
    required bool force,
    required Set<String> excludeRecommendationKeys,
  }) {
    final candidates = presets.where((preset) {
      if (excludeRecommendationKeys.contains(preset.recommendationKey)) {
        return false;
      }
      final current = existingByKey[preset.recommendationKey];
      if (current == null) {
        return true;
      }
      if (force) {
        return true;
      }
      if (preset.alwaysRefresh) {
        return true;
      }
      final nextCheckAt = current.nextCheckAt;
      return nextCheckAt == null || nextCheckAt <= nowMs;
    }).toList(growable: false);

    candidates.sort((left, right) {
      final leftCurrent = existingByKey[left.recommendationKey];
      final rightCurrent = existingByKey[right.recommendationKey];
      final leftFreshness = left.alwaysRefresh
          ? -1
          : (leftCurrent?.nextCheckAt ?? 0);
      final rightFreshness = right.alwaysRefresh
          ? -1
          : (rightCurrent?.nextCheckAt ?? 0);
      final freshnessCompare = leftFreshness.compareTo(rightFreshness);
      if (freshnessCompare != 0) {
        return freshnessCompare;
      }
      return right.priority.compareTo(left.priority);
    });
    return candidates;
  }

  Future<SemanticSearchResult> _searchPreset(
    _ResolvedRecommendationPreset preset, {
    required DateTime now,
    required Set<String> locationDictionary,
  }) async {
    final presetQuery = _templateService.buildPresetQuery(
      preset.query,
      now: now,
      locationDictionary: locationDictionary,
    );
    if (presetQuery != null) {
      return _semanticPhotoSearchService.searchWithQuery(presetQuery);
    }

    if (preset.locationText != null) {
      final structuredQuery = _queryParser.buildQueryFromStructuredJson(
        rawQuery: preset.query,
        jsonObject: <String, dynamic>{
          'query_type': 'metadata',
          'time_ranges': const <Map<String, Object?>>[],
          'locations': <Map<String, Object?>>[
            <String, Object?>{
              'text': preset.locationText!,
              'type': 'location',
            },
          ],
          'coarse_tags': const <Map<String, Object?>>[],
          'tag_strictness': 'optional',
          'positive_semantics': const <Map<String, Object?>>[],
          'recall_semantics': const <Map<String, Object?>>[],
          'negative_semantics': const <Map<String, Object?>>[],
          'estimated_result_count': const <String, Object?>{
            'min': 9,
            'max': 400,
            'confidence': 0.72,
          },
          'notes': '地点型创作推荐预置查询',
        },
        locationDictionary: locationDictionary,
      );
      return _semanticPhotoSearchService.searchWithQuery(structuredQuery);
    }

    return _semanticPhotoSearchService.search(preset.query);
  }

  List<PhotoEntity> _mergeRecommendationPhotos(SemanticSearchResult result) {
    final merged = <PhotoEntity>[];
    final seen = <int>{};
    for (final photo in [...result.exactPhotos, ...result.relatedPhotos]) {
      if (seen.add(photo.id)) {
        merged.add(photo);
      }
    }
    return merged;
  }

  String _buildFingerprint(List<PhotoEntity> photos) {
    final ids = photos.map((photo) => photo.id).toList(growable: false)..sort();
    return ids.join(',');
  }

  PhotoEntity? _pickRepresentativeCover(List<PhotoEntity> photos) {
    if (photos.isEmpty) {
      return null;
    }
    final ranked = List<PhotoEntity>.from(photos);
    ranked.sort((left, right) {
      final scoreCompare = _coverScore(right).compareTo(_coverScore(left));
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return right.timestamp.compareTo(left.timestamp);
    });
    return ranked.first;
  }

  double _coverScore(PhotoEntity photo) {
    var score = 0.0;
    if (!photo.isProbablyScreenshot) {
      score += 2.0;
    }
    if ((photo.aiCaption ?? '').trim().isNotEmpty) {
      score += 0.2;
    }
    score += photo.faceCount.clamp(0, 3) * 0.9;
    score += (photo.joyScore ?? 0) * 2.2;
    score += photo.smileProb * 1.5;

    final aspectRatio = photo.aspectRatio;
    final aspectDelta = (aspectRatio - 0.85).abs();
    score += (1.2 - aspectDelta).clamp(0.0, 1.2);

    final hasVisualTags =
        (photo.aiTags?.isNotEmpty ?? false) || (photo.ocrTags?.isNotEmpty ?? false);
    if (hasVisualTags) {
      score += 0.15;
    }

    return score;
  }

  _SeasonPreset _currentSeason(DateTime now) {
    if (now.month >= 3 && now.month <= 5) {
      return const _SeasonPreset(
        id: 'spring',
        label: '春日气息',
        title: '春天的气息',
        query: '春天的气息',
      );
    }
    if (now.month >= 6 && now.month <= 8) {
      return const _SeasonPreset(
        id: 'summer',
        label: '夏日气息',
        title: '夏天的气息',
        query: '夏天的气息',
      );
    }
    if (now.month >= 9 && now.month <= 11) {
      return const _SeasonPreset(
        id: 'autumn',
        label: '秋天气息',
        title: '秋天的气息',
        query: '秋天的气息',
      );
    }
    return const _SeasonPreset(
      id: 'winter',
      label: '冬日气息',
      title: '冬天的气息',
      query: '冬天的气息',
    );
  }

  List<String> _topLocations(List<PhotoEntity> photos) {
    final counter = <String, int>{};
    for (final photo in photos) {
      final candidates = <String?>[
        photo.city,
        photo.district,
        photo.locationName,
      ];
      for (final candidate in candidates) {
        final normalized = _normalizedLocation(candidate);
        if (normalized == null) {
          continue;
        }
        counter.update(normalized, (value) => value + 1, ifAbsent: () => 1);
        break;
      }
    }

    final sorted = counter.entries.toList(growable: false)
      ..sort((left, right) {
        final countCompare = right.value.compareTo(left.value);
        if (countCompare != 0) {
          return countCompare;
        }
        return left.key.length.compareTo(right.key.length);
      });

    return sorted
        .where((entry) => entry.value >= timeAndLocationMinimumRecommendedPhotos)
        .take(_maxLocationPresets)
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  String _slugify(String input) {
    final normalized = input.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    return normalized.replaceAll(RegExp(r'[^a-z0-9_\u4e00-\u9fa5]+'), '');
  }

  String? _normalizedLocation(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (trimmed == '中国' || trimmed == '中华人民共和国') {
      return null;
    }
    return trimmed;
  }
}

class CreateRecommendationCardData {
  const CreateRecommendationCardData({
    required this.entity,
    required this.cover,
  });

  final CreateRecommendationEntity entity;
  final PhotoEntity? cover;

  String get label => entity.label;
  String get title => entity.title;
  String get subtitle => entity.subtitle;
  String get query => entity.query;
  int get matchedCount => entity.matchedCount;
}

class CreateRecommendationRefreshResult {
  const CreateRecommendationRefreshResult({
    required this.processedRecommendationKeys,
    required this.remainingCount,
  });

  final List<String> processedRecommendationKeys;
  final int remainingCount;

  bool get hasRemaining => remainingCount > 0;
}

class _ResolvedRecommendationPreset {
  const _ResolvedRecommendationPreset({
    required this.recommendationKey,
    required this.presetId,
    required this.group,
    required this.label,
    required this.title,
    required this.query,
    required this.priority,
    required this.minPhotoCount,
    required this.alwaysRefresh,
    required this.subtitleBuilder,
    this.locationText,
  });

  final String recommendationKey;
  final String presetId;
  final String group;
  final String label;
  final String title;
  final String query;
  final int priority;
  final int minPhotoCount;
  final bool alwaysRefresh;
  final String Function(int count) subtitleBuilder;
  final String? locationText;
}

class _SeasonPreset {
  const _SeasonPreset({
    required this.id,
    required this.label,
    required this.title,
    required this.query,
  });

  final String id;
  final String label;
  final String title;
  final String query;
}
