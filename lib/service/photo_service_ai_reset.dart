/// 照片服务的 AI 重置模块，处理分析状态和缓存的重置逻辑。

part of 'photo_service.dart';

extension PhotoServiceAiReset on PhotoService {
  Future<List<PhotoEntity>> loadJunkCandidatePhotos() async {
    final query = _photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(true))
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    final photos = query.find();
    query.close();
    final junkPhotos = photos
        .where(
          (photo) =>
              photo.aiTags?.contains(JunkPhotoFilterService.junkCandidateTag) ??
              false,
        )
        .toList(growable: false);
    return reconcileAccessiblePhotos(junkPhotos);
  }

  Future<int> requeueLatestPhotosForAi({int? maxPhotos}) async {
    final query = _photoBox
        .query()
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    final photos = query.find();
    query.close();
    final scopedPhotos = maxPhotos == null
        ? photos
        : photos.take(maxPhotos).toList(growable: false);

    if (scopedPhotos.isEmpty) {
      return 0;
    }

    final taxonomyLabels = memoriaMasterLabels.toSet();
    const passthroughLabels = <String>{
      '截图',
      '视频',
      memoriaOtherLabel,
      JunkPhotoFilterService.junkCandidateTag,
    };

    var updatedCount = 0;
    final updatedPhotos = <PhotoEntity>[];
    final updatedPhotoIds = <int>[];
    for (final photo in scopedPhotos) {
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
        : () {
            final q = _faceBox
                .query(FaceEntity_.photoId.oneOf(resetPhotoIds))
                .build();
            try {
              return q.find();
            } finally {
              q.close();
            }
          }();

    _store.runInTransaction(TxMode.write, () {
      if (staleFaces.isNotEmpty) {
        _faceBox.removeMany(
          staleFaces.map((item) => item.id).toList(growable: false),
        );
      }
      _photoBox.putMany(updatedPhotos);
    });
    _photoEmbeddingIndexRepository.deleteByPhotoIds(resetPhotoIds);
    _faceEmbeddingIndexRepository.deleteByPhotoIds(resetPhotoIds);

    final scopeText = maxPhotos == null
        ? '${scopedPhotos.length} 张照片'
        : '最近 $maxPhotos 张照片';
    debugPrint('🔁 已将 $scopeText 中的 $updatedCount 张重新加入 AI 打标队列');
    return updatedCount;
  }

  Future<int> requeuePhotosForAiByIds(Iterable<int> photoIds) async {
    final normalizedIds = photoIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return 0;
    }

    final photos = _photoBox
        .getMany(normalizedIds)
        .whereType<PhotoEntity>()
        .toList(growable: false);
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

    _store.runInTransaction(TxMode.write, () => _photoBox.putMany(photos));
    _photoEmbeddingIndexRepository.deleteByPhotoIds(normalizedIds);
    _faceEmbeddingIndexRepository.deleteByPhotoIds(normalizedIds);

    debugPrint('🔁 已将 $updatedCount 张低质量候选重新加入正常 AI 打标队列');
    return updatedCount;
  }

  Future<void> migrateToMobileClip() async {
    debugPrint("🔄 开始执行 Memoria 2.0 AI 数据迁移...");

    // 1. 查出所有已经用旧模型（ML Kit）分析过的照片

    final q = _photoBox.query(PhotoEntity_.isAiAnalyzed.equals(true)).build();
    final oldPhotos = q.find();
    q.close();

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

    _store.runInTransaction(TxMode.write, () {
      _faceBox.removeAll();
      _photoBox.putMany(oldPhotos);
    });
    _photoEmbeddingIndexRepository.deleteAll();
    _faceEmbeddingIndexRepository.deleteAll();

    debugPrint("🎉 成功重置了 ${oldPhotos.length} 张照片的 AI 状态！");

    debugPrint("后台的闲时 AI 任务将会自动用 MobileCLIP 重新扫描并提取 512 维高维向量。");
  }
}
