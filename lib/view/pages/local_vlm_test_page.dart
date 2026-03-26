import 'dart:async';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;

import '../../models/entity/photo_entity.dart';
import '../../service/local_vlm_output_archive_service.dart';
import '../../service/photo_service.dart';
import '../../service/qwen_llamacpp_service.dart';
import '../widgets/path_image.dart';
import 'vlm_photo_picker_page.dart';

enum LocalVlmTaskMode { captions, story }

extension LocalVlmTaskModeX on LocalVlmTaskMode {
  String get title => this == LocalVlmTaskMode.captions ? '图片 Caption' : '多图故事';

  String get buttonLabel =>
      this == LocalVlmTaskMode.captions ? '开始生成 Caption' : '开始生成故事';

  String get extraPromptHint => this == LocalVlmTaskMode.captions
      ? '可选：例如“更简洁一点”“不要超过 20 个字”'
      : '可选：例如“更治愈一点”“像旅行随笔”';
}

class LocalVlmTestPage extends StatefulWidget {
  const LocalVlmTestPage({super.key});

  @override
  State<LocalVlmTestPage> createState() => _LocalVlmTestPageState();
}

class _LocalVlmTestPageState extends State<LocalVlmTestPage> {
  final TextEditingController _extraPromptController = TextEditingController();
  final QwenLlamacppService _qwenService = QwenLlamacppService();
  final LocalVlmOutputArchiveService _archiveService =
      LocalVlmOutputArchiveService();

  LocalVlmTaskMode _taskMode = LocalVlmTaskMode.captions;
  QwenLocalBackendOption _backendOption = QwenLocalBackendOption.vulkan;
  List<LocalVlmImagePayload> _selectedImages = const <LocalVlmImagePayload>[];

  bool _isRunning = false;
  double _progressValue = 0.0;
  String _progressLabel = '';
  Timer? _progressTimer;

  String? _resultPreview;
  String? _structuredJsonText;
  String? _outputFilePath;
  String? _runSummaryText;
  String? _errorText;

  @override
  void dispose() {
    _progressTimer?.cancel();
    _extraPromptController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotoFromGallery() async {
    final result = await Navigator.push<List<VlmPhotoPickerResult>>(
      context,
      MaterialPageRoute<List<VlmPhotoPickerResult>>(
        builder: (BuildContext context) => const VlmPhotoPickerPage(),
      ),
    );
    if (!mounted || result == null || result.isEmpty) {
      return;
    }

    final payloads = await _buildImagePayloads(result);
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedImages = payloads;
      _resultPreview = null;
      _structuredJsonText = null;
      _outputFilePath = null;
      _runSummaryText = null;
      _errorText = payloads.isEmpty ? '所选图片不可访问，请重新选择。' : null;
    });
  }

  Future<List<LocalVlmImagePayload>> _buildImagePayloads(
    List<VlmPhotoPickerResult> picks,
  ) async {
    final isar = PhotoService().isar;
    final payloads = <LocalVlmImagePayload>[];

    for (final item in picks) {
      if (item.path.trim().isEmpty) {
        continue;
      }

      final photo = await isar
          .collection<PhotoEntity>()
          .filter()
          .assetIdEqualTo(item.assetId)
          .findFirst();

      payloads.add(
        LocalVlmImagePayload(
          path: item.path,
          capturedAtIso: item.createdAt.toIso8601String(),
          locationName: _resolveLocationLabel(photo),
          latitude: photo?.latitude,
          longitude: photo?.longitude,
        ),
      );
    }

    return payloads;
  }

  String _resolveLocationLabel(PhotoEntity? photo) {
    final preferred = (photo?.locationName ?? photo?.formattedAddress)?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      return preferred;
    }

    final chunks = <String>[
      if (photo?.province?.trim().isNotEmpty == true) photo!.province!.trim(),
      if (photo?.city?.trim().isNotEmpty == true) photo!.city!.trim(),
      if (photo?.district?.trim().isNotEmpty == true) photo!.district!.trim(),
    ];
    return chunks.isNotEmpty ? chunks.join(' ') : '未知地点';
  }

  void _startProgressAnimation(int imageCount) {
    _progressTimer?.cancel();
    setState(() {
      _progressValue = 0.03;
      _progressLabel = '正在加载 Qwen3.5-0.8B 模型...';
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted || !_isRunning) {
        _progressTimer?.cancel();
        return;
      }

      setState(() {
        final step = imageCount >= 4 ? 0.012 : 0.018;
        _progressValue = (_progressValue + step).clamp(0.03, 0.9);
        if (_progressValue < 0.2) {
          _progressLabel = '正在加载 Qwen3.5-0.8B 模型...';
        } else if (_progressValue < 0.45) {
          _progressLabel = '正在准备图片与元数据...';
        } else if (_progressValue < 0.8) {
          _progressLabel = '正在进行本地 llama.cpp 推理...';
        } else {
          _progressLabel = '正在等待模型输出完成...';
        }
      });
    });
  }

  Future<void> _runTask() async {
    if (_selectedImages.isEmpty) {
      setState(() {
        _errorText = '请先选择至少一张图片';
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _resultPreview = null;
      _structuredJsonText = null;
      _outputFilePath = null;
      _runSummaryText = null;
      _errorText = null;
      _progressValue = 0.0;
      _progressLabel = '';
    });
    _startProgressAnimation(_selectedImages.length);

    try {
      final stopwatch = Stopwatch()..start();
      final partialPreview = StringBuffer();
      var lastUiRefreshMs = 0;

      final structured = await _qwenService.analyzeImagesStructured(
        prompt: _buildTaskPrompt(),
        images: _selectedImages,
        maxTokens: _taskMode == LocalVlmTaskMode.captions ? 192 : 480,
        temperature: _taskMode == LocalVlmTaskMode.captions ? 0.2 : 0.45,
        backend: _backendOption,
        onPartialOutput: (delta, accumulated) {
          if (!mounted || !_isRunning) {
            return;
          }
          partialPreview.write(delta);
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - lastUiRefreshMs < 120) {
            return;
          }
          lastUiRefreshMs = nowMs;
          setState(() {
            _resultPreview = accumulated;
            _progressLabel = '正在等待模型输出完成...（已输出 ${accumulated.length} 字）';
          });
        },
      );

      if (mounted) {
        setState(() {
          _progressValue = 0.94;
          _progressLabel = '正在整理 JSON 输出...';
        });
      }

      final document = <String, dynamic>{
        'task': _taskMode == LocalVlmTaskMode.captions
            ? 'caption_batch'
            : 'story_generation',
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'model': QwenLlamacppService.qwenModelAlias,
        'model_path': _qwenService.modelPath,
        'mmproj_path': _qwenService.mmprojPath,
        'engine': 'llamadart/llama.cpp',
        'images': _selectedImages
            .asMap()
            .entries
            .map((entry) => <String, dynamic>{
                  'index': entry.key + 1,
                  'path': entry.value.path,
                  'captured_at_iso': entry.value.capturedAtIso,
                  'location_name': entry.value.locationName,
                  'latitude': entry.value.latitude,
                  'longitude': entry.value.longitude,
                })
            .toList(growable: false),
        'result': structured.normalizedJson,
      };

      final archive = await _archiveService.saveStandardJson(document: document);
      stopwatch.stop();
        final generationStats = _qwenService.lastGenerationStats;
        final rateText = generationStats == null
          ? null
          : '${generationStats.charsPerSecond.toStringAsFixed(1)} 字/秒';
        final firstChunkText = generationStats?.firstChunkLatency == null
          ? null
          : '${(generationStats!.firstChunkLatency!.inMilliseconds / 1000).toStringAsFixed(2)} 秒';

      final preview = structured.narrative;
      _progressTimer?.cancel();
      setState(() {
        _progressValue = 1.0;
        _progressLabel = '处理完成';
        _resultPreview = preview;
        _structuredJsonText = archive.prettyJson;
        _outputFilePath = archive.filePath;
        _runSummaryText =
            '已完成，本次耗时 ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒'
            ' · 输入 ${_selectedImages.length} 张图片'
          ' · ${structured.usedFallback ? '模型未直接输出 JSON，已做标准化' : '模型已直接输出 JSON'}'
          '${rateText == null ? '' : ' · 平均输出速率 $rateText'}'
          '${generationStats == null ? '' : ' · 输出 ${generationStats.charCount} 字/${generationStats.chunkCount} 片段'}'
          '${firstChunkText == null ? '' : ' · 首片延迟 $firstChunkText'}';
        _errorText = null;
        _isRunning = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _progressTimer?.cancel();
      setState(() {
        _errorText = 'Qwen 本地推理失败: $error';
        _isRunning = false;
        _progressValue = 0.0;
        _progressLabel = '';
      });
    }
  }

  String _buildTaskPrompt() {
    final extraPrompt = _extraPromptController.text.trim();
    final metadataLines = <String>[
      '图片元数据:',
      for (var index = 0; index < _selectedImages.length; index++)
        '- 图片${index + 1}: ${_formatImageMeta(_selectedImages[index])}',
      '',
    ];

    switch (_taskMode) {
      case LocalVlmTaskMode.captions:
        return <String>[
          '你是手机本地运行的 Qwen3.5-0.8B 图片描述助手。',
          '任务：为每张图片生成一句简短中文 caption。',
          '严格基于可见内容与元数据，不要解释，不要展示推理过程。',
          '',
          ...metadataLines,
          '只输出 JSON，不要 markdown，不要分析，不要复述要求。',
          'JSON 格式严格固定为：{"captions":[{"index":1,"caption":"..."}]}',
          'captions 数组长度必须与输入图片数量一致，index 从 1 开始。',
          if (extraPrompt.isNotEmpty) ...<String>['', '[附加要求]', extraPrompt],
        ].join('\n');
      case LocalVlmTaskMode.story:
        return <String>[
          '你是手机本地运行的 Qwen3.5-0.8B 图像叙事写作助手。',
          '任务：结合多张图片与时间地点元数据，写一段连贯中文故事。',
          '',
          ...metadataLines,
          '只输出 JSON，不要 markdown。',
          'JSON 格式严格固定为：{"story":"..."}',
          'story 必须是一整段中文，长度 180-320 个中文字符。',
          if (extraPrompt.isNotEmpty) ...<String>['', '[附加要求]', extraPrompt],
        ].join('\n');
    }
  }

  String _formatImageMeta(LocalVlmImagePayload image) {
    final capturedAt = DateTime.tryParse(image.capturedAtIso)?.toLocal();
    final timeText = capturedAt == null
        ? '未知时间'
        : '${capturedAt.year}-${capturedAt.month.toString().padLeft(2, '0')}-${capturedAt.day.toString().padLeft(2, '0')} ${capturedAt.hour.toString().padLeft(2, '0')}:${capturedAt.minute.toString().padLeft(2, '0')}';
    final hasLatLng = image.latitude != null && image.longitude != null;
    if (!hasLatLng) {
      return '$timeText · ${image.locationName}';
    }
    return '$timeText · ${image.locationName} (${image.latitude!.toStringAsFixed(5)}, ${image.longitude!.toStringAsFixed(5)})';
  }

  String _modelNameText() {
    final modelPath = _qwenService.modelPath;
    if (modelPath.trim().isEmpty) {
      return '未配置模型路径';
    }
    return p.basename(modelPath);
  }

  Future<void> _openBackendSettingDialog() async {
    final selected = await showDialog<QwenLocalBackendOption>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('推理后端设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: QwenLocalBackendOption.values
              .map(
                (option) => RadioListTile<QwenLocalBackendOption>(
                  value: option,
                  groupValue: _backendOption,
                  title: Text(option.label),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    Navigator.of(context).pop(value);
                  },
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
    if (!mounted || selected == null || selected == _backendOption) {
      return;
    }
    setState(() {
      _backendOption = selected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地 Qwen3.5-0.8B 测试')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildRuntimeCard(context),
          const SizedBox(height: 16),
          _buildTaskModeCard(context),
          const SizedBox(height: 16),
          _buildPhotoPickerCard(context),
          const SizedBox(height: 16),
          _buildRequirementCard(context),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isRunning ? null : _runTask,
            icon: _isRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_isRunning ? '正在处理中...' : _taskMode.buttonLabel),
          ),
          if (_isRunning) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(value: _progressValue),
            const SizedBox(height: 8),
            Text(_progressLabel, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_runSummaryText != null) ...[
            const SizedBox(height: 12),
            Text(_runSummaryText!, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 16),
            _buildMessageCard(context, '错误信息', _errorText!, Colors.red.shade50),
          ],
          if (_resultPreview != null) ...[
            const SizedBox(height: 16),
            _buildMessageCard(
              context,
              _taskMode == LocalVlmTaskMode.captions ? 'Caption 结果' : '故事结果',
              _resultPreview!,
              Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ],
          if (_outputFilePath != null) ...[
            const SizedBox(height: 12),
            _buildMessageCard(context, 'JSON 文件路径', _outputFilePath!, Colors.blueGrey.shade50),
          ],
          if (_structuredJsonText != null) ...[
            const SizedBox(height: 12),
            _buildMessageCard(context, '结构化输出(JSON)', _structuredJsonText!, Colors.lightBlue.shade50),
          ],
        ],
      ),
    );
  }

  Widget _buildRuntimeCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '运行状态',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 10),
            Text('模型: ${_modelNameText()}'),
            const Text('执行方式: 纯本地 llamadart / llama.cpp（无 localhost 服务）'),
            Text('mmproj: ${_qwenService.mmprojPath.isEmpty ? '未配置' : p.basename(_qwenService.mmprojPath)}'),
            const SizedBox(height: 8),
            Text('当前后端: ${_backendOption.label}'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isRunning ? null : _openBackendSettingDialog,
              icon: const Icon(Icons.tune),
              label: const Text('设置推理后端'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskModeCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '任务类型',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<LocalVlmTaskMode>(
              segments: const <ButtonSegment<LocalVlmTaskMode>>[
                ButtonSegment<LocalVlmTaskMode>(
                  value: LocalVlmTaskMode.captions,
                  label: Text('图片 Caption'),
                  icon: Icon(Icons.short_text),
                ),
                ButtonSegment<LocalVlmTaskMode>(
                  value: LocalVlmTaskMode.story,
                  label: Text('多图故事'),
                  icon: Icon(Icons.auto_stories_outlined),
                ),
              ],
              selected: <LocalVlmTaskMode>{_taskMode},
              onSelectionChanged: _isRunning
                  ? null
                  : (Set<LocalVlmTaskMode> value) {
                      setState(() {
                        _taskMode = value.first;
                      });
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPickerCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '图片选择',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isRunning ? null : _pickPhotoFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('从相册选择 1~9 张图片'),
            ),
            const SizedBox(height: 12),
            Text(
              _selectedImages.isEmpty
                  ? '当前还没有选择图片'
                  : '已选择 ${_selectedImages.length} 张图片',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_selectedImages.isNotEmpty)
              SizedBox(
                height: 128,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final image = _selectedImages[index];
                    return SizedBox(
                      width: 150,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: PathImage(path: image.path, fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('图片${index + 1}'),
                          Text(
                            _formatImageMeta(image),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              )
            else
              Container(
                height: 100,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('请选择至少一张图片后开始本地推理'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequirementCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '附加要求（可选）',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _extraPromptController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: _taskMode.extraPromptHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard(
    BuildContext context,
    String title,
    String message,
    Color backgroundColor,
  ) {
    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            SelectableText(message),
          ],
        ),
      ),
    );
  }
}
