import 'package:objectbox/objectbox.dart';

@Entity()
class GeoCellCacheEntity {
  @Id()
  int id = 0;

  @Unique(onConflict: ConflictStrategy.replace)
  late String lookupKey;
  @Index()
  late String cellKey;
  @Index()
  int level = 0;
  int centerLatAmapE6 = 0;
  int centerLonAmapE6 = 0;
  String? country;
  String? province;
  String? city;
  String? district;
  String? adcode;
  String? township;
  String? locationName;
  String? formattedAddress;
  String? businessAreaText;
  String? aoiIdText;
  String? aoiSummaryText;
  String? poiIdText;
  String? poiSummaryText;
  String? geoTextTokens;
  String? rawCompactJson;
  int updatedAt = 0;
  String source = 'amap_regeo';
}
