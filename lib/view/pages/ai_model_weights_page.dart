import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';

import '../../service/ai_model_weight_service.dart';

class AiModelWeightsPage extends StatefulWidget {
  const AiModelWeightsPage({super.key});

  @override
  State<AiModelWeightsPage> createState() => _AiModelWeightsPageState();
}

class _AiModelWeightsPageState extends State<AiModelWeightsPage> {
  late Future<List<AiModelWeightStatus>> _future;
  final Map<AiModelWeightId, double> _downloadProgress = {};
  final Map<AiModelWeightId, TaskStatus> _downloadStatus = {};

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
      _downloadProgress[id] = 0.0;
      _downloadStatus[id] = TaskStatus.running;
    });
    
    await AiModelWeightService.instance.downloadWeights(
      id,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _downloadProgress[id] = progress;
            _downloadStatus[id] = status;
          });
        }
      },
    );
    
    if (!mounted) return;
    _reload();
    
    if (_downloadStatus[id] == TaskStatus.complete) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('已下载 ${id.label}'),
        ),
      );
    }
  }
  
  Future<void> _pauseDownload(AiModelWeightId id) async {
    await AiModelWeightService.instance.pauseDownload(id);
    if (mounted) {
      setState(() {
        _downloadStatus[id] = TaskStatus.paused;
      });
    }
  }
  
  Future<void> _resumeDownload(AiModelWeightId id) async {
    await AiModelWeightService.instance.resumeDownload(id);
    if (mounted) {
      setState(() {
        _downloadStatus[id] = TaskStatus.running;
      });
    }
  }
  
  Future<void> _cancelDownload(AiModelWeightId id) async {
    await AiModelWeightService.instance.cancelDownload(id);
    if (mounted) {
      setState(() {
        _downloadProgress.remove(id);
        _downloadStatus.remove(id);
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
    final isDownloading = AiModelWeightService.instance.isDownloading(id);
    final progress = _downloadProgress[id] ?? 0.0;
    final downloadStatus = _downloadStatus[id];
    
    if (isDownloading || downloadStatus != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (downloadStatus == TaskStatus.running ||
              downloadStatus == TaskStatus.paused)
            SizedBox(
              width: 100,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 4),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
          if (downloadStatus == TaskStatus.running)
            IconButton(
              onPressed: () => _pauseDownload(id),
              icon: const Icon(Icons.pause),
              tooltip: '暂停',
            ),
          if (downloadStatus == TaskStatus.paused)
            IconButton(
              onPressed: () => _resumeDownload(id),
              icon: const Icon(Icons.play_arrow),
              tooltip: '继续',
            ),
          if (downloadStatus == TaskStatus.running ||
              downloadStatus == TaskStatus.paused)
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
