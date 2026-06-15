import 'package:objectbox/objectbox.dart';

@Entity()
class PlaceResolveCacheEntity {
  @Id()
  int id = 0;

  @Unique(onConflict: ConflictStrategy.replace)
  late String lookupKey;
  @Index()
  late String normalizedText;
  String? queryText;
  String? cityHint;
  String? adcodeHint;
  @Index()
  String resolvedKind = 'poi';
  String? canonicalName;
  @Index()
  String? amapPoiId;
  @Index()
  String? amapAoiId;
  String? province;
  String? city;
  String? district;
  String? adcode;
  int? centerLatAmapE6;
  int? centerLonAmapE6;
  int coreRadiusMeters = 2500;
  int softRadiusMeters = 8000;
  String? aliasesText;
  double confidence = 0;
  int updatedAt = 0;
}
