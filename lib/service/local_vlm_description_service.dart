import 'dart:io';
import 'dart:typed_data';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_model_weight_service.dart';
import 'media_analysis_image_reader.dart';

class LocalVlmDescriptionService {
  LocalVlmDescriptionService._();
  static final LocalVlmDescriptionService instance =
      LocalVlmDescriptionService._();

  LlamaEngine? _engine;

  Future<bool> get isEnabled async => true;

  Future<String> generateImageDescription({
    required File imageFile,
    String? assetId,
    String prompt = 'Describe this image in one concise, concrete sentence.',
  }) async {
    return generateMediaDescription(
      mediaFile: imageFile,
      treatAsVideo: false,
      assetId: assetId,
      prompt: prompt,
    );
  }

  Future<String> generateMediaDescription({
    required File mediaFile,
    required bool treatAsVideo,
    String? assetId,
    String prompt =
        'Describe the visible content in one concise, concrete paragraph.',
  }) async {
    if (!await isEnabled) {
      return '';
    }
    final engine = await _ensureEngine();
    final chat = await engine.createChat();
    final cleanupPaths = <String>[];
    try {
      final frameResult =
          assetId != null && assetId.trim().isNotEmpty
              ? await MediaAnalysisImageReader.instance.readFrameFilesFromAsset(
                  assetId.trim(),
                  fallbackFile: mediaFile,
                  videoLike: treatAsVideo,
                  maxFrames: treatAsVideo ? 8 : 1,
                )
              : await MediaAnalysisImageReader.instance.readFrameFilesFromFile(
                  mediaFile,
                  videoLike: treatAsVideo,
                  maxFrames: treatAsVideo ? 8 : 1,
                );
      cleanupPaths.addAll(frameResult.cleanupPaths);
      final frameBytes = await _readFrameBytes(frameResult.frames);
      if (frameBytes.isEmpty) {
        throw StateError('No readable visual frames were extracted.');
      }
      final media = treatAsVideo
          ? LlamaMedia.videoFrames(frameBytes, idPrefix: 'frame')
          : <LlamaMedia>[LlamaMedia.imageBytes(frameBytes.first, id: 'image')];
      chat.addUser(prompt, media: media);
      final buffer = StringBuffer();
      await for (final event in chat.generate(
        sampler: const SamplerParams(temperature: 0.2, topP: 0.9),
        maxTokens: 160,
      )) {
        if (event is TokenEvent) {
          buffer.write(event.text);
        } else if (event is DoneEvent && event.trailingText.isNotEmpty) {
          buffer.write(event.trailingText);
        }
      }
      return buffer.toString().trim();
    } finally {
      await chat.dispose();
      for (final path in cleanupPaths) {
        try {
          final file = File(path);
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

  Future<List<Uint8List>> _readFrameBytes(List<File> frames) async {
    final bytes = <Uint8List>[];
    for (final frame in frames) {
      if (await frame.exists()) {
        final data = await frame.readAsBytes();
        if (data.isNotEmpty) {
          bytes.add(data);
        }
      }
    }
    return bytes;
  }

  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }
}
