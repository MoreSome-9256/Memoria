/// 垃圾照片清理服务，负责确认、恢复低价值照片和显式删除系统相册资源。

import 'dart:async';
import 'package:photo_manager/photo_manager.dart';

import '../models/entity/event_entity.dart';
import '../models/entity/photo_entity.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../storage/vector_index/vector_index_constants.dart';
import 'event_service.dart';
import 'junk_photo_filter_service.dart';

class JunkPhotoCleanupService {
  JunkPhotoCleanupService._internal();

  static final JunkPhotoCleanupService _instance =
      JunkPhotoCleanupService._internal();

  factory JunkPhotoCleanupService() => _instance;

  final PhotoEmbeddingIndexRepository _embeddingIndex =
      PhotoEmbeddingIndexRepository();

  Future<int> evaluateAnalyzedPhotosForPending() async {
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final query = photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(true))
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    final photos = query.find();
    query.close();

    final updates = <PhotoEntity>[];
    for (final photo in photos) {
      if (JunkPhotoFilterService.hasFinalDecision(photo.aiTags) ||
          JunkPhotoFilterService.isQuarantined(photo.aiTags)) {
        continue;
      }
      final embedding =
          photo.imageEmbedding ??
          _embeddingIndex.readEmbeddingForPhoto(
            photo,
            modelVersion: buildPhotoEmbeddingModelVersion(),
          );
      if (embedding == null || embedding.isEmpty) continue;
      final decision = await JunkPhotoFilterService().evaluatePhoto(
        imageEmbedding: embedding,
      );
      if (!decision.shouldFilter) continue;
      photo.aiTags = <String>{
        ...?photo.aiTags,
        JunkPhotoFilterService.pendingJunkCandidateTag,
      }.toList(growable: false);
      updates.add(photo);
    }
    if (updates.isNotEmpty) {
      photoBox.putMany(updates);
    }
    return updates.length;
  }

  Future<int> markCandidatesAsLowValue(
    Iterable<JunkPhotoCleanupCandidate> candidates,
  ) async {
    final candidateIds = candidates
        .map((candidate) => candidate.photoId)
        .where((id) => id > 0)
        .toSet()
        .toList(growable: false);
    if (candidateIds.isEmpty) return 0;

    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final photos = photoBox
        .getMany(candidateIds)
        .whereType<PhotoEntity>()
        .toList(growable: false);
    for (final photo in photos) {
      final tags = <String>{...?photo.aiTags}
        ..remove(JunkPhotoFilterService.pendingJunkCandidateTag)
        ..remove(JunkPhotoFilterService.keptJunkCandidateTag)
        ..removeWhere(
          (tag) =>
              JunkPhotoFilterService.isInternalJunkTag(tag) &&
              tag != JunkPhotoFilterService.junkCandidateTag,
        )
        ..add(JunkPhotoFilterService.junkCandidateTag);
      photo.aiTags = tags.toList(growable: false);
      photo.isAiAnalyzed = true;
      photo.isAiAnalysisCandidate = false;
    }
    photoBox.putMany(photos);
    return photos.length;
  }

  Future<int> movePhotosToSystemTrash(Iterable<PhotoEntity> photos) async {
    final photoList = photos
        .where((photo) => photo.assetId.trim().isNotEmpty)
        .toList(growable: false);
    final ids = photoList.map((photo) => photo.assetId).toSet().toList();
    if (ids.isEmpty) return 0;
    final deletedIds = await PhotoManager.editor.deleteWithIds(ids);
    final deletedSet = deletedIds.toSet();
    return _removePhotosFromLocalIndex(
      photoList.where((photo) => deletedSet.contains(photo.assetId)),
    );
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
      tags.add(JunkPhotoFilterService.keptJunkCandidateTag);
      photo.aiTags = tags.toList(growable: false);
      photo.isAiAnalyzed = true;
      photo.isAiAnalysisCandidate = false;
    }
    photoBox.putMany(photos);
    return photos.length;
  }

  Future<int> _removePhotosFromLocalIndex(Iterable<PhotoEntity> photos) async {
    final affectedEventIds = <int>{};
    var removedCount = 0;
    for (final photo in photos) {
      final affectedEventId = await _removeFromLocalIndex(photo);
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

  Future<int?> _removeFromLocalIndex(PhotoEntity photo) async {
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
