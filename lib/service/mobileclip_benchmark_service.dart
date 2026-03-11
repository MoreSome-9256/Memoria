import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/entity/photo_entity.dart';
import '../models/mobileclip_benchmark.dart';
import 'mobileclip_tag_service.dart';
import 'mobileclip_vision_service.dart';
import 'photo_service.dart';

abstract class MobileClipBenchmarkAdapter {
  const MobileClipBenchmarkAdapter();

  String get id;
  String get displayName;
  bool get isAvailable;

  Future<double> warmUp();

  Future<MobileClipAdapterRunResult> encodeSharedInput(
    Float32List input,
  );
}

class OnnxMobileClipBenchmarkAdapter extends MobileClipBenchmarkAdapter {
  OnnxMobileClipBenchmarkAdapter({
    MobileClipVisionService? visionService,
    MobileClipTagService? tagService,
  }) : _visionService = visionService ?? MobileClipVisionService(),
       _tagService = tagService ?? MobileClipTagService();

  final MobileClipVisionService _visionService;
  final MobileClipTagService _tagService;

  @override
  String get id => 'onnx';

  @override
  String get displayName => 'ONNX Runtime';

  @override
  bool get isAvailable => true;

  @override
  Future<double> warmUp() async {
    final stopwatch = Stopwatch()..start();
    await _visionService.warmUp();
    await _tagService.warmUp();
    stopwatch.stop();
    return stopwatch.elapsedMicroseconds / 1000.0;
  }

  @override
  Future<MobileClipAdapterRunResult> encodeSharedInput(Float32List input) async {
    final rssBefore = ProcessInfo.currentRss;
    final stopwatch = Stopwatch()..start();
    final embedding = await _visionService.embedPreprocessedInput(input);
    stopwatch.stop();
    final tags = await _tagService.retrieveTags(embedding);
    final rssAfter = ProcessInfo.currentRss;

    return MobileClipAdapterRunResult(
      adapterId: id,
      displayName: displayName,
      embedding: embedding,
      elapsedMs: stopwatch.elapsedMicroseconds / 1000.0,
      rssBeforeBytes: rssBefore,
      rssAfterBytes: rssAfter,
      tags: tags,
    );
  }
}

class NcnnMobileClipBenchmarkAdapter extends MobileClipBenchmarkAdapter {
  const NcnnMobileClipBenchmarkAdapter();

  @override
  String get id => 'ncnn';

  @override
  String get displayName => 'ncnn (待接入 FFI)';

  @override
  bool get isAvailable => false;

  @override
  Future<double> warmUp() async {
    throw UnsupportedError('ncnn adapter 尚未接入 FFI 动态库');
  }

  @override
  Future<MobileClipAdapterRunResult> encodeSharedInput(Float32List input) async {
    throw UnsupportedError('ncnn adapter 尚未接入 FFI 动态库');
  }
}

class MobileClipBenchmarkService {
  MobileClipBenchmarkService({
    List<MobileClipBenchmarkAdapter>? adapters,
    PhotoService? photoService,
    MobileClipVisionService? visionService,
  }) : _adapters =
           adapters ??
           <MobileClipBenchmarkAdapter>[
             OnnxMobileClipBenchmarkAdapter(visionService: visionService),
             const NcnnMobileClipBenchmarkAdapter(),
           ],
       _photoService = photoService ?? PhotoService(),
       _visionService = visionService ?? MobileClipVisionService();

  final List<MobileClipBenchmarkAdapter> _adapters;
  final PhotoService _photoService;
  final MobileClipVisionService _visionService;

  Future<MobileClipBenchmarkReport> runBenchmark({
    int sampleCount = 24,
  }) async {
    final warnings = <String>[];
    final samples = await _loadSamples(sampleCount);
    if (samples.isEmpty) {
      return MobileClipBenchmarkReport(
        generatedAt: DateTime.now(),
        sampleCount: 0,
        usesSharedPreprocessing: true,
        adapterSummaries: const <MobileClipAdapterSummary>[],
        comparisons: const <MobileClipEmbeddingComparisonSummary>[],
        warnings: <String>['没有找到可用于 benchmark 的本地照片样本。'],
      );
    }

    final availableAdapters = _adapters.where((adapter) => adapter.isAvailable).toList(growable: false);
    final unavailableAdapters = _adapters.where((adapter) => !adapter.isAvailable).toList(growable: false);
    for (final adapter in unavailableAdapters) {
      warnings.add('${adapter.displayName} 尚未接入，当前只会跑 ONNX 基线。');
    }

    final warmUpTimes = <String, double>{};
    for (final adapter in availableAdapters) {
      warmUpTimes[adapter.id] = await adapter.warmUp();
    }

    final runsByAdapter = <String, List<MobileClipAdapterRunResult>>{
      for (final adapter in availableAdapters) adapter.id: <MobileClipAdapterRunResult>[],
    };

    for (final sample in samples) {
      final file = File(sample.path);
      if (!file.existsSync()) {
        warnings.add('样本 ${sample.photoId} 的文件不存在，已跳过。');
        continue;
      }

      final bytes = await file.readAsBytes();
      final sharedInput = await _visionService.preprocessImageBytesForBenchmark(bytes);

      for (final adapter in availableAdapters) {
        final runResult = await adapter.encodeSharedInput(sharedInput);
        runsByAdapter[adapter.id]!.add(runResult);
      }
    }

    final summaries = availableAdapters
        .map((adapter) => _buildSummary(
              adapter: adapter,
              runs: runsByAdapter[adapter.id] ?? const <MobileClipAdapterRunResult>[],
              warmUpMs: warmUpTimes[adapter.id] ?? 0,
            ))
        .toList(growable: false);

    final comparisons = <MobileClipEmbeddingComparisonSummary>[];
    if (availableAdapters.length >= 2) {
      for (var i = 0; i < availableAdapters.length; i++) {
        for (var j = i + 1; j < availableAdapters.length; j++) {
          final left = availableAdapters[i];
          final right = availableAdapters[j];
          comparisons.add(
            _buildComparison(
              leftRuns: runsByAdapter[left.id] ?? const <MobileClipAdapterRunResult>[],
              rightRuns: runsByAdapter[right.id] ?? const <MobileClipAdapterRunResult>[],
            ),
          );
        }
      }
    }

    return MobileClipBenchmarkReport(
      generatedAt: DateTime.now(),
      sampleCount: samples.length,
      usesSharedPreprocessing: true,
      adapterSummaries: summaries,
      comparisons: comparisons,
      warnings: warnings,
    );
  }

  Future<List<MobileClipBenchmarkSample>> _loadSamples(int sampleCount) async {
    final candidates = await _photoService.isar
        .collection<PhotoEntity>()
        .where()
        .sortByTimestampDesc()
        .limit(math.max(sampleCount * 4, sampleCount))
        .findAll();

    final samples = <MobileClipBenchmarkSample>[];
    for (final photo in candidates) {
      if (photo.path.trim().isEmpty) {
        continue;
      }
      final file = File(photo.path);
      if (!file.existsSync()) {
        continue;
      }
      samples.add(
        MobileClipBenchmarkSample(
          photoId: photo.id,
          assetId: photo.assetId,
          path: photo.path,
          timestamp: photo.timestamp,
        ),
      );
      if (samples.length >= sampleCount) {
        break;
      }
    }

    return samples;
  }

  MobileClipAdapterSummary _buildSummary({
    required MobileClipBenchmarkAdapter adapter,
    required List<MobileClipAdapterRunResult> runs,
    required double warmUpMs,
  }) {
    final latencies = runs.map((run) => run.elapsedMs).toList(growable: false)..sort();
    final meanLatency = latencies.isEmpty
        ? 0.0
        : latencies.reduce((a, b) => a + b) / latencies.length;
    final meanRssDelta = runs.isEmpty
        ? 0.0
        : runs.map((run) => run.rssDeltaBytes.toDouble()).reduce((a, b) => a + b) /
            runs.length;

    return MobileClipAdapterSummary(
      adapterId: adapter.id,
      displayName: adapter.displayName,
      sampleCount: runs.length,
      warmUpMs: warmUpMs,
      meanLatencyMs: meanLatency,
      p50LatencyMs: _percentile(latencies, 0.50),
      p90LatencyMs: _percentile(latencies, 0.90),
      maxLatencyMs: latencies.isEmpty ? 0.0 : latencies.last,
      meanRssDeltaBytes: meanRssDelta,
    );
  }

  MobileClipEmbeddingComparisonSummary _buildComparison({
    required List<MobileClipAdapterRunResult> leftRuns,
    required List<MobileClipAdapterRunResult> rightRuns,
  }) {
    final pairCount = math.min(leftRuns.length, rightRuns.length);
    final cosines = <double>[];
    final l2Distances = <double>[];
    var top1AgreementCount = 0;
    var overlapCount = 0.0;

    for (var index = 0; index < pairCount; index++) {
      final left = leftRuns[index];
      final right = rightRuns[index];
      cosines.add(_cosineSimilarity(left.embedding, right.embedding));
      l2Distances.add(_l2Distance(left.embedding, right.embedding));
      if (left.tags.isNotEmpty && right.tags.isNotEmpty && left.tags.first == right.tags.first) {
        top1AgreementCount++;
      }
      overlapCount += _top5Overlap(left.tags, right.tags);
    }

    cosines.sort();
    l2Distances.sort();

    return MobileClipEmbeddingComparisonSummary(
      leftAdapterId: leftRuns.isEmpty ? 'unknown' : leftRuns.first.adapterId,
      rightAdapterId: rightRuns.isEmpty ? 'unknown' : rightRuns.first.adapterId,
      sampleCount: pairCount,
      meanCosine: _mean(cosines),
      minCosine: cosines.isEmpty ? 0.0 : cosines.first,
      maxCosine: cosines.isEmpty ? 0.0 : cosines.last,
      meanL2Distance: _mean(l2Distances),
      top1AgreementRate: pairCount == 0 ? 0.0 : top1AgreementCount / pairCount,
      top5OverlapRate: pairCount == 0 ? 0.0 : overlapCount / pairCount,
    );
  }

  double _top5Overlap(List<String> left, List<String> right) {
    if (left.isEmpty || right.isEmpty) {
      return 0.0;
    }
    final overlap = left.take(5).where(right.take(5).toSet().contains).length;
    return overlap / 5.0;
  }

  double _cosineSimilarity(List<double> left, List<double> right) {
    if (left.isEmpty || right.isEmpty || left.length != right.length) {
      return 0.0;
    }

    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftNorm += left[index] * left[index];
      rightNorm += right[index] * right[index];
    }
    if (leftNorm == 0 || rightNorm == 0) {
      return 0.0;
    }
    return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }

  double _l2Distance(List<double> left, List<double> right) {
    if (left.isEmpty || right.isEmpty || left.length != right.length) {
      return 0.0;
    }

    var sum = 0.0;
    for (var index = 0; index < left.length; index++) {
      final delta = left[index] - right[index];
      sum += delta * delta;
    }
    return math.sqrt(sum);
  }

  double _mean(List<double> values) {
    if (values.isEmpty) {
      return 0.0;
    }
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _percentile(List<double> sortedValues, double percentile) {
    if (sortedValues.isEmpty) {
      return 0.0;
    }
    final index = ((sortedValues.length - 1) * percentile).round();
    return sortedValues[index.clamp(0, sortedValues.length - 1)];
  }
}