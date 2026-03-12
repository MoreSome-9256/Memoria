import 'package:flutter/material.dart';

import '../../models/mobileclip_benchmark.dart';
import '../../service/mobileclip_benchmark_service.dart';

class MobileClipBenchmarkPage extends StatefulWidget {
  const MobileClipBenchmarkPage({super.key});

  @override
  State<MobileClipBenchmarkPage> createState() => _MobileClipBenchmarkPageState();
}

class _MobileClipBenchmarkPageState extends State<MobileClipBenchmarkPage> {
  final MobileClipBenchmarkService _benchmarkService = MobileClipBenchmarkService();
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
      final report = await _benchmarkService.runBenchmark(sampleCount: _sampleCount);
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
    return Scaffold(
      appBar: AppBar(title: const Text('MobileCLIP Benchmark')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '同一批照片、同一份预处理输入，先跑 ONNX 基线，再为未来 ncnn FFI 对比保留统一报告结构。',
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
          if (_report != null) ...[
            const SizedBox(height: 16),
            _ReportOverviewCard(report: _report!),
            const SizedBox(height: 16),
            ..._report!.warnings.map((warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _WarningCard(message: warning),
                )),
            ..._report!.adapterSummaries.map(
              (summary) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AdapterSummaryCard(summary: summary),
              ),
            ),
            ..._report!.comparisons.map(
              (comparison) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ComparisonCard(comparison: comparison),
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
            Text(summary.displayName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('样本数: ${summary.sampleCount}'),
            Text('Warm-up: ${summary.warmUpMs.toStringAsFixed(1)} ms'),
            Text('平均延迟: ${summary.meanLatencyMs.toStringAsFixed(1)} ms'),
            Text('P50 / P90: ${summary.p50LatencyMs.toStringAsFixed(1)} / ${summary.p90LatencyMs.toStringAsFixed(1)} ms'),
            Text('最大延迟: ${summary.maxLatencyMs.toStringAsFixed(1)} ms'),
            Text('平均 RSS 增量: ${(summary.meanRssDeltaBytes / 1024 / 1024).toStringAsFixed(2)} MB'),
          ],
        ),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.comparison});

  final MobileClipEmbeddingComparisonSummary comparison;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${comparison.leftAdapterId} vs ${comparison.rightAdapterId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('样本对数: ${comparison.sampleCount}'),
            Text('平均余弦相似度: ${comparison.meanCosine.toStringAsFixed(6)}'),
            Text('余弦范围: ${comparison.minCosine.toStringAsFixed(6)} - ${comparison.maxCosine.toStringAsFixed(6)}'),
            Text('平均 L2 距离: ${comparison.meanL2Distance.toStringAsFixed(6)}'),
            Text('Top-1 一致率: ${(comparison.top1AgreementRate * 100).toStringAsFixed(1)}%'),
            Text('Top-5 重叠率: ${(comparison.top5OverlapRate * 100).toStringAsFixed(1)}%'),
          ],
        ),
      ),
    );
  }
}