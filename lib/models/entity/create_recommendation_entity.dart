import 'package:isar/isar.dart';

/// 推荐生成记录的 ObjectBox 实体，保存预设类型和生成元数据。

part 'create_recommendation_entity.g.dart';

@Collection()
class CreateRecommendationEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String recommendationKey;

  @Index()
  late String presetId;

  late String group;
  late String label;
  late String title;
  late String subtitle;
  late String query;

  List<int> photoIds = <int>[];
  List<int> coverPhotoIds = <int>[];

  int matchedCount = 0;
  int priority = 0;

  late int createdAt;
  late int updatedAt;
  int? lastCheckedAt;
  int? lastRecommendedAt;
  int? nextCheckAt;

  @Index()
  late String status;

  String? resultFingerprint;

  bool get isActive => status == CreateRecommendationStatus.active;
}

abstract final class CreateRecommendationStatus {
  static const String active = 'active';
  static const String dismissed = 'dismissed';
  static const String expired = 'expired';
  static const String archived = 'archived';
}
