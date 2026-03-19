import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:isar/isar.dart';

import '../models/entity/photo_entity.dart';
import '../models/mobileclip_benchmark.dart';
import 'mobileclip_tag_service.dart';
import 'mobileclip_vision_service.dart';
import 'ncnn_mobileclip_native_service.dart';
import 'photo_service.dart';

abstract class MobileClipBenchmarkAdapter {
  const MobileClipBenchmarkAdapter();

  String get id;
  String get displayName;
  bool get usesSharedPreprocessing;
  Future<bool> isAvailable();
  Future<String?> unavailableReason();

  Future<double> warmUp();

  Future<MobileClipAdapterRunResult> encodeImageBytes(
    Uint8List imageBytes, {
    Float32List? sharedInput,
    required MobileClipBenchmarkSample sample,
  });
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
  bool get usesSharedPreprocessing => true;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> unavailableReason() async => null;

  @override
  Future<double> warmUp() async {
    final stopwatch = Stopwatch()..start();
    await _visionService.warmUp();
    await _tagService.warmUp();
    stopwatch.stop();
    return stopwatch.elapsedMicroseconds / 1000.0;
  }

  @override
  Future<MobileClipAdapterRunResult> encodeImageBytes(
    Uint8List imageBytes, {
    Float32List? sharedInput,
    required MobileClipBenchmarkSample sample,
  }) async {
    final preprocessWatch = Stopwatch()..start();
    final input =
        sharedInput ??
        await _visionService.preprocessImageBytesForBenchmark(imageBytes);
    preprocessWatch.stop();
    final rssBefore = ProcessInfo.currentRss;
    final inferenceWatch = Stopwatch()..start();
    final embedding = await _visionService.embedPreprocessedInput(input);
    inferenceWatch.stop();
    final tagWatch = Stopwatch()..start();
    final tags = await _tagService.retrieveTags(embedding);
    tagWatch.stop();
    final rssAfter = ProcessInfo.currentRss;

    return MobileClipAdapterRunResult(
      sample: sample,
      adapterId: id,
      displayName: displayName,
      embedding: embedding,
      preprocessMs: preprocessWatch.elapsedMicroseconds / 1000.0,
      inferenceMs: inferenceWatch.elapsedMicroseconds / 1000.0,
      tagRetrievalMs: tagWatch.elapsedMicroseconds / 1000.0,
      totalMs:
          preprocessWatch.elapsedMicroseconds / 1000.0 +
          inferenceWatch.elapsedMicroseconds / 1000.0 +
          tagWatch.elapsedMicroseconds / 1000.0,
      rssBeforeBytes: rssBefore,
      rssAfterBytes: rssAfter,
      tags: tags,
    );
  }
}

class NcnnMobileClipBenchmarkAdapter extends MobileClipBenchmarkAdapter {
  NcnnMobileClipBenchmarkAdapter({
    NcnnMobileClipNativeService? nativeService,
    MobileClipTagService? tagService,
  }) : _nativeService = nativeService ?? NcnnMobileClipNativeService(),
       _tagService = tagService ?? MobileClipTagService();

  final NcnnMobileClipNativeService _nativeService;
  final MobileClipTagService _tagService;

  @override
  String get id => 'ncnn';

  @override
  String get displayName => 'ncnn FFI (author export)';

  @override
  bool get usesSharedPreprocessing => false;

  @override
  Future<bool> isAvailable() async {
    final status = _nativeService.getStatus();
    if (!status.libraryLoaded) {
      return false;
    }

    try {
      await _nativeService.ensureModelInitialized();
    } catch (_) {
      return false;
    }

    return _nativeService.getStatus().canEncode;
  }

  @override
  Future<String?> unavailableReason() async {
    final status = _nativeService.getStatus();
    if (!status.libraryLoaded) {
      return status.summary;
    }

    try {
      await _nativeService.ensureModelInitialized();
    } catch (error) {
      return error.toString();
    }

    return _nativeService.getStatus().summary;
  }

  @override
  Future<double> warmUp() async {
    final stopwatch = Stopwatch()..start();
    await _tagService.warmUp();
    await _nativeService.warmUp();
    stopwatch.stop();
    return stopwatch.elapsedMicroseconds / 1000.0;
  }

  @override
  Future<MobileClipAdapterRunResult> encodeImageBytes(
    Uint8List imageBytes, {
    Float32List? sharedInput,
    required MobileClipBenchmarkSample sample,
  }) async {
    final rssBefore = ProcessInfo.currentRss;
    final profile = await _nativeService.profileEncodeImageBytes(imageBytes);
    final tagWatch = Stopwatch()..start();
    final tags = await _tagService.retrieveTags(profile.embedding);
    tagWatch.stop();
    final rssAfter = ProcessInfo.currentRss;

    return MobileClipAdapterRunResult(
      sample: sample,
      adapterId: id,
      displayName: displayName,
      embedding: profile.embedding,
      preprocessMs: profile.preprocessMs,
      inferenceMs: profile.inferenceMs,
      tagRetrievalMs: tagWatch.elapsedMicroseconds / 1000.0,
      totalMs:
          profile.preprocessMs +
          profile.inferenceMs +
          tagWatch.elapsedMicroseconds / 1000.0,
      rssBeforeBytes: rssBefore,
      rssAfterBytes: rssAfter,
      tags: tags,
    );
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
             NcnnMobileClipBenchmarkAdapter(),
           ],
       _photoService = photoService ?? PhotoService();

  final List<MobileClipBenchmarkAdapter> _adapters;
  final PhotoService _photoService;
  Future<MobileClipBenchmarkReport> runBenchmark({
    int sampleCount = 24,
  }) async {
    final warnings = <String>[];
    final samples = await _loadSamples(sampleCount);
    if (samples.isEmpty) {
      return MobileClipBenchmarkReport(
        generatedAt: DateTime.now(),
        sampleCount: 0,
        usesSharedPreprocessing: false,
        adapterSummaries: const <MobileClipAdapterSummary>[],
        comparisons: const <MobileClipEmbeddingComparisonSummary>[],
        warnings: <String>['没有找到可用于 benchmark 的本地照片样本。'],
      );
    }

    final availableAdapters = <MobileClipBenchmarkAdapter>[];
    final unavailableAdapters = <MobileClipBenchmarkAdapter>[];
    for (final adapter in _adapters) {
      if (await adapter.isAvailable()) {
        availableAdapters.add(adapter);
      } else {
        unavailableAdapters.add(adapter);
      }
    }
    for (final adapter in unavailableAdapters) {
      final reason = await adapter.unavailableReason();
      warnings.add(
        '${adapter.displayName} 当前不可用：${reason ?? 'unknown reason'}',
      );
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

      for (final adapter in availableAdapters) {
        final runResult = await adapter.encodeImageBytes(
          bytes,
          sharedInput: null,
          sample: sample,
        );
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
      usesSharedPreprocessing:
          availableAdapters.isNotEmpty &&
          availableAdapters.every((adapter) => adapter.usesSharedPreprocessing),
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
    final totalLatencies = runs.map((run) => run.totalMs).toList(growable: false)
      ..sort();
    final meanPreprocess = runs.isEmpty
      ? 0.0
      : runs.map((run) => run.preprocessMs).reduce((a, b) => a + b) /
        runs.length;
    final meanInference = runs.isEmpty
      ? 0.0
      : runs.map((run) => run.inferenceMs).reduce((a, b) => a + b) /
        runs.length;
    final meanTagRetrieval = runs.isEmpty
      ? 0.0
      : runs.map((run) => run.tagRetrievalMs).reduce((a, b) => a + b) /
        runs.length;
    final meanTotal = totalLatencies.isEmpty
        ? 0.0
      : totalLatencies.reduce((a, b) => a + b) / totalLatencies.length;
    final meanRssDelta = runs.isEmpty
        ? 0.0
        : runs.map((run) => run.rssDeltaBytes.toDouble()).reduce((a, b) => a + b) /
            runs.length;

    return MobileClipAdapterSummary(
      adapterId: adapter.id,
      displayName: adapter.displayName,
      sampleCount: runs.length,
      warmUpMs: warmUpMs,
      meanPreprocessMs: meanPreprocess,
      meanInferenceMs: meanInference,
      meanTagRetrievalMs: meanTagRetrieval,
      meanTotalMs: meanTotal,
      p50TotalMs: _percentile(totalLatencies, 0.50),
      p90TotalMs: _percentile(totalLatencies, 0.90),
      maxTotalMs: totalLatencies.isEmpty ? 0.0 : totalLatencies.last,
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
    final worstCases = <MobileClipWorstCaseSample>[];
    var top1AgreementCount = 0;
    var overlapCount = 0.0;

    for (var index = 0; index < pairCount; index++) {
      final left = leftRuns[index];
      final right = rightRuns[index];
      final cosine = _cosineSimilarity(left.embedding, right.embedding);
      final l2Distance = _l2Distance(left.embedding, right.embedding);
      cosines.add(cosine);
      l2Distances.add(l2Distance);
      worstCases.add(
        MobileClipWorstCaseSample(
          sample: left.sample,
          cosine: cosine,
          l2Distance: l2Distance,
          leftTags: left.tags,
          rightTags: right.tags,
        ),
      );
      if (left.tags.isNotEmpty && right.tags.isNotEmpty && left.tags.first == right.tags.first) {
        top1AgreementCount++;
      }
      overlapCount += _top5Overlap(left.tags, right.tags);
    }

    cosines.sort();
    l2Distances.sort();
    worstCases.sort((a, b) => a.cosine.compareTo(b.cosine));

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
      worstCases: worstCases.take(5).toList(growable: false),
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