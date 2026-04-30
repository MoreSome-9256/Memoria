import 'dart:async';

import '../models/entity/event_entity.dart';
import '../models/entity/photo_entity.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import 'event_service.dart';
import 'junk_photo_filter_service.dart';

class JunkPhotoCleanupService {
  JunkPhotoCleanupService._internal();

  static final JunkPhotoCleanupService _instance =
      JunkPhotoCleanupService._internal();

  factory JunkPhotoCleanupService() => _instance;

  Future<int> removeCandidatesFromLocalIndex(
    Iterable<JunkPhotoCleanupCandidate> candidates,
  ) async {
    final affectedEventIds = <int>{};
    var removedCount = 0;

    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    for (final candidate in candidates) {
      final photo = photoBox.get(candidate.photoId);
      if (photo == null) continue;
      final affectedEventId = await removeFromLocalIndex(photo);
      if (affectedEventId != null) {
        affectedEventIds.add(affectedEventId);
      }
      removedCount++;
    }

    if (affectedEventIds.isNotEmpty) {
      unawaited(
        EventService()
            .refreshEventSmartInfo(affectedEventIds.toList(), allowLlm: false)
            .catchError((error) {}),
      );
    }

    return removedCount;
  }

  Future<int?> removeFromLocalIndex(PhotoEntity photo) async {
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    final eventBox = store.box<EventEntity>();
    var affectedEventId = photo.eventId;

    store.runInTransaction(TxMode.write, () {
      final currentPhoto = photoBox.get(photo.id);
      if (currentPhoto == null) {
        affectedEventId = null;
        return;
      }

      final currentEventId = currentPhoto.eventId;
      photoBox.remove(currentPhoto.id);

      if (currentEventId == null) {
        affectedEventId = null;
        return;
      }

      final event = eventBox.get(currentEventId);
      if (event == null) {
        affectedEventId = null;
        return;
      }

      final remainingIds = event.photoIds
          .where((photoId) => photoId != currentPhoto.id)
          .toList(growable: false);
      final remainingPhotos = photoBox.getMany(remainingIds)
          .whereType<PhotoEntity>()
          .toList(growable: false)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (remainingPhotos.isEmpty) {
        eventBox.remove(currentEventId);
        affectedEventId = null;
        return;
      }

      final rebuilt = EventEntity.fromPhotos(remainingPhotos)..id = event.id;
      rebuilt.aiThemes = null;
      rebuilt.isLlmGenerated = false;
      rebuilt.analyzedPhotoCount = remainingPhotos
          .where((item) => item.isAiAnalyzed)
          .length;
      eventBox.put(rebuilt);
      affectedEventId = currentEventId;
    });

    return affectedEventId;
  }
}
