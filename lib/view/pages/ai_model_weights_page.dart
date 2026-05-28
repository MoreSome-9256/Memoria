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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(error.toString()),
        ),
      );
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
                trailing: status.hasDownloadedFiles
                    ? TextButton(
                        onPressed: () => _delete(id),
                        child: const Text('删除'),
                      )
                    : TextButton(
                        onPressed: () => _download(id),
                        child: const Text('下载'),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
