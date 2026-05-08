/// 垃圾照片清理服务，负责筛选、确认和清除低价值照片。

import 'dart:async';

import '../models/entity/event_entity.dart';
import '../models/entity/photo_entity.dart';
import 'event_service.dart';
import 'junk_photo_filter_service.dart';
import 'photo_service.dart';

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

    for (final candidate in candidates) {
      final photo = await PhotoService().isar
          .collection<PhotoEntity>()
          .get(candidate.photoId);
      if (photo == null) {
        continue;
      }
      final affectedEventId = await removeFromLocalIndex(photo);
      if (affectedEventId != null) {
        affectedEventIds.add(affectedEventId);
      }
      removedCount++;
    }

    if (affectedEventIds.isNotEmpty) {
      unawaited(
        EventService()
            .refreshEventSmartInfo(
              affectedEventIds.toList(),
              allowLlm: false,
            )
            .catchError((error) {
              // Keep cleanup fast; local event title refresh can fail independently.
            }),
      );
    }

    return removedCount;
  }

  Future<int?> removeFromLocalIndex(PhotoEntity photo) async {
    final isar = PhotoService().isar;
    var affectedEventId = photo.eventId;

    await isar.writeTxn(() async {
      final currentPhoto = await isar.collection<PhotoEntity>().get(photo.id);
      if (currentPhoto == null) {
        affectedEventId = null;
        return;
      }

      final currentEventId = currentPhoto.eventId;
      await isar.collection<PhotoEntity>().delete(currentPhoto.id);

      if (currentEventId == null) {
        affectedEventId = null;
        return;
      }

      final event = await isar.collection<EventEntity>().get(currentEventId);
      if (event == null) {
        affectedEventId = null;
        return;
      }

      final remainingIds = event.photoIds
          .where((photoId) => photoId != currentPhoto.id)
          .toList(growable: false);
      final remainingPhotos = (await isar
              .collection<PhotoEntity>()
              .getAll(remainingIds))
          .whereType<PhotoEntity>()
          .toList(growable: false)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (remainingPhotos.isEmpty) {
        await isar.collection<EventEntity>().delete(currentEventId);
        affectedEventId = null;
        return;
      }

      final rebuilt = EventEntity.fromPhotos(remainingPhotos)..id = event.id;
      rebuilt.aiThemes = null;
      rebuilt.isLlmGenerated = false;
      rebuilt.analyzedPhotoCount = remainingPhotos
          .where((item) => item.isAiAnalyzed)
          .length;
      await isar.collection<EventEntity>().put(rebuilt);
      affectedEventId = currentEventId;
    });

    return affectedEventId;
  }
}
