// MobileCLIP 基准测试页面，用于测试模型性能和资源占用。

import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/mobileclip_benchmark.dart';
import '../../service/mobileclip_benchmark_service.dart';
import '../widgets/path_image.dart';
import 'vlm_photo_picker_page.dart';

class MobileClipBenchmarkPage extends StatefulWidget {
  const MobileClipBenchmarkPage({super.key});

  @override
  State<MobileClipBenchmarkPage> createState() =>
      _MobileClipBenchmarkPageState();
}

class _MobileClipBenchmarkPageState extends State<MobileClipBenchmarkPage> {
  final MobileClipBenchmarkService _benchmarkService =
      MobileClipBenchmarkService();
  List<MobileClipBenchmarkSample> _samples =
      const <MobileClipBenchmarkSample>[];
  bool _isRunning = false;
  MobileClipBenchmarkReport? _report;
  String? _errorMessage;

  Future<void> _pickSamples() async {
    final result = await Navigator.of(context).push<List<VlmPhotoPickerResult>>(
      MaterialPageRoute<List<VlmPhotoPickerResult>>(
        builder: (context) => const VlmPhotoPickerPage(
          maxSelection: 48,
          title: '选择 Benchmark 图片',
        ),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() {
      _samples = result
          .map((item) {
            return MobileClipBenchmarkSample(
              photoId: 0,
              assetId: item.assetId,
              path: item.path,
              timestamp: item.createdAt.millisecondsSinceEpoch,
            );
          })
          .toList(growable: false);
      _report = null;
      _errorMessage = null;
    });
  }

  Future<void> _runBenchmark() async {
    setState(() {
      _isRunning = true;
      _errorMessage = null;
    });

    try {
      final report = await _benchmarkService.runBenchmark(samples: _samples);
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
    return Scaffold(
      appBar: AppBar(title: const Text('MobileCLIP Benchmark')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            Platform.isAndroid
                ? '从相册选择同一批图片，对比 MobileCLIP2 LiteRT XNNPACK、CPU 与 NCNN 路径上的 embedding、标签和速度。'
                : '从相册选择同一批图片，对比当前平台可用的 LiteRT 后端 embedding、标签和速度。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Benchmark 样本',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('已选择 ${_samples.length} 张图片'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _isRunning ? null : _pickSamples,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('从相册选择图片'),
                      ),
                      FilledButton.icon(
                        onPressed: _isRunning || _samples.isEmpty
                            ? null
                            : _runBenchmark,
                        icon: _isRunning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.speed_outlined),
                        label: Text(_isRunning ? '运行中...' : '开始 Benchmark'),
                      ),
                    ],
                  ),
                  if (_samples.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _SelectedSamplesStrip(samples: _samples),
                  ],
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

class _SelectedSamplesStrip extends StatelessWidget {
  const _SelectedSamplesStrip({required this.samples});

  final List<MobileClipBenchmarkSample> samples;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: samples.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final sample = samples[index];
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 72,
              height: 72,
              child: PathImage(path: sample.path, fit: BoxFit.cover),
            ),
          );
        },
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
