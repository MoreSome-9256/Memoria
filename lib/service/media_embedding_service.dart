import 'dart:typed_data';

import '../storage/vector_index/vector_index_constants.dart';
import '../utils/media_type_helper.dart';
import 'app_ai_settings_service.dart';
import 'clip_tokenizer_service.dart';
import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_litert_service.dart';
import 'mobileviclip_video_service.dart';
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
    switch (effectiveBackend) {
      case MobileClipBackend.mobileclip2LiteRt:
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
  }

  Future<MediaEmbeddingResult> embedVideoFrameBytes(
    List<Uint8List> frameBytes,
  ) async {
    final profile = await MobileViClipVideoService().profileFrameBytes(
      frameBytes,
    );
    return MediaEmbeddingResult(
      kind: MemoriaMediaKind.video,
      embedding: profile.embedding,
      modelVersion: MobileViClipVideoService.modelVersion,
      modelLabel: 'MobileViCLIP Small',
      preprocessMs: profile.preprocessMs,
      inferenceMs: profile.inferenceMs,
      isSameSpaceAsMobileClipText: false,
    );
  }

  Future<MediaEmbeddingResult> embedPreparedMediaBytes({
    required MemoriaMediaKind kind,
    required Uint8List imageOrThumbnailBytes,
    required bool mobileViClipEnabled,
    required MobileClipBackend backend,
    required MobileClipLiteRtService liteRt,
  }) async {
    final shouldUseVideoEncoder =
        (kind == MemoriaMediaKind.video ||
            kind == MemoriaMediaKind.dynamicImage) &&
        mobileViClipEnabled;
    if (shouldUseVideoEncoder) {
      final result = await embedVideoFrameBytes(
        List<Uint8List>.filled(
          MobileViClipVideoService.frameCount,
          imageOrThumbnailBytes,
          growable: false,
        ),
      );
      return result.copyWith(kind: kind);
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
    if (media.modelVersion == MobileViClipVideoService.modelVersion) {
      return MediaTextSimilarityResult.unavailable(
        text: text,
        reason: 'MobileViCLIP 视频向量不与 MobileCLIP 文本向量共空间。',
      );
    }
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
