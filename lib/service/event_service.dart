import 'dart:convert';

import 'package:dio/dio.dart';
import '../data/tag_taxonomy_v2.dart';
import '../models/entity/photo_entity.dart';
import '../models/entity/event_entity.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../utils/ocr_policy.dart';
import '../utils/tag_sanitizer.dart';
import '../utils/event_cluster_helper.dart';
import '../utils/smart_title_generator.dart';
import '../service/llm_service.dart';

class EventService {
  static final EventService _instance = EventService._internal();
  factory EventService() => _instance;
  EventService._internal();

  static const Set<String> _blockedSmartTitleTags = <String>{
    '套路',
    '未婚妻',
    '字幕',
    '房主',
    '采购员',
    memoriaOtherLabel,
  };

  static const Set<String> _textSceneTags = <String>{
    '文字',
    '文本',
    '文档',
    '屏幕',
    '截图',
    '聊天',
    '表格',
    '课件',
    '试卷',
    '海报',
    '春联',
    '书页',
    '书本',
    '页面',
    '黑板',
    '广告',
    '专题',
  };

  static const String _amapWebKey = String.fromEnvironment(
    'AMAP_WEB_KEY',
    defaultValue: '7fe01f8a449b2aac28068feac9177316',
  );

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      responseType: ResponseType.json,
    ),
  );

  // 📊 聚类算法配置（旅游同日增强）
  static const ClusterConfig _clusterConfig = ClusterConfig(
    initialTimeThresholdHours: 4,
    baseDistanceThresholdKm: 12,
    sameCityTimeThresholdHours: 6,
    sameCityDistanceThresholdKm: 20,
    fallbackSameCityDistanceKm: 45,
    sameDayMergeGapHours: 10,
    crossDayMergeGapHours: 18,
    minPhotosPerClusterForMerge: 1,
    enableSameDayTravelMerge: true,
    enableCrossDayTravelMerge: true,
  );
  static const int minPhotosForDisplay = 5;
  static const int minPhotosForTimelineDisplay = 1;

  static bool shouldResolvePhotoLocation({
    required int eventPhotoCount,
    required bool isLocationProcessed,
    required double? latitude,
    required double? longitude,
  }) {
    return eventPhotoCount >= minPhotosForDisplay &&
        !isLocationProcessed &&
        latitude != null &&
        longitude != null;
  }

  // 🧮 核心方法：运行时空聚类算法
  Future<void> runClustering({
    int? maxPhotos,
  }) async {
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    final eventBox = store.box<EventEntity>();

    // 1. 读取照片
    final query = photoBox.query()
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    if (maxPhotos != null) query.limit = maxPhotos;
    final recentPhotos = query.find();
    query.close();

    if (recentPhotos.isEmpty) {
      print("⚠️ 没有照片可以聚类");
      return;
    }

    print(
      maxPhotos == null
          ? "🔍 开始聚类分析，共 ${recentPhotos.length} 张照片"
          : "🔍 开始聚类分析（最近 ${recentPhotos.length} 张照片）",
    );

    // 2. 反转为时间升序
    final photos = recentPhotos.reversed.toList();

    // 3. 聚类逻辑
    final clusterResult = EventClusterHelper.clusterPhotos(
      photos: photos,
      config: _clusterConfig,
    );
    final clusters = _splitClustersByLocalDay(clusterResult.clusters);

    print(
      "✅ 聚类完成: 初分簇=${clusterResult.initialClusterCount} 合并=${clusterResult.mergedCount} 最终事件=${clusters.length}",
    );

    // 4. 将聚类结果存入数据库并设置 eventId 反向关联
    store.runInTransaction(TxMode.write, () {
      // 清空旧 eventId
      final withEventQ = photoBox.query(PhotoEntity_.eventId.notNull()).build();
      final photosWithEvent = withEventQ.find();
      withEventQ.close();
      for (final photo in photosWithEvent) {
        photo.eventId = null;
      }
      photoBox.putMany(photosWithEvent);

      // 清空旧事件
      eventBox.removeAll();

      // 插入新事件并更新照片的 eventId
      final photosToUpdate = <PhotoEntity>[];
      for (final cluster in clusters) {
        final event = EventEntity.fromPhotos(cluster);
        final eventId = eventBox.put(event);
        for (final photo in cluster) {
          photo.eventId = eventId;
          photosToUpdate.add(photo);
        }
      }

      if (photosToUpdate.isNotEmpty) {
        photoBox.putMany(photosToUpdate);
      }
    });

    print("💾 事件已存入数据库，照片关联已建立");

    // 5. 启动地址解析
    _resolveEventLocations();
    _resolvePhotoLocationsForVisibleEvents();
  }

  Future<void> _resolveEventLocations() async {
    if (_amapWebKey.trim().isEmpty) {
      print("⚠️ AMAP_WEB_KEY 未配置，跳过地址解析");
      return;
    }

    final store = ObjectBoxService().store;
    final eventBox = store.box<EventEntity>();

    // 查询需要解析地址的事件（有GPS但还没有细粒度地点）
    final q = eventBox.query(
      EventEntity_.avgLatitude.notNull()
          .and(EventEntity_.photoCount.greaterThan(minPhotosForDisplay - 1))
          .and(EventEntity_.locationName.isNull()),
    ).build();
    q.limit = 10;
    final events = q.find();
    q.close();

    if (events.isEmpty) {
      print("✅ 所有事件地址已解析完成");
      return;
    }

    print("🌏 开始解析 ${events.length} 个事件地址...");

    for (final event in events) {
      try {
        print(
          "开始解析事件地址: id=${event.id} lat=${event.avgLatitude} lon=${event.avgLongitude}",
        );
        final regeocode = await _reverseGeocodeWithAmap(
          latitude: event.avgLatitude!,
          longitude: event.avgLongitude!,
          extensions: 'all',
        );
        final data = regeocode['addressComponent'];
        if (data is! Map<String, dynamic>) {
          throw Exception('高德返回缺少addressComponent');
        }

        final province = _extractNonEmptyString(data, ['province']);
        final district = _extractNonEmptyString(data, ['district']);
        String? city = _extractNonEmptyString(data, ['city']);
        city ??= district;
        city ??= province;
        final adcode = _extractNonEmptyString(data, ['adcode']);
        final citycode = _extractNonEmptyString(data, ['citycode']);
        final formattedAddress = _extractNonEmptyString(regeocode, ['formatted_address']);
        final locationName = _extractLocationName(
          regeocode,
          data,
          city: city,
          district: district,
          formattedAddress: formattedAddress,
        );

        store.runInTransaction(TxMode.write, () {
          final e = eventBox.get(event.id);
          if (e == null) return;
          e.province = province;
          e.city = city;
          e.district = district;
          e.locationName = locationName;
          e.formattedAddress = formattedAddress;
          final displayLocation = e.locationName ?? e.district ?? e.city ?? e.province;
          if ((displayLocation?.trim().isNotEmpty ?? false)) {
            e.title = "${displayLocation!.trim()} · ${e.dateRangeText}";
          }
          eventBox.put(e);
        });

        print(
          "📍 事件地址解析成功: ${event.title} -> ${locationName ?? district ?? city ?? province ?? '未知地点'} "
          "(adcode=${adcode ?? '-'} citycode=${citycode ?? '-'})",
        );
      } catch (e) {
        print("❌ 地址解析失败: $e");
      }

      await Future.delayed(const Duration(milliseconds: 1300));
    }

    _resolveEventLocations();
  }

  Future<void> _resolvePhotoLocationsForVisibleEvents() async {
    if (_amapWebKey.trim().isEmpty) {
      return;
    }

    final store = ObjectBoxService().store;
    final eventBox = store.box<EventEntity>();
    final photoBox = store.box<PhotoEntity>();

    final evQ = eventBox.query(
      EventEntity_.photoCount.greaterThan(minPhotosForDisplay - 1),
    ).build();
    final visibleEvents = evQ.find();
    evQ.close();
    if (visibleEvents.isEmpty) return;

    final eventIds = visibleEvents.map((e) => e.id).toList(growable: false);
    final eventPhotoCountById = {
      for (final event in visibleEvents) event.id: event.photoCount,
    };

    final photoQ = photoBox.query(
      PhotoEntity_.eventId.oneOf(eventIds)
          .and(PhotoEntity_.isLocationProcessed.equals(false))
          .and(PhotoEntity_.latitude.notNull())
          .and(PhotoEntity_.longitude.notNull()),
    ).build();
    photoQ.limit = 20;
    final photos = photoQ.find();
    photoQ.close();

    if (photos.isEmpty) return;

    print("🌏 开始逐图解析地址，本批次: ${photos.length} 张");

    for (final photo in photos) {
      final eventPhotoCount = eventPhotoCountById[photo.eventId];
      if (eventPhotoCount == null ||
          !shouldResolvePhotoLocation(
            eventPhotoCount: eventPhotoCount,
            isLocationProcessed: photo.isLocationProcessed,
            latitude: photo.latitude,
            longitude: photo.longitude,
          )) {
        continue;
      }

      final lat = photo.latitude;
      final lon = photo.longitude;
      if (lat == null || lon == null) continue;

      try {
        final regeocode = await _reverseGeocodeWithAmap(
          latitude: lat,
          longitude: lon,
          extensions: 'all',
        );
        final addressComponent = regeocode['addressComponent'];
        if (addressComponent is! Map<String, dynamic>) {
          throw Exception('高德返回缺少addressComponent');
        }

        final formattedAddress = _extractNonEmptyString(regeocode, ['formatted_address']);
        final district = _extractNonEmptyString(addressComponent, ['district']);
        final adcode = _extractNonEmptyString(addressComponent, ['adcode']);
        final province = _extractNonEmptyString(addressComponent, ['province']);
        String? city = _extractNonEmptyString(addressComponent, ['city']);
        city ??= district;
        city ??= province;
        final locationName = _extractLocationName(
          regeocode,
          addressComponent,
          city: city,
          district: district,
          formattedAddress: formattedAddress,
        );

        store.runInTransaction(TxMode.write, () {
          final latest = photoBox.get(photo.id);
          if (latest == null) return;
          latest.province = province;
          latest.city = city;
          latest.district = district;
          latest.locationName = locationName;
          latest.adcode = adcode;
          latest.formattedAddress = formattedAddress;
          latest.isLocationProcessed = true;
          photoBox.put(latest);
        });

        print(
          "📌 照片地址解析成功: id=${photo.id} location=${locationName ?? city ?? '-'} district=${district ?? '-'}",
        );
      } catch (e) {
        print("❌ 照片地址解析失败: id=${photo.id} error=$e");
      }

      await Future.delayed(const Duration(milliseconds: 450));
    }

    _resolvePhotoLocationsForVisibleEvents();
  }

  Future<Map<String, dynamic>> _reverseGeocodeWithAmap({
    required double latitude,
    required double longitude,
    String extensions = 'base',
  }) async {
    final response = await _dio.get(
      'https://restapi.amap.com/v3/geocode/regeo',
      queryParameters: {
        'key': _amapWebKey,
        'location': '$longitude,$latitude',
        'extensions': extensions,
        'coordsys': 'gps',
      },
    );

    final body = response.data;

    print("高德地图返回值${jsonEncode(body)}");

    if (body is! Map<String, dynamic>) {
      throw Exception('高德返回格式异常');
    }

    if (body['status'] != '1') {
      throw Exception('高德返回失败: ${body['info'] ?? '未知错误'}');
    }

    final regeocode = body['regeocode'];
    if (regeocode is! Map<String, dynamic>) {
      throw Exception('高德返回缺少regeocode');
    }
    return regeocode;
  }

  String? _extractNonEmptyString(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is String && first.trim().isNotEmpty) {
          return first.trim();
        }
      }
    }
    return null;
  }

  String? _extractLocationName(
    Map<String, dynamic> regeocode,
    Map<String, dynamic> addressComponent, {
    String? city,
    String? district,
    String? formattedAddress,
  }) {
    final poi = regeocode['pois'];
    if (poi is List && poi.isNotEmpty) {
      final firstPoi = poi.first;
      if (firstPoi is Map<String, dynamic>) {
        final poiName = _extractNonEmptyString(firstPoi, ['name']);
        if (_isUsefulLocationName(poiName, city: city, district: district)) {
          return poiName;
        }
      }
    }

    final aois = regeocode['aois'];
    if (aois is List && aois.isNotEmpty) {
      final firstAoi = aois.first;
      if (firstAoi is Map<String, dynamic>) {
        final aoiName = _extractNonEmptyString(firstAoi, ['name']);
        if (_isUsefulLocationName(aoiName, city: city, district: district)) {
          return aoiName;
        }
      }
    }

    final building = addressComponent['building'];
    if (building is Map<String, dynamic>) {
      final buildingName = _extractNonEmptyString(building, ['name']);
      if (_isUsefulLocationName(buildingName, city: city, district: district)) {
        return buildingName;
      }
    }

    final neighborhood = addressComponent['neighborhood'];
    if (neighborhood is Map<String, dynamic>) {
      final neighborhoodName = _extractNonEmptyString(neighborhood, ['name']);
      if (_isUsefulLocationName(neighborhoodName, city: city, district: district)) {
        return neighborhoodName;
      }
    }

    final formattedAddressName = _extractLocationNameFromFormattedAddress(
      formattedAddress,
      addressComponent,
      city: city,
      district: district,
    );
    if (_isUsefulLocationName(
      formattedAddressName,
      city: city,
      district: district,
    )) {
      return formattedAddressName;
    }

    final township = _extractNonEmptyString(addressComponent, ['township']);
    if (_isUsefulLocationName(township, city: city, district: district)) {
      return township;
    }

    return district ?? city;
  }

  String? _extractLocationNameFromFormattedAddress(
    String? formattedAddress,
    Map<String, dynamic> addressComponent, {
    String? city,
    String? district,
  }) {
    if (formattedAddress == null) {
      return null;
    }

    var candidate = formattedAddress.trim();
    if (candidate.isEmpty) {
      return null;
    }

    final province = _extractNonEmptyString(addressComponent, ['province']);
    final township = _extractNonEmptyString(addressComponent, ['township']);
    final streetName = _extractStreetName(addressComponent);
    final prefixes = <String>{
      if (province != null && province.isNotEmpty) province,
      if (city != null && city.isNotEmpty) city,
      if (district != null && district.isNotEmpty) district,
      if (township != null && township.isNotEmpty) township,
      if (streetName != null && streetName.isNotEmpty) streetName,
    }.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    var changed = true;
    while (changed && candidate.isNotEmpty) {
      changed = false;
      for (final prefix in prefixes) {
        if (candidate.startsWith(prefix)) {
          candidate = candidate.substring(prefix.length).trim();
          changed = true;
        }
      }
      candidate = candidate.replaceFirst(RegExp(r'^[,，\s]+'), '').trim();
    }

    if (_isUsefulLocationName(candidate, city: city, district: district)) {
      return candidate;
    }

    return null;
  }

  String? _extractStreetName(Map<String, dynamic> addressComponent) {
    final streetName = _extractNonEmptyString(addressComponent, ['street']);
    if (streetName != null && streetName.isNotEmpty) {
      return streetName;
    }

    final streetNumber = addressComponent['streetNumber'];
    if (streetNumber is Map<String, dynamic>) {
      return _extractNonEmptyString(streetNumber, ['street', 'name']);
    }

    return null;
  }

  bool _isUsefulLocationName(String? value, {String? city, String? district}) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return false;
    }

    if (normalized == city || normalized == district) {
      return false;
    }

    const ignored = <String>{'[]', '[[]]'};
    if (ignored.contains(normalized)) {
      return false;
    }

    return true;
  }

  Future<Map<String, int>> getEventStats() async {
    final eventBox = ObjectBoxService().store.box<EventEntity>();
    final total = eventBox.count();
    final withLocationQ = eventBox.query(EventEntity_.city.notNull()).build();
    final withLocation = withLocationQ.count();
    withLocationQ.close();
    return {'total': total, 'withLocation': withLocation};
  }

  Stream<List<EventEntity>> watchEvents() {
    final eventBox = ObjectBoxService().store.box<EventEntity>();
    return eventBox.query().watch(triggerImmediately: true).map((query) {
      final events = query.find()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));
      return events
          .where((event) => event.photoCount >= minPhotosForTimelineDisplay)
          .toList();
    });
  }

  // 🧠 核心方法：增量刷新事件的智能信息（混合标题生成）
  // 此方法由 AIService 在分析完一批照片后调用
  List<List<PhotoEntity>> _splitClustersByLocalDay(
    List<List<PhotoEntity>> clusters,
  ) {
    final buckets = <String, List<PhotoEntity>>{};
    for (final cluster in clusters) {
      if (cluster.isEmpty) {
        continue;
      }
      for (final photo in cluster) {
        final key = _localDayKey(photo.timestamp);
        buckets.putIfAbsent(key, () => <PhotoEntity>[]).add(photo);
      }
    }

    final orderedKeys = buckets.keys.toList()..sort();
    final dayGroups = orderedKeys
        .map((key) {
          final group =
              buckets[key]!..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          return _DayPhotoGroup(dateKey: key, photos: group);
        })
        .toList(growable: false);

    final mergedGroups = <List<PhotoEntity>>[];
    var index = 0;
    while (index < dayGroups.length) {
      final current = dayGroups[index];
      if (current.photos.length <= 5 && index + 1 < dayGroups.length) {
        final next = dayGroups[index + 1];
        if (_isAdjacentDay(current.dateKey, next.dateKey)) {
          final merged = <PhotoEntity>[
            ...current.photos,
            ...next.photos,
          ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          mergedGroups.add(merged);
          index += 2;
          continue;
        }
      }

      mergedGroups.add(current.photos);
      index += 1;
    }

    mergedGroups.sort((a, b) => b.first.timestamp.compareTo(a.first.timestamp));
    return mergedGroups;
  }

  String _localDayKey(int timestampMs) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  bool _isAdjacentDay(String earlier, String later) {
    final start = DateTime.parse(earlier);
    final end = DateTime.parse(later);
    return end.difference(start).inDays == 1;
  }

  Future<void> refreshEventSmartInfo(
    List<int> eventIds, {
    bool allowLlm = true,
  }) async {
    if (eventIds.isEmpty) return;

    final store = ObjectBoxService().store;
    final eventBox = store.box<EventEntity>();
    final photoBox = store.box<PhotoEntity>();

    print("🧠 开始刷新 ${eventIds.length} 个事件的智能信息...");

    for (final eventId in eventIds) {
      try {
        final event = eventBox.get(eventId);
        if (event == null) continue;
        if (event.photoCount < minPhotosForDisplay) {
          print("  ℹ️ 事件 $eventId 照片数(${event.photoCount})低于展示阈值，跳过智能信息刷新");
          continue;
        }

        final analyzedQ = photoBox.query(
          PhotoEntity_.eventId.equals(eventId)
              .and(PhotoEntity_.isAiAnalyzed.equals(true)),
        ).build();
        final analyzedPhotos = analyzedQ.find();
        analyzedQ.close();

        if (analyzedPhotos.isEmpty) {
          print("  ⚠️ 事件 $eventId 暂无已分析照片，跳过");
          continue;
        }

        final stats = _calculateEventStats(analyzedPhotos);
        final progress = SmartTitleGenerator.calculateProgress(
          stats['analyzedCount'] as int,
          event.photoCount,
        );

        List<String> generatedTitles;
        bool shouldUseLLM = false;

        if (allowLlm && progress >= 100) {
          shouldUseLLM = true;
          if (event.isLlmGenerated) {
            print("  ℹ️ 事件 $eventId 已有 LLM 标题，跳过重复生成");
            continue;
          }
        }

        final topTags = _extractTopTags(stats, 5);
        var isLlmGenerated = false;
        if (shouldUseLLM) {
          try {
            final llmService = LLMService();
            if (llmService.isApiKeyConfigured) {
              generatedTitles = await llmService.generateCreativeTitles(event, topTags);
            } else {
              print("  ⚠️ LLM API Key 未配置，使用模拟模式");
              generatedTitles = await llmService.generateCreativeTitlesMock(event, topTags);
            }
            isLlmGenerated = true;
            print("  🎨 [LLM] 生成 ${generatedTitles.length} 个创意标题");
          } catch (llmError) {
            print("  ❌ LLM 生成失败: $llmError，回退到本地规则");
            generatedTitles = [_generateLocalTitle(event, stats)];
          }
        } else {
          generatedTitles = [_generateLocalTitle(event, stats)];
          print("  🏠 [本地] 生成规则标题: ${generatedTitles.first} (进度: $progress%)");
        }

        store.runInTransaction(TxMode.write, () {
          final e = eventBox.get(eventId);
          if (e == null) return;
          e.joyScore = stats['avgJoyScore'];
          e.analyzedPhotoCount = stats['analyzedCount'] as int;
          e.coverPhotoId = stats['bestPhotoId'] as int?;
          e.tags = topTags;
          e.aiThemes = generatedTitles;
          e.isLlmGenerated = isLlmGenerated;
          if (generatedTitles.isNotEmpty) {
            e.title = generatedTitles.first;
          }
          eventBox.put(e);
          print(
            "  ✅ 事件 $eventId 已更新：封面=${e.coverPhotoId} 欢乐=${e.joyScore?.toStringAsFixed(2)} 进度=$progress%",
          );
        });
      } catch (e) {
        print("  ❌ 刷新事件 $eventId 失败: $e");
      }
    }

    print("🎉 智能信息刷新完成");
  }

  // 🏠 生成本地规则标题
  String _generateLocalTitle(EventEntity event, Map<String, dynamic> stats) {
    final date = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final topTag = stats['topTag'] as String?;
    final joyScore = stats['avgJoyScore'] as double?;

    return SmartTitleGenerator.generate(
      date: date,
      city: event.locationName ?? event.district ?? event.city,
      province: event.province,
      topTag: topTag,
      joyScore: joyScore,
    );
  }

  // 🏷️ 从统计数据中提取前 N 个标签
  List<String> _extractTopTags(Map<String, dynamic> stats, int count) {
    final tagCounts = stats['tagCounts'] as Map<String, int>?;
    if (tagCounts == null || tagCounts.isEmpty) return [];

    final sortedTags = tagCounts.entries.toList()
      ..removeWhere(
        (entry) =>
            _blockedSmartTitleTags.contains(entry.key) ||
            TagSanitizer.isBlockedExactTag(entry.key),
      )
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedTags.take(count).map((e) => e.key).toList();
  }

  // 📊 计算事件统计数据
  Map<String, dynamic> _calculateEventStats(List<PhotoEntity> photos) {
    if (photos.isEmpty) {
      return {
        'analyzedCount': 0,
        'avgJoyScore': null,
        'topTag': null,
        'topTagRatio': 0.0,
        'tagCounts': <String, int>{},
        'bestPhotoId': null,
      };
    }

    // 统计1：已分析照片数量
    final analyzedCount = photos.length;

    // 统计2：平均欢乐值
    final joyScores = photos
        .where((p) => p.joyScore != null)
        .map((p) => p.joyScore!)
        .toList();

    final avgJoyScore = joyScores.isNotEmpty
        ? joyScores.reduce((a, b) => a + b) / joyScores.length
        : null;

    // 统计3：标签频率（找出最高频标签）
    final Map<String, int> tagCounts = {};
    for (final photo in photos) {
      for (final tag in _effectiveTagsForEventStats(photo)) {
        if (_blockedSmartTitleTags.contains(tag)) {
          continue;
        }
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
    }

    String? topTag;
    double topTagRatio = 0.0;
    if (tagCounts.isNotEmpty) {
      final sortedTags = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      topTag = sortedTags.first.key;
      topTagRatio = sortedTags.first.value / analyzedCount;
    }

    // 统计4：最佳照片（最高 joyScore）
    int? bestPhotoId;
    double maxJoy = 0.0;
    for (final photo in photos) {
      if (photo.joyScore != null && photo.joyScore! > maxJoy) {
        maxJoy = photo.joyScore!;
        bestPhotoId = photo.id;
      }
    }

    return {
      'analyzedCount': analyzedCount,
      'avgJoyScore': avgJoyScore,
      'topTag': topTag,
      'topTagRatio': topTagRatio,
      'tagCounts': tagCounts, // 返回完整的标签统计，供 LLM 使用
      'bestPhotoId': bestPhotoId,
    };
  }

  List<String> _effectiveTagsForEventStats(PhotoEntity photo) {
    final aiTags = TagSanitizer.sanitizeVisualTags(
      photo.aiTags ?? const <String>[],
    ).where((tag) => !_blockedSmartTitleTags.contains(tag)).toList(
      growable: false,
    );
    final ocrTags = OcrPolicy.effectiveTags(
      photo.ocrTags ?? const <String>[],
    ).where((tag) => !_blockedSmartTitleTags.contains(tag)).toList(
      growable: false,
    );

    if (_isTextHeavyPhoto(photo, aiTags: aiTags, ocrTags: ocrTags)) {
      final textTags = <String>[];

      void addTag(String value) {
        if (value.isEmpty || textTags.contains(value)) {
          return;
        }
        textTags.add(value);
      }

      for (final tag in aiTags) {
        if (_textSceneTags.contains(tag)) {
          addTag(tag);
        }
      }

      for (final tag in ocrTags) {
        if (_looksUsefulOcrTag(tag)) {
          addTag(tag);
        }
      }

      if (photo.isProbablyScreenshot) {
        addTag('截图');
      }

      if (textTags.isEmpty) {
        addTag(photo.isProbablyScreenshot ? '屏幕' : '文字');
      }

      return textTags.take(5).toList(growable: false);
    }

    return aiTags.take(5).toList(growable: false);
  }

  bool _isTextHeavyPhoto(
    PhotoEntity photo, {
    required List<String> aiTags,
    required List<String> ocrTags,
  }) {
    final ocrText = OcrPolicy.effectiveText(photo.ocrText);
    final textLikeAiCount = aiTags.where(_textSceneTags.contains).length;

    return photo.isProbablyScreenshot ||
        ocrTags.length >= 2 ||
        ocrText.length >= 12 ||
        textLikeAiCount >= 2;
  }

  bool _looksUsefulOcrTag(String tag) {
    if (_textSceneTags.contains(tag)) {
      return true;
    }

    if (tag.length < 2 || tag.length > 16) {
      return false;
    }

    if (RegExp(r'^[A-Za-z0-9_./-]+$').hasMatch(tag)) {
      return false;
    }

    return true;
  }
}

class _DayPhotoGroup {
  const _DayPhotoGroup({
    required this.dateKey,
    required this.photos,
  });

  final String dateKey;
  final List<PhotoEntity> photos;
}
