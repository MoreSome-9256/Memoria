/// 照片扫描服务 — 提供增量发现和全量重建两种入口。
///
/// 【增量发现（推荐）】scanBatchPhotos
///   stop-early 策略：从最新照片开始扫描，收集到 batchSize 张新照片后立即停止。
///   适合 "下一批 N 张" 场景。
///
/// 【全量重建】rebuildAllCachedData
///   扫描所有照片。仅适合首次初始化或 "安全重建" 场景。

part of 'photo_service.dart';

extension PhotoServiceScan on PhotoService {
  void invalidateScanSessionCache() {
    _PhotoScanCoordinator.invalidateSessionCache();
    _photoAccessCache.clear();
  }

  // ── 全量重建（清空所有后重建）───────────────────────────────────
  Future<PhotoScanSummary> rebuildAllCachedData({int? maxAssets}) async {
    final plan = await _PhotoScanCoordinator(
      this,
    ).prepareRebuild(maxAssets: maxAssets);

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

  // ── ★ 推荐入口：增量收集新照片，收够即停 ────────────────────────
  /// 从系统相册最新照片开始扫描，收集到 [batchSize] 张新照片后停止。
  /// [batchSize] 为 null 时扫描完整授权范围。
  /// 返回 [BatchScanResult]，包含新照片列表和统计信息。
  Future<BatchScanResult> scanBatchPhotos({
    required int? batchSize,
    ValueChanged<BatchScanProgress>? onProgress,
  }) async {
    final plan = await _PhotoScanCoordinator(
      this,
    ).prepareIncremental(maxAssets: batchSize, onProgress: onProgress);

    var insertedPhotoIds = const <int>[];
    if (plan.built.photos.isNotEmpty) {
      final storedIds = _store.runInTransaction(
        TxMode.write,
        () => _photoBox.putMany(plan.built.photos),
      );
      insertedPhotoIds = storedIds
          .where((id) => id > 0)
          .toList(growable: false);
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

/// 批量扫描过程中的轻量进度，用于全局预处理状态。
class BatchScanProgress {
  const BatchScanProgress({
    required this.scannedCount,
    required this.candidateCount,
    required this.acceptedCount,
    required this.totalCount,
    required this.targetNew,
  });

  final int scannedCount;
  final int candidateCount;
  final int acceptedCount;
  final int totalCount;
  final int targetNew;

  double get scannedFraction {
    if (totalCount <= 0) return 0;
    return (scannedCount / totalCount).clamp(0, 1).toDouble();
  }

  double get acceptedFraction {
    if (targetNew <= 0) return 0;
    return (acceptedCount / targetNew).clamp(0, 1).toDouble();
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
