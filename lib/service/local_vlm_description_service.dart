import 'dart:async';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_model_weight_service.dart';
import 'media_analysis_image_reader.dart';

class LocalVlmModelConfig {
  const LocalVlmModelConfig({
    required this.id,
    required this.modelPath,
    required this.projectorPath,
  });

  final String id;
  final String modelPath;
  final String projectorPath;
}

class LocalVlmAssetInput {
  const LocalVlmAssetInput({required this.assetId, required this.treatAsVideo});

  final String assetId;
  final bool treatAsVideo;
}

class LocalVlmDescriptionService {
  LocalVlmDescriptionService._();
  static final LocalVlmDescriptionService instance =
      LocalVlmDescriptionService._();

  LlamaEngine? _engine;
  LocalVlmModelConfig? _overrideConfig;
  Future<LlamaEngine>? _loading;
  Future<void> _generationTail = Future<void>.value();
  static const int _mobileFrameSize = 448;
  static const int _mobileVideoFrameCount = 3;

  Future<bool> get isEnabled async => true;

  /// Allows another compatible GGUF vision model, including Gemma-family
  /// models, without changing the caption pipeline.
  Future<void> configureModel(LocalVlmModelConfig? config) async {
    if (_sameConfig(_overrideConfig, config)) return;
    _overrideConfig = config;
    await _resetEngine();
  }

  Future<String> generateAssetDescription({
    required String assetId,
    required bool treatAsVideo,
    String prompt =
        'Describe the visible content in one concise, concrete paragraph.',
  }) async {
    return generateAssetsDescription(
      assets: <LocalVlmAssetInput>[
        LocalVlmAssetInput(assetId: assetId, treatAsVideo: treatAsVideo),
      ],
      prompt: prompt,
      maxTokens: 160,
    );
  }

  Future<String> generateAssetsDescription({
    required List<LocalVlmAssetInput> assets,
    required String prompt,
    int maxTokens = 320,
  }) async {
    if (assets.isEmpty) throw ArgumentError('At least one asset is required.');
    final previous = _generationTail;
    final completer = Completer<void>();
    _generationTail = completer.future;
    await previous;
    try {
      return await _generateAssetsDescriptionLocked(
        assets: assets,
        prompt: prompt,
        maxTokens: maxTokens,
      );
    } finally {
      completer.complete();
    }
  }

  Future<String> _generateAssetsDescriptionLocked({
    required List<LocalVlmAssetInput> assets,
    required String prompt,
    required int maxTokens,
  }) async {
    final frameResults = <MediaAnalysisFrameFiles>[];
    try {
      for (final asset in assets.take(9)) {
        frameResults.add(
          await MediaAnalysisImageReader.instance.readFrameFilesFromAsset(
            asset.assetId.trim(),
            videoLike: asset.treatAsVideo,
            maxFrames: assets.length == 1 && asset.treatAsVideo
                ? _mobileVideoFrameCount
                : 1,
            imageSize: _mobileFrameSize,
          ),
        );
      }
      final frameFiles = frameResults
          .expand((result) => result.frames)
          .toList();
      if (frameFiles.isEmpty) {
        throw StateError('No readable visual frames were extracted.');
      }
      final engine = await _ensureEngine().timeout(const Duration(minutes: 2));
      final content = <LlamaContentPart>[
        for (final frame in frameFiles) LlamaImageContent(path: frame.path),
        LlamaTextContent(prompt),
      ];
      final response = engine.create(
        <LlamaChatMessage>[
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: content,
          ),
        ],
        params: GenerationParams(
          maxTokens: maxTokens.clamp(32, 512),
          temp: 0.2,
          topP: 0.9,
        ),
      );
      final buffer = StringBuffer();
      await for (final chunk in response.timeout(const Duration(minutes: 3))) {
        final text = chunk.choices.firstOrNull?.delta.content;
        if (text != null) buffer.write(text);
      }
      final result = buffer.toString().trim();
      if (result.isEmpty) throw StateError('Local VLM returned empty output.');
      return result;
    } catch (_) {
      await _resetEngine();
      rethrow;
    } finally {
      for (final path in frameResults.expand((result) => result.cleanupPaths)) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<LlamaEngine> _ensureEngine() async {
    final existing = _engine;
    if (existing != null) return existing;
    final activeLoad = _loading;
    if (activeLoad != null) return activeLoad;
    final load = _loadEngine();
    _loading = load;
    try {
      return await load;
    } finally {
      if (identical(_loading, load)) _loading = null;
    }
  }

  Future<LlamaEngine> _loadEngine() async {
    final config = _overrideConfig ?? await _defaultConfig();
    final engine = LlamaEngine(LlamaBackend());
    try {
      await engine.setLogLevel(LlamaLogLevel.warn);
      await engine.loadModel(
        config.modelPath,
        modelParams: ModelParams(gpuLayers: Platform.isAndroid ? 0 : 99),
      );
      await engine.loadMultimodalProjector(config.projectorPath);
      _engine = engine;
      return engine;
    } catch (_) {
      await engine.dispose();
      rethrow;
    }
  }

  Future<LocalVlmModelConfig> _defaultConfig() async {
    final available = await AiModelWeightService.instance
        .ensureWeightsAvailableForInference(AiModelWeightId.smolVlm2);
    if (!available) {
      throw StateError('SmolVLM2 model weights are not available.');
    }
    final docs = await getApplicationDocumentsDirectory();
    final directory = Directory('${docs.path}/models/smolvlm2');
    final model = File('${directory.path}/smolvlm2.gguf');
    final projector = File('${directory.path}/mmproj.gguf');
    if (!model.existsSync() || !projector.existsSync()) {
      throw StateError('SmolVLM2 model or visual projector is missing.');
    }
    return LocalVlmModelConfig(
      id: 'smolvlm2',
      modelPath: model.path,
      projectorPath: projector.path,
    );
  }

  bool _sameConfig(LocalVlmModelConfig? left, LocalVlmModelConfig? right) =>
      left?.id == right?.id &&
      left?.modelPath == right?.modelPath &&
      left?.projectorPath == right?.projectorPath;

  Future<void> dispose() => _resetEngine();

  Future<void> _resetEngine() async {
    final engine = _engine;
    _engine = null;
    await engine?.dispose();
  }
}
