/// 垃圾照片清理服务，负责筛选、确认、标记和必要的本地清除。

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

  Future<int> markCandidatesAsLowValue(
    Iterable<JunkPhotoCleanupCandidate> candidates,
  ) async {
    final candidateIds = candidates
        .map((candidate) => candidate.photoId)
        .where((id) => id > 0)
        .toSet()
        .toList(growable: false);
    if (candidateIds.isEmpty) {
      return 0;
    }

    final affectedEventIds = <int>{};
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final photos = photoBox
        .getMany(candidateIds)
        .whereType<PhotoEntity>()
        .toList(growable: false);
    if (photos.isEmpty) {
      return 0;
    }

    for (final photo in photos) {
      final tags =
          <String>{...?photo.aiTags, JunkPhotoFilterService.junkCandidateTag}
            ..remove(JunkPhotoFilterService.pendingJunkCandidateTag)
            ..removeWhere(JunkPhotoFilterService.isInternalJunkTag);
      tags.add(JunkPhotoFilterService.junkCandidateTag);
      photo.aiTags = tags.toList(growable: false);
      photo.isAiAnalyzed = true;
      photo.isAiAnalysisCandidate = false;
      final eventId = photo.eventId;
      if (eventId != null) {
        affectedEventIds.add(eventId);
      }
    }
    photoBox.putMany(photos);

    if (affectedEventIds.isNotEmpty) {
      unawaited(
        EventService()
            .refreshEventSmartInfo(affectedEventIds.toList(), allowLlm: false)
            .catchError((error) {}),
      );
    }

    return photos.length;
  }

  Future<int> markCandidatesAsKept(
    Iterable<JunkPhotoCleanupCandidate> candidates,
  ) async {
    final candidateIds = candidates
        .map((candidate) => candidate.photoId)
        .where((id) => id > 0)
        .toSet()
        .toList(growable: false);
    if (candidateIds.isEmpty) {
      return 0;
    }

    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final photos = photoBox
        .getMany(candidateIds)
        .whereType<PhotoEntity>()
        .toList(growable: false);
    if (photos.isEmpty) {
      return 0;
    }

    for (final photo in photos) {
      final tags = <String>{...?photo.aiTags}
        ..remove(JunkPhotoFilterService.pendingJunkCandidateTag)
        ..remove(JunkPhotoFilterService.junkCandidateTag)
        ..removeWhere(JunkPhotoFilterService.isInternalJunkTag);
      photo.aiTags = tags.toList(growable: false);
      photo.isAiAnalyzed = true;
      photo.isAiAnalysisCandidate = false;
    }
    photoBox.putMany(photos);
    return photos.length;
  }

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
      final remainingPhotos =
          photoBox
              .getMany(remainingIds)
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
