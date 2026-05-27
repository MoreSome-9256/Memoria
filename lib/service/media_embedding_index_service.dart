import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../storage/objectbox/entities/media_asset_entity.dart';
import '../storage/objectbox/media_asset_repository.dart';
import '../storage/vector_index/vector_index_constants.dart';
import '../utils/media_type_helper.dart';
import 'app_ai_settings_service.dart';
import 'media_embedding_service.dart';
import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_litert_service.dart';
import 'semantic_matching_service.dart';

class MediaIndexProgress {
  const MediaIndexProgress({
    required this.processed,
    required this.total,
    required this.running,
    required this.lastError,
  });

  final int processed;
  final int total;
  final bool running;
  final String? lastError;

  double get ratio => total == 0 ? 0 : processed / total;
}

class MediaSearchHit {
  const MediaSearchHit({required this.assetId, required this.score});

  final String assetId;
  final double score;
}

class MediaEmbeddingIndexService {
  MediaEmbeddingIndexService._internal();

  static final MediaEmbeddingIndexService _instance =
      MediaEmbeddingIndexService._internal();

  factory MediaEmbeddingIndexService() => _instance;

  final MediaAssetRepository _repository = MediaAssetRepository();
  final SemanticMatchingService _semanticService = SemanticMatchingService();

  final ValueNotifier<MediaIndexProgress> progressNotifier =
      ValueNotifier<MediaIndexProgress>(
        MediaIndexProgress(
          processed: 0,
          total: 0,
          running: false,
          lastError: null,
        ),
      );

  bool _running = false;

  Future<void> encodePending({
    int maxConcurrency = 2,
    int batchSize = 240,
    int inputSize = MobileClipLiteRtService.inputImageSize,
  }) async {
    if (_running) {
      return;
    }
    _running = true;
    final safeConcurrency = maxConcurrency.clamp(1, 4);

    try {
      final pending = _repository.loadPending(limit: batchSize);
      progressNotifier.value = MediaIndexProgress(
        processed: 0,
        total: pending.length,
        running: true,
        lastError: null,
      );

      if (pending.isEmpty) {
        progressNotifier.value = const MediaIndexProgress(
          processed: 0,
          total: 0,
          running: false,
          lastError: null,
        );
        return;
      }

      var processed = 0;
      for (var cursor = 0; cursor < pending.length; cursor += safeConcurrency) {
        final slice = pending
            .skip(cursor)
            .take(safeConcurrency)
            .toList(growable: false);

        await Future.wait(
          slice.map((entity) => _encodeOne(entity, inputSize: inputSize)),
        );

        processed += slice.length;
        progressNotifier.value = MediaIndexProgress(
          processed: processed,
          total: pending.length,
          running: true,
          lastError: null,
        );
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await PhotoManager.clearFileCache();
      }

      progressNotifier.value = MediaIndexProgress(
        processed: pending.length,
        total: pending.length,
        running: false,
        lastError: null,
      );
    } catch (error) {
      progressNotifier.value = MediaIndexProgress(
        processed: progressNotifier.value.processed,
        total: progressNotifier.value.total,
        running: false,
        lastError: error.toString(),
      );
      rethrow;
    } finally {
      _running = false;
    }
  }

  Future<List<MediaSearchHit>> searchByText(
    String query, {
    int topK = 24,
  }) async {
    await _semanticService.warmUp();
    final vector = await _semanticService.embedText(query);
    final modelVersion = await _activePhotoModelVersion();
    return _searchByVector(vector, topK, modelVersion: modelVersion);
  }

  Future<List<MediaSearchHit>> searchByImageBytes(
    Uint8List imageBytes, {
    int topK = 24,
  }) async {
    final backend = await MobileClipBackendPreferenceService()
        .getSelectedBackend();
    final settings = await AppAiSettingsService.instance.load();
    final result = await MediaEmbeddingService().embedImageBytes(
      imageBytes,
      backend: backend,
      liteRt: MobileClipLiteRtService.withRuntimeOptions(
        accelerator: settings.inferenceAccelerator,
        xnnpackThreadCount: settings.xnnpackThreadCount,
        modelBatchSize: settings.analysisBatchSize,
      ),
    );
    return _searchByVector(
      result.embedding,
      topK,
      modelVersion: result.modelVersion,
    );
  }

  Future<void> _encodeOne(
    MediaAssetEntity entity, {
    required int inputSize,
  }) async {
    try {
      final asset = await AssetEntity.fromId(entity.assetId);
      if (asset == null) {
        _repository.removeByAssetIds(<String>[entity.assetId]);
        return;
      }

      final bytes = await asset.thumbnailDataWithSize(
        ThumbnailSize(inputSize, inputSize),
        quality: 92,
      );
      if (bytes == null || bytes.isEmpty) {
        entity.setStatus(MediaAssetStatus.failed);
        entity.errorMessage = 'thumbnail-empty';
        _repository.putMany(<MediaAssetEntity>[entity]);
        return;
      }

      final settings = await AppAiSettingsService.instance.load();
      final backend = await MobileClipBackendPreferenceService()
          .getSelectedBackend();
      final kind = asset.type == AssetType.video
          ? MemoriaMediaKind.video
          : asset.isLivePhoto
          ? MemoriaMediaKind.dynamicImage
          : MemoriaMediaKind.image;
      final embedding = await MediaEmbeddingService().embedPreparedMediaBytes(
        kind: kind,
        imageOrThumbnailBytes: bytes,
        mobileViClipEnabled: settings.mobileViClipEnabled,
        backend: backend,
        liteRt: MobileClipLiteRtService.withRuntimeOptions(
          accelerator: settings.inferenceAccelerator,
          xnnpackThreadCount: settings.xnnpackThreadCount,
          modelBatchSize: settings.analysisBatchSize,
        ),
      );
      entity.embedding = _l2Normalize(embedding.embedding);
      entity.modelVersion = embedding.modelVersion;
      entity.embeddingUpdatedAtMs = DateTime.now().millisecondsSinceEpoch;
      entity.setStatus(MediaAssetStatus.ready);
      entity.errorMessage = null;
      _repository.putMany(<MediaAssetEntity>[entity]);
    } catch (error) {
      entity.setStatus(MediaAssetStatus.failed);
      entity.errorMessage = error.toString();
      _repository.putMany(<MediaAssetEntity>[entity]);
    }
  }

  Future<String> _activePhotoModelVersion() async {
    final backend = await MobileClipBackendPreferenceService()
        .getSelectedBackend();
    return buildPhotoEmbeddingModelVersion(backend);
  }

  List<MediaSearchHit> _searchByVector(
    List<double> vector,
    int k, {
    required String modelVersion,
  }) {
    final normalized = _l2Normalize(vector);
    final rows = _repository.queryNearest(
      normalized,
      k,
      modelVersion: modelVersion,
    );
    return rows
        .map(
          (row) =>
              MediaSearchHit(assetId: row.object.assetId, score: row.score),
        )
        .toList(growable: false);
  }

  List<double> _l2Normalize(List<double> vector) {
    final norm = math.sqrt(
      vector.fold<double>(0, (sum, value) => sum + value * value),
    );
    if (norm <= 0) {
      return vector;
    }
    return vector.map((value) => value / norm).toList(growable: false);
  }
}
