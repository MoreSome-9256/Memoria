import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../service/app_ai_settings_service.dart';
import '../../service/litert_inference_service.dart';
import '../../service/media_embedding_service.dart';
import '../../service/media_file_embedding_input_service.dart';
import '../../service/mobileclip_backend_preference_service.dart';
import '../../service/mobileclip_litert_service.dart';
import '../../utils/media_type_helper.dart';

class MediaVectorSimilarityTestPage extends StatefulWidget {
  const MediaVectorSimilarityTestPage({super.key});

  @override
  State<MediaVectorSimilarityTestPage> createState() =>
      _MediaVectorSimilarityTestPageState();
}

class _MediaVectorSimilarityTestPageState
    extends State<MediaVectorSimilarityTestPage> {
  final _queryController = TextEditingController(text: 'a photo of a person');
  final _inputService = MediaFileEmbeddingInputService();
  final _embeddingService = MediaEmbeddingService();

  bool _isRunning = false;
  String? _path;
  String? _error;
  MediaEmbeddingResult? _mediaResult;
  MediaTextSimilarityResult? _similarityResult;
  VideoPlayerController? _videoController;
  List<String> _cleanupPaths = const <String>[];
  MobileClipBackend _selectedBackend = MobileClipBackend.mobileclip2LiteRt;
  LocalInferenceAccelerator _selectedAccelerator =
      LocalInferenceAccelerator.gpu;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitialSettings());
  }

  @override
  void dispose() {
    _queryController.dispose();
    _videoController?.dispose();
    _cleanupTempFiles();
    super.dispose();
  }

  Future<void> _loadInitialSettings() async {
    final settings = await AppAiSettingsService.instance.load();
    final backend = await MobileClipBackendPreferenceService()
        .getSelectedBackend();
    if (!mounted) return;
    setState(() {
      _selectedBackend = backend;
      _selectedAccelerator = settings.inferenceAccelerator;
    });
  }

  Future<void> _pickAndRun() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>[
        'jpg',
        'jpeg',
        'png',
        'webp',
        'gif',
        'heic',
        'heif',
        'mp4',
        'mov',
        'm4v',
        '3gp',
        'webm',
      ],
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    await _run(path);
  }

  Future<void> _rerunCurrent() async {
    final path = _path;
    if (path == null) return;
    await _run(path);
  }

  Future<void> _run(String path) async {
    setState(() {
      _isRunning = true;
      _error = null;
      _path = path;
      _mediaResult = null;
      _similarityResult = null;
    });

    await _videoController?.dispose();
    _videoController = null;
    _cleanupTempFiles();

    try {
      final input = await _inputService.prepare(path);
      _cleanupPaths = input.cleanupPaths;
      if (input.kind == MemoriaMediaKind.video) {
        final controller = VideoPlayerController.file(File(path));
        await controller.initialize();
        await controller.setVolume(0);
        await controller.setLooping(true);
        await controller.play();
        _videoController = controller;
      }

      final settings = await AppAiSettingsService.instance.load();
      final liteRt = MobileClipLiteRtService.detachedWithAccelerator(
        _selectedAccelerator,
      );
      final mediaResult = input.kind == MemoriaMediaKind.video &&
              settings.mobileViClipEnabled
          ? await _embeddingService.embedVideoFrameBytes(input.videoFrameBytes)
          : await _embeddingService.embedImageBytes(
              input.imageOrThumbnailBytes,
              backend: _selectedBackend,
              liteRt: liteRt,
            ).then(
              (value) => input.kind == MemoriaMediaKind.image
                  ? value
                  : value.copyWith(kind: input.kind),
            );
      final query = _queryController.text.trim();
      final similarity = query.isEmpty
          ? null
          : await _embeddingService.compareWithText(
              media: mediaResult,
              text: query,
              liteRt: liteRt,
            );

      if (!mounted) return;
      setState(() {
        _mediaResult = mediaResult;
        _similarityResult = similarity;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  void _cleanupTempFiles() {
    for (final path in _cleanupPaths) {
      unawaited(_deleteTempFile(path));
    }
    _cleanupPaths = const <String>[];
  }

  Future<void> _deleteTempFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    final result = _mediaResult;
    final similarity = _similarityResult;
    final videoController = _videoController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体向量相似度测试'),
        actions: [
          IconButton(
            onPressed: _isRunning || path == null ? null : _rerunCurrent,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RuntimeOptionsCard(
            selectedBackend: _selectedBackend,
            selectedAccelerator: _selectedAccelerator,
            isRunning: _isRunning,
            onBackendChanged: (backend) {
              setState(() => _selectedBackend = backend);
            },
            onAcceleratorChanged: (accelerator) {
              setState(() => _selectedAccelerator = accelerator);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _queryController,
            decoration: const InputDecoration(
              labelText: '文本查询',
              helperText: '使用 MobileCLIP2 文本编码；英文短语通常更稳定。',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _rerunCurrent(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isRunning ? null : _pickAndRun,
            icon: _isRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_open_outlined),
            label: Text(_isRunning ? '计算中...' : '选择图片或视频并计算'),
          ),
          if (path != null) ...[
            const SizedBox(height: 16),
            SelectableText(path),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: videoController != null &&
                        videoController.value.isInitialized
                    ? VideoPlayer(videoController)
                    : Image.file(File(path), fit: BoxFit.cover),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_error!),
              ),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 16),
            _EmbeddingCard(result: result),
          ],
          if (similarity != null) ...[
            const SizedBox(height: 12),
            _SimilarityCard(result: similarity),
          ],
        ],
      ),
    );
  }
}

class _RuntimeOptionsCard extends StatelessWidget {
  const _RuntimeOptionsCard({
    required this.selectedBackend,
    required this.selectedAccelerator,
    required this.isRunning,
    required this.onBackendChanged,
    required this.onAcceleratorChanged,
  });

  final MobileClipBackend selectedBackend;
  final LocalInferenceAccelerator selectedAccelerator;
  final bool isRunning;
  final ValueChanged<MobileClipBackend> onBackendChanged;
  final ValueChanged<LocalInferenceAccelerator> onAcceleratorChanged;

  @override
  Widget build(BuildContext context) {
    final isApple =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    final acceleratorSegments = isApple
        ? const <ButtonSegment<LocalInferenceAccelerator>>[
            ButtonSegment<LocalInferenceAccelerator>(
              value: LocalInferenceAccelerator.coreml,
              label: Text('Core ML'),
            ),
            ButtonSegment<LocalInferenceAccelerator>(
              value: LocalInferenceAccelerator.metal,
              label: Text('Metal'),
            ),
            ButtonSegment<LocalInferenceAccelerator>(
              value: LocalInferenceAccelerator.xnnpack,
              label: Text('XNNPACK'),
            ),
            ButtonSegment<LocalInferenceAccelerator>(
              value: LocalInferenceAccelerator.cpu,
              label: Text('CPU'),
            ),
          ]
        : const <ButtonSegment<LocalInferenceAccelerator>>[
            ButtonSegment<LocalInferenceAccelerator>(
              value: LocalInferenceAccelerator.gpu,
              label: Text('GPU'),
            ),
            ButtonSegment<LocalInferenceAccelerator>(
              value: LocalInferenceAccelerator.npu,
              label: Text('NPU'),
            ),
            ButtonSegment<LocalInferenceAccelerator>(
              value: LocalInferenceAccelerator.xnnpack,
              label: Text('XNNPACK'),
            ),
            ButtonSegment<LocalInferenceAccelerator>(
              value: LocalInferenceAccelerator.cpu,
              label: Text('CPU'),
            ),
          ];
    final normalizedAccelerator = acceleratorSegments.any(
      (segment) => segment.value == selectedAccelerator,
    )
        ? selectedAccelerator
        : (isApple
              ? LocalInferenceAccelerator.coreml
              : LocalInferenceAccelerator.gpu);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('运行配置', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('图像后端', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<MobileClipBackend>(
              segments: const <ButtonSegment<MobileClipBackend>>[
                ButtonSegment<MobileClipBackend>(
                  value: MobileClipBackend.mobileclip2LiteRt,
                  label: Text('LiteRT'),
                ),
                ButtonSegment<MobileClipBackend>(
                  value: MobileClipBackend.ncnn,
                  label: Text('NCNN'),
                ),
              ],
              selected: <MobileClipBackend>{selectedBackend},
              onSelectionChanged: isRunning
                  ? null
                  : (selection) => onBackendChanged(selection.first),
            ),
            const SizedBox(height: 12),
            Text(
              'LiteRT 推理方式',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<LocalInferenceAccelerator>(
              segments: acceleratorSegments,
              selected: <LocalInferenceAccelerator>{normalizedAccelerator},
              onSelectionChanged: isRunning
                  ? null
                  : (selection) => onAcceleratorChanged(selection.first),
            ),
            const SizedBox(height: 8),
            Text(
              selectedBackend == MobileClipBackend.ncnn
                  ? 'NCNN 图像向量走原生 FFI；文本向量仍使用这里选择的 LiteRT 推理方式。'
                  : '图片和文本都会使用这里选择的 LiteRT 推理方式；视频默认走 MobileViCLIP。',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmbeddingCard extends StatelessWidget {
  const _EmbeddingCard({required this.result});

  final MediaEmbeddingResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('媒体向量', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('kind: ${result.kind.name}'),
            Text('model: ${result.modelLabel}'),
            SelectableText('modelVersion: ${result.modelVersion}'),
            Text('dim: ${result.embedding.length}'),
            Text(
              'preprocess: ${result.preprocessMs.toStringAsFixed(1)} ms, '
              'inference: ${result.inferenceMs.toStringAsFixed(1)} ms',
            ),
            const SizedBox(height: 8),
            SelectableText('first16: ${_formatVectorPreview(result.embedding)}'),
          ],
        ),
      ),
    );
  }
}

String _formatVectorPreview(List<double> vector) {
  return vector.take(16).map((v) => v.toStringAsFixed(6)).join(', ');
}

class _SimilarityCard extends StatelessWidget {
  const _SimilarityCard({required this.result});

  final MediaTextSimilarityResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final unavailableReason = result.unavailableReason;
    final normalized = ((result.score + 1) / 2).clamp(0.0, 1.0);
    return Card(
      color: result.isSameEmbeddingSpace && unavailableReason == null
          ? null
          : colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文本相似度', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText('query: ${result.text}'),
            if (unavailableReason == null) ...[
              Text('score: ${result.score.toStringAsFixed(6)}'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: normalized),
            ],
            if (unavailableReason != null) ...[
              const SizedBox(height: 12),
              Text(unavailableReason),
            ] else if (!result.isSameEmbeddingSpace) ...[
              const SizedBox(height: 12),
              const Text(
                '注意：当前媒体向量和文本向量不是已验证的同一 embedding space。'
                '此分数只适合调试，不适合作为真实检索结果。',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
