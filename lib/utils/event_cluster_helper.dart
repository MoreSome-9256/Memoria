import 'dart:math';

import '../models/entity/photo_entity.dart';

class ClusterConfig {
  final int initialTimeThresholdHours;
  final double baseDistanceThresholdKm;
  final int sameCityTimeThresholdHours;
  final double sameCityDistanceThresholdKm;
  final double fallbackSameCityDistanceKm;
  final int sameDayMergeGapHours;
  final int crossDayMergeGapHours;
  final int minPhotosPerClusterForMerge;
  final bool enableSameDayTravelMerge;
  final bool enableCrossDayTravelMerge;

  const ClusterConfig({
    this.initialTimeThresholdHours = 3,
    this.baseDistanceThresholdKm = 8,
    this.sameCityTimeThresholdHours = 6,
    this.sameCityDistanceThresholdKm = 20,
    this.fallbackSameCityDistanceKm = 45,
    this.sameDayMergeGapHours = 8,
    this.crossDayMergeGapHours = 18,
    this.minPhotosPerClusterForMerge = 3,
    this.enableSameDayTravelMerge = true,
    this.enableCrossDayTravelMerge = true,
  });
}

class ClusterResult {
  final List<List<PhotoEntity>> clusters;
  final int initialClusterCount;
  final int mergedCount;

  const ClusterResult({
    required this.clusters,
    required this.initialClusterCount,
    required this.mergedCount,
  });
}

class EventClusterHelper {
  const EventClusterHelper._();

  static ClusterResult clusterPhotos({
    required List<PhotoEntity> photos,
    ClusterConfig config = const ClusterConfig(),
  }) {
    if (photos.isEmpty) {
      return const ClusterResult(
        clusters: [],
        initialClusterCount: 0,
        mergedCount: 0,
      );
    }

    final initialClusters = _initialSplit(photos: photos, config: config);
    final mergedClusters = config.enableSameDayTravelMerge
        ? _mergeSameDayTravelClusters(clusters: initialClusters, config: config)
        : initialClusters;

    return ClusterResult(
      clusters: mergedClusters,
      initialClusterCount: initialClusters.length,
      mergedCount: initialClusters.length - mergedClusters.length,
    );
  }

  static List<List<PhotoEntity>> _initialSplit({
    required List<PhotoEntity> photos,
    required ClusterConfig config,
  }) {
    final clusters = <List<PhotoEntity>>[];
    var currentCluster = <PhotoEntity>[photos.first];

    for (var i = 1; i < photos.length; i++) {
      final prev = photos[i - 1];
      final curr = photos[i];
      final timeDiff = (curr.timestamp - prev.timestamp) / (1000 * 60 * 60);

      final shouldSplit = _shouldSplitByPair(
        prev: prev,
        curr: curr,
        timeDiffHours: timeDiff,
        config: config,
      );

      if (shouldSplit) {
        clusters.add(currentCluster);
        currentCluster = <PhotoEntity>[curr];
      } else {
        currentCluster.add(curr);
      }
    }

    if (currentCluster.isNotEmpty) {
      clusters.add(currentCluster);
    }

    return clusters;
  }

  static List<List<PhotoEntity>> _mergeSameDayTravelClusters({
    required List<List<PhotoEntity>> clusters,
    required ClusterConfig config,
  }) {
    if (clusters.length <= 1) {
      return clusters;
    }

    final merged = <List<PhotoEntity>>[List<PhotoEntity>.from(clusters.first)];

    for (var i = 1; i < clusters.length; i++) {
      final lastCluster = merged.last;
      final currentCluster = clusters[i];

      if (_shouldMergeClusters(
        left: lastCluster,
        right: currentCluster,
        config: config,
      )) {
        lastCluster.addAll(currentCluster);
      } else {
        merged.add(List<PhotoEntity>.from(currentCluster));
      }
    }

    return merged;
  }

  static bool _shouldMergeClusters({
    required List<PhotoEntity> left,
    required List<PhotoEntity> right,
    required ClusterConfig config,
  }) {
    if (left.length < config.minPhotosPerClusterForMerge ||
        right.length < config.minPhotosPerClusterForMerge) {
      return false;
    }

    final leftEnd = left.last;
    final rightStart = right.first;
    final gapHours =
        (rightStart.timestamp - leftEnd.timestamp) / (1000 * 60 * 60);
    final isSameDay = _isSameLocalDay(leftEnd.timestamp, rightStart.timestamp);
    final mergeGapThreshold = isSameDay
        ? config.sameDayMergeGapHours
        : config.crossDayMergeGapHours;

    if (gapHours > mergeGapThreshold) {
      return false;
    }

    if (!isSameDay && !config.enableCrossDayTravelMerge) {
      return false;
    }

    // 已识别为跨城的相邻簇不合并
    if (_isCrossCity(leftEnd, rightStart, config: config)) {
      return false;
    }

    return true;
  }

  static bool _shouldSplitByPair({
    required PhotoEntity prev,
    required PhotoEntity curr,
    required double timeDiffHours,
    required ClusterConfig config,
  }) {
    if (_isCrossCity(prev, curr, config: config)) {
      return true;
    }

    final hasBothGps = _hasGps(prev) && _hasGps(curr);
    final sameCity = _isSameCity(prev, curr, config: config);

    final timeThreshold = sameCity
        ? config.sameCityTimeThresholdHours
        : config.initialTimeThresholdHours;
    if (timeDiffHours > timeThreshold) {
      return true;
    }

    if (!hasBothGps) {
      return false;
    }

    final distance = _calculateDistance(
      prev.latitude!,
      prev.longitude!,
      curr.latitude!,
      curr.longitude!,
    );
    final distanceThreshold = sameCity
        ? config.sameCityDistanceThresholdKm
        : config.baseDistanceThresholdKm;
    return distance > distanceThreshold;
  }

  static bool _hasGps(PhotoEntity photo) {
    return photo.latitude != null && photo.longitude != null;
  }

  static bool _isSameLocalDay(int ts1, int ts2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ts1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ts2);
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  static bool _isCrossCity(
    PhotoEntity a,
    PhotoEntity b, {
    required ClusterConfig config,
  }) {
    final aCityKey = _cityKey(a);
    final bCityKey = _cityKey(b);
    if (aCityKey != null && bCityKey != null) {
      return aCityKey != bCityKey;
    }

    if (_hasGps(a) && _hasGps(b)) {
      final distance = _calculateDistance(
        a.latitude!,
        a.longitude!,
        b.latitude!,
        b.longitude!,
      );
      return distance > config.fallbackSameCityDistanceKm;
    }

    return false;
  }

  static bool _isSameCity(
    PhotoEntity a,
    PhotoEntity b, {
    required ClusterConfig config,
  }) {
    final aCityKey = _cityKey(a);
    final bCityKey = _cityKey(b);
    if (aCityKey != null && bCityKey != null) {
      return aCityKey == bCityKey;
    }

    if (_hasGps(a) && _hasGps(b)) {
      final distance = _calculateDistance(
        a.latitude!,
        a.longitude!,
        b.latitude!,
        b.longitude!,
      );
      return distance <= config.fallbackSameCityDistanceKm;
    }

    return false;
  }

  static String? _cityKey(PhotoEntity photo) {
    if (photo.adcode != null && photo.adcode!.trim().isNotEmpty) {
      return 'adcode:${photo.adcode!.trim()}';
    }

    final city = photo.city?.trim();
    final province = photo.province?.trim();
    if (city != null && city.isNotEmpty) {
      return 'city:${province ?? ''}/$city';
    }

    return null;
  }

  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRadians(double degree) {
    return degree * pi / 180;
  }
}
