import 'package:flutter/material.dart';

import '../../models/mobileclip_benchmark.dart';
import '../../service/mobileclip_benchmark_service.dart';
import '../widgets/path_image.dart';

class MobileClipBenchmarkPage extends StatefulWidget {
  const MobileClipBenchmarkPage({super.key});

  @override
  State<MobileClipBenchmarkPage> createState() =>
      _MobileClipBenchmarkPageState();
}

class _MobileClipBenchmarkPageState extends State<MobileClipBenchmarkPage> {
  final MobileClipBenchmarkService _benchmarkService =
      MobileClipBenchmarkService();
  int _sampleCount = 24;
  bool _isRunning = false;
  MobileClipBenchmarkReport? _report;
  String? _errorMessage;

  Future<void> _runBenchmark() async {
    setState(() {
      _isRunning = true;
      _errorMessage = null;
    });

    try {
      final report = await _benchmarkService.runBenchmark(
        sampleCount: _sampleCount,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _report = report;
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

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final summariesById = report == null
        ? const <String, MobileClipAdapterSummary>{}
        : <String, MobileClipAdapterSummary>{
            for (final summary in report.adapterSummaries)
              summary.adapterId: summary,
          };
    final cpuSummary = summariesById['onnx_cpu'];
    final npuSummary = summariesById['onnx_nnapi_hardware'];

    return Scaffold(
      appBar: AppBar(title: const Text('MobileCLIP Benchmark')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '在同一批照片上对比同一个 MobileCLIP2 ONNX 模型在手机端 CPU 与 NNAPI hardware 上的速度。当前默认会展示 ONNX CPU 与 ONNX NNAPI hardware 两条链路，且共享同一份 Flutter 预处理输入。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('样本数量', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment<int>(value: 12, label: Text('12')),
                      ButtonSegment<int>(value: 24, label: Text('24')),
                      ButtonSegment<int>(value: 48, label: Text('48')),
                    ],
                    selected: <int>{_sampleCount},
                    onSelectionChanged: _isRunning
                        ? null
                        : (selection) {
                            setState(() {
                              _sampleCount = selection.first;
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isRunning ? null : _runBenchmark,
                    icon: _isRunning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.speed_outlined),
                    label: Text(_isRunning ? '运行中...' : '开始 Benchmark'),
                  ),
                ],
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_errorMessage!),
              ),
            ),
          ],
          if (report != null) ...[
            const SizedBox(height: 16),
            _ReportOverviewCard(report: report),
            const SizedBox(height: 16),
            if (cpuSummary != null && npuSummary != null) ...[
              _SpeedupCard(cpuSummary: cpuSummary, npuSummary: npuSummary),
              const SizedBox(height: 16),
            ],
            ...report.warnings.map(
              (warning) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _WarningCard(message: warning),
              ),
            ),
            ...report.adapterSummaries.map(
              (summary) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AdapterSummaryCard(summary: summary),
              ),
            ),
            ...report.comparisons.map(
              (comparison) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ComparisonCard(
                  comparison: comparison,
                  displayNamesById: <String, String>{
                    for (final summary in report.adapterSummaries)
                      summary.adapterId: summary.displayName,
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportOverviewCard extends StatelessWidget {
  const _ReportOverviewCard({required this.report});

  final MobileClipBenchmarkReport report;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('运行概览', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('样本数: ${report.sampleCount}'),
            Text('共享预处理: ${report.usesSharedPreprocessing ? '是' : '否'}'),
            Text('生成时间: ${report.generatedAt.toLocal()}'),
          ],
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _AdapterSummaryCard extends StatelessWidget {
  const _AdapterSummaryCard({required this.summary});

  final MobileClipAdapterSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('样本数: ${summary.sampleCount}'),
            Text('Warm-up: ${summary.warmUpMs.toStringAsFixed(1)} ms'),
            Text('平均预处理: ${summary.meanPreprocessMs.toStringAsFixed(1)} ms'),
            Text('平均推理: ${summary.meanInferenceMs.toStringAsFixed(1)} ms'),
            Text('平均标签检索: ${summary.meanTagRetrievalMs.toStringAsFixed(1)} ms'),
            Text('平均总耗时: ${summary.meanTotalMs.toStringAsFixed(1)} ms'),
            Text(
              'P50 / P90 总耗时: ${summary.p50TotalMs.toStringAsFixed(1)} / ${summary.p90TotalMs.toStringAsFixed(1)} ms',
            ),
            Text('最大总耗时: ${summary.maxTotalMs.toStringAsFixed(1)} ms'),
            Text(
              '平均 RSS 增量: ${(summary.meanRssDeltaBytes / 1024 / 1024).toStringAsFixed(2)} MB',
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedupCard extends StatelessWidget {
  const _SpeedupCard({required this.cpuSummary, required this.npuSummary});

  final MobileClipAdapterSummary cpuSummary;
  final MobileClipAdapterSummary npuSummary;

  @override
  Widget build(BuildContext context) {
    final inferenceSpeedup = _speedup(
      baselineMs: cpuSummary.meanInferenceMs,
      candidateMs: npuSummary.meanInferenceMs,
    );
    final totalSpeedup = _speedup(
      baselineMs: cpuSummary.meanTotalMs,
      candidateMs: npuSummary.meanTotalMs,
    );

    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CPU vs NNAPI hardware 速度对比',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '平均推理: CPU ${cpuSummary.meanInferenceMs.toStringAsFixed(1)} ms, '
              'NNAPI hardware ${npuSummary.meanInferenceMs.toStringAsFixed(1)} ms, '
              '加速比 $inferenceSpeedup',
            ),
            Text(
              '平均总耗时: CPU ${cpuSummary.meanTotalMs.toStringAsFixed(1)} ms, '
              'NNAPI hardware ${npuSummary.meanTotalMs.toStringAsFixed(1)} ms, '
              '加速比 $totalSpeedup',
            ),
            Text(
              '共享预处理后，这里的差异主要反映 ONNX Runtime 在 CPU 与 NNAPI hardware 上的执行差异。',
            ),
          ],
        ),
      ),
    );
  }

  String _speedup({required double baselineMs, required double candidateMs}) {
    if (baselineMs <= 0 || candidateMs <= 0) {
      return '-';
    }
    return '${(baselineMs / candidateMs).toStringAsFixed(2)}x';
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.comparison,
    required this.displayNamesById,
  });

  final MobileClipEmbeddingComparisonSummary comparison;
  final Map<String, String> displayNamesById;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${displayNamesById[comparison.leftAdapterId] ?? comparison.leftAdapterId} vs '
              '${displayNamesById[comparison.rightAdapterId] ?? comparison.rightAdapterId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('样本对数: ${comparison.sampleCount}'),
            Text('平均余弦相似度: ${comparison.meanCosine.toStringAsFixed(6)}'),
            Text(
              '余弦范围: ${comparison.minCosine.toStringAsFixed(6)} - ${comparison.maxCosine.toStringAsFixed(6)}',
            ),
            Text('平均 L2 距离: ${comparison.meanL2Distance.toStringAsFixed(6)}'),
            Text(
              'Top-1 一致率: ${(comparison.top1AgreementRate * 100).toStringAsFixed(1)}%',
            ),
            Text(
              'Top-5 重叠率: ${(comparison.top5OverlapRate * 100).toStringAsFixed(1)}%',
            ),
            if (comparison.worstCases.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('最低余弦样本', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...comparison.worstCases.map(
                (worstCase) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _WorstCaseRow(worstCase: worstCase),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorstCaseRow extends StatelessWidget {
  const _WorstCaseRow({required this.worstCase});

  final MobileClipWorstCaseSample worstCase;

  @override
  Widget build(BuildContext context) {
    final pathSegments = worstCase.sample.path.split(RegExp(r'[\\/]'));
    final fileName = pathSegments.isEmpty
        ? worstCase.sample.path
        : pathSegments.last;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: PathImage(
                  path: worstCase.sample.path,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(fileName, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text('photoId: ${worstCase.sample.photoId}'),
            SelectableText(worstCase.sample.path),
            Text('cosine: ${worstCase.cosine.toStringAsFixed(6)}'),
            Text('l2: ${worstCase.l2Distance.toStringAsFixed(6)}'),
            Text('left tags: ${worstCase.leftTags.join(', ')}'),
            Text('right tags: ${worstCase.rightTags.join(', ')}'),
          ],
        ),
      ),
    );
  }
}
