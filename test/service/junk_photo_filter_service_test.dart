import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/junk_photo_filter_service.dart';
import 'package:photo_album/service/ocr_service.dart';
import 'package:photo_album/utils/ocr_policy.dart';
import 'package:photo_album/utils/tag_sanitizer.dart';

void main() {
  test('cleanup report exposes a review category for legacy candidates', () {
    final report =
        JunkPhotoCleanupReport.fromCandidates(<JunkPhotoCleanupCandidate>[
          const JunkPhotoCleanupCandidate(
            photoId: 1,
            assetId: 'asset-1',
            path: '',
            timestamp: 1,
            reasons: <JunkPhotoHit>[],
          ),
        ]);

    expect(report.reasonCounts, <String, int>{'原因待复核': 1});
    expect(report.reasonSummaries.single.categoryId, 'unknown');
    expect(report.reasonSummaries.single.count, 1);
  });

  test('cleanup report groups reasons by stable category id', () {
    const screenshot = JunkPhotoHit(
      categoryId: 'screenshot',
      label: '应用/网页截图',
      description: '',
      score: 0.3,
      threshold: 0.2,
    );
    final report = JunkPhotoCleanupReport.fromCandidates(
      <JunkPhotoCleanupCandidate>[
        const JunkPhotoCleanupCandidate(
          photoId: 1,
          assetId: 'asset-1',
          path: '',
          timestamp: 1,
          reasons: <JunkPhotoHit>[screenshot],
        ),
        const JunkPhotoCleanupCandidate(
          photoId: 2,
          assetId: 'asset-2',
          path: '',
          timestamp: 2,
          reasons: <JunkPhotoHit>[screenshot],
        ),
      ],
    );

    expect(report.reasonSummaries.single.categoryId, 'screenshot');
    expect(report.reasonSummaries.single.count, 2);
  });

  test('junk candidate reasons survive database tag round-trip', () {
    final reasons = JunkPhotoFilterService().reasonsFromTags(<String>[
      JunkPhotoFilterService.pendingJunkCandidateTag,
      JunkPhotoFilterService.reasonTag('screenshot'),
      JunkPhotoFilterService.reasonTag('document'),
    ]);

    expect(
      reasons.map((reason) => reason.categoryId),
      containsAll(<String>['screenshot', 'document']),
    );
    expect(
      JunkPhotoFilterService.isInternalJunkTag(
        JunkPhotoFilterService.reasonTag('document'),
      ),
      isTrue,
    );
  });

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

  test('junk state and persisted reason tags stay internal', () {
    expect(
      JunkPhotoFilterService.isInternalJunkTag(
        JunkPhotoFilterService.pendingJunkCandidateTag,
      ),
      isTrue,
    );
    expect(
      JunkPhotoFilterService.isInternalJunkTag('__junk_reason__:meme'),
      isTrue,
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

  test(
    'screenshot and document categories mark every score above threshold',
    () {
      final definitions = JunkPhotoFilterService().definitions;
      for (final id in const <String>['screenshot', 'document']) {
        final definition = definitions.singleWhere((item) => item.id == id);
        expect(definition.alwaysMarkAboveThreshold, isTrue);
      }
    },
  );

  test('small albums still detect strong category matches', () {
    expect(
      JunkPhotoFilterService.significantOutlierIds(const <int, double>{
        1: 0.05,
        2: 0.24,
        3: 0.08,
      }, absoluteFloor: 0.2),
      <int>{2},
    );
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

  test('small albums still detect an unambiguous strong outlier', () {
    final scores = <int, double>{
      for (var i = 0; i < 10; i++) i: 0.12,
      100: 0.9,
    };

    expect(
      JunkPhotoFilterService.significantOutlierIds(scores, absoluteFloor: 0.2),
      <int>{100},
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
