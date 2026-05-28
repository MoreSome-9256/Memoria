import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_model_weight_service.dart';

class LocalVlmDescriptionService {
  LocalVlmDescriptionService._();
  static final LocalVlmDescriptionService instance =
      LocalVlmDescriptionService._();

  LlamaEngine? _engine;

  Future<bool> get isEnabled async => true;

  Future<String> generateImageDescription({
    required File imageFile,
    String prompt = 'Describe this image in one concise, concrete sentence.',
  }) async {
    return generateMediaDescription(
      mediaFile: imageFile,
      treatAsVideo: false,
      prompt: prompt,
    );
  }

  Future<String> generateMediaDescription({
    required File mediaFile,
    required bool treatAsVideo,
    String prompt =
        'Describe the visible content in one concise, concrete paragraph.',
  }) async {
    if (!await isEnabled) {
      return '';
    }
    final engine = await _ensureEngine();
    final chat = await engine.createChat();
    final cleanupFiles = <File>[];
    try {
      final media = <LlamaMedia>[];
      if (treatAsVideo) {
        final frames = await _extractVideoFrameFiles(mediaFile);
        cleanupFiles.addAll(frames);
        if (frames.isNotEmpty) {
          media.addAll(frames.map((file) => LlamaMedia.imageFile(file.path)));
        }
      }
      if (media.isEmpty) {
        media.add(LlamaMedia.imageFile(mediaFile.path));
      }
      chat.addUser(prompt, media: media);
      final buffer = StringBuffer();
      await for (final event in chat.generate(maxTokens: 96)) {
        if (event is TokenEvent) {
          buffer.write(event.text);
        }
      }
      return buffer.toString().trim();
    } finally {
      await chat.dispose();
      for (final file in cleanupFiles) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<LlamaEngine> _ensureEngine() async {
    final existing = _engine;
    if (existing != null) {
      return existing;
    }
    final isAvailable = await AiModelWeightService.instance
        .ensureWeightsAvailableForInference(AiModelWeightId.smolVlm2);
    if (!isAvailable) {
      throw StateError(
        'SmolVLM2 model weights not found. Please download the model first using AiModelWeightService.instance.downloadWeights(AiModelWeightId.smolVlm2).',
      );
    }
    final docs = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${docs.path}/models/smolvlm2');
    final modelFile = File('${modelDir.path}/smolvlm2.gguf');
    final mmprojFile = File('${modelDir.path}/mmproj.gguf');
    if (!modelFile.existsSync() || !mmprojFile.existsSync()) {
      throw StateError(
        'SmolVLM2 model assets are missing. Expected ${modelFile.path} and ${mmprojFile.path}.',
      );
    }
    final engine = await (Platform.isAndroid
        ? LlamaEngine.spawn(
            libraryPath: 'libllama.so',
            modelParams: ModelParams(path: modelFile.path, gpuLayers: 0),
            contextParams: const ContextParams(nCtx: 2048),
            multimodalParams: MultimodalParams(mmprojPath: mmprojFile.path),
          )
        : LlamaEngine.spawnFromProcess(
            modelParams: ModelParams(path: modelFile.path, gpuLayers: 99),
            contextParams: const ContextParams(nCtx: 4096),
            multimodalParams: MultimodalParams(mmprojPath: mmprojFile.path),
          ));
    _engine = engine;
    return engine;
  }

  Future<List<File>> _extractVideoFrameFiles(File mediaFile) async {
    if (!await mediaFile.exists()) {
      return const <File>[];
    }
    final dir = await getTemporaryDirectory();
    final runId = DateTime.now().microsecondsSinceEpoch;
    final framePattern = '${dir.path}/memoria_smolvlm2_${runId}_%02d.jpg';
    final command =
        '-y -i ${_quote(mediaFile.path)} -vf fps=1,scale=512:-1 -frames:v 6 ${_quote(framePattern)}';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      debugPrint('SmolVLM2 video frame extraction failed: $logs');
    }

    final frames = <File>[];
    for (var i = 1; i <= 6; i++) {
      final framePath =
          '${dir.path}/memoria_smolvlm2_${runId}_${i.toString().padLeft(2, '0')}.jpg';
      final file = File(framePath);
      if (await file.exists()) {
        frames.add(file);
      }
    }
    return frames;
  }

  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }
}
