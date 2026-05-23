import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path_provider/path_provider.dart';

import 'vlm_types.dart';

class SmolVlm2Service {
  SmolVlm2Service._();

  static final SmolVlm2Service _instance = SmolVlm2Service._();
  factory SmolVlm2Service() => _instance;

  LlamaEngine? _engine;
  bool _isLoaded = false;

  static const String _modelUrl =
      'https://huggingface.co/unsloth/smolVLM2-256M-Instruct-GGUF/resolve/main/smolVLM2-256M-Instruct-Q8_0.gguf';
  static const String _modelFilename = 'smolVLM2-256M-Instruct-Q8_0.gguf';

  bool get isLoaded => _isLoaded && _engine != null;
  bool get supportsVision => _engine?.supportsVision ?? false;

  Future<String> _resolveModelPath() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$_modelFilename');
    if (await file.exists()) return file.path;
    throw StateError('smolVLM2 model not found at ${file.path}. Download first.');
  }

  Future<void> loadModel({VlmConfig? config}) async {
    if (_isLoaded) return;

    final modelPath = config?.modelPath ?? await _resolveModelPath();

    final modelParams = ModelParams(
      path: modelPath,
      gpuLayers: 99,
    );
    final contextParams = const ContextParams(nCtx: 4096);
    final multimodalParams = MultimodalParams(mmprojPath: modelPath);

    if (Platform.isAndroid) {
      _engine = await LlamaEngine.spawn(
        libraryPath: 'libllama.so',
        modelParams: modelParams,
        contextParams: contextParams,
        multimodalParams: multimodalParams,
      );
    } else {
      _engine = await LlamaEngine.spawnFromProcess(
        modelParams: modelParams,
        contextParams: contextParams,
        multimodalParams: multimodalParams,
      );
    }

    _isLoaded = true;
    debugPrint('✅ smolVLM2 loaded, vision=$supportsVision');
  }

  Future<VlmResult> captionImage({
    required Uint8List imageBytes,
    String? prompt,
    int maxTokens = 128,
  }) async {
    if (!isLoaded) return const VlmResult(text: '');

    final chat = await _engine!.createChat();
    chat.addUser(
      prompt ?? '请用一句话描述这张图片的内容。',
      media: [LlamaMedia.imageBytes(imageBytes)],
    );

    final buffer = StringBuffer();
    var tokens = 0;
    final timer = Stopwatch()..start();

    try {
      await for (final event in chat.generate(
        maxTokens: maxTokens,
        sampler: const SamplerParams(temperature: 0.3),
      )) {
        if (event is TokenEvent) {
          buffer.write(event.text);
          tokens++;
        }
      }
    } finally {
      timer.stop();
      await chat.dispose();
    }

    return VlmResult(
      text: buffer.toString().trim(),
      tokensUsed: tokens,
      inferenceMs: timer.elapsedMilliseconds,
    );
  }

  Future<VlmResult> describeImages({
    required List<Uint8List> imageBytesList,
    String? prompt,
    int maxTokens = 256,
  }) async {
    if (!isLoaded || imageBytesList.isEmpty) {
      return const VlmResult(text: '');
    }

    final chat = await _engine!.createChat();
    chat.addUser(
      prompt ?? '请描述这些图片。',
      media: imageBytesList.map(LlamaMedia.imageBytes).toList(),
    );

    final buffer = StringBuffer();
    var tokens = 0;
    final timer = Stopwatch()..start();

    try {
      await for (final event in chat.generate(
        maxTokens: maxTokens,
        sampler: const SamplerParams(temperature: 0.3),
      )) {
        if (event is TokenEvent) {
          buffer.write(event.text);
          tokens++;
        }
      }
    } finally {
      timer.stop();
      await chat.dispose();
    }

    return VlmResult(
      text: buffer.toString().trim(),
      tokensUsed: tokens,
      inferenceMs: timer.elapsedMilliseconds,
    );
  }

  Future<void> downloadModel({
    String? url,
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$_modelFilename');

    if (await file.exists()) {
      debugPrint('✅ smolVLM2 model already downloaded');
      return;
    }

    final downloadUrl = url ?? _modelUrl;
    debugPrint('⬇️ Downloading smolVLM2 model from $downloadUrl');

    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(downloadUrl));
      final response = await request.close();
      final total = response.contentLength;
      var received = 0;

      final sink = file.openWrite();
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) {
            onProgress?.call(received, total);
          }
        }
      } finally {
        await sink.close();
      }

      debugPrint('✅ smolVLM2 model downloaded: ${file.path}');
    } catch (e) {
      debugPrint('❌ download failed: $e');
      rethrow;
    } finally {
      httpClient.close();
    }
  }

  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
    _isLoaded = false;
  }
}
