import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/media_type_helper.dart';
import 'clip_tokenizer_service.dart';
import 'mobileclip_litert_service.dart';

const int defaultVideoMaxFrames = 16;
const int defaultGifMaxFrames = 8;
const int defaultLivePhotoMotionFrames = 4;

const double frameDedupThreshold = 0.98;

const int defaultCandidateK = 200;
const int defaultTopK = 100;

const double videoTopKFrameWeight = 0.50;
const double videoMaxFrameWeight = 0.25;
const double videoMediaWeight = 0.25;
const int frameScoreTopK = 3;

enum SemanticMediaType { image, video, gif, livePhoto }

class MediaVectorRecord {
  const MediaVectorRecord({
    required this.mediaId,
    required this.mediaType,
    required this.mediaEmbedding,
    required this.frameEmbeddings,
    required this.width,
    required this.height,
    required this.createdAt,
    this.durationSeconds,
    this.albumName,
    this.localPathOrUri,
  });

  final String mediaId;
  final SemanticMediaType mediaType;
  final Float32List mediaEmbedding;
  final List<FrameVectorRecord> frameEmbeddings;
  final int width;
  final int height;
  final double? durationSeconds;
  final DateTime createdAt;
  final String? albumName;
  final String? localPathOrUri;
}

class FrameVectorRecord {
  const FrameVectorRecord({
    required this.timestampSeconds,
    required this.embedding,
  });

  final double timestampSeconds;
  final Float32List embedding;
}

class MobileClip2SearchResult {
  const MobileClip2SearchResult({
    required this.mediaId,
    required this.mediaType,
    required this.score,
    required this.mediaScore,
    this.maxFrameScore,
    this.topKFrameScore,
    this.bestTimestampSeconds,
  });

  final String mediaId;
  final SemanticMediaType mediaType;
  final double score;
  final double mediaScore;
  final double? maxFrameScore;
  final double? topKFrameScore;
  final double? bestTimestampSeconds;
}

class SampledFrame {
  const SampledFrame({
    required this.timestampSeconds,
    required this.imageBytes,
  });

  final double timestampSeconds;
  final Uint8List imageBytes;
}

abstract class MobileClip2SemanticEncoder {
  Future<Float32List> encodeImageEmbedding(Uint8List imageBytes);

  Future<Float32List> encodeTextEmbedding(String query);
}

abstract class MobileClip2FrameExtractor {
  Future<ExtractedMediaFrames> extractFrames(
    String mediaUri, {
    required int maxFrames,
  });
}

class ExtractedMediaFrames {
  const ExtractedMediaFrames({
    required this.frames,
    this.width = 0,
    this.height = 0,
    this.durationSeconds,
  });

  final List<SampledFrame> frames;
  final int width;
  final int height;
  final double? durationSeconds;
}

class LiteRtMobileClip2SemanticEncoder implements MobileClip2SemanticEncoder {
  LiteRtMobileClip2SemanticEncoder({
    MobileClipLiteRtService? liteRtService,
    ClipTokenizerService? tokenizer,
  }) : _liteRtService = liteRtService ?? MobileClipLiteRtService(),
       _tokenizer = tokenizer ?? ClipTokenizerService();

  final MobileClipLiteRtService _liteRtService;
  final ClipTokenizerService _tokenizer;

  @override
  Future<Float32List> encodeImageEmbedding(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError('imageBytes is empty');
    }
    final raw = await _liteRtService.embedImageBytes(imageBytes);
    return MobileClip2VectorMath.l2Normalize(Float32List.fromList(raw));
  }

  @override
  Future<Float32List> encodeTextEmbedding(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      throw ArgumentError('query is empty');
    }
    final tokens = await _tokenizer.tokenize(normalizedQuery);
    final raw = await _liteRtService.embedTextTokens(tokens);
    return MobileClip2VectorMath.l2Normalize(Float32List.fromList(raw));
  }
}

class FfmpegMobileClip2FrameExtractor implements MobileClip2FrameExtractor {
  const FfmpegMobileClip2FrameExtractor();

  @override
  Future<ExtractedMediaFrames> extractFrames(
    String mediaUri, {
    required int maxFrames,
  }) async {
    final path = _filePathFromUri(mediaUri);
    final file = File(path);
    if (!file.existsSync()) {
      throw ArgumentError('media file does not exist: $mediaUri');
    }

    final info = await _probe(path);
    final targetFrameCount = _targetFrameCount(
      durationSeconds: info.durationSeconds,
      maxFrames: maxFrames,
    );
    final tempDir = await getTemporaryDirectory();
    final runId = DateTime.now().microsecondsSinceEpoch;
    final frameDir = Directory(
      p.join(tempDir.path, 'memoria_mobileclip2_frames_$runId'),
    );
    await frameDir.create(recursive: true);

    try {
      final pattern = p.join(frameDir.path, 'frame_%03d.jpg');
      final vf = _buildFrameFilter(
        durationSeconds: info.durationSeconds,
        frameCount: targetFrameCount,
      );
      final command =
          '-y -i ${_quote(path)} -vf ${_quote(vf)} -vsync 0 '
          '-frames:v $targetFrameCount ${_quote(pattern)}';
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw StateError('FFmpeg frame extraction failed: $logs');
      }

      final files = await frameDir
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      files.sort((a, b) => a.path.compareTo(b.path));
      final frames = <SampledFrame>[];
      for (var i = 0; i < files.length; i++) {
        frames.add(
          SampledFrame(
            timestampSeconds: _timestampForIndex(
              index: i,
              frameCount: files.length,
              durationSeconds: info.durationSeconds,
            ),
            imageBytes: await files[i].readAsBytes(),
          ),
        );
      }
      if (frames.isEmpty) {
        throw StateError('no frames extracted from media: $mediaUri');
      }
      return ExtractedMediaFrames(
        frames: frames,
        width: info.width,
        height: info.height,
        durationSeconds: info.durationSeconds,
      );
    } finally {
      try {
        await frameDir.delete(recursive: true);
      } catch (error) {
        debugPrint('Failed to clean MobileCLIP2 frame temp dir: $error');
      }
    }
  }

  Future<_MediaProbeInfo> _probe(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    final videoStream = info?.getStreams().where((stream) {
      return stream.getType() == 'video';
    }).firstOrNull;
    return _MediaProbeInfo(
      width: videoStream?.getWidth() ?? 0,
      height: videoStream?.getHeight() ?? 0,
      durationSeconds: _parsePositiveDouble(info?.getDuration()),
    );
  }

  int _targetFrameCount({
    required double? durationSeconds,
    required int maxFrames,
  }) {
    final cappedMax = math.max(1, maxFrames);
    final chosen = chooseFrameCount(durationSeconds ?? 0);
    return math.min(cappedMax, chosen);
  }

  String _buildFrameFilter({
    required double? durationSeconds,
    required int frameCount,
  }) {
    final duration = durationSeconds;
    if (duration == null || duration <= 0 || frameCount <= 1) {
      return 'fps=1,scale=512:-1';
    }
    final fps = frameCount / duration;
    return 'fps=$fps,scale=512:-1';
  }

  double _timestampForIndex({
    required int index,
    required int frameCount,
    required double? durationSeconds,
  }) {
    final duration = durationSeconds;
    if (duration == null || duration <= 0 || frameCount <= 1) {
      return index.toDouble();
    }
    return duration * (index + 0.5) / frameCount;
  }

  static double? _parsePositiveDouble(String? value) {
    final parsed = double.tryParse(value ?? '');
    if (parsed == null || parsed <= 0 || parsed.isNaN || parsed.isInfinite) {
      return null;
    }
    return parsed;
  }

  static String _filePathFromUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed != null && parsed.scheme == 'file') {
      return parsed.toFilePath();
    }
    return uri;
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}

class MobileClip2SemanticIndex {
  MobileClip2SemanticIndex({
    MobileClip2SemanticEncoder? encoder,
    MobileClip2FrameExtractor? frameExtractor,
    Iterable<MediaVectorRecord> initialRecords = const <MediaVectorRecord>[],
  }) : _encoder = encoder ?? LiteRtMobileClip2SemanticEncoder(),
       _frameExtractor =
           frameExtractor ?? const FfmpegMobileClip2FrameExtractor() {
    for (final record in initialRecords) {
      upsertRecord(record);
    }
  }

  final MobileClip2SemanticEncoder _encoder;
  final MobileClip2FrameExtractor _frameExtractor;
  final Map<String, MediaVectorRecord> _recordsById =
      <String, MediaVectorRecord>{};

  List<MediaVectorRecord> get records =>
      List<MediaVectorRecord>.unmodifiable(_recordsById.values);

  void clear() => _recordsById.clear();

  void upsertRecord(MediaVectorRecord record) {
    _validateRecord(record);
    _recordsById[record.mediaId] = record;
  }

  Future<MediaVectorRecord> buildImageEmbedding(String imageUri) async {
    final path = _filePathFromUri(imageUri);
    final file = File(path);
    if (!file.existsSync()) {
      throw ArgumentError('image file does not exist: $imageUri');
    }
    final bytes = await file.readAsBytes();
    final embedding = await _encoder.encodeImageEmbedding(bytes);
    final record = MediaVectorRecord(
      mediaId: imageUri,
      mediaType: SemanticMediaType.image,
      mediaEmbedding: embedding,
      frameEmbeddings: <FrameVectorRecord>[
        FrameVectorRecord(timestampSeconds: 0, embedding: embedding),
      ],
      width: 0,
      height: 0,
      createdAt: await _createdAt(file),
      localPathOrUri: imageUri,
    );
    upsertRecord(record);
    return record;
  }

  Future<MediaVectorRecord> buildVideoEmbedding(
    String videoUri, {
    int maxFrames = defaultVideoMaxFrames,
  }) {
    return _buildFrameBasedMediaEmbedding(
      mediaUri: videoUri,
      mediaType: SemanticMediaType.video,
      maxFrames: maxFrames,
    );
  }

  Future<MediaVectorRecord> buildGifEmbedding(
    String gifUri, {
    int maxFrames = defaultGifMaxFrames,
  }) {
    return _buildFrameBasedMediaEmbedding(
      mediaUri: gifUri,
      mediaType: SemanticMediaType.gif,
      maxFrames: maxFrames,
    );
  }

  Future<MediaVectorRecord> buildLivePhotoEmbedding(
    String stillImageUri,
    String motionVideoUri, {
    int maxMotionFrames = defaultLivePhotoMotionFrames,
  }) async {
    final stillPath = _filePathFromUri(stillImageUri);
    final stillFile = File(stillPath);
    if (!stillFile.existsSync()) {
      throw ArgumentError('still image file does not exist: $stillImageUri');
    }
    final stillEmbedding = await _encoder.encodeImageEmbedding(
      await stillFile.readAsBytes(),
    );
    final motion = await _frameExtractor.extractFrames(
      motionVideoUri,
      maxFrames: maxMotionFrames,
    );
    final frames = <FrameVectorRecord>[
      FrameVectorRecord(timestampSeconds: 0, embedding: stillEmbedding),
    ];
    for (final frame in motion.frames) {
      final embedding = await _encoder.encodeImageEmbedding(frame.imageBytes);
      if (MobileClip2VectorMath.dot(embedding, frames.last.embedding) <
          frameDedupThreshold) {
        frames.add(
          FrameVectorRecord(
            timestampSeconds: frame.timestampSeconds,
            embedding: embedding,
          ),
        );
      }
    }
    final record = MediaVectorRecord(
      mediaId: '$stillImageUri#$motionVideoUri',
      mediaType: SemanticMediaType.livePhoto,
      mediaEmbedding: MobileClip2VectorMath.meanPool(
        frames.map((frame) => frame.embedding).toList(growable: false),
      ),
      frameEmbeddings: List<FrameVectorRecord>.unmodifiable(frames),
      width: motion.width,
      height: motion.height,
      durationSeconds: motion.durationSeconds,
      createdAt: await _createdAt(stillFile),
      localPathOrUri: stillImageUri,
    );
    upsertRecord(record);
    return record;
  }

  Future<Float32List> buildTextEmbedding(String query) {
    return _encoder.encodeTextEmbedding(query);
  }

  Future<List<MobileClip2SearchResult>> search(
    String query, {
    int topK = defaultTopK,
    int candidateK = defaultCandidateK,
  }) async {
    if (topK <= 0 || candidateK <= 0 || _recordsById.isEmpty) {
      return const <MobileClip2SearchResult>[];
    }
    final queryEmbedding = await buildTextEmbedding(query);
    return searchByEmbedding(
      queryEmbedding,
      topK: topK,
      candidateK: candidateK,
    );
  }

  List<MobileClip2SearchResult> searchByEmbedding(
    Float32List queryEmbedding, {
    int topK = defaultTopK,
    int candidateK = defaultCandidateK,
  }) {
    if (topK <= 0 || candidateK <= 0 || _recordsById.isEmpty) {
      return const <MobileClip2SearchResult>[];
    }
    final normalizedQuery = MobileClip2VectorMath.l2Normalize(queryEmbedding);
    final candidates = _recordsById.values.map((record) {
      return _MediaCandidate(
        record: record,
        mediaScore: MobileClip2VectorMath.dot(
          normalizedQuery,
          record.mediaEmbedding,
        ),
      );
    }).toList();
    candidates.sort((a, b) => b.mediaScore.compareTo(a.mediaScore));

    final reranked = candidates
        .take(math.min(candidateK, candidates.length))
        .map((candidate) {
          return _scoreCandidate(normalizedQuery, candidate);
        })
        .toList();
    reranked.sort((a, b) => b.score.compareTo(a.score));
    return reranked.take(math.min(topK, reranked.length)).toList();
  }

  Future<MediaVectorRecord> _buildFrameBasedMediaEmbedding({
    required String mediaUri,
    required SemanticMediaType mediaType,
    required int maxFrames,
  }) async {
    final extracted = await _frameExtractor.extractFrames(
      mediaUri,
      maxFrames: maxFrames,
    );
    final kept = <FrameVectorRecord>[];
    for (final frame in extracted.frames) {
      final embedding = await _encoder.encodeImageEmbedding(frame.imageBytes);
      if (kept.isEmpty ||
          MobileClip2VectorMath.dot(embedding, kept.last.embedding) <
              frameDedupThreshold) {
        kept.add(
          FrameVectorRecord(
            timestampSeconds: frame.timestampSeconds,
            embedding: embedding,
          ),
        );
      }
    }
    if (kept.isEmpty) {
      throw StateError('no usable frame embeddings for media: $mediaUri');
    }
    final path = _filePathFromUri(mediaUri);
    final file = File(path);
    final record = MediaVectorRecord(
      mediaId: mediaUri,
      mediaType: mediaType,
      mediaEmbedding: MobileClip2VectorMath.meanPool(
        kept.map((frame) => frame.embedding).toList(growable: false),
      ),
      frameEmbeddings: List<FrameVectorRecord>.unmodifiable(kept),
      width: extracted.width,
      height: extracted.height,
      durationSeconds: extracted.durationSeconds,
      createdAt: file.existsSync() ? await _createdAt(file) : DateTime.now(),
      localPathOrUri: mediaUri,
    );
    upsertRecord(record);
    return record;
  }

  MobileClip2SearchResult _scoreCandidate(
    Float32List queryEmbedding,
    _MediaCandidate candidate,
  ) {
    final record = candidate.record;
    if (record.mediaType == SemanticMediaType.image) {
      return MobileClip2SearchResult(
        mediaId: record.mediaId,
        mediaType: record.mediaType,
        score: candidate.mediaScore,
        mediaScore: candidate.mediaScore,
      );
    }

    var maxFrameScore = -double.infinity;
    double? bestTimestampSeconds;
    final frameScores = <double>[];
    for (final frame in record.frameEmbeddings) {
      final score = MobileClip2VectorMath.dot(queryEmbedding, frame.embedding);
      frameScores.add(score);
      if (score > maxFrameScore) {
        maxFrameScore = score;
        bestTimestampSeconds = frame.timestampSeconds;
      }
    }
    if (frameScores.isEmpty) {
      return MobileClip2SearchResult(
        mediaId: record.mediaId,
        mediaType: record.mediaType,
        score: candidate.mediaScore,
        mediaScore: candidate.mediaScore,
      );
    }
    final topKFrameScore = MobileClip2VectorMath.topKMean(
      frameScores,
      frameScoreTopK,
    );
    final finalScore =
        videoTopKFrameWeight * topKFrameScore +
        videoMaxFrameWeight * maxFrameScore +
        videoMediaWeight * candidate.mediaScore;
    return MobileClip2SearchResult(
      mediaId: record.mediaId,
      mediaType: record.mediaType,
      score: finalScore,
      mediaScore: candidate.mediaScore,
      maxFrameScore: maxFrameScore,
      topKFrameScore: topKFrameScore,
      bestTimestampSeconds: bestTimestampSeconds,
    );
  }

  void _validateRecord(MediaVectorRecord record) {
    if (record.mediaId.trim().isEmpty) {
      throw ArgumentError('mediaId is empty');
    }
    if (record.mediaEmbedding.isEmpty) {
      throw ArgumentError('mediaEmbedding is empty');
    }
    for (final frame in record.frameEmbeddings) {
      if (frame.embedding.length != record.mediaEmbedding.length) {
        throw ArgumentError(
          'frame embedding dimension mismatch for mediaId=${record.mediaId}',
        );
      }
    }
  }

  static Future<DateTime> _createdAt(File file) async {
    try {
      return await file.lastModified();
    } catch (_) {
      return DateTime.now();
    }
  }

  static String _filePathFromUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed != null && parsed.scheme == 'file') {
      return parsed.toFilePath();
    }
    return uri;
  }
}

class MobileClip2VectorMath {
  const MobileClip2VectorMath._();

  static double dot(Float32List a, Float32List b) {
    if (a.length != b.length) {
      throw ArgumentError(
        'vector dimension mismatch: ${a.length} != ${b.length}',
      );
    }
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  static Float32List l2Normalize(Float32List x) {
    var sumSq = 0.0;
    for (var i = 0; i < x.length; i++) {
      sumSq += x[i] * x[i];
    }
    final norm = math.sqrt(sumSq);
    if (norm == 0 || norm.isNaN || norm.isInfinite) {
      return Float32List.fromList(x);
    }
    final out = Float32List(x.length);
    for (var i = 0; i < x.length; i++) {
      out[i] = x[i] / norm;
    }
    return out;
  }

  static Float32List meanPool(List<Float32List> embeddings) {
    if (embeddings.isEmpty) {
      throw ArgumentError('embeddings is empty');
    }
    final dim = embeddings.first.length;
    final out = Float32List(dim);
    for (final embedding in embeddings) {
      if (embedding.length != dim) {
        throw ArgumentError(
          'vector dimension mismatch: ${embedding.length} != $dim',
        );
      }
      for (var i = 0; i < dim; i++) {
        out[i] += embedding[i];
      }
    }
    for (var i = 0; i < dim; i++) {
      out[i] /= embeddings.length;
    }
    return l2Normalize(out);
  }

  static double topKMean(List<double> scores, int k) {
    if (scores.isEmpty) return -1.0;
    final sorted = [...scores]..sort((a, b) => b.compareTo(a));
    final count = math.min(k, sorted.length);
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      sum += sorted[i];
    }
    return sum / count;
  }
}

int chooseFrameCount(double durationSeconds) {
  if (durationSeconds <= 0) return 1;
  if (durationSeconds <= 10) return 4;
  if (durationSeconds <= 60) {
    return (durationSeconds / 4).round().clamp(4, 16);
  }
  return 16;
}

SemanticMediaType semanticMediaTypeFromPath(String path) {
  return switch (MediaTypeHelper.fromPath(path)) {
    MemoriaMediaKind.video => SemanticMediaType.video,
    MemoriaMediaKind.dynamicImage => SemanticMediaType.gif,
    MemoriaMediaKind.image => SemanticMediaType.image,
  };
}

class _MediaProbeInfo {
  const _MediaProbeInfo({
    required this.width,
    required this.height,
    required this.durationSeconds,
  });

  final int width;
  final int height;
  final double? durationSeconds;
}

class _MediaCandidate {
  const _MediaCandidate({required this.record, required this.mediaScore});

  final MediaVectorRecord record;
  final double mediaScore;
}
