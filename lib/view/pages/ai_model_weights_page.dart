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
    try {
      await AiModelWeightService.instance.downloadWeights(id);
      if (!mounted) return;
      _reload();
      final snapshot =
          AiModelWeightService.instance.downloadsListenable.value[id];
      if (snapshot?.status == TaskStatus.complete) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('已下载 ${id.label}'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${id.label} 下载失败: $error'),
        ),
      );
    }
  }

  Future<void> _pauseDownload(AiModelWeightId id) async {
    await AiModelWeightService.instance.pauseDownload(id);
  }

  Future<void> _resumeDownload(AiModelWeightId id) async {
    await AiModelWeightService.instance.resumeDownload(id);
  }

  Future<void> _cancelDownload(AiModelWeightId id) async {
    await AiModelWeightService.instance.cancelDownload(id);
    if (mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 模型权重')),
      body:
          ValueListenableBuilder<
            Map<AiModelWeightId, AiModelWeightDownloadSnapshot>
          >(
            valueListenable: AiModelWeightService.instance.downloadsListenable,
            builder: (context, downloads, _) {
              return FutureBuilder<List<AiModelWeightStatus>>(
                future: _future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final statuses = snapshot.data!;
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: statuses.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final status = statuses[index];
                      final id = status.id;
                      final download = downloads[id];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        leading: Icon(
                          _leadingIcon(status, download),
                          color: _leadingColor(context, status, download),
                        ),
                        title: Text(id.label),
                        subtitle: Text(_subtitleFor(status, download)),
                        isThreeLine: true,
                        trailing: _buildTrailing(context, id, status, download),
                      );
                    },
                  );
                },
              );
            },
          ),
    );
  }

  IconData _leadingIcon(
    AiModelWeightStatus status,
    AiModelWeightDownloadSnapshot? download,
  ) {
    if (download?.isActive == true) return Icons.downloading;
    if (download?.status == TaskStatus.failed) return Icons.error_outline;
    if (status.checkPassed) return Icons.check_circle_outline;
    if (status.hasDownloadedFiles) return Icons.pending_outlined;
    return Icons.error_outline;
  }

  Color _leadingColor(
    BuildContext context,
    AiModelWeightStatus status,
    AiModelWeightDownloadSnapshot? download,
  ) {
    if (download?.status == TaskStatus.failed) {
      return Theme.of(context).colorScheme.error;
    }
    if (download?.isActive == true) {
      return Theme.of(context).colorScheme.primary;
    }
    if (status.checkPassed) return Colors.green;
    if (status.hasDownloadedFiles) return Colors.orange;
    return Theme.of(context).colorScheme.error;
  }

  String _subtitleFor(
    AiModelWeightStatus status,
    AiModelWeightDownloadSnapshot? download,
  ) {
    final parts = <String>[
      status.id.description,
      '当前检查：${status.checkPassed ? '可推理' : '缺少权重'}',
    ];
    if (status.hasDownloadedFiles) {
      parts.add(
        '已下载 ${status.presentFiles.length}/${status.id.relativePaths.length} 个文件',
      );
    }
    if (download != null && download.isActive) {
      parts.add(
        '${download.message} · ${download.completedFiles}/${download.totalFiles} 文件',
      );
      final currentFile = download.currentFile;
      if (currentFile != null && currentFile.isNotEmpty) {
        parts.add(currentFile);
      }
    } else if (download?.status == TaskStatus.failed) {
      parts.add(download!.error ?? download.message);
    }
    return parts.join('\n');
  }

  Widget _buildTrailing(
    BuildContext context,
    AiModelWeightId id,
    AiModelWeightStatus status,
    AiModelWeightDownloadSnapshot? download,
  ) {
    if (download != null && download.isActive) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 116,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: download.progress),
                const SizedBox(height: 4),
                Text(
                  '${(download.progress * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (download.canPause)
            IconButton(
              onPressed: () => _pauseDownload(id),
              icon: const Icon(Icons.pause),
              tooltip: '暂停',
            ),
          if (download.canResume)
            IconButton(
              onPressed: () => _resumeDownload(id),
              icon: const Icon(Icons.play_arrow),
              tooltip: '继续',
            ),
          if (download.canCancel)
            IconButton(
              onPressed: () => _cancelDownload(id),
              icon: const Icon(Icons.cancel),
              tooltip: '取消',
            ),
        ],
      );
    }

    if (status.hasDownloadedFiles) {
      return TextButton(onPressed: () => _delete(id), child: const Text('删除'));
    }

    return TextButton(
      onPressed: () => unawaited(_download(id)),
      child: const Text('下载'),
    );
  }
}
