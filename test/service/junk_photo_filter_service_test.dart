import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/junk_photo_filter_service.dart';
import 'package:photo_album/utils/tag_sanitizer.dart';

void main() {
  test(
    'junk filter definitions include post-filter categories used by workers',
    () {
      final ids = JunkPhotoFilterService().definitions
          .map((definition) => definition.id)
          .toSet();

      expect(ids, contains('code'));
      expect(ids, contains('meme'));
      expect(ids, contains('plain_selfie'));
      expect(ids, contains('advertisement_poster'));
      expect(ids, contains('abstract_low_value'));
      expect(ids, contains('dark_or_occluded'));
      expect(ids, contains('blurred_or_broken'));
      expect(ids, contains('low_value_landmark'));
    },
  );

  test('junk reason tags round-trip to cleanup report reasons', () {
    final tags = <String>[
      JunkPhotoFilterService.pendingJunkCandidateTag,
      ...JunkPhotoFilterService.reasonTagsForCategoryIds(<String>[
        'low_value_landmark',
      ]),
    ];

    final hits = JunkPhotoFilterService.hitsFromTags(tags);

    expect(hits, hasLength(1));
    expect(hits.single.categoryId, 'low_value_landmark');
    expect(hits.single.label, '低价值地标/路牌');
  });

  test('internal junk tags are hidden from normal display tags', () {
    final tags = TagSanitizer.sanitizeDisplayTags(<String>[
      '旅行',
      JunkPhotoFilterService.pendingJunkCandidateTag,
      '${JunkPhotoFilterService.junkReasonTagPrefix}meme',
    ]);

    expect(tags, <String>['旅行']);
  });
}
