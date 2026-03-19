import 'dart:async';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../../models/entity/photo_entity.dart';
import '../../service/internvl_experiment_service.dart';
import '../../service/internvl_output_archive_service.dart';
import '../../service/on_device_internvl_service.dart';
import '../../service/photo_service.dart';
import '../widgets/path_image.dart';
import 'vlm_photo_picker_page.dart';

class InternvlLabPage extends StatefulWidget {
  const InternvlLabPage({super.key});

  @override
  State<InternvlLabPage> createState() => _InternvlLabPageState();
}

class _InternvlLabPageState extends State<InternvlLabPage> {
  final TextEditingController _promptController = TextEditingController(
    text: '请综合分析这些照片，结合时间和地点信息进行回答，并列出最确定的视觉事实。',
  );
  final InternvlExperimentService _experimentService =
      InternvlExperimentService();
    final InternvlOutputArchiveService _outputArchiveService =
      InternvlOutputArchiveService();

  OnDeviceInternvlProfile? _profile;
  OnDeviceInternvlBackendStatus? _backendStatus;
  OnDeviceInternvlServerDeploymentStatus? _serverDeploymentStatus;
  OnDeviceInternvlServerStatus? _serverStatus;
  bool _isLoading = true;
  bool _isTesting = false;
  List<OnDeviceInternvlImagePayload> _selectedImages =
      const <OnDeviceInternvlImagePayload>[];
  String? _responseText;
  String? _structuredJsonText;
  String? _outputFilePath;
  String? _runSummaryText;
  String? _errorText;
  double _progressValue = 0.0;
  String _progressLabel = '';
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _loadPageData();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadPageData() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final profile = await OnDeviceInternvlService().probeDeviceProfile();
      final backendStatus = await OnDeviceInternvlService().getBackendStatus();
      final serverDeploymentStatus =
          await OnDeviceInternvlService().getServerDeploymentStatus();
      final serverStatus = await OnDeviceInternvlService().getServerStatus();

      if (!mounted) {
        return;
      }

      setState(() {
        _profile = profile;
        _backendStatus = backendStatus;
        _serverDeploymentStatus = serverDeploymentStatus;
        _serverStatus = serverStatus;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '初始化实验页失败: $error';
        _isLoading = false;
      });
    }
  }

  String _buildExecutionModeText() {
    final backend = _backendStatus;
    final serverStatus = _serverStatus;
    if (backend?.supportsDirectOnDeviceInternvl == true) {
      if (serverStatus?.ready == true) {
        return '当前运行位置：手机本地，模型由常驻 llama-server 保持在内存中，通过 127.0.0.1 HTTP 调用；当前 App 还没有接入 NPU 通路';
      }
      return '当前运行位置：手机本地，已切换为常驻 llama-server 方案；首次会自动加载模型，后续请求走 127.0.0.1 HTTP';
    }
    return '当前还没有可用的手机本地推理链路';
  }

  void _startProgressAnimation(int imageCount) {
    _progressTimer?.cancel();
    setState(() {
      _progressValue = 0.03;
      _progressLabel = '正在唤醒本地模型服务...';
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted || !_isTesting) {
        _progressTimer?.cancel();
        return;
      }

      setState(() {
        final step = imageCount >= 4 ? 0.012 : 0.018;
        _progressValue = (_progressValue + step).clamp(0.03, 0.9);
        if (_progressValue < 0.16) {
          _progressLabel = '正在唤醒本地模型服务...';
        } else if (_progressValue < 0.3) {
          _progressLabel = '正在准备图片与元数据...';
        } else if (_progressValue < 0.5) {
          _progressLabel = '正在发送图片到本地服务...';
        } else if (_progressValue < 0.8) {
          _progressLabel = '正在进行多图推理...';
        } else {
          _progressLabel = '正在生成最终回答...';
        }
      });
    });
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
      _responseText = null;
      _structuredJsonText = null;
      _outputFilePath = null;
      _runSummaryText = null;
      _errorText = payloads.isEmpty ? '所选图片不可访问，请重新选择。' : null;
    });
  }

  Future<List<OnDeviceInternvlImagePayload>> _buildImagePayloads(
    List<VlmPhotoPickerResult> picks,
  ) async {
    final isar = PhotoService().isar;
    final payloads = <OnDeviceInternvlImagePayload>[];

    for (final item in picks) {
      if (item.path.trim().isEmpty) {
        continue;
      }

      final photo = await isar
          .collection<PhotoEntity>()
          .filter()
          .assetIdEqualTo(item.assetId)
          .findFirst();

      final locationName = _resolveLocationLabel(photo);
      payloads.add(
        OnDeviceInternvlImagePayload(
          path: item.path,
          capturedAtIso: item.createdAt.toIso8601String(),
          locationName: locationName,
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

    final district = photo?.district?.trim();
    final city = photo?.city?.trim();
    final province = photo?.province?.trim();
    final chunks = <String>[];
    if (province != null && province.isNotEmpty) {
      chunks.add(province);
    }
    if (city != null && city.isNotEmpty) {
      chunks.add(city);
    }
    if (district != null && district.isNotEmpty) {
      chunks.add(district);
    }
    if (chunks.isNotEmpty) {
      return chunks.join(' ');
    }

    return '未知地点';
  }

  String _formatImageMeta(OnDeviceInternvlImagePayload image) {
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

  Future<void> _runCliExperiment() async {
    final profile = _profile;
    final serverDeploymentStatus = _serverDeploymentStatus;
    if (_selectedImages.isEmpty) {
      setState(() {
        _errorText = '请先选择至少一张图片';
      });
      return;
    }

    if (serverDeploymentStatus == null || !serverDeploymentStatus.isRunnable) {
      setState(() {
        _errorText = serverDeploymentStatus?.summary ?? '手机侧本地 llama-server 尚未部署完整';
      });
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() {
        _errorText = '提问内容不能为空';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _responseText = null;
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
      final usedThreads = profile?.recommendedThreads ?? 4;
      final usedContextSize = profile?.recommendedContextSize ?? 2048;
      final startedServer = await OnDeviceInternvlService().ensureServerStarted(
        threads: usedThreads,
        contextSize: usedContextSize,
      );

      if (!mounted) {
        return;
      }

      if (startedServer == null) {
        setState(() {
          _errorText = '未拿到本地 llama-server 状态';
          _isTesting = false;
          _progressValue = 0.0;
          _progressLabel = '';
        });
        return;
      }

      if (!startedServer.ready) {
        setState(() {
          _serverStatus = startedServer;
          _errorText = startedServer.error.isNotEmpty
              ? startedServer.error
              : startedServer.summary;
          _isTesting = false;
          _progressValue = 0.0;
          _progressLabel = '';
        });
        return;
      }

      final structured = await _experimentService.analyzeImagesStructured(
        serverUrl: startedServer.chatCompletionsUrl,
        model: startedServer.modelAlias,
        prompt: _composePromptWithMetadata(prompt),
        imagePaths: _selectedImages
            .map((item) => item.path)
            .toList(growable: false),
        maxTokens: 512,
        temperature: 0.35,
      );

      final archive = await _outputArchiveService.saveStandardJson(
        document: _buildOutputDocument(
          structured.normalizedJson,
          startedServer,
          prompt,
        ),
      );
      debugPrint('🧾 [VLM JSON OUTPUT]\n${archive.prettyJson}');
      debugPrint('🧾 [VLM JSON FILE] ${archive.filePath}');

      stopwatch.stop();

      _progressTimer?.cancel();
      setState(() {
        _serverStatus = startedServer;
        _progressValue = 1.0;
        _progressLabel = '推理完成';
        _responseText = structured.narrative.isNotEmpty
            ? structured.narrative
            : '本次推理已完成，但没有提取到可展示的自然语言回答。';
        _structuredJsonText = archive.prettyJson;
        _outputFilePath = archive.filePath;
        _runSummaryText =
            '已完成，本次耗时 ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒 · 输入 ${_selectedImages.length} 张图片 · 走本地常驻服务 · ${structured.usedFallback ? '模型未直接输出 JSON，已自动标准化' : '模型已输出 JSON'}';
        _errorText = null;
        _isTesting = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _progressTimer?.cancel();
      setState(() {
        _errorText = '本地 llama-server 推理失败: $error';
        _isTesting = false;
        _progressValue = 0.0;
        _progressLabel = '';
      });
    }
  }

  String _composePromptWithMetadata(String userPrompt) {
    final lines = <String>[
      '你是一位擅长“图像叙事写作”的中文作家助手。',
      '你的任务不是逐图罗列信息，而是把多张图片串联成一个完整、连贯、有情绪起伏的故事段落。',
      '本次输入包含 ${_selectedImages.length} 张图片，请综合全部图片进行创作。',
      '请将图片元数据(时间/地点)作为上下文线索，但不要编造图片中不存在的事实。',
      '',
      '图片元数据:',
    ];

    for (var index = 0; index < _selectedImages.length; index++) {
      final image = _selectedImages[index];
      final coordinateText = image.latitude != null && image.longitude != null
          ? '，坐标=${image.latitude!.toStringAsFixed(5)}, ${image.longitude!.toStringAsFixed(5)}'
          : '';
      lines.add(
        '- 图片${index + 1}: 时间=${image.capturedAtIso.isEmpty ? '未知时间' : image.capturedAtIso}，地点=${image.locationName.isEmpty ? '未知地点' : image.locationName}$coordinateText',
      );
    }

    lines.addAll(<String>[
      '',
      '输出要求（必须严格遵守）:',
      '1) 只输出一个 JSON 对象，不要输出 markdown，不要输出解释文字。',
      '2) JSON 必须包含这些字段：',
      '{',
      '  "schema_version": "memoria.vlm.output.v1",',
      '  "output": {',
      '    "scene_summary": "一句话总结场景",',
      '    "narrative": "把多图串联为一个完整段落的故事正文",',
      '    "key_facts": ["事实1", "事实2"],',
      '    "visual_entities": ["主体1", "主体2"],',
      '    "style_tags": ["风格标签1", "风格标签2"],',
      '    "time_location_hints": ["时间/地点线索"],',
      '    "confidence": 0.0',
      '  }',
      '}',
      '3) narrative 写作要求：',
      '   - 必须是一整段中文，不要分点，不要小标题。',
      '   - 字数必须不少于 300 个中文字符。',
      '   - 必须把多张图片串联起来，体现时间推进或空间转换。',
      '   - 语言要有画面感、节奏感和余味，避免模板化口吻。',
      '   - 在不违背事实的前提下，允许适度文学化表达。',
      '4) key_facts 只写图片中可确认的事实，不要编造。',
      '5) 如果图片之间存在明显关系(人物、地点、事件延续)，在 narrative 中明确体现。',
      '6) confidence 取值范围必须是 0.0 到 1.0。',
      '7) 不要输出被转义的 JSON 字符串；不要把 JSON 文本塞进 narrative 字段。',
      '',
      '[用户问题]',
      userPrompt,
    ]);
    return lines.join('\n');
  }

  Map<String, dynamic> _buildOutputDocument(
    Map<String, dynamic> normalized,
    OnDeviceInternvlServerStatus server,
    String userPrompt,
  ) {
    final imageItems = _selectedImages
        .map(
          (item) => <String, dynamic>{
            'path': item.path,
            'captured_at_iso': item.capturedAtIso,
            'location_name': item.locationName,
            'latitude': item.latitude,
            'longitude': item.longitude,
          },
        )
        .toList(growable: false);

    final request = (normalized['request'] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    final mergedRequest = <String, dynamic>{
      ...request,
      'user_prompt': userPrompt,
      'image_count': _selectedImages.length,
      'images': imageItems,
      'runtime': <String, dynamic>{
        'server_url': server.chatCompletionsUrl,
        'model_alias': server.modelAlias,
        'device_host': server.host,
        'device_port': server.port,
      },
    };

    final doc = Map<String, dynamic>.from(normalized);
    doc['request'] = mergedRequest;
    doc['saved_at'] = DateTime.now().toUtc().toIso8601String();
    return doc;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VLM 推理')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPhotoPickerCard(context),
                const SizedBox(height: 16),
                _buildPromptCard(context),
                const SizedBox(height: 12),
                Text(
                  _buildExecutionModeText(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isTesting ? null : _runCliExperiment,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_isTesting ? '推理中...' : '开始手机本地 VLM 推理'),
                ),
                if (_isTesting) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: _progressValue),
                  const SizedBox(height: 8),
                  Text(
                    _progressLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_runSummaryText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _runSummaryText!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_errorText != null) ...[
                  const SizedBox(height: 16),
                  _buildMessageCard(
                    context,
                    '错误信息',
                    _errorText!,
                    Colors.red.shade50,
                  ),
                ],
                if (_responseText != null) ...[
                  const SizedBox(height: 16),
                  _buildMessageCard(
                    context,
                    '模型回答',
                    _responseText!,
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ],
                if (_outputFilePath != null) ...[
                  const SizedBox(height: 12),
                  _buildMessageCard(
                    context,
                    'JSON 文件路径',
                    _outputFilePath!,
                    Colors.blueGrey.shade50,
                  ),
                ],
                if (_structuredJsonText != null) ...[
                  const SizedBox(height: 12),
                  _buildMessageCard(
                    context,
                    '结构化输出(JSON)',
                    _structuredJsonText!,
                    Colors.lightBlue.shade50,
                  ),
                ],
              ],
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
              '图片',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _pickPhotoFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('上传多张图片'),
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
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final image = _selectedImages[index];
                    return SizedBox(
                      width: 140,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: PathImage(
                                path: image.path,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
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
                child: const Text('请选择至少一张图片后开始推理'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '问题',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _promptController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '输入你希望模型回答的问题',
                border: OutlineInputBorder(),
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
