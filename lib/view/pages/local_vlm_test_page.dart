import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/entity/photo_entity.dart';
import '../../service/internvl_experiment_service.dart';
import '../../service/internvl_output_archive_service.dart';
import '../../service/on_device_internvl_service.dart';
import '../widgets/path_image.dart';
import 'vlm_photo_picker_page.dart';
import '../../objectbox.g.dart';
import '../../storage/objectbox/objectbox_service.dart';

enum LocalVlmTaskMode { captions, story }

extension LocalVlmTaskModeX on LocalVlmTaskMode {
  String get title {
    switch (this) {
      case LocalVlmTaskMode.captions:
        return '图片 Caption';
      case LocalVlmTaskMode.story:
        return '多图故事';
    }
  }

  String get subtitle {
    switch (this) {
      case LocalVlmTaskMode.captions:
        return '为每张图片分别生成一句或一小段描述';
      case LocalVlmTaskMode.story:
        return '把多张图片串成一段完整故事';
    }
  }

  String get buttonLabel {
    switch (this) {
      case LocalVlmTaskMode.captions:
        return '开始生成 Caption';
      case LocalVlmTaskMode.story:
        return '开始生成故事';
    }
  }

  String get outputSchema {
    switch (this) {
      case LocalVlmTaskMode.captions:
        return 'memoria.local_vlm.caption.v1';
      case LocalVlmTaskMode.story:
        return 'memoria.local_vlm.story.v1';
    }
  }

  String get extraPromptHint {
    switch (this) {
      case LocalVlmTaskMode.captions:
        return '可选：例如“更简洁一点”“突出人物动作”“不要超过 20 个字”';
      case LocalVlmTaskMode.story:
        return '可选：例如“更治愈一点”“像旅行随笔”“强调时间推进”';
    }
  }
}

class LocalVlmTestPage extends StatefulWidget {
  const LocalVlmTestPage({super.key});

  @override
  State<LocalVlmTestPage> createState() => _LocalVlmTestPageState();
}

class _LocalVlmTestPageState extends State<LocalVlmTestPage> {
  final TextEditingController _extraPromptController = TextEditingController();
  final InternvlExperimentService _experimentService =
      InternvlExperimentService();
  final InternvlOutputArchiveService _archiveService =
      InternvlOutputArchiveService();

  LocalVlmTaskMode _taskMode = LocalVlmTaskMode.captions;
  OnDeviceInternvlProfile? _profile;
  OnDeviceInternvlBackendStatus? _backendStatus;
  OnDeviceInternvlServerDeploymentStatus? _serverDeploymentStatus;
  OnDeviceInternvlServerStatus? _serverStatus;

  bool _isLoading = true;
  bool _isRunning = false;
  List<OnDeviceInternvlImagePayload> _selectedImages =
      const <OnDeviceInternvlImagePayload>[];
  String? _resultPreview;
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
    _extraPromptController.dispose();
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
      final deploymentStatus =
          await OnDeviceInternvlService().getServerDeploymentStatus();
      final serverStatus = await OnDeviceInternvlService().getServerStatus();

      if (!mounted) {
        return;
      }

      setState(() {
        _profile = profile;
        _backendStatus = backendStatus;
        _serverDeploymentStatus = deploymentStatus;
        _serverStatus = serverStatus;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '加载本地 VLM 状态失败: $error';
        _isLoading = false;
      });
    }
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

  Future<List<OnDeviceInternvlImagePayload>> _buildImagePayloads(
    List<VlmPhotoPickerResult> picks,
  ) async {
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final payloads = <OnDeviceInternvlImagePayload>[];

    for (final item in picks) {
      if (item.path.trim().isEmpty) {
        continue;
      }

      final q = photoBox.query(PhotoEntity_.assetId.equals(item.assetId)).build();
      final photo = q.findFirst();
      q.close();

      payloads.add(
        OnDeviceInternvlImagePayload(
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
    if (chunks.isNotEmpty) {
      return chunks.join(' ');
    }
    return '未知地点';
  }

  void _startProgressAnimation(int imageCount) {
    _progressTimer?.cancel();
    setState(() {
      _progressValue = 0.03;
      _progressLabel = '正在唤醒本地常驻服务...';
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted || !_isRunning) {
        _progressTimer?.cancel();
        return;
      }

      setState(() {
        final step = imageCount >= 4 ? 0.012 : 0.018;
        _progressValue = (_progressValue + step).clamp(0.03, 0.9);
        if (_progressValue < 0.18) {
          _progressLabel = '正在唤醒本地常驻服务...';
        } else if (_progressValue < 0.32) {
          _progressLabel = '正在准备图片与元数据...';
        } else if (_progressValue < 0.52) {
          _progressLabel = '正在发送图片到本地 Qwen 服务...';
        } else if (_progressValue < 0.82) {
          _progressLabel = _taskMode == LocalVlmTaskMode.captions
              ? '正在逐图生成 caption...'
              : '正在串联多图生成故事...';
        } else {
          _progressLabel = '正在整理 JSON 输出...';
        }
      });
    });
  }

  Future<void> _runTask() async {
    final deploymentStatus = _serverDeploymentStatus;
    if (_selectedImages.isEmpty) {
      setState(() {
        _errorText = '请先选择至少一张图片';
      });
      return;
    }
    if (deploymentStatus == null || !deploymentStatus.isRunnable) {
      setState(() {
        _errorText = deploymentStatus?.summary ?? '本地模型服务依赖尚未部署完整';
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
      final startedServer = await OnDeviceInternvlService().ensureServerStarted(
        threads: _profile?.recommendedThreads ?? 4,
        contextSize: _profile?.recommendedContextSize ?? 2048,
      );

      if (!mounted) {
        return;
      }

      if (startedServer == null || !startedServer.ready) {
        setState(() {
          _serverStatus = startedServer;
          _errorText = startedServer?.error.isNotEmpty == true
              ? startedServer!.error
              : startedServer?.summary ?? '本地常驻服务启动失败';
          _isRunning = false;
          _progressValue = 0.0;
          _progressLabel = '';
        });
        return;
      }

      final structured = await _invokeLocalModelWithRetry(startedServer);

      final document = _buildTaskOutputDocument(
        structured: structured,
        server: startedServer,
      );
      final archive = await _archiveService.saveStandardJson(document: document);
      stopwatch.stop();

      final preview = _buildPreviewFromDocument(document);
      _progressTimer?.cancel();
      setState(() {
        _serverStatus = startedServer;
        _progressValue = 1.0;
        _progressLabel = '处理完成';
        _resultPreview = preview;
        _structuredJsonText = archive.prettyJson;
        _outputFilePath = archive.filePath;
        _runSummaryText =
            '已完成，本次耗时 ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒'
            ' · 输入 ${_selectedImages.length} 张图片'
            ' · 本地常驻服务 PID=${startedServer.pid}'
            ' · ${structured.usedFallback ? '模型未完全按要求输出 JSON，已做兜底整理' : '模型已直接输出标准 JSON'}';
        _errorText = null;
        _isRunning = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _progressTimer?.cancel();
      setState(() {
        _errorText = '本地 VLM 推理失败: $error';
        _isRunning = false;
        _progressValue = 0.0;
        _progressLabel = '';
      });
    }
  }

  Future<InternvlStructuredResponse> _invokeLocalModelWithRetry(
    OnDeviceInternvlServerStatus server,
  ) async {
    try {
      return await _invokeLocalModel(server);
    } catch (error) {
      if (_looksLikeEmptyServerText(error)) {
        return _invokeLocalCliFallback(server);
      }
      if (_looksLikeServerUnavailable(error)) {
        if (mounted) {
          setState(() {
            _progressLabel = '本地服务正在预热，等待后重试...';
          });
        }
        await Future<void>.delayed(const Duration(seconds: 4));
        try {
          return await _invokeLocalModel(server);
        } catch (retryUnavailableError) {
          if (_looksLikeEmptyServerText(retryUnavailableError) ||
              _looksLikeServerUnavailable(retryUnavailableError)) {
            return _invokeLocalCliFallback(server);
          }
          rethrow;
        }
      }
      if (!_looksLikeServerPipeFailure(error)) {
        rethrow;
      }

      await OnDeviceInternvlService().stopServer();
      final restarted = await OnDeviceInternvlService().ensureServerStarted(
        threads: _profile?.recommendedThreads ?? 4,
        contextSize: _profile?.recommendedContextSize ?? 2048,
      );
      if (restarted == null || !restarted.ready) {
        throw StateError(
          '本地服务在接收图片时断开，且重启失败：${restarted?.error.isNotEmpty == true ? restarted!.error : restarted?.summary ?? '未知错误'}',
        );
      }
      if (mounted) {
        setState(() {
          _serverStatus = restarted;
          _progressLabel = '本地服务已自动重启，正在重试...';
        });
      }
      try {
        return await _invokeLocalModel(restarted);
      } catch (retryError) {
        if (_looksLikeEmptyServerText(retryError)) {
          return _invokeLocalCliFallback(restarted);
        }
        rethrow;
      }
    }
  }

  Future<InternvlStructuredResponse> _invokeLocalModel(
    OnDeviceInternvlServerStatus server,
  ) {
    debugPrint(
      '🦙 [Local VLM] test page -> llama-server '
      'url=${server.chatCompletionsUrl} '
      'images=${_selectedImages.length} '
      'mode=${_taskMode.name}',
    );
    return _experimentService.analyzeImagesStructured(
      serverUrl: server.chatCompletionsUrl,
      model: server.modelAlias,
      prompt: _buildTaskPrompt(),
      imagePaths: _selectedImages
          .map((item) => item.path)
          .toList(growable: false),
      maxTokens: _taskMode == LocalVlmTaskMode.captions ? 192 : 480,
      temperature: _taskMode == LocalVlmTaskMode.captions ? 0.2 : 0.45,
    );
  }

  bool _looksLikeServerPipeFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('broken pipe') ||
        text.contains('socketexception') ||
        text.contains('connection reset') ||
        text.contains('connection terminated during handshake') ||
        text.contains('write failed');
  }

  bool _looksLikeServerUnavailable(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('status code of 503') ||
        text.contains('bad response') ||
        text.contains('server error') ||
        text.contains('no available slot') ||
        text.contains('loading model');
  }

  bool _looksLikeEmptyServerText(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('未解析出文本内容') ||
        text.contains('did not contain parseable text') ||
        text.contains('raw response');
  }

  Future<InternvlStructuredResponse> _invokeLocalCliFallback(
    OnDeviceInternvlServerStatus server,
  ) async {
    debugPrint(
      '🦙 [Local VLM] test page -> CLI fallback '
      'images=${_selectedImages.length} '
      'mode=${_taskMode.name}',
    );
    if (mounted) {
      setState(() {
        _progressLabel = '常驻服务返回空文本，已切换到本地 CLI 兜底...';
      });
    }

    final cliResult = await OnDeviceInternvlService().runCliExperiment(
      images: _selectedImages,
      prompt: _buildTaskPrompt(),
      threads: _profile?.recommendedThreads ?? 4,
      contextSize: _profile?.recommendedContextSize ?? 2048,
      maxTokens: _taskMode == LocalVlmTaskMode.captions ? 192 : 480,
      timeoutMs: 240000,
    );
    if (cliResult == null) {
      throw StateError('本地 CLI 兜底失败：未拿到执行结果');
    }
    if (!cliResult.success) {
      throw StateError(
        '本地 CLI 兜底失败: ${cliResult.error.isNotEmpty ? cliResult.error : 'exit=${cliResult.exitCode}'}',
      );
    }

    final rawText = cliResult.answer.trim().isNotEmpty
        ? cliResult.answer.trim()
        : cliResult.rawOutput.trim();
    if (rawText.isEmpty) {
      throw StateError('本地 CLI 兜底失败：模型没有返回可用文本');
    }

    return _experimentService.normalizeRawTextToStructuredResponse(
      rawContent: rawText,
      model: server.modelAlias,
      prompt: _buildTaskPrompt(),
      imageCount: _selectedImages.length,
      serverUrl: server.chatCompletionsUrl,
    );
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
          '你是手机本地运行的图片描述助手。',
          '任务：为每张图片生成一句简短中文 caption。',
          '严格基于可见内容与元数据，不要解释，不要展示推理过程。',
          '',
          ...metadataLines,
          '只输出 JSON，不要 markdown，不要分析，不要复述要求。',
          'JSON 格式严格固定为：{"captions":[{"index":1,"caption":"..."}]}',
          'captions 数组长度必须与输入图片数量一致，index 从 1 开始。',
          'caption 长度控制在 12-40 个中文字符。',
          if (extraPrompt.isNotEmpty) ...<String>['', '[附加要求]', extraPrompt],
        ].join('\n');
      case LocalVlmTaskMode.story:
        return <String>[
          '你是手机本地运行的图像叙事写作助手。',
          '任务：结合多张图片与时间地点元数据，写一段连贯中文故事。',
          '不要解释，不要展示推理过程，不要复述要求。',
          '',
          ...metadataLines,
          '只输出 JSON，不要 markdown。',
          'JSON 格式严格固定为：{"story":"..."}',
          'story 必须是一整段中文，长度 180-320 个中文字符。',
          '故事要体现图片之间的联系、时间推进或空间转换。',
          if (extraPrompt.isNotEmpty) ...<String>['', '[附加要求]', extraPrompt],
        ].join('\n');
    }
  }

  Map<String, dynamic> _buildTaskOutputDocument({
    required InternvlStructuredResponse structured,
    required OnDeviceInternvlServerStatus server,
  }) {
    final parsed = _tryParseJsonObject(structured.rawContent);
    final output = _taskMode == LocalVlmTaskMode.captions
        ? _normalizeCaptionOutput(parsed, structured)
        : _normalizeStoryOutput(parsed, structured);

    return <String, dynamic>{
      'task': _taskMode == LocalVlmTaskMode.captions
          ? 'caption_batch'
          : 'story_generation',
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'prompt': _buildTaskPrompt(),
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
      'runtime': <String, dynamic>{
        'mode': 'local_persistent_server',
        'acceleration': 'cpu',
        'model': _modelNameText(),
        'pid': server.pid,
        'host': server.host,
        'port': server.port,
        'npu_enabled': _profile?.npuAvailableThroughApp ?? false,
      },
      'result': output,
    };
  }

  Map<String, dynamic> _normalizeCaptionOutput(
    Map<String, dynamic>? parsed,
    InternvlStructuredResponse structured,
  ) {
    final output = _extractOutputMap(parsed);
    final rawCaptions = _extractListOfMaps(
      output['captions'] ?? output['items'] ?? output['images'],
    );
    final captionCount = _selectedImages.length;
    final captions = <Map<String, dynamic>>[];
    final fallbackCaptions = _extractDraftCaptions(structured.rawContent);

    for (var index = 0; index < captionCount; index++) {
      final item = index < rawCaptions.length ? rawCaptions[index] : null;
      final caption = _cleanCaptionText(
        _firstString(
              item,
              const <String>['caption', 'description', 'text', 'summary'],
            ) ??
            (index < fallbackCaptions.length
                ? fallbackCaptions[index]
                : (captionCount == 1
                    ? _extractFinalParagraph(structured.rawContent)
                    : '')),
      );
      captions.add(<String, dynamic>{
        'index': index + 1,
        'caption': caption,
      });
    }

    return <String, dynamic>{
      'captions': captions,
    };
  }

  Map<String, dynamic> _normalizeStoryOutput(
    Map<String, dynamic>? parsed,
    InternvlStructuredResponse structured,
  ) {
    final output = _extractOutputMap(parsed);
    final parsedStory = _cleanStoryText(
      _firstString(
            output,
            const <String>['story', 'narrative', 'content', 'answer'],
          ) ??
          _extractFinalParagraph(structured.rawContent),
    );
    return <String, dynamic>{
      'story': parsedStory,
    };
  }

  String _buildPreviewFromDocument(Map<String, dynamic> document) {
    final output = document['result'];
    if (output is! Map<String, dynamic>) {
      return '模型已完成推理，但没有可直接展示的结果。';
    }

    if (_taskMode == LocalVlmTaskMode.captions) {
      final captions = _extractListOfMaps(output['captions']);
      return captions
          .map((item) {
            final index = item['index'] ?? '?';
            final caption = item['caption']?.toString().trim() ?? '';
            return '图片$index：$caption';
          })
          .join('\n\n');
    }

    final title = output['title']?.toString().trim() ?? '';
    final story = output['story']?.toString().trim() ?? '';
    if (title.isNotEmpty) {
      return '$title\n\n$story';
    }
    return story;
  }

  List<String> _extractDraftCaptions(String rawText) {
    final matches = RegExp(
      r'caption\s*\d*\s*[:：]\s*(.+)',
      caseSensitive: false,
    ).allMatches(rawText);
    final extracted = matches
        .map((match) => _cleanCaptionText(match.group(1) ?? ''))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (extracted.isNotEmpty) {
      return extracted.toSet().toList(growable: false);
    }

    final compact = _extractFinalParagraph(rawText);
    return compact.isEmpty ? const <String>[] : <String>[compact];
  }

  String _extractFinalParagraph(String rawText) {
    final lines = rawText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !_looksLikeInstructionLine(line))
        .toList(growable: false);
    if (lines.isEmpty) {
      return '';
    }
    return lines.last;
  }

  bool _looksLikeInstructionLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains('schema_version') ||
        lower.contains('"task"') ||
        lower.contains("'task'") ||
        lower.contains('"output"') ||
        lower.contains("'output'") ||
        lower.contains('json') ||
        lower.contains('captions') ||
        lower.contains('facts') ||
        lower.contains('time_hint') ||
        lower.contains('location_hint') ||
        lower.contains('confidence') ||
        lower.startsWith('1.') ||
        lower.startsWith('2.') ||
        lower.startsWith('3.') ||
        lower.startsWith('*') ||
        lower.startsWith('-') ||
        lower.contains('输出要求') ||
        lower.contains('构建 json') ||
        lower.contains('检查约束') ||
        lower.contains('分析图片内容');
  }

  String _cleanCaptionText(String value) {
    var cleaned = value.trim();
    if (cleaned.isEmpty) {
      return '';
    }
    cleaned = cleaned.replaceAll(RegExp(r'\\n+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r'^[#*\-\d.\s:：]+'), '').trim();
    final stopMarkers = <String>[
      'schema_version',
      '"task"',
      '\'task\'',
      '"output"',
      '\'output\'',
      'json',
      'facts',
      'time_hint',
      'location_hint',
      'confidence',
      '分析图片内容',
      '构建 json',
      '检查约束',
    ];
    for (final marker in stopMarkers) {
      final index = cleaned.toLowerCase().indexOf(marker.toLowerCase());
      if (index > 0) {
        cleaned = cleaned.substring(0, index).trim();
      }
    }
    return cleaned;
  }

  String _cleanStoryText(String value) {
    var cleaned = value.trim();
    if (cleaned.isEmpty) {
      return '';
    }
    cleaned = cleaned.replaceAll(RegExp(r'\\n+'), '\n');
    final lines = cleaned
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !_looksLikeInstructionLine(line))
        .toList(growable: false);
    return lines.join(' ');
  }

  Map<String, dynamic> _extractOutputMap(Map<String, dynamic>? parsed) {
    if (parsed == null) {
      return <String, dynamic>{};
    }
    final output = parsed['output'];
    if (output is Map<String, dynamic>) {
      return output;
    }
    return parsed;
  }

  List<Map<String, dynamic>> _extractListOfMaps(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }
    return value
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry<String, dynamic>(key.toString(), value),
          ),
        )
        .toList(growable: false);
  }

  String? _firstString(Map<String, dynamic>? map, List<String> keys) {
    if (map == null) {
      return null;
    }
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  Map<String, dynamic>? _tryParseJsonObject(String rawContent) {
    final direct = _tryDecodeMap(rawContent);
    if (direct != null) {
      return direct;
    }

    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      multiLine: true,
    ).firstMatch(rawContent)?.group(1);
    if (fenced != null) {
      final decoded = _tryDecodeMap(fenced);
      if (decoded != null) {
        return decoded;
      }
    }

    final firstBrace = rawContent.indexOf('{');
    final lastBrace = rawContent.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return _tryDecodeMap(rawContent.substring(firstBrace, lastBrace + 1));
    }
    return null;
  }

  Map<String, dynamic>? _tryDecodeMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is String) {
        final nested = decoded.trim();
        if (nested.isNotEmpty && nested != text) {
          return _tryDecodeMap(nested);
        }
      }
    } catch (_) {
      return null;
    }
    return null;
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

  String _modelNameText() {
    final modelPath = _serverDeploymentStatus?.modelPath ?? '';
    if (modelPath.trim().isEmpty) {
      return '未检测到模型路径';
    }
    return p.basename(modelPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地 Qwen3.5-0.8B 测试'),
        actions: [
          IconButton(
            onPressed: _isLoading || _isRunning ? null : _loadPageData,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新状态',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                  label: Text(
                    _isRunning ? '正在处理中...' : _taskMode.buttonLabel,
                  ),
                ),
                if (_isRunning) ...[
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
                if (_resultPreview != null) ...[
                  const SizedBox(height: 16),
                  _buildMessageCard(
                    context,
                    _taskMode == LocalVlmTaskMode.captions
                        ? 'Caption 结果'
                        : '故事结果',
                    _resultPreview!,
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

  Widget _buildRuntimeCard(BuildContext context) {
    final profile = _profile;
    final server = _serverStatus;
    final deployment = _serverDeploymentStatus;
    final supportsNpu = profile?.npuAvailableThroughApp == true;

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
            Text('模型文件: ${_modelNameText()}'),
            Text('执行方式: 手机本地常驻 llama-server'),
            Text('当前加速: CPU'),
            Text('NPU 状态: ${supportsNpu ? '已接通' : '未接通'}'),
            if (_serverDeploymentStatus?.modelPath.isNotEmpty == true &&
                !_serverDeploymentStatus!.modelPath.toLowerCase().contains(
                  'qwen',
                ))
              Text(
                '警告: 当前实际命中的不是 Qwen 模型，请检查手机侧部署目录是否为 checkpoints/qwen。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (_backendStatus != null)
              Text('后端说明: ${_backendStatus!.reason}'),
            if (!supportsNpu)
              Text(
                '当前仓库尚未接入 NNAPI / QNN / MediaTek NeuroPilot 等 NPU 推理后端，因此暂时不能切到 NPU。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text('服务状态: ${server?.summary ?? '未知'}'),
            if (server != null) Text('PID: ${server.pid}'),
            if (profile != null)
              Text(
                '推荐线程/上下文: ${profile.recommendedThreads} / ${profile.recommendedContextSize}',
              ),
            if (deployment != null && deployment.missingItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '缺失依赖: ${deployment.missingItems.join('；')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
                        _resultPreview = null;
                        _structuredJsonText = null;
                        _outputFilePath = null;
                        _runSummaryText = null;
                        _errorText = null;
                      });
                    },
            ),
            const SizedBox(height: 10),
            Text(
              _taskMode.subtitle,
              style: Theme.of(context).textTheme.bodySmall,
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
                              child: PathImage(
                                path: image.path,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '图片${index + 1}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
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
