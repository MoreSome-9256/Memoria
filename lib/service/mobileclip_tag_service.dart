import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../utils/tag_sanitizer.dart';

class MobileClipTagService {
  MobileClipTagService._internal();

  static final MobileClipTagService _instance =
      MobileClipTagService._internal();

  factory MobileClipTagService() => _instance;

  static const String _vectorsAssetPath = 'assets/expanded_tags_taxonomy.json';
  static const int _defaultTopK = 5;
  static const double _minimumScore = 0.16;
  static const double _displayScoreGap = 0.04;
  static const double _nmsThreshold = 0.92;

  static const Set<String> _blockedTags = <String>{
    '套路',
    '未婚妻',
    '字幕',
    '房主',
    '采购员',
  };

  List<_TagVectorEntry>? _entries;

  Future<void> warmUp() async {
    await _ensureLoaded();
  }

  Future<List<String>> retrieveTags(
    List<double> imageEmbedding, {
    int topK = _defaultTopK,
  }) async {
    final diagnostics = await retrieveTagDiagnostics(
      imageEmbedding,
      topK: topK,
    );
    return diagnostics.map((item) => item.tag).toList(growable: false);
  }

  Future<List<MobileClipTagDiagnostic>> retrieveTagDiagnostics(
    List<double> imageEmbedding, {
    int topK = _defaultTopK,
  }) async {
    final entries = await _ensureLoaded();
    if (entries.isEmpty || imageEmbedding.isEmpty) {
      return const <MobileClipTagDiagnostic>[];
    }

    final normalizedEmbedding = _normalize(imageEmbedding);
    final matches =
        entries
            .map(
              (entry) => _TagMatch(
                entry: entry,
                score: _dot(normalizedEmbedding, entry.vector),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.score.compareTo(a.score));

    final filteredTags = _selectCoreTags(
      matches,
      topK: topK,
      filterNoisy: true,
    );
    if (filteredTags.isNotEmpty) {
      return filteredTags
          .map(
            (match) => MobileClipTagDiagnostic(
              tag: match.entry.tag,
              score: match.score,
              category: match.entry.category,
            ),
          )
          .toList(growable: false);
    }

    final permissiveTags = _selectCoreTags(
      matches,
      topK: topK,
      filterNoisy: false,
    );
    if (permissiveTags.isNotEmpty) {
      return permissiveTags
          .map(
            (match) => MobileClipTagDiagnostic(
              tag: match.entry.tag,
              score: match.score,
              category: match.entry.category,
            ),
          )
          .toList(growable: false);
    }

    return matches
        .take(topK)
        .map(
          (match) => MobileClipTagDiagnostic(
            tag: match.entry.tag,
            score: match.score,
            category: match.entry.category,
          ),
        )
        .toList(growable: false);
  }

  List<_TagMatch> _selectCoreTags(
    List<_TagMatch> rankedMatches, {
    required int topK,
    required bool filterNoisy,
  }) {
    if (rankedMatches.isEmpty) {
      return const <_TagMatch>[];
    }

    final topScore = rankedMatches.first.score;
    final displayThreshold = math.max(
      _minimumScore,
      topScore - _displayScoreGap,
    );

    final candidates =
        rankedMatches
            .where((match) {
              if (match.score < displayThreshold) {
                return false;
              }
              if (!filterNoisy) {
                return true;
              }
              return !_isNoisyCandidate(match.entry);
            })
            .toList(growable: false)
          ..sort(_compareCandidates);

    if (candidates.isEmpty) {
      return const <_TagMatch>[];
    }

    final selected = <_TagMatch>[];

    for (final candidate in candidates) {
      var isRedundant = false;
      for (final existing in selected) {
        final redundancyScore = _dot(
          candidate.entry.vector,
          existing.entry.vector,
        );
        if (redundancyScore > _nmsThreshold) {
          isRedundant = true;
          break;
        }
      }
      if (isRedundant) {
        continue;
      }

      selected.add(candidate);
      if (selected.length >= topK) {
        break;
      }
    }

    if (selected.isEmpty) {
      return const <_TagMatch>[];
    }

    return selected;
  }

  Future<List<_TagVectorEntry>> _ensureLoaded() async {
    final cached = _entries;
    if (cached != null) {
      return cached;
    }

    final rawJson = await rootBundle.loadString(_vectorsAssetPath);
    final decoded = jsonDecode(rawJson) as List<dynamic>;

    _entries = decoded
        .map((dynamic item) {
          final map = item as Map<String, dynamic>;
          final tag = map['tag'] as String;
          final category = (map['category'] as String?) ?? '抽象与其他';
          final commonWordOrder =
              (map['common_word_order'] as num?)?.toInt() ?? 1000000000;
          final rawVector = (map['vector'] as List<dynamic>)
              .map((dynamic value) => (value as num).toDouble())
              .toList(growable: false);
          return _TagVectorEntry(
            tag: tag,
            category: category,
            commonWordOrder: commonWordOrder,
            vector: _normalize(rawVector),
          );
        })
        .toList(growable: false);

    return _entries!;
  }

  Float32List _normalize(List<double> vector) {
    final normalized = Float32List(vector.length);
    var squaredSum = 0.0;
    for (final value in vector) {
      squaredSum += value * value;
    }

    final norm = math.sqrt(squaredSum);
    if (norm == 0) {
      for (var index = 0; index < vector.length; index++) {
        normalized[index] = vector[index];
      }
      return normalized;
    }

    for (var index = 0; index < vector.length; index++) {
      normalized[index] = vector[index] / norm;
    }
    return normalized;
  }

  double _dot(Float32List left, Float32List right) {
    final length = math.min(left.length, right.length);
    var sum = 0.0;
    for (var index = 0; index < length; index++) {
      sum += left[index] * right[index];
    }
    return sum;
  }

  bool _isNoisyCandidate(_TagVectorEntry entry) {
    if (_blockedTags.contains(entry.tag)) {
      return true;
    }

    if (TagSanitizer.isBlockedExactTag(entry.tag)) {
      return true;
    }

    if (entry.category == '抽象与其他' && entry.commonWordOrder > 8000) {
      return true;
    }

    if (entry.category == '人物与群体') {
      if (entry.commonWordOrder > 6000) {
        return true;
      }
      if (entry.tag.length >= 4 && entry.commonWordOrder > 2500) {
        return true;
      }
    }

    if (entry.category == '活动与事件' && entry.commonWordOrder > 12000) {
      return true;
    }

    return false;
  }

  int _compareCandidates(_TagMatch left, _TagMatch right) {
    final leftBucket = left.score.toStringAsFixed(2);
    final rightBucket = right.score.toStringAsFixed(2);
    final bucketCompare = rightBucket.compareTo(leftBucket);
    if (bucketCompare != 0) {
      return bucketCompare;
    }

    final lengthCompare = right.entry.tag.length.compareTo(
      left.entry.tag.length,
    );
    if (lengthCompare != 0) {
      return lengthCompare;
    }

    final commonnessCompare = left.entry.commonWordOrder.compareTo(
      right.entry.commonWordOrder,
    );
    if (commonnessCompare != 0) {
      return commonnessCompare;
    }

    final scoreCompare = right.score.compareTo(left.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }

    return left.entry.tag.compareTo(right.entry.tag);
  }
}

class MobileClipTagDiagnostic {
  const MobileClipTagDiagnostic({
    required this.tag,
    required this.score,
    required this.category,
  });

  final String tag;
  final double score;
  final String category;
}

class _TagVectorEntry {
  const _TagVectorEntry({
    required this.tag,
    required this.category,
    required this.commonWordOrder,
    required this.vector,
  });

  final String tag;
  final String category;
  final int commonWordOrder;
  final Float32List vector;
}

class _TagMatch {
  const _TagMatch({required this.entry, required this.score});

  final _TagVectorEntry entry;
  final double score;
}
