import 'package:objectbox/objectbox.dart';

@Entity()
class CreateRecommendationEntity {
  @Id()
  int id = 0;

  @Unique(onConflict: ConflictStrategy.replace)
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
