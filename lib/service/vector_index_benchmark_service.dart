/// 向量索引基准测试服务，收集嵌入检索和写入性能数据。

import 'dart:math' as math;

import 'package:isar/isar.dart';

import '../models/entity/photo_entity.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import 'mobileclip_embedding_service.dart';
import 'photo_service.dart';

class VectorIndexStorageBenchmarkService {
  VectorIndexStorageBenchmarkService({
    PhotoService? photoService,
    ObjectBoxService? objectBoxService,
    PhotoEmbeddingIndexRepository? photoEmbeddingIndexRepository,
    MobileClipEmbeddingService? mobileClipEmbeddingService,
  }) : _photoService = photoService ?? PhotoService(),
       _objectBoxService = objectBoxService ?? ObjectBoxService(),
       _photoEmbeddingIndexRepository =
           photoEmbeddingIndexRepository ?? PhotoEmbeddingIndexRepository(),
       _mobileClipEmbeddingService =
           mobileClipEmbeddingService ?? MobileClipEmbeddingService();

  final PhotoService _photoService;
  final ObjectBoxService _objectBoxService;
  final PhotoEmbeddingIndexRepository _photoEmbeddingIndexRepository;
  final MobileClipEmbeddingService _mobileClipEmbeddingService;

  Future<VectorIndexStorageBenchmarkReport> runPhotoEmbeddingReadBenchmark({
    int sampleCount = 200,
    int rounds = 6,
  }) async {
    await _photoService.init();
    await _objectBoxService.init();

    final warnings = <String>[];
    final activeModelVersion = await _mobileClipEmbeddingService
        .getSelectedModelVersion();

    final candidateLimit = math.max(sampleCount * 6, sampleCount);
    final candidateQuery = _photoService.isar
        .collection<PhotoEntity>()
        .where()
        .sortByTimestampDesc();
    final candidatePhotos = await candidateQuery
        .limit(candidateLimit)
        .findAll();

    final legacyCandidates = candidatePhotos
        .where((photo) => _hasUsableLegacyEmbedding(photo.imageEmbedding))
        .toList(growable: false);
    final indexedCandidates = _photoEmbeddingIndexRepository
        .readIndexedEmbeddingsByPhotoIds(
          legacyCandidates.map((photo) => photo.id),
          modelVersion: activeModelVersion,
        );

    final benchmarkIds = <int>[];
    for (final photo in legacyCandidates) {
      if (!indexedCandidates.containsKey(photo.id)) {
        continue;
      }
      benchmarkIds.add(photo.id);
      if (benchmarkIds.length >= sampleCount) {
        break;
      }
    }

    if (benchmarkIds.isEmpty) {
      warnings.add('没有找到同时具备 Isar legacy 向量和 ObjectBox 当前版本索引的数据，暂时无法比较读耗时。');
      return VectorIndexStorageBenchmarkReport(
        modelVersion: activeModelVersion,
        requestedSampleCount: sampleCount,
        actualSampleCount: 0,
        rounds: rounds,
        isarReadRoundsMs: const <double>[],
        objectBoxReadRoundsMs: const <double>[],
        warnings: warnings,
      );
    }

    await _photoService.isar.collection<PhotoEntity>().getAll(benchmarkIds);
    _photoEmbeddingIndexRepository.readIndexedEmbeddingsByPhotoIds(
      benchmarkIds,
      modelVersion: activeModelVersion,
    );

    final isarReadRoundsMs = <double>[];
    final objectBoxReadRoundsMs = <double>[];
    final isarChecksums = <double>[];
    final objectBoxChecksums = <double>[];

    for (var round = 0; round < rounds; round++) {
      final isarWatch = Stopwatch()..start();
      final isarPhotos =
          (await _photoService.isar.collection<PhotoEntity>().getAll(
            benchmarkIds,
          )).whereType<PhotoEntity>().toList(growable: false);
      final isarChecksum = _computePhotoChecksum(isarPhotos);
      isarWatch.stop();

      final objectBoxWatch = Stopwatch()..start();
      final objectBoxVectors = _photoEmbeddingIndexRepository
          .readIndexedEmbeddingsByPhotoIds(
            benchmarkIds,
            modelVersion: activeModelVersion,
          );
      final objectBoxChecksum = _computeVectorChecksum(objectBoxVectors.values);
      objectBoxWatch.stop();

      isarReadRoundsMs.add(isarWatch.elapsedMicroseconds / 1000.0);
      objectBoxReadRoundsMs.add(objectBoxWatch.elapsedMicroseconds / 1000.0);
      isarChecksums.add(isarChecksum);
      objectBoxChecksums.add(objectBoxChecksum);
    }

    final checksumDrift = _mean(isarChecksums) - _mean(objectBoxChecksums);
    if (checksumDrift.abs() > 1e-6) {
      warnings.add(
        'Isar/ObjectBox 读回的 checksum 存在差异 (${checksumDrift.toStringAsFixed(6)})，请确认当前样本是否混入了不同版本向量。',
      );
    }

    return VectorIndexStorageBenchmarkReport(
      modelVersion: activeModelVersion,
      requestedSampleCount: sampleCount,
      actualSampleCount: benchmarkIds.length,
      rounds: rounds,
      isarReadRoundsMs: isarReadRoundsMs,
      objectBoxReadRoundsMs: objectBoxReadRoundsMs,
      warnings: warnings,
    );
  }

  bool _hasUsableLegacyEmbedding(List<double>? vector) {
    return vector != null &&
        vector.length == MobileClipEmbeddingService.expectedEmbeddingDim;
  }

  double _computePhotoChecksum(Iterable<PhotoEntity> photos) {
    var checksum = 0.0;
    for (final photo in photos) {
      final vector = photo.imageEmbedding;
      if (!_hasUsableLegacyEmbedding(vector)) {
        continue;
      }
      checksum += vector!.first;
      checksum += vector.last;
      checksum += vector.length.toDouble();
    }
    return checksum;
  }

  double _computeVectorChecksum(Iterable<List<double>> vectors) {
    var checksum = 0.0;
    for (final vector in vectors) {
      if (vector.isEmpty) {
        continue;
      }
      checksum += vector.first;
      checksum += vector.last;
      checksum += vector.length.toDouble();
    }
    return checksum;
  }

  double _mean(List<double> values) {
    if (values.isEmpty) {
      return 0.0;
    }
    return values.reduce((left, right) => left + right) / values.length;
  }
}

class VectorIndexStorageBenchmarkReport {
  const VectorIndexStorageBenchmarkReport({
    required this.modelVersion,
    required this.requestedSampleCount,
    required this.actualSampleCount,
    required this.rounds,
    required this.isarReadRoundsMs,
    required this.objectBoxReadRoundsMs,
    required this.warnings,
  });

  final String modelVersion;
  final int requestedSampleCount;
  final int actualSampleCount;
  final int rounds;
  final List<double> isarReadRoundsMs;
  final List<double> objectBoxReadRoundsMs;
  final List<String> warnings;

  bool get hasSamples => actualSampleCount > 0;

  double get isarMeanReadMs => _mean(isarReadRoundsMs);
  double get objectBoxMeanReadMs => _mean(objectBoxReadRoundsMs);

  double get isarP90ReadMs => _percentile(isarReadRoundsMs, 0.90);
  double get objectBoxP90ReadMs => _percentile(objectBoxReadRoundsMs, 0.90);

  double? get speedupRatio {
    if (objectBoxMeanReadMs <= 0) {
      return null;
    }
    return isarMeanReadMs / objectBoxMeanReadMs;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'modelVersion': modelVersion,
      'requestedSampleCount': requestedSampleCount,
      'actualSampleCount': actualSampleCount,
      'rounds': rounds,
      'isarReadRoundsMs': isarReadRoundsMs,
      'objectBoxReadRoundsMs': objectBoxReadRoundsMs,
      'isarMeanReadMs': isarMeanReadMs,
      'objectBoxMeanReadMs': objectBoxMeanReadMs,
      'isarP90ReadMs': isarP90ReadMs,
      'objectBoxP90ReadMs': objectBoxP90ReadMs,
      'speedupRatio': speedupRatio,
      'warnings': warnings,
    };
  }
}

double _mean(List<double> values) {
  if (values.isEmpty) {
    return 0.0;
  }
  return values.reduce((left, right) => left + right) / values.length;
}

double _percentile(List<double> values, double percentile) {
  if (values.isEmpty) {
    return 0.0;
  }
  final sorted = values.toList(growable: false)..sort();
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index.clamp(0, sorted.length - 1)];
}
