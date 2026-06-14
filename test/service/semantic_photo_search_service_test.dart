import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/models/vo/semantic_search_models.dart';
import 'package:photo_album/service/junk_photo_filter_service.dart';
import 'package:photo_album/service/semantic_photo_search_service.dart';

PhotoEntity _photo({
  required int id,
  required int timestamp,
  bool analyzed = true,
  List<String>? aiTags,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = '/tmp/$id.jpg'
    ..timestamp = timestamp
    ..width = 1000
    ..height = 1000
    ..isAiAnalyzed = analyzed
    ..aiTags = aiTags ?? const <String>[];
}

void main() {
  test('metadata candidates use the same searchable photo boundary', () {
    final service = SemanticPhotoSearchService();
    final day = DateTime(2026, 6, 8, 12).millisecondsSinceEpoch;
    final query = SemanticSearchQuery.empty('2026-06-08').copyWith(
      timeRanges: <SemanticSearchTimeRange>[
        SemanticSearchTimeRange(
          startTimeMs: DateTime(2026, 6, 8).millisecondsSinceEpoch,
          endTimeMs: DateTime(
            2026,
            6,
            9,
          ).subtract(const Duration(milliseconds: 1)).millisecondsSinceEpoch,
          reason: 'day',
        ),
      ],
    );

    final candidates = service.metadataCandidatesForTesting(<PhotoEntity>[
      _photo(id: 1, timestamp: day),
      _photo(id: 2, timestamp: day, analyzed: false),
      _photo(
        id: 3,
        timestamp: day,
        aiTags: const <String>[JunkPhotoFilterService.pendingJunkCandidateTag],
      ),
      _photo(
        id: 4,
        timestamp: day,
        aiTags: const <String>[JunkPhotoFilterService.junkCandidateTag],
      ),
    ], query);

    expect(candidates.map((photo) => photo.id), <int>[1]);
  });

  test('direct semantic search queries reject CJK vector prompts', () {
    final query = SemanticSearchQuery.empty('海边照片').copyWith(
      queryType: SemanticSearchQueryType.concrete,
      positiveSemantics: const <SemanticSearchSemanticItem>[
        SemanticSearchSemanticItem(text: '海边照片', weight: 1.0),
      ],
      recallSemantics: const <SemanticSearchSemanticItem>[
        SemanticSearchSemanticItem(text: 'a sunny coastal scene', weight: 1.0),
      ],
    );

    expect(
      () => SemanticPhotoSearchService().validateSemanticVectorInputsForTesting(
        query,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
