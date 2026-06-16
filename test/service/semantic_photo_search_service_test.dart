import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/models/vo/semantic_search_models.dart';
import 'package:photo_album/service/junk_photo_filter_service.dart';
import 'package:photo_album/service/app_ai_settings_service.dart';
import 'package:photo_album/service/semantic_photo_search_service.dart';
import 'package:photo_album/service/searchable_photo_policy.dart';
import 'package:photo_album/utils/ocr_policy.dart';

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
  test('searchable photo policy rejects incomplete and quarantined photos', () {
    final analyzed = _photo(id: 1, timestamp: 1, analyzed: true);
    final pendingAnalysis = _photo(id: 2, timestamp: 2, analyzed: false);
    final activeCandidate = _photo(id: 3, timestamp: 3, analyzed: true)
      ..isAiAnalysisCandidate = true;
    final junkPending = _photo(id: 4, timestamp: 4, analyzed: true)
      ..aiTags = const <String>['__junk_pending__'];
    final junkCandidate = _photo(id: 5, timestamp: 5, analyzed: true)
      ..aiTags = const <String>['__junk_candidate__'];

    expect(
      SearchablePhotoPolicy.filter(<PhotoEntity>[
        analyzed,
        pendingAnalysis,
        activeCandidate,
        junkPending,
        junkCandidate,
      ]).map((photo) => photo.id),
      <int>[1],
    );
  });

  test('searchable photo policy enforces enabled attribute completion', () {
    final photo = _photo(id: 1, timestamp: 1, analyzed: true);
    expect(
      SearchablePhotoPolicy.allows(photo, settings: AppAiSettings.defaults),
      isFalse,
    );

    photo
      ..isCaptionAnalyzed = true
      ..isOcrAnalyzed = true
      ..isFaceAnalyzed = true;
    expect(
      SearchablePhotoPolicy.allows(photo, settings: AppAiSettings.defaults),
      isTrue,
    );
  });
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

  test('metadata matches become related fallback when semantics miss', () {
    final service = SemanticPhotoSearchService();
    final query = SemanticSearchQuery.empty('某地的海边').copyWith(
      locations: const <SemanticSearchLocation>[
        SemanticSearchLocation(text: '某地', type: 'city'),
      ],
    );
    final photo = _photo(id: 1, timestamp: 1)..city = '某地';

    final candidates = service.metadataCandidatesForTesting(<PhotoEntity>[
      photo,
    ], query);
    final hits = service.metadataFallbackHitsForTesting(
      query: query,
      strictMetadataCandidates: candidates,
    );

    expect(candidates, <PhotoEntity>[photo]);
    expect(hits.keys, <int>[photo.id]);
    expect(hits[photo.id]!.isExactMatch, isFalse);
  });

  test('specific POI does not drop geo filters for global semantic recall', () {
    final query = SemanticSearchQuery.empty('五四广场').copyWith(
      queryType: SemanticSearchQueryType.concrete,
      locations: const <SemanticSearchLocation>[
        SemanticSearchLocation(text: '五四广场', type: 'poi'),
      ],
      positiveSemantics: const <SemanticSearchSemanticItem>[
        SemanticSearchSemanticItem(text: 'a city square', weight: 1),
      ],
    );

    expect(
      SemanticPhotoSearchService().shouldUseGlobalPoiSemanticRecallForTesting(
        query,
        const <PhotoEntity>[],
      ),
      isFalse,
    );
  });

  test('OCR text contributes searchable text feature score when enabled', () {
    final service = SemanticPhotoSearchService();
    final photo = _photo(id: 1, timestamp: 1)
      ..isCaptionAnalyzed = true
      ..isOcrAnalyzed = true
      ..ocrText = '南京东路餐厅发票 合计 128 元'
      ..ocrTags = const <String>['餐厅发票', '南京东路'];

    OcrPolicy.setRuntimeEnabled(false);
    expect(service.textFeatureScoreForTesting(photo, '餐厅发票'), 0);

    OcrPolicy.setRuntimeEnabled(true);
    expect(service.textFeatureScoreForTesting(photo, '餐厅发票'), greaterThan(0));

    OcrPolicy.setRuntimeEnabled(false);
  });
}
