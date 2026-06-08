import 'dart:typed_data';

import '../storage/vector_index/vector_index_constants.dart';
import '../utils/media_type_helper.dart';
import 'app_ai_settings_service.dart';
import 'clip_tokenizer_service.dart';
import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_litert_service.dart';
import 'mobileclip2_semantic_index_service.dart';
import 'semantic_matching_service.dart';

class MediaEmbeddingService {
  MediaEmbeddingService._internal();

  static final MediaEmbeddingService _instance =
      MediaEmbeddingService._internal();

  factory MediaEmbeddingService() => _instance;

  final SemanticMatchingService _semanticService = SemanticMatchingService();
  final ClipTokenizerService _tokenizer = ClipTokenizerService();

  Future<MediaEmbeddingResult> embedImageBytes(
    Uint8List bytes, {
    MobileClipBackend? backend,
    MobileClipLiteRtService? liteRt,
  }) async {
    final effectiveBackend =
        backend ??
        await MobileClipBackendPreferenceService().getSelectedBackend();
    final settings = await AppAiSettingsService.instance.load();
    final effectiveLiteRt =
        liteRt ??
        MobileClipLiteRtService.withRuntimeOptions(
          accelerator: settings.inferenceAccelerator,
          xnnpackThreadCount: settings.xnnpackThreadCount,
          modelBatchSize: settings.analysisBatchSize,
        );
    final profile = await effectiveLiteRt.profileImageBytes(bytes);
    return MediaEmbeddingResult(
      kind: MemoriaMediaKind.image,
      embedding: profile.embedding,
      modelVersion: buildPhotoEmbeddingModelVersion(effectiveBackend),
      modelLabel:
          'MobileCLIP2 LiteRT (${effectiveLiteRt.executionProviderLabel})',
      preprocessMs: profile.decodeMs + profile.resizeNormalizeMs,
      inferenceMs: profile.inferenceMs,
      isSameSpaceAsMobileClipText: true,
    );
  }

  Future<MediaEmbeddingResult> embedVideoFrameBytes(
    List<Uint8List> frameBytes, {
    MemoriaMediaKind kind = MemoriaMediaKind.video,
    MobileClipLiteRtService? liteRt,
  }) async {
    if (frameBytes.isEmpty) {
      throw ArgumentError('frameBytes is empty');
    }
    final settings = await AppAiSettingsService.instance.load();
    final effectiveLiteRt =
        liteRt ??
        MobileClipLiteRtService.withRuntimeOptions(
          accelerator: settings.inferenceAccelerator,
          xnnpackThreadCount: settings.xnnpackThreadCount,
          modelBatchSize: settings.analysisBatchSize,
        );
    final kept = <Float32List>[];
    var preprocessMs = 0.0;
    var inferenceMs = 0.0;
    for (final bytes in frameBytes) {
      if (bytes.isEmpty) {
        continue;
      }
      final profile = await effectiveLiteRt.profileImageBytes(bytes);
      final vector = Float32List.fromList(profile.embedding);
      if (kept.isEmpty ||
          MobileClip2VectorMath.dot(vector, kept.last) < frameDedupThreshold) {
        kept.add(vector);
      }
      preprocessMs += profile.decodeMs + profile.resizeNormalizeMs;
      inferenceMs += profile.inferenceMs;
    }
    if (kept.isEmpty) {
      throw StateError('no usable MobileCLIP2 frame embeddings');
    }
    final embedding = MobileClip2VectorMath.meanPool(
      kept,
    ).toList(growable: false);
    return MediaEmbeddingResult(
      kind: kind,
      embedding: embedding,
      modelVersion: buildPhotoEmbeddingModelVersion(),
      modelLabel:
          'MobileCLIP2 S2 frame mean-pool (${effectiveLiteRt.executionProviderLabel})',
      preprocessMs: preprocessMs,
      inferenceMs: inferenceMs,
      isSameSpaceAsMobileClipText: true,
    );
  }

  Future<MediaEmbeddingResult> embedPreparedMediaBytes({
    required MemoriaMediaKind kind,
    required Uint8List imageOrThumbnailBytes,
    required MobileClipBackend backend,
    required MobileClipLiteRtService liteRt,
    List<Uint8List> frameBytes = const <Uint8List>[],
  }) async {
    final shouldUseVideoEncoder =
        kind == MemoriaMediaKind.video || kind == MemoriaMediaKind.dynamicImage;
    if (shouldUseVideoEncoder) {
      final result = await embedVideoFrameBytes(
        frameBytes.isEmpty ? <Uint8List>[imageOrThumbnailBytes] : frameBytes,
        kind: kind,
        liteRt: liteRt,
      );
      return result;
    }
    final result = await embedImageBytes(
      imageOrThumbnailBytes,
      backend: backend,
      liteRt: liteRt,
    );
    return kind == MemoriaMediaKind.image
        ? result
        : result.copyWith(kind: kind);
  }

  Future<MediaTextSimilarityResult> compareWithText({
    required MediaEmbeddingResult media,
    required String text,
    MobileClipLiteRtService? liteRt,
  }) async {
    final textVector = liteRt == null
        ? await _semanticService.embedText(text)
        : await liteRt.embedTextTokens(await _tokenizer.tokenize(text));
    return MediaTextSimilarityResult(
      text: text,
      textVector: textVector,
      score: _semanticService.calculateSimilarity(media.embedding, textVector),
      isSameEmbeddingSpace: media.isSameSpaceAsMobileClipText,
      unavailableReason: null,
    );
  }
}

class MediaEmbeddingResult {
  const MediaEmbeddingResult({
    required this.kind,
    required this.embedding,
    required this.modelVersion,
    required this.modelLabel,
    required this.preprocessMs,
    required this.inferenceMs,
    required this.isSameSpaceAsMobileClipText,
  });

  final MemoriaMediaKind kind;
  final List<double> embedding;
  final String modelVersion;
  final String modelLabel;
  final double preprocessMs;
  final double inferenceMs;
  final bool isSameSpaceAsMobileClipText;

  MediaEmbeddingResult copyWith({MemoriaMediaKind? kind}) {
    return MediaEmbeddingResult(
      kind: kind ?? this.kind,
      embedding: embedding,
      modelVersion: modelVersion,
      modelLabel: modelLabel,
      preprocessMs: preprocessMs,
      inferenceMs: inferenceMs,
      isSameSpaceAsMobileClipText: isSameSpaceAsMobileClipText,
    );
  }
}

class MediaTextSimilarityResult {
  const MediaTextSimilarityResult({
    required this.text,
    required this.textVector,
    required this.score,
    required this.isSameEmbeddingSpace,
    this.unavailableReason,
  });

  const MediaTextSimilarityResult.unavailable({
    required this.text,
    required String reason,
  }) : textVector = const <double>[],
       score = 0,
       isSameEmbeddingSpace = false,
       unavailableReason = reason;

  final String text;
  final List<double> textVector;
  final double score;
  final bool isSameEmbeddingSpace;
  final String? unavailableReason;

  bool get isAvailable => unavailableReason == null;
}
