import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/models/vo/semantic_search_models.dart';
import 'package:photo_album/service/create_recommendation_service.dart';
import 'package:photo_album/service/junk_photo_filter_service.dart';

void main() {
  PhotoEntity photo(int id, {List<String>? tags}) {
    return PhotoEntity()
      ..id = id
      ..assetId = 'asset-$id'
      ..path = '/tmp/$id.jpg'
      ..timestamp = id
      ..width = 100
      ..height = 100
      ..aiTags = tags;
  }

  test('recommendation merge excludes quarantined junk candidates', () {
    final normal = photo(1);
    final pendingJunk = photo(
      2,
      tags: const <String>[JunkPhotoFilterService.pendingJunkCandidateTag],
    );
    final confirmedJunk = photo(
      3,
      tags: const <String>[JunkPhotoFilterService.junkCandidateTag],
    );
    final keptJunk = photo(
      4,
      tags: const <String>[JunkPhotoFilterService.keptJunkCandidateTag],
    );

    final result = SemanticSearchResult(
      query: SemanticSearchQuery.empty('metadata'),
      exactPhotos: <PhotoEntity>[
        normal,
        pendingJunk,
        confirmedJunk,
        keptJunk,
        normal,
      ],
      relatedPhotos: const <PhotoEntity>[],
      hits: const <int, SemanticSearchHit>{},
      totalAnalyzedPhotos: 4,
      filteredCandidateCount: 4,
      metadataCandidateCount: 4,
      tagCandidateCount: 0,
      noExactMatchMessage: null,
    );

    final merged = CreateRecommendationService()
        .mergeRecommendationPhotosForTesting(result);

    expect(merged.map((photo) => photo.id), <int>[1, 4]);
  });
}
