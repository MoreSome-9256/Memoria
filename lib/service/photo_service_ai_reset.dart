part of 'photo_service.dart';

extension PhotoServiceAiReset on PhotoService {
  Future<int> requeueLatestPhotosForAi({int? maxPhotos}) async {
    final query = _isar.collection<PhotoEntity>().where().sortByTimestampDesc();
    final photos = maxPhotos == null
        ? await query.findAll()
        : await query.limit(maxPhotos).findAll();

    if (photos.isEmpty) {
      return 0;
    }

    final taxonomyLabels = memoriaMasterLabels.toSet();
    const passthroughLabels = <String>{
      '截图',
      memoriaOtherLabel,
      JunkPhotoFilterService.junkCandidateTag,
    };

    var updatedCount = 0;
    final updatedPhotos = <PhotoEntity>[];
    final updatedPhotoIds = <int>[];
    for (final photo in photos) {
      final aiTags = photo.aiTags ?? const <String>[];
      final isJunkCandidate = aiTags.contains(
        JunkPhotoFilterService.junkCandidateTag,
      );
      final needsReset =
          photo.isAiAnalyzed &&
          !isJunkCandidate &&
          (aiTags.isEmpty ||
              (photo.imageEmbedding == null || photo.imageEmbedding!.isEmpty));
      final hasOutdatedTags =
          photo.isAiAnalyzed &&
          aiTags.isNotEmpty &&
          aiTags.any(
            (tag) =>
                !taxonomyLabels.contains(tag.trim()) &&
                !passthroughLabels.contains(tag.trim()),
          );

      if (!needsReset && !hasOutdatedTags) {
        continue;
      }

      photo.isAiAnalyzed = false;
      photo.aiTags = <String>[];
      photo.aiCaption = null;
      photo.imageEmbedding = null;
      photo.ocrText = null;
      photo.ocrTags = <String>[];
      photo.faceCount = 0;
      photo.smileProb = 0.0;
      photo.joyScore = 0.0;
      updatedCount++;
      updatedPhotos.add(photo);
      updatedPhotoIds.add(photo.id);
    }

    if (updatedCount == 0) {
      return 0;
    }

    final resetPhotoIds = updatedPhotoIds.toSet().toList(growable: false);
    final staleFaces = resetPhotoIds.isEmpty
        ? const <FaceEntity>[]
        : await _isar
              .collection<FaceEntity>()
              .filter()
              .anyOf(
                resetPhotoIds,
                (query, photoId) => query.photoIdEqualTo(photoId),
              )
              .findAll();

    await _isar.writeTxn(() async {
      if (staleFaces.isNotEmpty) {
        await _isar.collection<FaceEntity>().deleteAll(
          staleFaces.map((item) => item.id).toList(growable: false),
        );
      }
      await _isar.collection<PhotoEntity>().putAll(updatedPhotos);
    });
    _photoEmbeddingIndexRepository.deleteByPhotoIds(resetPhotoIds);
    _faceEmbeddingIndexRepository.deleteByPhotoIds(resetPhotoIds);

    final scopeText = maxPhotos == null
        ? '${photos.length} 张照片'
        : '最近 $maxPhotos 张照片';
    debugPrint('🔁 已将 $scopeText 中的 $updatedCount 张重新加入 AI 打标队列');
    return updatedCount;
  }

  Future<int> requeuePhotosForAiByIds(Iterable<int> photoIds) async {
    final normalizedIds = photoIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return 0;
    }

    final photos = (await _isar.collection<PhotoEntity>().getAll(
      normalizedIds,
    )).whereType<PhotoEntity>().toList(growable: false);
    if (photos.isEmpty) {
      return 0;
    }

    var updatedCount = 0;
    for (final photo in photos) {
      photo.isAiAnalyzed = false;
      photo.aiTags = <String>[];
      photo.aiCaption = null;
      photo.imageEmbedding = null;
      photo.ocrText = null;
      photo.ocrTags = <String>[];
      photo.faceCount = 0;
      photo.smileProb = 0.0;
      photo.joyScore = 0.0;
      updatedCount++;
    }

    await _isar.writeTxn(() async {
      await _isar.collection<PhotoEntity>().putAll(photos);
    });
    _photoEmbeddingIndexRepository.deleteByPhotoIds(normalizedIds);

    debugPrint('🔁 已将 $updatedCount 张低质量候选重新加入正常 AI 打标队列');
    return updatedCount;
  }

  Future<void> migrateToMobileClip() async {
    debugPrint("🔄 开始执行 Memoria 2.0 AI 数据迁移...");

    // 1. 查出所有已经用旧模型（ML Kit）分析过的照片

    final oldPhotos = await _isar
        .collection<PhotoEntity>()
        .filter()
        .isAiAnalyzedEqualTo(true)
        .findAll();

    if (oldPhotos.isEmpty) {
      debugPrint("✅ 没有需要迁移的旧照片。");

      return;
    }

    // 2. 将它们的状态重置，并清空旧标签

    for (var photo in oldPhotos) {
      photo.isAiAnalyzed = false;

      photo.aiTags = []; // 清空 ML Kit 时代干瘪的标签
      photo.imageEmbedding = null;
      photo.ocrText = null;
      photo.ocrTags = [];
    }

    // 3. 批量写回数据库

    await _isar.writeTxn(() async {
      await _isar.collection<FaceEntity>().clear();
      await _isar.collection<PhotoEntity>().putAll(oldPhotos);
    });
    _photoEmbeddingIndexRepository.deleteAll();
    _faceEmbeddingIndexRepository.deleteAll();

    debugPrint("🎉 成功重置了 ${oldPhotos.length} 张照片的 AI 状态！");

    debugPrint("后台的闲时 AI 任务将会自动用 MobileCLIP 重新扫描并提取 512 维高维向量。");
  }
}
