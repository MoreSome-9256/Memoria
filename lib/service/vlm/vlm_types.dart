import 'package:flutter/foundation.dart';

enum VlmBackend {
  smolVlm2,
}

enum VlmTask {
  caption,
  multiImageStory,
}

class VlmConfig {
  const VlmConfig({
    this.modelPath,
    this.modelUrl,
    this.contextSize = 8192,
    this.maxTokens = 256,
    this.gpuLayers = 0,
    this.numThreads = 4,
    this.backend = VlmBackend.smolVlm2,
  });

  final String? modelPath;
  final String? modelUrl;
  final int contextSize;
  final int maxTokens;
  final int gpuLayers;
  final int numThreads;
  final VlmBackend backend;

  static const recommendedModelName = 'smolvlm2-256m-q8_0.gguf';
  static const recommendedModelSize = 279 * 1024 * 1024; // ~279MB
}

class VlmResult {
  const VlmResult({
    required this.text,
    this.tokensUsed = 0,
    this.inferenceMs = 0,
  });

  final String text;
  final int tokensUsed;
  final int inferenceMs;

  bool get isEmpty => text.trim().isEmpty;
}
