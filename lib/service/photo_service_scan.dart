/// 照片扫描服务 — 提供增量发现和全量重建两种入口。
///
/// 【增量发现（推荐）】scanBatchPhotos
///   stop-early 策略：从最新照片开始扫描，收集到 batchSize 张新照片后立即停止。
///   适合 "下一批 N 张" 场景。
///
/// 【全量重建】rebuildAllCachedData / scanAndSyncPhotos
///   扫描所有照片。仅适合首次初始化或 "安全重建" 场景。

part of 'photo_service.dart';

extension PhotoServiceScan on PhotoService {
  // ── 全量重建（清空所有后重建）───────────────────────────────────
  Future<PhotoScanSummary> rebuildAllCachedData({int? maxAssets}) async {
    final plan = await _PhotoScanCoordinator(this).prepareRebuild(
      maxAssets: maxAssets,
    );

    _store.runInTransaction(TxMode.write, () {
      _albumBookBox.removeAll();
      _recommendationBox.removeAll();
      _storyBox.removeAll();
      _eventBox.removeAll();
      _faceBox.removeAll();
      _photoBox.removeAll();
      _photoBox.putMany(plan.built.photos);
    });
    _photoAccessCache.clear();
    _photoEmbeddingIndexRepository.deleteAll();
    _faceEmbeddingIndexRepository.deleteAll();

    debugPrint(
      '重建完成: 入库=${plan.built.insertedCount} '
      '无GPS=${plan.built.insertedNoGps} 无效时间=${plan.built.skippedInvalidTime}',
    );
    return PhotoScanSummary(
      totalBefore: plan.totalBefore,
      totalAfter: plan.built.insertedCount,
      removedCount: plan.totalBefore,
      insertedCount: plan.built.insertedCount,
      skippedInvalidTime: plan.built.skippedInvalidTime,
      insertedNoGps: plan.built.insertedNoGps,
      skippedNonCamera: plan.built.skippedNonCamera,
      skippedScreenshot: plan.built.skippedScreenshot,
    );
  }

  // ── 兼容原 API ──────────────────────────────────────────────────
  Future<PhotoScanSummary> scanAndSyncPhotos({int? maxAssets}) {
    return scanAndSyncPhotosWithOffset(maxAssets: maxAssets);
  }

  Future<PhotoScanSummary> scanAndSyncPhotosWithOffset({
    int? maxAssets,
    int offsetFromNewest = 0,
  }) async {
    final plan = await _PhotoScanCoordinator(this).prepareIncremental(
      maxAssets: maxAssets,
      offsetFromNewest: offsetFromNewest,
    );

    var insertedPhotoIds = const <int>[];
    if (plan.built.photos.isNotEmpty) {
      final storedIds = _store.runInTransaction(
        TxMode.write,
        () => _photoBox.putMany(plan.built.photos),
      );
      insertedPhotoIds = storedIds.where((id) => id > 0).toList(growable: false);
    }

    final totalAfter = _photoBox.count();
    if (totalAfter == 0) {
      throw const PhotoScanException(
        PhotoScanError.noEligiblePhoto,
        '没有找到可用照片。请检查相册权限和本地相册。',
      );
    }

    return PhotoScanSummary(
      totalBefore: plan.totalBefore,
      totalAfter: totalAfter,
      removedCount: plan.removedCount,
      insertedCount: plan.built.insertedCount,
      insertedPhotoIds: insertedPhotoIds,
      scanStartOffset: plan.prepared.startOffset,
      scannedCount: plan.prepared.fetchCount,
      skippedInvalidTime: plan.built.skippedInvalidTime,
      insertedNoGps: plan.built.insertedNoGps,
      skippedNonCamera: plan.built.skippedNonCamera,
      skippedScreenshot: plan.built.skippedScreenshot,
    );
  }

  // ── ★ 推荐入口：增量收集新照片，收够即停 ────────────────────────
  /// 从系统相册最新照片开始扫描，收集到 [batchSize] 张新照片后停止。
  /// 返回 [BatchScanResult]，包含新照片列表和统计信息。
  Future<BatchScanResult> scanBatchPhotos({required int batchSize}) async {
    final plan = await _PhotoScanCoordinator(this).prepareIncremental(
      maxAssets: batchSize,
    );

    var insertedPhotoIds = const <int>[];
    if (plan.built.photos.isNotEmpty) {
      final storedIds = _store.runInTransaction(
        TxMode.write,
        () => _photoBox.putMany(plan.built.photos),
      );
      insertedPhotoIds = storedIds.where((id) => id > 0).toList(growable: false);
    }

    return BatchScanResult(
      newPhotos: plan.built.photos,
      insertedPhotoIds: insertedPhotoIds,
      scannedCount: plan.prepared.fetchCount,
      insertedCount: plan.built.insertedCount,
      totalAfter: _photoBox.count(),
      insertedNoGps: plan.built.insertedNoGps,
      skippedInvalidTime: plan.built.skippedInvalidTime,
      skippedNonCamera: plan.built.skippedNonCamera,
      skippedScreenshot: plan.built.skippedScreenshot,
    );
  }
}

/// 批量扫描结果
class BatchScanResult {
  const BatchScanResult({
    required this.newPhotos,
    required this.insertedPhotoIds,
    required this.scannedCount,
    required this.insertedCount,
    required this.totalAfter,
    required this.insertedNoGps,
    required this.skippedInvalidTime,
    required this.skippedNonCamera,
    required this.skippedScreenshot,
  });

  final List<PhotoEntity> newPhotos;
  final List<int> insertedPhotoIds;
  final int scannedCount;
  final int insertedCount;
  final int totalAfter;
  final int insertedNoGps;
  final int skippedInvalidTime;
  final int skippedNonCamera;
  final int skippedScreenshot;

  bool get hasNewPhotos => insertedCount > 0;
}
