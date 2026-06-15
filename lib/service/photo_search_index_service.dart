import '../models/entity/photo_entity.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import 'geo_coordinate_service.dart';

class PhotoSearchIndexService {
  PhotoSearchIndexService._();

  static const int currentVersion = 2;
  static Future<void>? _backfillInFlight;

  static bool updateTimeFields(PhotoEntity photo) {
    final timestamp = normalizeTimestampMs(photo.timestamp);
    if (timestamp <= 0) {
      if (photo.searchIndexVersion == currentVersion) return false;
      photo.searchIndexVersion = currentVersion;
      return true;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final dayOfYear = date.difference(DateTime(date.year)).inDays + 1;
    final changed =
        photo.capturedAtMillis != timestamp ||
        photo.capturedYear != date.year ||
        photo.capturedMonth != date.month ||
        photo.capturedDay != date.day ||
        photo.capturedDayOfYear != dayOfYear ||
        photo.capturedMinuteOfDay != date.hour * 60 + date.minute ||
        photo.capturedWeekday != date.weekday ||
        photo.searchIndexVersion != currentVersion;
    if (!changed) return false;

    photo
      ..capturedAtMillis = timestamp
      ..capturedYear = date.year
      ..capturedMonth = date.month
      ..capturedDay = date.day
      ..capturedDayOfYear = dayOfYear
      ..capturedMinuteOfDay = date.hour * 60 + date.minute
      ..capturedWeekday = date.weekday
      ..searchIndexVersion = currentVersion;
    return true;
  }

  static bool updateCoordinateFields(PhotoEntity photo) {
    final latitude = photo.latitude;
    final longitude = photo.longitude;
    if (latitude == null || longitude == null) return false;
    final amap = GeoCoordinateService.wgs84ToGcj02(latitude, longitude);
    final fine = GeoCoordinateService.cellKey(amap.latitude, amap.longitude, 3);
    final mid = GeoCoordinateService.cellKey(amap.latitude, amap.longitude, 2);
    final coarse = GeoCoordinateService.cellKey(
      amap.latitude,
      amap.longitude,
      1,
    );
    final changed =
        photo.latAmapE6 != amap.latitudeE6 ||
        photo.lonAmapE6 != amap.longitudeE6 ||
        photo.geoCellFine != fine ||
        photo.geoCellMid != mid ||
        photo.geoCellCoarse != coarse;
    if (!changed) return false;
    photo
      ..latAmapE6 = amap.latitudeE6
      ..lonAmapE6 = amap.longitudeE6
      ..geoCellFine = fine
      ..geoCellMid = mid
      ..geoCellCoarse = coarse;
    return true;
  }

  static int normalizeTimestampMs(int timestamp) {
    if (timestamp > 0 && timestamp < 10000000000) return timestamp * 1000;
    return timestamp;
  }

  static Future<void> backfillMissingIndexes({int batchSize = 500}) async {
    final active = _backfillInFlight;
    if (active != null) {
      await active;
      return;
    }
    final future = _runBackfill(batchSize);
    _backfillInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_backfillInFlight, future)) _backfillInFlight = null;
    }
  }

  static Future<void> _runBackfill(int batchSize) async {
    final box = ObjectBoxService().store.box<PhotoEntity>();
    while (true) {
      final query =
          box
              .query(PhotoEntity_.searchIndexVersion.notEquals(currentVersion))
              .build()
            ..limit = batchSize;
      final photos = query.find();
      query.close();
      if (photos.isEmpty) return;

      final changed = photos.where(updateTimeFields).toList();
      for (final photo in photos) {
        if (updateCoordinateFields(photo) && !changed.contains(photo)) {
          changed.add(photo);
        }
      }
      if (changed.isEmpty) return;
      box.putMany(changed);
      await Future<void>.delayed(Duration.zero);
    }
  }
}
