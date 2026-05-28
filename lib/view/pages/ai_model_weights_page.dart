import 'dart:async';

import 'package:flutter/material.dart';

import '../../service/ai_model_weight_service.dart';

class AiModelWeightsPage extends StatefulWidget {
  const AiModelWeightsPage({super.key});

  @override
  State<AiModelWeightsPage> createState() => _AiModelWeightsPageState();
}

class _AiModelWeightsPageState extends State<AiModelWeightsPage> {
  late Future<List<AiModelWeightStatus>> _future;
  final Map<AiModelWeightId, DownloadProgress> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _future = AiModelWeightService.instance.loadStatuses();
  }

  void _reload() {
    setState(() {
      _future = AiModelWeightService.instance.loadStatuses();
    });
  }

  Future<void> _delete(AiModelWeightId id) async {
    await AiModelWeightService.instance.deleteDownloadedWeights(id);
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('已删除 ${id.label} 的可下载权重文件'),
      ),
    );
  }

  Future<void> _download(AiModelWeightId id) async {
    setState(() {
      _downloadProgress[id] = const DownloadProgress(
        state: DownloadState.downloading,
        progress: 0.0,
        currentFile: 0,
        totalFiles: 1,
      );
    });

    await AiModelWeightService.instance.downloadWeights(
      id,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress[id] = progress;
          });
        }
      },
    );

    if (!mounted) return;
    _reload();

    final progress = _downloadProgress[id];
    if (progress?.state == DownloadState.completed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('已下载 ${id.label}'),
        ),
      );
    } else if (progress?.state == DownloadState.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('下载失败: ${progress?.error ?? "未知错误"}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelDownload(AiModelWeightId id) async {
    await AiModelWeightService.instance.cancelDownload(id);
    if (mounted) {
      setState(() {
        _downloadProgress.remove(id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 模型权重')),
      body: FutureBuilder<List<AiModelWeightStatus>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final statuses = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: statuses.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final status = statuses[index];
              final id = status.id;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                leading: Icon(
                  status.checkPassed
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: status.checkPassed ? Colors.green : Colors.red,
                ),
                title: Text(id.label),
                subtitle: Text(
                  '${id.description}\n'
                  '当前检查：${status.checkPassed ? '可推理' : '缺少权重'}'
                  '${status.hasDownloadedFiles ? ' · 已下载 ${status.presentFiles.length} 个文件' : ''}',
                ),
                isThreeLine: true,
                trailing: _buildTrailing(context, id, status),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTrailing(BuildContext context, AiModelWeightId id, AiModelWeightStatus status) {
    final progress = _downloadProgress[id];
    final isDownloading = AiModelWeightService.instance.isDownloading(id);

    if (isDownloading || progress != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress?.overallProgress ?? 0.0,
                ),
                const SizedBox(height: 4),
                Text(
                  '${((progress?.overallProgress ?? 0.0) * 100).toStringAsFixed(0)}% '
                  '(${progress?.currentFile ?? 0}/${progress?.totalFiles ?? 1})',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (progress?.state == DownloadState.downloading)
            IconButton(
              onPressed: () => _cancelDownload(id),
              icon: const Icon(Icons.cancel),
              tooltip: '取消',
            ),
        ],
      );
    }

    if (status.hasDownloadedFiles) {
      return TextButton(
        onPressed: () => _delete(id),
        child: const Text('删除'),
      );
    }

    return TextButton(
      onPressed: () => _download(id),
      child: const Text('下载'),
    );
  }
}
