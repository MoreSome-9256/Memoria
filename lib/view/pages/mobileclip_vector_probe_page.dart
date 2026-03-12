import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../service/mobileclip_vision_service.dart';
import '../../service/ncnn_mobileclip_native_service.dart';

class MobileClipVectorProbePage extends StatefulWidget {
  const MobileClipVectorProbePage({super.key});

  @override
  State<MobileClipVectorProbePage> createState() =>
      _MobileClipVectorProbePageState();
}

class _MobileClipVectorProbePageState extends State<MobileClipVectorProbePage> {
  final MobileClipVisionService _visionService = MobileClipVisionService();
  final NcnnMobileClipNativeService _ncnnService = NcnnMobileClipNativeService();

  bool _isRunning = false;
  String? _errorMessage;
  String? _reportFilePath;
  List<_VectorProbeResult> _results = const <_VectorProbeResult>[];

  @override
  void initState() {
    super.initState();
    _runProbe();
  }

  Future<void> _runProbe() async {
    setState(() {
      _isRunning = true;
      _errorMessage = null;
    });

    try {
      await _visionService.warmUp();
      await _ncnnService.ensureModelInitialized();
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
          ..._results.map((result) => _VectorProbeCard(result: result)),
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