import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/junk_photo_filter_service.dart';
import 'package:photo_album/service/ocr_service.dart';
import 'package:photo_album/utils/ocr_policy.dart';
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
      expect(ids, contains('screenshot'));
      expect(ids, contains('document'));
      expect(ids, contains('abstract_low_value'));
      expect(ids, contains('dark_or_occluded'));
      expect(ids, contains('blurred_or_broken'));
      expect(ids, contains('low_value_landmark'));
    },
  );

  test('junk state tags contain no semantic category guesses', () {
    expect(
      JunkPhotoFilterService.isInternalJunkTag(
        JunkPhotoFilterService.pendingJunkCandidateTag,
      ),
      isTrue,
    );
    expect(
      JunkPhotoFilterService.isInternalJunkTag('__junk_reason__:meme'),
      isFalse,
    );
    expect(
      JunkPhotoFilterService.hasFinalDecision(<String>[
        JunkPhotoFilterService.keptJunkCandidateTag,
      ]),
      isTrue,
    );
    expect(
      JunkPhotoFilterService.isQuarantined(<String>[
        JunkPhotoFilterService.keptJunkCandidateTag,
      ]),
      isFalse,
    );
  });

  test('OCR selection uses semantic tags instead of image aspect ratio', () {
    OcrPolicy.setRuntimeEnabled(true);
    try {
      expect(OcrService.shouldRunOcr(<String>['截图']), isTrue);
      expect(OcrService.shouldRunOcr(<String>['文档']), isTrue);
      expect(OcrService.shouldRunOcr(<String>['风景']), isFalse);
    } finally {
      OcrPolicy.setRuntimeEnabled(false);
    }
  });

  test('post filter definitions contain only CLIP similarity thresholds', () {
    for (final definition in JunkPhotoFilterService().definitionsJson) {
      expect(definition.keys.toSet(), <String>{
        'id',
        'label',
        'description',
        'threshold',
      });
    }
  });

  test('distribution filter selects only significant upper outliers', () {
    final scores = <int, double>{
      for (var i = 0; i < 30; i++) i: 0.14 + (i % 4) * 0.002,
      100: 0.27,
      101: 0.29,
    };

    expect(
      JunkPhotoFilterService.significantOutlierIds(scores, absoluteFloor: 0.2),
      <int>{100, 101},
    );
  });

  test('distribution filter does not invent candidates for a tight album', () {
    final scores = <int, double>{
      for (var i = 0; i < 40; i++) i: 0.23 + (i % 5) * 0.001,
    };

    expect(
      JunkPhotoFilterService.significantOutlierIds(scores, absoluteFloor: 0.2),
      isEmpty,
    );
  });

  test('distribution filter does not guess from a small album', () {
    final scores = <int, double>{
      for (var i = 0; i < 10; i++) i: 0.12,
      100: 0.9,
    };

    expect(
      JunkPhotoFilterService.significantOutlierIds(scores, absoluteFloor: 0.2),
      isEmpty,
    );
  });

  test('internal junk tags are hidden from normal display tags', () {
    final tags = TagSanitizer.sanitizeDisplayTags(<String>[
      '旅行',
      JunkPhotoFilterService.pendingJunkCandidateTag,
      JunkPhotoFilterService.keptJunkCandidateTag,
    ]);

    expect(tags, <String>['旅行']);
  });
}
