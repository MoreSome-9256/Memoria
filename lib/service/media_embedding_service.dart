import 'dart:convert';
import 'dart:typed_data';

import '../storage/vector_index/vector_index_constants.dart';
import '../utils/media_type_helper.dart';
import 'app_ai_settings_service.dart';
import 'clip_tokenizer_service.dart';
import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_litert_service.dart';
import 'mobileclip2_semantic_index_service.dart';
import 'media_analysis_image_reader.dart';
import 'media_thumbnail_cache_service.dart';
import 'semantic_matching_service.dart';

class MediaEmbeddingTextSpace {
  const MediaEmbeddingTextSpace._();

  static const String mobileClip2Text = 'mobileclip2_text';
  static const String none = 'none';
}

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
    if (!MediaThumbnailCacheService.isSupportedImageBytes(bytes)) {
      throw ArgumentError('bytes is not a supported encoded image');
    }
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
      modelFamily: kPhotoEmbeddingModelFamily,
      modelLabel:
          'MobileCLIP2 LiteRT (${effectiveLiteRt.executionProviderLabel})',
      textSpace: MediaEmbeddingTextSpace.mobileClip2Text,
      preprocessMs: profile.decodeMs + profile.resizeNormalizeMs,
      inferenceMs: profile.inferenceMs,
      isSameSpaceAsMobileClipText: true,
      frameDiagnostics: MediaFrameExtractionDiagnostics.none,
    );
  }

  Future<MediaEmbeddingResult> embedVideoFrameBytes(
    List<Uint8List> frameBytes, {
    MemoriaMediaKind kind = MemoriaMediaKind.video,
    MobileClipLiteRtService? liteRt,
    MediaFrameExtractionDiagnostics? frameDiagnostics,
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
      if (!MediaThumbnailCacheService.isSupportedImageBytes(bytes)) {
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
      modelFamily: kPhotoEmbeddingModelFamily,
      modelLabel:
          'MobileCLIP2 S2 frame mean-pool (${effectiveLiteRt.executionProviderLabel})',
      textSpace: MediaEmbeddingTextSpace.mobileClip2Text,
      preprocessMs: preprocessMs,
      inferenceMs: inferenceMs,
      isSameSpaceAsMobileClipText: true,
      frameDiagnostics:
          frameDiagnostics ??
          MediaFrameExtractionDiagnostics(
            frameCount: frameBytes.length,
            frameSource: 'unknown_video_frames',
            frameTimestampsUs: const <int>[],
            isRepeatedFrame: frameBytes.length <= 1,
          ),
    );
  }

  Future<MediaEmbeddingResult> embedPreparedMediaBytes({
    required MemoriaMediaKind kind,
    required Uint8List imageOrThumbnailBytes,
    required MobileClipBackend backend,
    required MobileClipLiteRtService liteRt,
    List<Uint8List> frameBytes = const <Uint8List>[],
    MediaFrameExtractionDiagnostics? frameDiagnostics,
  }) async {
    final shouldUseVideoEncoder =
        kind == MemoriaMediaKind.video || kind == MemoriaMediaKind.dynamicImage;
    if (shouldUseVideoEncoder) {
      final result = await embedVideoFrameBytes(
        frameBytes.isEmpty ? <Uint8List>[imageOrThumbnailBytes] : frameBytes,
        kind: kind,
        liteRt: liteRt,
        frameDiagnostics:
            frameDiagnostics ??
            (frameBytes.isEmpty
                ? const MediaFrameExtractionDiagnostics(
                    frameCount: 1,
                    frameSource: 'fallback_thumbnail_repeat',
                    frameTimestampsUs: <int>[],
                    isRepeatedFrame: true,
                  )
                : null),
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
    required this.modelFamily,
    required this.modelLabel,
    required this.textSpace,
    required this.preprocessMs,
    required this.inferenceMs,
    required this.isSameSpaceAsMobileClipText,
    required this.frameDiagnostics,
  });

  final MemoriaMediaKind kind;
  final List<double> embedding;
  final String modelVersion;
  final String modelFamily;
  final String modelLabel;
  final String textSpace;
  final double preprocessMs;
  final double inferenceMs;
  final bool isSameSpaceAsMobileClipText;
  final MediaFrameExtractionDiagnostics frameDiagnostics;

  MediaEmbeddingRecord toRecord() {
    return MediaEmbeddingRecord(
      vector: embedding,
      modelVersion: modelVersion,
      modelFamily: modelFamily,
      mediaKind: kind,
      textSpace: textSpace,
      frameSource: frameDiagnostics.frameSource,
      frameCount: frameDiagnostics.frameCount,
      frameTimestampsUs: frameDiagnostics.frameTimestampsUs,
      isRepeatedFrame: frameDiagnostics.isRepeatedFrame,
    );
  }

  MediaEmbeddingResult copyWith({
    MemoriaMediaKind? kind,
    MediaFrameExtractionDiagnostics? frameDiagnostics,
  }) {
    return MediaEmbeddingResult(
      kind: kind ?? this.kind,
      embedding: embedding,
      modelVersion: modelVersion,
      modelFamily: modelFamily,
      modelLabel: modelLabel,
      textSpace: textSpace,
      preprocessMs: preprocessMs,
      inferenceMs: inferenceMs,
      isSameSpaceAsMobileClipText: isSameSpaceAsMobileClipText,
      frameDiagnostics: frameDiagnostics ?? this.frameDiagnostics,
    );
  }
}

class MediaEmbeddingRecord {
  const MediaEmbeddingRecord({
    required this.vector,
    required this.modelVersion,
    required this.modelFamily,
    required this.mediaKind,
    required this.textSpace,
    required this.frameSource,
    required this.frameCount,
    required this.frameTimestampsUs,
    required this.isRepeatedFrame,
  });

  final List<double> vector;
  final String modelVersion;
  final String modelFamily;
  final MemoriaMediaKind mediaKind;
  final String textSpace;
  final String frameSource;
  final int frameCount;
  final List<int> frameTimestampsUs;
  final bool isRepeatedFrame;

  bool get isPhotoModel => modelFamily == kPhotoEmbeddingModelFamily;
  bool get isVideoModel =>
      mediaKind == MemoriaMediaKind.video ||
      mediaKind == MemoriaMediaKind.dynamicImage ||
      isVideoEmbeddingModelVersion(modelVersion);

  Map<String, Object?> toJson() => <String, Object?>{
    'modelVersion': modelVersion,
    'modelFamily': modelFamily,
    'mediaKind': mediaKind.name,
    'textSpace': textSpace,
    'frameSource': frameSource,
    'frameCount': frameCount,
    'frameTimestampsUs': frameTimestampsUs,
    'isRepeatedFrame': isRepeatedFrame,
    'dimension': vector.length,
  };

  Map<String, Object?> toMetaJsonMap() => <String, Object?>{
    'modelVersion': modelVersion,
    'modelFamily': modelFamily,
    'mediaKind': mediaKind.name,
    'textSpace': textSpace,
    'frameSource': frameSource,
    'frameCount': frameCount,
    'isRepeatedFrame': isRepeatedFrame,
  };

  String toMetaJson() => jsonEncode(toMetaJsonMap());
}

class MediaEmbeddingMeta {
  const MediaEmbeddingMeta({
    this.modelVersion = '',
    this.modelFamily = '',
    this.mediaKind = 'unknown',
    this.textSpace = MediaEmbeddingTextSpace.none,
    this.frameSource = 'unknown',
    this.frameCount = 0,
    this.isRepeatedFrame = false,
  });

  final String modelVersion;
  final String modelFamily;
  final String mediaKind;
  final String textSpace;
  final String frameSource;
  final int frameCount;
  final bool isRepeatedFrame;

  bool get isVideoModel =>
      mediaKind == MemoriaMediaKind.video.name ||
      mediaKind == MemoriaMediaKind.dynamicImage.name ||
      isVideoEmbeddingModelVersion(modelVersion);

  bool get isPhotoModel =>
      modelFamily == kPhotoEmbeddingModelFamily ||
      isPhotoEmbeddingModelVersion(modelVersion);

  static MediaEmbeddingMeta fromJsonString(
    String? raw, {
    String fallbackModelVersion = '',
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return MediaEmbeddingMeta(modelVersion: fallbackModelVersion);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return fromJsonMap(decoded, fallbackModelVersion: fallbackModelVersion);
      }
    } catch (_) {}
    return MediaEmbeddingMeta(modelVersion: fallbackModelVersion);
  }

  static MediaEmbeddingMeta fromJsonMap(
    Map<String, Object?> json, {
    String fallbackModelVersion = '',
  }) {
    final modelVersion =
        (json['modelVersion'] as String?)?.trim() ?? fallbackModelVersion;
    return MediaEmbeddingMeta(
      modelVersion: modelVersion.isEmpty ? fallbackModelVersion : modelVersion,
      modelFamily: (json['modelFamily'] as String?)?.trim() ?? '',
      mediaKind: (json['mediaKind'] as String?)?.trim().isNotEmpty == true
          ? (json['mediaKind'] as String).trim()
          : 'unknown',
      textSpace: (json['textSpace'] as String?)?.trim().isNotEmpty == true
          ? (json['textSpace'] as String).trim()
          : MediaEmbeddingTextSpace.none,
      frameSource: (json['frameSource'] as String?)?.trim().isNotEmpty == true
          ? (json['frameSource'] as String).trim()
          : 'unknown',
      frameCount: (json['frameCount'] as num?)?.toInt() ?? 0,
      isRepeatedFrame: (json['isRepeatedFrame'] as bool?) ?? false,
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
