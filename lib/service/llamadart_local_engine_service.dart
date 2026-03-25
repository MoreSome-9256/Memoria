import 'dart:async';

import 'package:llamadart/llamadart.dart';

/// 基于 llamadart 的本地 FFI 推理服务。
///
/// 这个服务只负责模型生命周期与多模态推理，不关心 UI 层或业务结构化输出。
class LlamadartLocalEngineService {
  LlamadartLocalEngineService._internal();

  static final LlamadartLocalEngineService _instance =
      LlamadartLocalEngineService._internal();

  factory LlamadartLocalEngineService() => _instance;

  LlamaEngine? _engine;
  String? _loadedModelPath;
  String? _loadedMmprojPath;

  Future<void> ensureLoaded({
    required String modelPath,
    String? mmprojPath,
  }) async {
    final normalizedModelPath = modelPath.trim();
    final normalizedMmprojPath = mmprojPath?.trim() ?? '';

    if (normalizedModelPath.isEmpty) {
      throw ArgumentError('modelPath 不能为空');
    }

    final alreadyLoaded =
        _engine != null &&
        _loadedModelPath == normalizedModelPath &&
        _loadedMmprojPath == normalizedMmprojPath;
    if (alreadyLoaded) {
      return;
    }

    if (_engine != null) {
      await dispose();
    }

    final engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(normalizedModelPath);

    if (normalizedMmprojPath.isNotEmpty) {
      await engine.loadMultimodalProjector(normalizedMmprojPath);
    }

    _engine = engine;
    _loadedModelPath = normalizedModelPath;
    _loadedMmprojPath = normalizedMmprojPath;
  }

  Future<String> generateVisionText({
    required String prompt,
    required List<String> imagePaths,
    int maxTokens = 256,
    double temperature = 0.2,
  }) async {
    final engine = _engine;
    if (engine == null) {
      throw StateError('llamadart 引擎尚未加载，请先调用 ensureLoaded');
    }
    if (imagePaths.isEmpty) {
      throw ArgumentError('至少需要一张图片');
    }

    final messages = <LlamaChatMessage>[
      LlamaChatMessage.withContent(
        role: LlamaChatRole.user,
        content: <LlamaContent>[
          ...imagePaths.map((path) => LlamaImageContent(path: path)),
          LlamaTextContent(prompt),
        ],
      ),
    ];

    final response = engine.create(
      messages,
      generationParams: GenerationParams(
        maxTokens: maxTokens,
        temperature: temperature,
      ),
    );

    final buffer = StringBuffer();
    await for (final chunk in response) {
      final content = chunk.choices.first.delta.content;
      if (content != null && content.isNotEmpty) {
        buffer.write(content);
      }
    }

    return buffer.toString().trim();
  }

  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    _loadedModelPath = null;
    _loadedMmprojPath = null;
    if (engine != null) {
      await engine.dispose();
    }
  }
}
