import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';

import '../storage/objectbox/entities/media_asset_entity.dart';
import '../storage/objectbox/media_asset_repository.dart';
import 'mobileclip_vision_service.dart';
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
  final MobileClipVisionService _visionService = MobileClipVisionService();
  final SemanticMatchingService _semanticService = SemanticMatchingService();

  final ValueNotifier<MediaIndexProgress> progressNotifier =
      ValueNotifier<MediaIndexProgress>(
        MediaIndexProgress(processed: 0, total: 0, running: false, lastError: null),
      );

  static const String _modelVersion = 'mobileclip2_vision_336_v1';

  bool _running = false;

  Future<void> encodePending({
    int maxConcurrency = 2,
    int batchSize = 240,
    int inputSize = 336,
    List<double> mean = const <double>[0.48145466, 0.4578275, 0.40821073],
    List<double> std = const <double>[0.26862954, 0.26130258, 0.27577711],
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
          slice.map(
            (entity) => _encodeOne(
              entity,
              inputSize: inputSize,
              mean: mean,
              std: std,
            ),
          ),
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

  Future<List<MediaSearchHit>> searchByText(String query, {int topK = 24}) async {
    await _semanticService.warmUp();
    final vector = await _semanticService.embedText(query);
    return _searchByVector(vector, topK);
  }

  Future<List<MediaSearchHit>> searchByImageBytes(
    Uint8List imageBytes, {
    int topK = 24,
    int inputSize = 336,
    List<double> mean = const <double>[0.48145466, 0.4578275, 0.40821073],
    List<double> std = const <double>[0.26862954, 0.26130258, 0.27577711],
  }) async {
    final input = await compute<_ImagePreprocessTask, Float32List>(
      _preprocessToNchwFloat32,
      _ImagePreprocessTask(
        imageBytes: imageBytes,
        inputSize: inputSize,
        mean: mean,
        std: std,
      ),
    );
    final vector = await _visionService.embedPreprocessedInput(input);
    return _searchByVector(vector, topK);
  }

  Future<void> _encodeOne(
    MediaAssetEntity entity, {
    required int inputSize,
    required List<double> mean,
    required List<double> std,
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
        entity.statusEnum = MediaAssetStatus.failed;
        entity.errorMessage = 'thumbnail-empty';
        _repository.putMany(<MediaAssetEntity>[entity]);
        return;
      }

      final input = await compute<_ImagePreprocessTask, Float32List>(
        _preprocessToNchwFloat32,
        _ImagePreprocessTask(
          imageBytes: bytes,
          inputSize: inputSize,
          mean: mean,
          std: std,
        ),
      );
      final embedding = await _visionService.embedPreprocessedInput(input);
      entity.embedding = _l2Normalize(embedding);
      entity.modelVersion = _modelVersion;
      entity.embeddingUpdatedAtMs = DateTime.now().millisecondsSinceEpoch;
      entity.statusEnum = MediaAssetStatus.ready;
      entity.errorMessage = null;
      _repository.putMany(<MediaAssetEntity>[entity]);
    } catch (error) {
      entity.statusEnum = MediaAssetStatus.failed;
      entity.errorMessage = error.toString();
      _repository.putMany(<MediaAssetEntity>[entity]);
    }
  }

  List<MediaSearchHit> _searchByVector(List<double> vector, int k) {
    final normalized = _l2Normalize(vector);
    final rows = _repository.queryNearest(normalized, k);
    return rows
        .map(
          (row) => MediaSearchHit(
            assetId: row.object.assetId,
            score: row.score,
          ),
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

class _ImagePreprocessTask {
  const _ImagePreprocessTask({
    required this.imageBytes,
    required this.inputSize,
    required this.mean,
    required this.std,
  });

  final Uint8List imageBytes;
  final int inputSize;
  final List<double> mean;
  final List<double> std;
}

Float32List _preprocessToNchwFloat32(_ImagePreprocessTask task) {
  final decoded = img.decodeImage(task.imageBytes);
  if (decoded == null) {
    throw ArgumentError('decode image failed');
  }

  final oriented = img.bakeOrientation(decoded);
  final resized = img.copyResize(
    oriented,
    width: task.inputSize,
    height: task.inputSize,
    interpolation: img.Interpolation.linear,
  );

  final out = Float32List(3 * task.inputSize * task.inputSize);
  final planeSize = task.inputSize * task.inputSize;
  for (var y = 0; y < task.inputSize; y++) {
    for (var x = 0; x < task.inputSize; x++) {
      final p = resized.getPixel(x, y);
      final r = (p.r / 255.0 - task.mean[0]) / task.std[0];
      final g = (p.g / 255.0 - task.mean[1]) / task.std[1];
      final b = (p.b / 255.0 - task.mean[2]) / task.std[2];
      final i = y * task.inputSize + x;
      out[i] = r;
      out[planeSize + i] = g;
      out[2 * planeSize + i] = b;
    }
  }

  return out;
}
