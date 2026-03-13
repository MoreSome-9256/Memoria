import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/tag_dictionary.dart';
import '../../service/mobileclip_vision_service.dart';
import '../../service/ncnn_mobileclip_native_service.dart';
import '../../service/semantic_matching_service.dart';

class MobileClipVectorProbePage extends StatefulWidget {
  const MobileClipVectorProbePage({super.key});

  @override
  State<MobileClipVectorProbePage> createState() =>
      _MobileClipVectorProbePageState();
}

class _MobileClipVectorProbePageState extends State<MobileClipVectorProbePage> {
  final MobileClipVisionService _visionService = MobileClipVisionService();
  final NcnnMobileClipNativeService _ncnnService = NcnnMobileClipNativeService();
  final SemanticMatchingService _semanticService = SemanticMatchingService();

  bool _isRunning = false;
  String? _errorMessage;
  String? _zeroShotWarning;
  String? _reportFilePath;
  List<_VectorProbeResult> _results = const <_VectorProbeResult>[];
  List<_ZeroShotResult> _zeroShotResults = const <_ZeroShotResult>[];

  @override
  void initState() {
    super.initState();
    _runProbe();
  }

  Future<void> _runProbe() async {
    setState(() {
      _isRunning = true;
      _errorMessage = null;
      _zeroShotWarning = null;
    });

    try {
      await _visionService.warmUp();
      await _ncnnService.ensureModelInitialized();
      var zeroShotEnabled = true;
      try {
        await _semanticService.warmUp();
        await _semanticService.preCacheTagMap(memoriaMasterTaxonomyPromptToLabel);
      } catch (error) {
        zeroShotEnabled = false;
        final message = error.toString();
        if (message.contains('ArgMax') || message.contains('/ArgMax')) {
          _zeroShotWarning =
              '当前设备内置 onnxruntime 不支持 ArgMax 算子，已自动跳过零样本打标，只保留视觉向量探针。\n\n'
              '建议：升级 onnxruntime Android 运行库后再开启语义打标。';
        } else {
          _zeroShotWarning =
              '零样本打标初始化失败，已自动跳过：$message';
        }
      }
      final output = <_VectorProbeResult>[];

      for (final sample in _probeSamples) {
        final bytes = (await rootBundle.load(sample.assetPath)).buffer.asUint8List();
        final input = await _visionService.preprocessImageBytesForBenchmark(bytes);
        final onnxVector = await _visionService.embedPreprocessedInput(input);
        final ncnnVector = await _ncnnService.encodeImageBytes(bytes);

        output.add(
          _VectorProbeResult(
            sample: sample,
            onnxVector: onnxVector,
            ncnnVector: ncnnVector,
            cosine: _cosine(onnxVector, ncnnVector),
            l2Distance: _l2Distance(onnxVector, ncnnVector),
          ),
        );
      }

      // Zero-shot tagging: reuse the onnxVectors already computed above.
      final zsOutput = <_ZeroShotResult>[];
      if (zeroShotEnabled) {
        for (final probeResult in output) {
          final scored = await _semanticService.scoreTagsForImage(
            imageVector: probeResult.onnxVector,
            tagMap: memoriaMasterTaxonomyPromptToLabel,
            topK: 3,
          );
          zsOutput.add(
            _ZeroShotResult(label: probeResult.sample.label, scored: scored),
          );
          debugPrint(
            'ZERO_SHOT [${probeResult.sample.label}]: '
            '${scored.map((e) => "${e.label}=${e.score.toStringAsFixed(4)}").join(", ")}',
          );
        }
      }

      final report = <String, Object?>{
        'results': output.map((item) => item.toJson()).toList(growable: false),
      };
      final reportFilePath = await _writeReportToFile(report);
      debugPrint('MOBILECLIP_VECTOR_PROBE_JSON=${jsonEncode(report)}');
      debugPrint('MOBILECLIP_VECTOR_PROBE_FILE=$reportFilePath');

      if (!mounted) {
        return;
      }
      setState(() {
        _results = output;
        _zeroShotResults = zsOutput;
        _reportFilePath = reportFilePath;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  Future<String> _writeReportToFile(Map<String, Object?> report) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/mobileclip_vector_probe.json');
    await file.writeAsString(jsonEncode(report), flush: true);
    return file.path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MobileCLIP Vector Probe'),
        actions: [
          IconButton(
            onPressed: _isRunning ? null : _runProbe,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '固定测试三张图片，ONNX 使用当前 Flutter 预处理；NCNN 使用作者提供的 mobileclip_s2_export 模型和 native resize/normalize。完整 JSON 会输出到 debug log。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_reportFilePath != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('结果文件'),
                    const SizedBox(height: 8),
                    SelectableText(_reportFilePath!),
                  ],
                ),
              ),
            ),
          if (_isRunning)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: Text('正在提取手机端 ONNX / NCNN 向量...')),
                  ],
                ),
              ),
            ),
          if (_errorMessage != null) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_errorMessage!),
              ),
            ),
          ],
          if (_zeroShotWarning != null) ...[
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_zeroShotWarning!),
              ),
            ),
          ],
          ..._results.map((result) => _VectorProbeCard(result: result)),
          if (_zeroShotResults.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '🏷️ 零样本打标 (Zero-Shot Tagging)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 4),
            ..._zeroShotResults.map((r) => _ZeroShotCard(result: r)),
          ],
        ],
      ),
    );
  }
}

class _VectorProbeCard extends StatelessWidget {
  const _VectorProbeCard({required this.result});

  final _VectorProbeResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    result.sample.assetPath,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.sample.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      SelectableText(result.sample.assetPath),
                      const SizedBox(height: 6),
                      Text('cosine(onnx, ncnn): ${result.cosine.toStringAsFixed(6)}'),
                      Text('l2(onnx, ncnn): ${result.l2Distance.toStringAsFixed(6)}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText('onnx first16: ${_formatVectorSlice(result.onnxVector, 16)}'),
            const SizedBox(height: 8),
            SelectableText('ncnn first16: ${_formatVectorSlice(result.ncnnVector, 16)}'),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('完整向量 JSON'),
              children: [
                SelectableText(jsonEncode(result.toJson())),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProbeSample {
  const _ProbeSample({required this.label, required this.assetPath});

  final String label;
  final String assetPath;
}

class _VectorProbeResult {
  const _VectorProbeResult({
    required this.sample,
    required this.onnxVector,
    required this.ncnnVector,
    required this.cosine,
    required this.l2Distance,
  });

  final _ProbeSample sample;
  final List<double> onnxVector;
  final List<double> ncnnVector;
  final double cosine;
  final double l2Distance;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': sample.label,
      'assetPath': sample.assetPath,
      'onnxVector': onnxVector,
      'ncnnVector': ncnnVector,
      'cosine': cosine,
      'l2Distance': l2Distance,
    };
  }
}

const List<_ProbeSample> _probeSamples = <_ProbeSample>[
  _ProbeSample(label: 'student', assetPath: 'ai_tools/test_student.png'),
  _ProbeSample(label: 'test1', assetPath: 'ai_tools/test1.png'),
  _ProbeSample(label: 'youleyuan', assetPath: 'ai_tools/test_youleyuan.png'),
];

double _cosine(List<double> left, List<double> right) {
  final usable = math.min(left.length, right.length);
  var dot = 0.0;
  for (var index = 0; index < usable; index++) {
    dot += left[index] * right[index];
  }
  return dot;
}

double _l2Distance(List<double> left, List<double> right) {
  final usable = math.min(left.length, right.length);
  var sum = 0.0;
  for (var index = 0; index < usable; index++) {
    final delta = left[index] - right[index];
    sum += delta * delta;
  }
  return math.sqrt(sum);
}

String _formatVectorSlice(List<double> vector, int count) {
  final preview = vector.take(count).map((value) => value.toStringAsFixed(6));
  return '[${preview.join(', ')}]';
}

// ---------------------------------------------------------------------------
// Zero-shot result data + card widget
// ---------------------------------------------------------------------------

class _ZeroShotResult {
  _ZeroShotResult({required this.label, required this.scored});

  final String label;
  final List<({String label, double score})> scored;
}

class _ZeroShotCard extends StatelessWidget {
  const _ZeroShotCard({required this.result});

  final _ZeroShotResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.label,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            ...result.scored.map((entry) {
              final pct = entry.score.clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.label,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          entry.score.toStringAsFixed(4),
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 7,
                        backgroundColor:
                            colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}