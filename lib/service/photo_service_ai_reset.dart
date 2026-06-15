/// 照片服务的 AI 重置模块，处理分析状态和缓存的重置逻辑。

part of 'photo_service.dart';

extension PhotoServiceAiReset on PhotoService {
  Future<int> clearAllAiAnalysisData() async {
    final query = _photoBox.query().build();
    final photos = query.find();
    query.close();
    if (photos.isEmpty) {
      _store.runInTransaction(TxMode.write, () {
        _albumBookBox.removeAll();
        _recommendationBox.removeAll();
        _storyBox.removeAll();
        _eventBox.removeAll();
        _faceBox.removeAll();
      });
      _photoEmbeddingIndexRepository.deleteAll();
      _faceEmbeddingIndexRepository.deleteAll();
      return 0;
    }

    for (final photo in photos) {
      final isConfirmedJunk = _isConfirmedJunkPhoto(photo);
      photo.isAiAnalyzed = isConfirmedJunk;
      photo.isAiAnalysisCandidate = false;
      photo.aiTags = isConfirmedJunk
          ? <String>[JunkPhotoFilterService.junkCandidateTag]
          : <String>[];
      photo.aiCaption = null;
      photo.imageEmbedding = null;
      photo.ocrText = null;
      photo.ocrTags = <String>[];
      photo.isOcrAnalyzed = false;
      photo.isCaptionAnalyzed = false;
      photo.faceCount = 0;
      photo.smileProb = 0.0;
      photo.isFaceAnalyzed = false;
      photo.joyScore = 0.0;
      photo.eventId = null;
    }

    _store.runInTransaction(TxMode.write, () {
      _albumBookBox.removeAll();
      _recommendationBox.removeAll();
      _storyBox.removeAll();
      _eventBox.removeAll();
      _faceBox.removeAll();
      _photoBox.putMany(photos);
    });
    _photoEmbeddingIndexRepository.deleteAll();
    _faceEmbeddingIndexRepository.deleteAll();

    debugPrint('🧹 已清空 ${photos.length} 张照片的 AI 分析字段和派生索引');
    return photos.length;
  }

  Future<List<PhotoEntity>> loadJunkCandidatePhotos() async {
    return _loadPhotosWithAiTag(JunkPhotoFilterService.junkCandidateTag);
  }

  Future<List<PhotoEntity>> loadPendingJunkCandidatePhotos() async {
    return _loadPhotosWithAiTag(JunkPhotoFilterService.pendingJunkCandidateTag);
  }

  Future<List<PhotoEntity>> loadAnalyzedPhotosForJunkScoring() async {
    final query = _photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(true))
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  Future<List<PhotoEntity>> _loadPhotosWithAiTag(String tag) async {
    final query = _photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(true))
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    final photos = query.find();
    query.close();
    final junkPhotos = photos
        .where((photo) => photo.aiTags?.contains(tag) ?? false)
        .toList(growable: false);
    return reconcileAccessiblePhotos(junkPhotos);
  }

  Future<int> requeueAllPhotosForAi() async {
    final query = _photoBox
        .query()
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    final photos = query.find();
    query.close();

    if (photos.isEmpty) {
      return 0;
    }

    final taxonomyLabels = <String>{
      ...memoriaMasterLabels,
      ...memoriaLegacyCoarseLabelToCoarseId.keys,
    };
    const passthroughLabels = <String>{
      '视频',
      JunkPhotoFilterService.junkCandidateTag,
      JunkPhotoFilterService.pendingJunkCandidateTag,
      JunkPhotoFilterService.keptJunkCandidateTag,
    };

    var updatedCount = 0;
    final updatedPhotos = <PhotoEntity>[];
    final updatedPhotoIds = <int>[];
    for (final photo in photos) {
      final aiTags = photo.aiTags ?? const <String>[];
      final normalizedAiTags = aiTags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false);
      final isJunkCandidate =
          aiTags.contains(JunkPhotoFilterService.junkCandidateTag) ||
          aiTags.contains(JunkPhotoFilterService.pendingJunkCandidateTag) ||
          aiTags.contains(JunkPhotoFilterService.keptJunkCandidateTag);
      final mediaKind = MediaTypeHelper.fromStorageValue(
        photo.mediaKind,
        path: photo.path,
      );
      final isOnlyOtherResult =
          normalizedAiTags.isNotEmpty &&
          normalizedAiTags.every((tag) => tag == memoriaOtherLabel);
      final isStaleOtherOnlyImageResult =
          photo.isAiAnalyzed &&
          !isJunkCandidate &&
          mediaKind == MemoriaMediaKind.image &&
          isOnlyOtherResult;
      final needsReset =
          photo.isAiAnalyzed &&
          !isJunkCandidate &&
          (aiTags.isEmpty ||
              (photo.imageEmbedding == null || photo.imageEmbedding!.isEmpty));
      final hasOutdatedTags =
          photo.isAiAnalyzed &&
          aiTags.isNotEmpty &&
          normalizedAiTags.any(
            (tag) =>
                !taxonomyLabels.contains(tag) &&
                !passthroughLabels.contains(tag),
          );

      if (!needsReset && !hasOutdatedTags && !isStaleOtherOnlyImageResult) {
        continue;
      }

      photo.isAiAnalyzed = false;
      photo.isAiAnalysisCandidate = true;
      photo.aiTags = <String>[];
      photo.aiCaption = null;
      photo.imageEmbedding = null;
      photo.ocrText = null;
      photo.ocrTags = <String>[];
      photo.isOcrAnalyzed = false;
      photo.isCaptionAnalyzed = false;
      photo.faceCount = 0;
      photo.smileProb = 0.0;
      photo.isFaceAnalyzed = false;
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

    debugPrint('🔁 已将 ${photos.length} 张照片中的 $updatedCount 张重新加入 AI 打标队列');
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
      photo.isAiAnalysisCandidate = true;
      photo.aiTags = <String>[];
      photo.aiCaption = null;
      photo.imageEmbedding = null;
      photo.ocrText = null;
      photo.ocrTags = <String>[];
      photo.isOcrAnalyzed = false;
      photo.isCaptionAnalyzed = false;
      photo.faceCount = 0;
      photo.smileProb = 0.0;
      photo.isFaceAnalyzed = false;
      photo.joyScore = 0.0;
      updatedCount++;
    }

    _store.runInTransaction(TxMode.write, () => _photoBox.putMany(photos));
    _photoEmbeddingIndexRepository.deleteByPhotoIds(normalizedIds);
    _faceEmbeddingIndexRepository.deleteByPhotoIds(normalizedIds);

    debugPrint('🔁 已将 $updatedCount 张低质量候选重新加入正常 AI 打标队列');
    return updatedCount;
  }

  Future<int> requeuePhotosMissingEnabledAttributes(
    AppAiSettings settings,
  ) async {
    var missingCondition = PhotoEntity_.isCaptionAnalyzed.equals(false);
    if (settings.ocrEnabled) {
      missingCondition = missingCondition.or(
        PhotoEntity_.isOcrAnalyzed.equals(false),
      );
    }
    if (settings.faceAnalysisEnabled) {
      missingCondition = missingCondition.or(
        PhotoEntity_.isFaceAnalyzed.equals(false),
      );
    }
    final query = _photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(true).and(missingCondition))
        .build();
    final missingIds = query
        .find()
        .where((photo) {
          if (_isJunkQuarantinedPhoto(photo)) return false;
          final kind = MediaTypeHelper.fromStorageValue(
            photo.mediaKind,
            path: photo.path,
          );
          if (kind != MemoriaMediaKind.image) return false;
          return !photo.isCaptionAnalyzed ||
              (settings.ocrEnabled && !photo.isOcrAnalyzed) ||
              (settings.faceAnalysisEnabled && !photo.isFaceAnalyzed);
        })
        .map((photo) => photo.id)
        .toList(growable: false);
    query.close();
    if (missingIds.isEmpty) return 0;

    final count = await requeuePhotosForAiByIds(missingIds);
    debugPrint('🔁 已将 $count 张缺少已启用属性分析的照片重新加入队列');
    return count;
  }

  List<int> loadPendingAiPhotoIds({int? limit}) {
    final q = _photoBox
        .query(PhotoEntity_.isAiAnalyzed.equals(false))
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    try {
      final ids = q
          .find()
          .where((photo) => !_isJunkQuarantinedPhoto(photo))
          .map((photo) => photo.id)
          .where((id) => id > 0);
      return limit == null
          ? ids.toList(growable: false)
          : ids.take(limit).toList(growable: false);
    } finally {
      q.close();
    }
  }

  int countPendingAnalysisCandidates() {
    final q = _photoBox
        .query(
          PhotoEntity_.isAiAnalysisCandidate
              .equals(true)
              .and(PhotoEntity_.isAiAnalyzed.equals(false)),
        )
        .build();
    try {
      return q.find().where((photo) => !_isJunkQuarantinedPhoto(photo)).length;
    } finally {
      q.close();
    }
  }

  List<int> loadPendingAnalysisCandidateIds({int? limit}) {
    final q = _photoBox
        .query(
          PhotoEntity_.isAiAnalysisCandidate
              .equals(true)
              .and(PhotoEntity_.isAiAnalyzed.equals(false)),
        )
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    try {
      final ids = q
          .find()
          .where((photo) => !_isJunkQuarantinedPhoto(photo))
          .map((photo) => photo.id)
          .where((id) => id > 0);
      return limit == null
          ? ids.toList(growable: false)
          : ids.take(limit).toList(growable: false);
    } finally {
      q.close();
    }
  }

  List<PhotoEntity> loadPendingAnalysisCandidatePhotos({int? limit}) {
    final ids = loadPendingAnalysisCandidateIds(limit: limit);
    if (ids.isEmpty) {
      return const <PhotoEntity>[];
    }
    return _photoBox
        .getMany(ids)
        .whereType<PhotoEntity>()
        .toList(growable: false);
  }

  bool _isConfirmedJunkPhoto(PhotoEntity photo) {
    return photo.aiTags?.contains(JunkPhotoFilterService.junkCandidateTag) ??
        false;
  }

  bool _isJunkQuarantinedPhoto(PhotoEntity photo) {
    return JunkPhotoFilterService.isQuarantined(photo.aiTags);
  }

  void markAiAnalysisCandidatesByIds(Iterable<int> photoIds) {
    final ids = photoIds.where((id) => id > 0).toSet().toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final photos = _photoBox
        .getMany(ids)
        .whereType<PhotoEntity>()
        .toList(growable: false);
    if (photos.isEmpty) {
      return;
    }
    for (final photo in photos) {
      if (!photo.isAiAnalyzed) {
        photo.isAiAnalysisCandidate = true;
      }
    }
    _store.runInTransaction(TxMode.write, () => _photoBox.putMany(photos));
  }

  void clearAiAnalysisCandidatesByIds(Iterable<int> photoIds) {
    final ids = photoIds.where((id) => id > 0).toSet().toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    final photos = _photoBox
        .getMany(ids)
        .whereType<PhotoEntity>()
        .toList(growable: false);
    if (photos.isEmpty) {
      return;
    }
    for (final photo in photos) {
      if (!photo.isAiAnalyzed) {
        photo.isAiAnalysisCandidate = false;
      }
    }
    _store.runInTransaction(TxMode.write, () => _photoBox.putMany(photos));
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
      photo.isAiAnalysisCandidate = true;

      photo.aiTags = []; // 清空 ML Kit 时代干瘪的标签
      photo.imageEmbedding = null;
      photo.ocrText = null;
      photo.ocrTags = [];
      photo.isOcrAnalyzed = false;
      photo.isCaptionAnalyzed = false;
      photo.isFaceAnalyzed = false;
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
