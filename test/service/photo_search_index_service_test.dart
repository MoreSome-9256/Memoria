import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/service/photo_search_index_service.dart';

void main() {
  test('derives all mechanical time indexes from timestamp', () {
    final time = DateTime(2026, 6, 15, 19, 42);
    final photo = PhotoEntity()..timestamp = time.millisecondsSinceEpoch;

    expect(PhotoSearchIndexService.updateTimeFields(photo), isTrue);
    expect(photo.capturedAtMillis, time.millisecondsSinceEpoch);
    expect(photo.capturedYear, 2026);
    expect(photo.capturedMonth, 6);
    expect(photo.capturedDay, 15);
    expect(photo.capturedDayOfYear, 166);
    expect(photo.capturedMinuteOfDay, 19 * 60 + 42);
    expect(photo.capturedWeekday, DateTime.monday);
    expect(photo.searchIndexVersion, PhotoSearchIndexService.currentVersion);
    expect(PhotoSearchIndexService.updateTimeFields(photo), isFalse);
  });

  test('normalizes legacy second timestamps', () {
    final time = DateTime(2025, 1, 2, 3, 4);
    final photo = PhotoEntity()
      ..timestamp = time.millisecondsSinceEpoch ~/ 1000;

    PhotoSearchIndexService.updateTimeFields(photo);

    expect(photo.capturedAtMillis, time.millisecondsSinceEpoch);
    expect(photo.capturedYear, 2025);
    expect(photo.capturedMinuteOfDay, 184);
  });
}
