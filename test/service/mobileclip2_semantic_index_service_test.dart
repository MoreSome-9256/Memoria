import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/mobileclip2_semantic_index_service.dart';

void main() {
  group('MobileClip2VectorMath', () {
    test('normalizes vectors and uses dot product cosine scores', () {
      final normalized = MobileClip2VectorMath.l2Normalize(_v(3, 4));

      expect(normalized[0], closeTo(0.6, 1e-6));
      expect(normalized[1], closeTo(0.8, 1e-6));
      expect(
        MobileClip2VectorMath.dot(normalized, _v(0, 1)),
        closeTo(0.8, 1e-6),
      );
    });

    test('meanPool normalizes again after averaging', () {
      final pooled = MobileClip2VectorMath.meanPool(<Float32List>[
        _v(1, 0),
        _v(0, 1),
      ]);

      expect(pooled[0], closeTo(0.70710678, 1e-6));
      expect(pooled[1], closeTo(0.70710678, 1e-6));
    });

    test('topKMean averages the highest scores only', () {
      expect(
        MobileClip2VectorMath.topKMean(<double>[0.1, 0.8, 0.6], 2),
        closeTo(0.7, 1e-6),
      );
      expect(MobileClip2VectorMath.topKMean(const <double>[], 3), -1);
    });
  });

  group('MobileClip2SemanticIndex', () {
    test(
      'deduplicates adjacent video frames and mean-pools kept frames',
      () async {
        final index = MobileClip2SemanticIndex(
          encoder: _FakeEncoder(
            imageEmbeddings: <int, Float32List>{
              1: _v(1, 0),
              2: _v(0.999, 0.01),
              3: _v(0, 1),
            },
          ),
          frameExtractor: _FakeFrameExtractor(<SampledFrame>[
            _frame(0, 1),
            _frame(1, 2),
            _frame(2, 3),
          ]),
        );

        final record = await index.buildVideoEmbedding('video.mov');

        expect(record.frameEmbeddings, hasLength(2));
        expect(record.frameEmbeddings.map((frame) => frame.timestampSeconds), [
          0.0,
          2.0,
        ]);
        expect(record.mediaEmbedding[0], closeTo(0.70710678, 1e-6));
        expect(record.mediaEmbedding[1], closeTo(0.70710678, 1e-6));
      },
    );

    test('reranks frame-based media and returns best timestamp', () {
      final index = MobileClip2SemanticIndex(
        encoder: _FakeEncoder(
          textEmbeddings: <String, Float32List>{'red dress': _v(1, 0)},
        ),
      );
      index.upsertRecord(
        _record(
          id: 'image',
          mediaType: SemanticMediaType.image,
          mediaEmbedding: _v(0.65, 0.76),
          frames: <FrameVectorRecord>[
            FrameVectorRecord(timestampSeconds: 0, embedding: _v(0.65, 0.76)),
          ],
        ),
      );
      index.upsertRecord(
        _record(
          id: 'video',
          mediaType: SemanticMediaType.video,
          mediaEmbedding: _v(0.6, 0.8),
          frames: <FrameVectorRecord>[
            FrameVectorRecord(timestampSeconds: 1, embedding: _v(0, 1)),
            FrameVectorRecord(timestampSeconds: 4, embedding: _v(1, 0)),
            FrameVectorRecord(timestampSeconds: 8, embedding: _v(0.8, 0.6)),
          ],
        ),
      );

      final results = index.searchByEmbedding(_v(1, 0), topK: 2);

      expect(results.first.mediaId, 'video');
      expect(results.first.bestTimestampSeconds, 4);
      expect(results.first.maxFrameScore, closeTo(1, 1e-6));
      expect(results.first.topKFrameScore, closeTo(0.6, 1e-6));
      expect(results.first.score, closeTo(0.7, 1e-6));
    });
  });

  group('chooseFrameCount', () {
    test('keeps the first version sampling limits small and predictable', () {
      expect(chooseFrameCount(0), 1);
      expect(chooseFrameCount(8), 4);
      expect(chooseFrameCount(40), 10);
      expect(chooseFrameCount(180), 16);
    });
  });
}

Float32List _v(double x, double y) {
  return MobileClip2VectorMath.l2Normalize(
    Float32List.fromList(<double>[x, y]),
  );
}

SampledFrame _frame(double timestampSeconds, int imageId) {
  return SampledFrame(
    timestampSeconds: timestampSeconds,
    imageBytes: Uint8List.fromList(<int>[imageId]),
  );
}

MediaVectorRecord _record({
  required String id,
  required SemanticMediaType mediaType,
  required Float32List mediaEmbedding,
  required List<FrameVectorRecord> frames,
}) {
  return MediaVectorRecord(
    mediaId: id,
    mediaType: mediaType,
    mediaEmbedding: mediaEmbedding,
    frameEmbeddings: frames,
    width: 100,
    height: 100,
    createdAt: DateTime(2026),
  );
}

class _FakeEncoder implements MobileClip2SemanticEncoder {
  const _FakeEncoder({
    this.imageEmbeddings = const <int, Float32List>{},
    this.textEmbeddings = const <String, Float32List>{},
  });

  final Map<int, Float32List> imageEmbeddings;
  final Map<String, Float32List> textEmbeddings;

  @override
  Future<Float32List> encodeImageEmbedding(Uint8List imageBytes) async {
    return imageEmbeddings[imageBytes.first] ?? _v(1, 0);
  }

  @override
  Future<Float32List> encodeTextEmbedding(String query) async {
    return textEmbeddings[query] ?? _v(1, 0);
  }
}

class _FakeFrameExtractor implements MobileClip2FrameExtractor {
  const _FakeFrameExtractor(this.frames);

  final List<SampledFrame> frames;

  @override
  Future<ExtractedMediaFrames> extractFrames(
    String mediaUri, {
    required int maxFrames,
  }) async {
    return ExtractedMediaFrames(
      frames: frames.take(maxFrames).toList(),
      width: 1920,
      height: 1080,
      durationSeconds: 9,
    );
  }
}
