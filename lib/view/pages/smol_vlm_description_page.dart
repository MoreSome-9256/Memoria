import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../models/entity/photo_entity.dart';
import '../../objectbox.g.dart';
import '../../service/internvl_output_archive_service.dart';
import '../../service/local_vlm_description_service.dart';
import '../../storage/objectbox/objectbox_service.dart';
import '../../utils/media_type_helper.dart';
import 'vlm_photo_picker_page.dart';

class SmolVlmDescriptionPage extends StatefulWidget {
  const SmolVlmDescriptionPage({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  State<SmolVlmDescriptionPage> createState() => _SmolVlmDescriptionPageState();
}

class _SmolVlmDescriptionPageState extends State<SmolVlmDescriptionPage> {
  final TextEditingController _focusController = TextEditingController();
  final InternvlOutputArchiveService _archiveService =
      InternvlOutputArchiveService();

  bool _running = false;
  List<_SelectedVlmMedia> _selected = const <_SelectedVlmMedia>[];
  String? _errorText;
  String? _jsonText;
  String? _outputFilePath;

  @override
  void dispose() {
    _focusController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final result = await Navigator.of(context).push<List<VlmPhotoPickerResult>>(
      MaterialPageRoute<List<VlmPhotoPickerResult>>(
        builder: (context) => const VlmPhotoPickerPage(
          title: '选择图片或视频',
          requestType: RequestType.common,
          maxSelection: 6,
        ),
      ),
    );
    if (!mounted || result == null || result.isEmpty) {
      return;
    }
    final selected = await _buildSelectedMedia(result);
    if (!mounted) return;
    setState(() {
      _selected = selected;
      _errorText = selected.isEmpty ? '所选媒体不可访问，请重新选择。' : null;
      _jsonText = null;
      _outputFilePath = null;
    });
  }

  Future<List<_SelectedVlmMedia>> _buildSelectedMedia(
    List<VlmPhotoPickerResult> picks,
  ) async {
    final photoBox = ObjectBoxService().store.box<PhotoEntity>();
    final selected = <_SelectedVlmMedia>[];
    for (final pick in picks) {
      if (pick.assetId.trim().isEmpty) {
        continue;
      }
      final q = photoBox
          .query(PhotoEntity_.assetId.equals(pick.assetId))
          .build();
      final photo = q.findFirst();
      q.close();
      final kind = photo == null
          ? pick.mediaKind
          : MediaTypeHelper.fromStorageValue(photo.mediaKind, path: photo.path);
      selected.add(_SelectedVlmMedia(pick: pick, photo: photo, kind: kind));
    }
    return selected;
  }

  Future<void> _runDescriptions() async {
    if (_selected.isEmpty || _running) return;
    setState(() {
      _running = true;
      _errorText = null;
      _jsonText = null;
      _outputFilePath = null;
    });

    final outputs = <Map<String, Object?>>[];
    try {
      for (var i = 0; i < _selected.length; i++) {
        final item = _selected[i];
        final description = await LocalVlmDescriptionService.instance
            .generateAssetDescription(
              assetId: item.pick.assetId,
              treatAsVideo: item.isVideoLike,
              prompt: _buildPrompt(item),
            );
        outputs.add(item.toJson(description: description, error: null));
        if (!mounted) return;
        setState(() {
          _selected = <_SelectedVlmMedia>[
            for (var j = 0; j < _selected.length; j++)
              j == i
                  ? _selected[j].copyWith(description: description)
                  : _selected[j],
          ];
        });
      }

      final document = <String, Object?>{
        'schema': 'memoria.smolvlm2.description.v1',
        'createdAt': DateTime.now().toIso8601String(),
        'model': 'SmolVLM2 via llama.cpp FFI',
        'task': 'description_only',
        'items': outputs,
      };
      final archive = await _archiveService.saveStandardJson(
        document: jsonDecode(jsonEncode(document)) as Map<String, dynamic>,
      );
      if (!mounted) return;
      setState(() {
        _jsonText = archive.prettyJson;
        _outputFilePath = archive.filePath;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  String _buildPrompt(_SelectedVlmMedia item) {
    final focus = _focusController.text.trim();
    final buffer = StringBuffer(
      item.isVideoLike
          ? 'Describe only observable visual facts across these sampled video or animated-image frames. Treat a dynamic photo, GIF, or motion photo as a short video. Do not write a story, infer intent, solve visible math problems, answer chat messages, continue memes, or perform any generation task.'
          : 'Describe only observable visual facts in this image. Do not write a story, infer intent, solve visible math problems, answer chat messages, continue memes, or perform any generation task.',
    );
    if (focus.isNotEmpty) {
      buffer.write(' Observation focus: $focus.');
    }
    final location = item.locationLabel;
    if (location != null) {
      buffer.write(' Known location metadata: $location.');
    }
    buffer.write(' Answer in concise, standard English.');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _focusController,
            decoration: const InputDecoration(
              labelText: '可选观察重点',
              hintText: '例如：人物动作、场景、视频中的变化',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _pickMedia,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('选择媒体'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _running || _selected.isEmpty
                    ? null
                    : _runDescriptions,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.psychology_outlined),
                label: Text(_running ? '描述中' : '生成描述'),
              ),
            ],
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(_errorText!, style: TextStyle(color: Colors.red[700])),
          ],
          const SizedBox(height: 16),
          for (final item in _selected) _buildSelectedCard(context, item),
          if (_outputFilePath != null) ...[
            const SizedBox(height: 16),
            Text('已归档: $_outputFilePath'),
          ],
          if (_jsonText != null) ...[
            const SizedBox(height: 12),
            SelectableText(_jsonText!),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedCard(BuildContext context, _SelectedVlmMedia item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.isVideoLike ? Icons.videocam : Icons.image),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.kindLabel),
                  if (item.locationLabel != null)
                    Text(
                      item.locationLabel!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (item.description != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(item.description!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedVlmMedia {
  const _SelectedVlmMedia({
    required this.pick,
    required this.photo,
    required this.kind,
    this.description,
  });

  final VlmPhotoPickerResult pick;
  final PhotoEntity? photo;
  final MemoriaMediaKind kind;
  final String? description;

  bool get isVideoLike =>
      kind == MemoriaMediaKind.video || kind == MemoriaMediaKind.dynamicImage;

  String get kindLabel => switch (kind) {
    MemoriaMediaKind.image => '图片',
    MemoriaMediaKind.dynamicImage => '动态照片（按视频处理）',
    MemoriaMediaKind.video => '视频',
  };

  String? get locationLabel {
    final preferred = (photo?.locationName ?? photo?.formattedAddress)?.trim();
    if (preferred != null && preferred.isNotEmpty) return preferred;
    final chunks = <String>[
      if (photo?.province?.trim().isNotEmpty == true) photo!.province!.trim(),
      if (photo?.city?.trim().isNotEmpty == true) photo!.city!.trim(),
      if (photo?.district?.trim().isNotEmpty == true) photo!.district!.trim(),
    ];
    return chunks.isEmpty ? null : chunks.join(' ');
  }

  _SelectedVlmMedia copyWith({String? description}) {
    return _SelectedVlmMedia(
      pick: pick,
      photo: photo,
      kind: kind,
      description: description ?? this.description,
    );
  }

  Map<String, Object?> toJson({required String description, String? error}) {
    return <String, Object?>{
      'assetId': pick.assetId,
      'path': pick.path,
      'capturedAt': pick.createdAt.toIso8601String(),
      'kind': kind.name,
      'treatedAsVideo': isVideoLike,
      'location': locationLabel,
      'description': description,
      'error': error,
    };
  }
}
