import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/entity/photo_entity.dart';
import '../models/mobileclip_benchmark.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import 'mobileclip_tag_service.dart';
import 'mobileclip_vision_service.dart';
import 'ncnn_mobileclip_native_service.dart';
import 'onnx_session_provider_service.dart';

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
    double? sharedPreprocessMs,
    required MobileClipBenchmarkSample sample,
  });

  Future<void> dispose() async {}
}

class OnnxMobileClipBenchmarkAdapter extends MobileClipBenchmarkAdapter {
  OnnxMobileClipBenchmarkAdapter({
    required this.adapterId,
    required this.adapterDisplayName,
    required OnnxSessionProviderPreference providerPreference,
    MobileClipVisionService? visionService,
    MobileClipTagService? tagService,
  }) : _visionService =
           visionService ??
           MobileClipVisionService.withProviderPreference(providerPreference),
       _tagService = tagService ?? MobileClipTagService();

  final String adapterId;
  final String adapterDisplayName;
  final MobileClipVisionService _visionService;
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
    double? sharedPreprocessMs,
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

  @override
  Future<void> dispose() async {
    await _nativeService.dispose();
  }
}

class MobileClipBenchmarkService {
  MobileClipBenchmarkService({
    List<MobileClipBenchmarkAdapter>? adapters,
    PhotoService? photoService,
    MobileClipVisionService? sharedPreprocessingVisionService,
  }) : _adapters = adapters ?? _buildDefaultAdapters(),
       _photoService = photoService ?? PhotoService(),
       _sharedPreprocessingVisionService =
           sharedPreprocessingVisionService ??
           MobileClipVisionService.withProviderPreference(
             OnnxSessionProviderPreference.cpu,
           );

  final List<MobileClipBenchmarkAdapter> _adapters;
  final PhotoService _photoService;
  final MobileClipVisionService _sharedPreprocessingVisionService;

  static List<MobileClipBenchmarkAdapter> _buildDefaultAdapters() {
    final adapters = <MobileClipBenchmarkAdapter>[
      OnnxMobileClipBenchmarkAdapter(
        adapterId: 'onnx_nnapi_hardware',
        adapterDisplayName: 'ONNX NNAPI hardware',
        providerPreference: OnnxSessionProviderPreference.nnapiHardwareOnly,
      ),
      OnnxMobileClipBenchmarkAdapter(
        adapterId: 'onnx_cpu',
        adapterDisplayName: 'ONNX CPU',
        providerPreference: OnnxSessionProviderPreference.cpu,
      ),
    ];

    if (!Platform.isAndroid) {
      return <MobileClipBenchmarkAdapter>[
        OnnxMobileClipBenchmarkAdapter(
          adapterId: 'onnx_cpu',
          adapterDisplayName: 'ONNX CPU',
          providerPreference: OnnxSessionProviderPreference.cpu,
        ),
      ];
    }

    return adapters;
  }

  Future<MobileClipBenchmarkReport> runBenchmark({int sampleCount = 24}) async {
    try {
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
          sharedInput = await _sharedPreprocessingVisionService
              .preprocessImageBytesForBenchmark(bytes);
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
      await _sharedPreprocessingVisionService.dispose();
      for (final adapter in _adapters) {
        await adapter.dispose();
      }
    }
  }

  Future<List<MobileClipBenchmarkSample>> _loadSamples(int sampleCount) async {
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final q = photoBox.query()
        .order(PhotoEntity_.timestamp, flags: Order.descending)
        .build();
    q.limit = math.max(sampleCount * 4, sampleCount);
    final candidates = q.find();
    q.close();

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
