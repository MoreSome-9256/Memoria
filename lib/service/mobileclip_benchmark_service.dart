/// MobileCLIP 基准测试服务，负责收集模型运行时性能数据。

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/mobileclip_benchmark.dart';
import 'litert_inference_service.dart';
import 'mobileclip_litert_service.dart';
import 'mobileclip_tag_service.dart';

abstract class MobileClipBenchmarkAdapter {
  const MobileClipBenchmarkAdapter();

  String get id;
  String get displayName;
  bool get usesSharedPreprocessing;
  Future<bool> isAvailable();
  Future<String?> unavailableReason();

  Future<double> warmUp();

  Future<Float32List> encodePreprocessedInput(Uint8List imageBytes);

  Future<MobileClipAdapterRunResult> encodeImageBytes(
    Uint8List imageBytes, {
    Float32List? sharedInput,
    double? sharedPreprocessMs,
    required MobileClipBenchmarkSample sample,
  });

  Future<void> dispose() async {}
}

class LiteRtMobileClipBenchmarkAdapter extends MobileClipBenchmarkAdapter {
  LiteRtMobileClipBenchmarkAdapter({
    required this.adapterId,
    required this.adapterDisplayName,
    required LocalInferenceAccelerator accelerator,
    MobileClipLiteRtService? visionService,
    MobileClipTagService? tagService,
  }) : _visionService =
           visionService ??
           MobileClipLiteRtService.detachedWithAccelerator(accelerator),
       _tagService = tagService ?? MobileClipTagService();

  final String adapterId;
  final String adapterDisplayName;
  final MobileClipLiteRtService _visionService;
  final MobileClipTagService _tagService;

  @override
  String get id => adapterId;

  @override
  String get displayName {
    final providerLabel = _visionService.executionProviderLabel;
    if (providerLabel == 'Pending session init') {
      return adapterDisplayName;
    }
    return '$adapterDisplayName ($providerLabel)';
  }

  @override
  bool get usesSharedPreprocessing => true;

  @override
  Future<bool> isAvailable() async {
    try {
      await _visionService.warmUp();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> unavailableReason() async {
    try {
      await _visionService.warmUp();
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  @override
  Future<double> warmUp() async {
    final stopwatch = Stopwatch()..start();
    await _visionService.warmUp();
    await _tagService.warmUp();
    stopwatch.stop();
    return stopwatch.elapsedMicroseconds / 1000.0;
  }

  @override
  Future<Float32List> encodePreprocessedInput(Uint8List imageBytes) {
    return _visionService.preprocessImageBytesForBenchmark(imageBytes);
  }

  @override
  Future<MobileClipAdapterRunResult> encodeImageBytes(
    Uint8List imageBytes, {
    Float32List? sharedInput,
    double? sharedPreprocessMs,
    required MobileClipBenchmarkSample sample,
  }) async {
    final Float32List input;
    final double preprocessMs;
    if (sharedInput != null) {
      input = sharedInput;
      preprocessMs = sharedPreprocessMs ?? 0.0;
    } else {
      final preprocessWatch = Stopwatch()..start();
      input = await _visionService.preprocessImageBytesForBenchmark(imageBytes);
      preprocessWatch.stop();
      preprocessMs = preprocessWatch.elapsedMicroseconds / 1000.0;
    }
    final rssBefore = ProcessInfo.currentRss;
    final inferenceWatch = Stopwatch()..start();
    final embedding = await _visionService.embedPreprocessedImageInput(input);
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
      preprocessMs: preprocessMs,
      inferenceMs: inferenceWatch.elapsedMicroseconds / 1000.0,
      tagRetrievalMs: tagWatch.elapsedMicroseconds / 1000.0,
      totalMs:
          preprocessMs +
          inferenceWatch.elapsedMicroseconds / 1000.0 +
          tagWatch.elapsedMicroseconds / 1000.0,
      rssBeforeBytes: rssBefore,
      rssAfterBytes: rssAfter,
      tags: tags,
    );
  }

  @override
  Future<void> dispose() async {
    await _visionService.dispose();
  }
}

class MobileClipBenchmarkService {
  MobileClipBenchmarkService({
    List<MobileClipBenchmarkAdapter>? adapters,
  }) : _adapters = adapters ?? _buildDefaultAdapters();

  final List<MobileClipBenchmarkAdapter> _adapters;

  static List<MobileClipBenchmarkAdapter> _buildDefaultAdapters() {
    final accelerators = Platform.isAndroid
        ? const <(String, String, LocalInferenceAccelerator)>[
            ('litert_gpu', 'LiteRT GPU', LocalInferenceAccelerator.gpu),
            ('litert_npu', 'LiteRT NPU', LocalInferenceAccelerator.npu),
            (
              'litert_xnnpack',
              'LiteRT XNNPACK',
              LocalInferenceAccelerator.xnnpack,
            ),
            ('litert_cpu', 'LiteRT CPU', LocalInferenceAccelerator.cpu),
          ]
        : (Platform.isIOS || Platform.isMacOS)
        ? const <(String, String, LocalInferenceAccelerator)>[
            (
              'litert_coreml',
              'LiteRT Core ML',
              LocalInferenceAccelerator.coreml,
            ),
            ('litert_metal', 'LiteRT Metal', LocalInferenceAccelerator.metal),
            (
              'litert_xnnpack',
              'LiteRT XNNPACK',
              LocalInferenceAccelerator.xnnpack,
            ),
            ('litert_cpu', 'LiteRT CPU', LocalInferenceAccelerator.cpu),
          ]
        : const <(String, String, LocalInferenceAccelerator)>[
            (
              'litert_xnnpack',
              'LiteRT XNNPACK',
              LocalInferenceAccelerator.xnnpack,
            ),
            ('litert_cpu', 'LiteRT CPU', LocalInferenceAccelerator.cpu),
          ];

    return accelerators.map((entry) {
      return LiteRtMobileClipBenchmarkAdapter(
        adapterId: entry.$1,
        adapterDisplayName: entry.$2,
        accelerator: entry.$3,
      );
    }).toList(growable: false);
  }

  Future<MobileClipBenchmarkReport> runBenchmark({
    required List<MobileClipBenchmarkSample> samples,
  }) async {
    try {
      final warnings = <String>[];
      if (samples.isEmpty) {
        return MobileClipBenchmarkReport(
          generatedAt: DateTime.now(),
          sampleCount: 0,
          usesSharedPreprocessing: false,
          adapterSummaries: const <MobileClipAdapterSummary>[],
          comparisons: const <MobileClipEmbeddingComparisonSummary>[],
          warnings: <String>['请先从相册选择用于 benchmark 的图片样本。'],
        );
      }

      final availableAdapters = <MobileClipBenchmarkAdapter>[];
      for (final adapter in _adapters) {
        if (await adapter.isAvailable()) {
          availableAdapters.add(adapter);
          continue;
        }

        final reason = await adapter.unavailableReason();
        warnings.add(
          '${adapter.displayName} 当前不可用：${reason ?? 'unknown reason'}',
        );
      }

      final warmedAdapters = <MobileClipBenchmarkAdapter>[];
      final warmUpTimes = <String, double>{};
      await MobileClipTagService().warmUp();
      for (final adapter in availableAdapters) {
        try {
          warmUpTimes[adapter.id] = await adapter.warmUp();
          warmedAdapters.add(adapter);
        } catch (error) {
          warnings.add('${adapter.displayName} 预热失败：$error');
        }
      }

      final runsByAdapter = <String, List<MobileClipAdapterRunResult>>{
        for (final adapter in warmedAdapters)
          adapter.id: <MobileClipAdapterRunResult>[],
      };
      final sharedPreprocessingEnabled =
          warmedAdapters.isNotEmpty &&
          warmedAdapters.every((adapter) => adapter.usesSharedPreprocessing);

      for (final sample in samples) {
        final file = File(sample.path);
        if (!file.existsSync()) {
          warnings.add('样本 ${sample.photoId} 的文件不存在，已跳过。');
          continue;
        }

        final bytes = await file.readAsBytes();
        Float32List? sharedInput;
        double? sharedPreprocessMs;
        if (sharedPreprocessingEnabled) {
          final preprocessWatch = Stopwatch()..start();
          sharedInput = await warmedAdapters.first.encodePreprocessedInput(
            bytes,
          );
          preprocessWatch.stop();
          sharedPreprocessMs = preprocessWatch.elapsedMicroseconds / 1000.0;
        }

        for (final adapter in warmedAdapters) {
          final runResult = await adapter.encodeImageBytes(
            bytes,
            sharedInput: adapter.usesSharedPreprocessing ? sharedInput : null,
            sharedPreprocessMs: adapter.usesSharedPreprocessing
                ? sharedPreprocessMs
                : null,
            sample: sample,
          );
          runsByAdapter[adapter.id]!.add(runResult);
        }
      }

      final summaries = warmedAdapters
          .map(
            (adapter) => _buildSummary(
              adapter: adapter,
              runs:
                  runsByAdapter[adapter.id] ??
                  const <MobileClipAdapterRunResult>[],
              warmUpMs: warmUpTimes[adapter.id] ?? 0,
            ),
          )
          .toList(growable: false);

      final comparisons = <MobileClipEmbeddingComparisonSummary>[];
      if (warmedAdapters.length >= 2) {
        for (var i = 0; i < warmedAdapters.length; i++) {
          for (var j = i + 1; j < warmedAdapters.length; j++) {
            final left = warmedAdapters[i];
            final right = warmedAdapters[j];
            comparisons.add(
              _buildComparison(
                leftRuns:
                    runsByAdapter[left.id] ??
                    const <MobileClipAdapterRunResult>[],
                rightRuns:
                    runsByAdapter[right.id] ??
                    const <MobileClipAdapterRunResult>[],
              ),
            );
          }
        }
      }

      return MobileClipBenchmarkReport(
        generatedAt: DateTime.now(),
        sampleCount: samples.length,
        usesSharedPreprocessing: sharedPreprocessingEnabled,
        adapterSummaries: summaries,
        comparisons: comparisons,
        warnings: warnings,
      );
    } finally {
      for (final adapter in _adapters) {
        await adapter.dispose();
      }
    }
  }

  MobileClipAdapterSummary _buildSummary({
    required MobileClipBenchmarkAdapter adapter,
    required List<MobileClipAdapterRunResult> runs,
    required double warmUpMs,
  }) {
    final totalLatencies =
        runs.map((run) => run.totalMs).toList(growable: false)..sort();
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
        : runs
                  .map((run) => run.rssDeltaBytes.toDouble())
                  .reduce((a, b) => a + b) /
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
      if (left.tags.isNotEmpty &&
          right.tags.isNotEmpty &&
          left.tags.first == right.tags.first) {
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
