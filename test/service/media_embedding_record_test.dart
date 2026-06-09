import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/media_analysis_image_reader.dart';
import 'package:photo_album/service/media_embedding_service.dart';
import 'package:photo_album/storage/vector_index/vector_index_constants.dart';
import 'package:photo_album/utils/media_type_helper.dart';

void main() {
  group('MediaEmbeddingRecord', () {
    test('keeps video model family and frame diagnostics', () {
      const diagnostics = MediaFrameExtractionDiagnostics(
        frameCount: 2,
        frameSource: 'ffmpeg_fps_sample',
        frameTimestampsUs: <int>[],
        isRepeatedFrame: false,
      );
      const result = MediaEmbeddingResult(
        kind: MemoriaMediaKind.video,
        embedding: <double>[0.1, 0.2, 0.3],
        modelVersion: kMobileClip2S2EmbeddingModelVersion,
        modelFamily: kPhotoEmbeddingModelFamily,
        modelLabel: 'MobileCLIP2 S2 frame mean-pool',
        textSpace: MediaEmbeddingTextSpace.mobileClip2Text,
        preprocessMs: 1,
        inferenceMs: 2,
        isSameSpaceAsMobileClipText: true,
        frameDiagnostics: diagnostics,
      );

      final record = result.toRecord();

      expect(record.isVideoModel, isTrue);
      expect(record.isPhotoModel, isTrue);
      expect(record.mediaKind, MemoriaMediaKind.video);
      expect(record.frameSource, 'ffmpeg_fps_sample');
      expect(record.frameCount, 2);
      expect(record.frameTimestampsUs, <int>[]);
      expect(record.isRepeatedFrame, isFalse);

      final meta = jsonDecode(record.toMetaJson()) as Map<String, Object?>;
      expect(meta['mediaKind'], 'video');
      expect(meta['modelFamily'], kPhotoEmbeddingModelFamily);
      expect(meta['textSpace'], MediaEmbeddingTextSpace.mobileClip2Text);
      expect(meta['frameSource'], 'ffmpeg_fps_sample');
      expect(meta['frameCount'], 2);
      expect(meta['isRepeatedFrame'], isFalse);
      expect(meta.containsKey('frameTimestampsUs'), isFalse);
    });

    test('marks repeated thumbnail fallback distinctly', () {
      const diagnostics = MediaFrameExtractionDiagnostics(
        frameCount: MediaAnalysisImageReader.defaultFrameCount,
        frameSource: 'fallback_thumbnail_repeat',
        frameTimestampsUs: <int>[],
        isRepeatedFrame: true,
      );
      const result = MediaEmbeddingResult(
        kind: MemoriaMediaKind.video,
        embedding: <double>[1, 0],
        modelVersion: kMobileClip2S2EmbeddingModelVersion,
        modelFamily: kPhotoEmbeddingModelFamily,
        modelLabel: 'MobileCLIP2 S2 frame mean-pool',
        textSpace: MediaEmbeddingTextSpace.mobileClip2Text,
        preprocessMs: 0,
        inferenceMs: 0,
        isSameSpaceAsMobileClipText: true,
        frameDiagnostics: diagnostics,
      );

      final livePhotoResult = result.copyWith(
        kind: MemoriaMediaKind.dynamicImage,
      );
      final record = livePhotoResult.toRecord();

      expect(record.mediaKind, MemoriaMediaKind.dynamicImage);
      expect(record.modelFamily, kPhotoEmbeddingModelFamily);
      expect(record.frameSource, 'fallback_thumbnail_repeat');
      expect(record.isRepeatedFrame, isTrue);
    });

    test('decodes partial or malformed meta with stable defaults', () {
      final missing = MediaEmbeddingMeta.fromJsonString(null);
      expect(missing.mediaKind, 'unknown');
      expect(missing.frameSource, 'unknown');
      expect(missing.frameCount, 0);
      expect(missing.isRepeatedFrame, isFalse);

      final invalid = MediaEmbeddingMeta.fromJsonString(
        '{not json',
        fallbackModelVersion: kMobileClip2S2EmbeddingModelVersion,
      );
      expect(invalid.isPhotoModel, isTrue);
      expect(invalid.frameSource, 'unknown');

      final oldVersionOnly = MediaEmbeddingMeta.fromJsonString(
        jsonEncode(<String, Object?>{
          'modelVersion': kMobileClip2S2EmbeddingModelVersion,
        }),
      );
      expect(oldVersionOnly.isPhotoModel, isTrue);
      expect(oldVersionOnly.textSpace, MediaEmbeddingTextSpace.none);
      expect(oldVersionOnly.isRepeatedFrame, isFalse);

      final partial = MediaEmbeddingMeta.fromJsonString(
        jsonEncode(<String, Object?>{
          'mediaKind': 'video',
          'modelFamily': kPhotoEmbeddingModelFamily,
          'frameCount': 3,
        }),
      );
      expect(partial.mediaKind, 'video');
      expect(partial.isVideoModel, isTrue);
      expect(partial.frameSource, 'unknown');
      expect(partial.frameCount, 3);
    });
  });
}
