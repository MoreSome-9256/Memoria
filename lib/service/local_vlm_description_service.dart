import 'dart:async';
import 'dart:io';

import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';

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
    if (!await isEnabled) {
      return '';
    }
    final engine = await _ensureEngine();
    final chat = await engine.createChat();
    try {
      chat.addUser(prompt, media: <LlamaMedia>[LlamaMedia.imageFile(imageFile.path)]);
      final buffer = StringBuffer();
      await for (final event in chat.generate(maxTokens: 96)) {
        if (event is TokenEvent) {
          buffer.write(event.text);
        }
      }
      return buffer.toString().trim();
    } finally {
      await chat.dispose();
    }
  }

  Future<LlamaEngine> _ensureEngine() async {
    final existing = _engine;
    if (existing != null) {
      return existing;
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
    final engine = await LlamaEngine.spawn(
      libraryPath: Platform.isAndroid ? 'libllama.so' : '',
      modelParams: ModelParams(path: modelFile.path, gpuLayers: 0),
      contextParams: const ContextParams(nCtx: 2048),
      multimodalParams: MultimodalParams(mmprojPath: mmprojFile.path),
    );
    _engine = engine;
    return engine;
  }

  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }
}
