import 'dart:math' as math;

import 'clip_tokenizer_service.dart';
import 'mobileclip_text_service.dart';

/// High-level semantic matching hub combining BPE tokenisation and the
/// MobileCLIP2 text encoder.
///
/// Typical flow:
/// ```dart
/// final svc = SemanticMatchingService();
/// await svc.warmUp(); // once, at app start
///
/// // Zero-shot tagging
/// final tags = await svc.matchTagsForImage(
///   imageVector: imageEmbedding,
///   tagMap: {'a photo of a cat': '猫咪', 'a photo of food': '美食'},
///   topK: 3,
/// );
/// ```
class SemanticMatchingService {
  SemanticMatchingService._internal();

  static final SemanticMatchingService _instance =
      SemanticMatchingService._internal();

  factory SemanticMatchingService() => _instance;

  final ClipTokenizerService _tokenizer = ClipTokenizerService();
  final MobileClipTextService _textService = MobileClipTextService();

  /// Persistent cache: English prompt string → L2-normalised 512-D vector.
  /// For a fixed tag vocabulary this is effectively free after the first scan.
  final Map<String, List<double>> _textVectorCache = {};

  bool _isReady = false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Pre-warms both the tokeniser (vocab + merges) and the ONNX text session.
  /// Safe to call multiple times — subsequent calls return immediately.
  Future<void> warmUp() async {
    if (_isReady) return;
    await Future.wait([
      _tokenizer.warmUp(),
      _textService.warmUp(),
    ]);
    _isReady = true;
  }

  /// Releases the ONNX session and clears the vector cache.
  Future<void> dispose() async {
    await _textService.dispose();
    _textVectorCache.clear();
    _isReady = false;
  }

  /// Clears only the in-memory text vector cache without tearing down the
  /// ONNX session. Useful when the active tag set changes.
  void clearCache() => _textVectorCache.clear();

  // ---------------------------------------------------------------------------
  // Core API
  // ---------------------------------------------------------------------------

  /// Converts any English text phrase into a 512-D L2-normalised CLIP vector.
  ///
  /// Results are cached by text content — repeated calls for the same string
  /// (e.g. the same label across thousands of photos) are ~O(1).
  Future<List<double>> embedText(String text) async {
    final cached = _textVectorCache[text];
    if (cached != null) return cached;

    final tokenIds = await _tokenizer.tokenize(text);
    final vector = await _textService.embedTextTokens(tokenIds);
    _textVectorCache[text] = vector;
    return vector;
  }

  /// Computes the cosine similarity between two L2-normalised vectors.
  ///
  /// Because both [vectorA] and [vectorB] are already unit-length (L2-norm = 1),
  /// cosine similarity reduces to a simple dot product.
  /// Returns a value clamped to [-1.0, 1.0]; higher means more similar.
  double calculateSimilarity(List<double> vectorA, List<double> vectorB) {
    final len = vectorA.length;
    if (len == 0 || len != vectorB.length) return 0.0;
    var dot = 0.0;
    for (var i = 0; i < len; i++) {
      dot += vectorA[i] * vectorB[i];
    }
    // Clamp to [-1, 1] to handle minor floating-point drift.
    return dot.clamp(-1.0, 1.0);
  }

  /// Zero-shot image tagging via natural-language prompts.
  ///
  /// [imageVector]  — 512-D L2-normalised visual embedding from
  ///                  `MobileClipVisionService`.
  /// [tagMap]       — Maps English prompts to the display label you want
  ///                  returned, e.g. `{'a photo of a cat': '猫咪'}`.
  /// [topK]         — How many top labels to return (default 3).
  /// [threshold]    — Optional minimum similarity score. Labels below this
  ///                  are filtered out even if they rank in the top-K.
  ///
  /// Text vectors for all prompts are computed **in parallel** on the first
  /// call, then served from cache on every subsequent call.
  Future<List<String>> matchTagsForImage({
    required List<double> imageVector,
    required Map<String, String> tagMap,
    int topK = 3,
    double threshold = 0.0,
  }) async {
    if (tagMap.isEmpty) return const [];

    // Embed all prompts in parallel — model session handles concurrency via
    // the internal OrtRunOptions lock; cache makes this nearly free after
    // the first call.
    final prompts = tagMap.keys.toList(growable: false);
    final textVectors = await Future.wait(
      prompts.map(embedText),
    );

    // Score and sort.
    final scored = <({String label, double score})>[];
    for (var i = 0; i < prompts.length; i++) {
      final score = calculateSimilarity(imageVector, textVectors[i]);
      if (score >= threshold) {
        scored.add((label: tagMap[prompts[i]]!, score: score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored
        .take(math.min(topK, scored.length))
        .map((e) => e.label)
        .toList(growable: false);
  }

  /// Variant of [matchTagsForImage] that returns scored entries, useful when
  /// you need the similarity values (e.g. for confidence display or filtering).
  Future<List<({String label, double score})>> scoreTagsForImage({
    required List<double> imageVector,
    required Map<String, String> tagMap,
    int topK = 5,
    double threshold = 0.0,
  }) async {
    if (tagMap.isEmpty) return const [];

    final prompts = tagMap.keys.toList(growable: false);
    final textVectors = await Future.wait(prompts.map(embedText));

    final scored = <({String label, double score})>[];
    for (var i = 0; i < prompts.length; i++) {
      final score = calculateSimilarity(imageVector, textVectors[i]);
      if (score >= threshold) {
        scored.add((label: tagMap[prompts[i]]!, score: score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(math.min(topK, scored.length)).toList(growable: false);
  }

  /// Pre-warms the text vector cache for every prompt in [tagMap].
  ///
  /// Call this once after [warmUp] with your full tag vocabulary to ensure that
  /// the first batch of image analysis has all prompts ready in cache.
  Future<void> preCacheTagMap(Map<String, String> tagMap) async {
    await Future.wait(tagMap.keys.map(embedText));
  }
}
