import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/data/tag_taxonomy_v2.dart';
import 'package:photo_album/service/mobileclip_tag_service.dart';

void main() {
  test(
    'coarse tag selection falls back to relative leaders below strict thresholds',
    () {
      final service = MobileClipTagService();
      final people = memoriaCoarseIdToDefinition['people']!;
      final food = memoriaCoarseIdToDefinition['food_drink']!;
      final landscape = memoriaCoarseIdToDefinition['natural_landscape']!;

      final selected = service
          .selectCoarseCandidatesForTesting(<MobileClipCoarseDiagnostic>[
            MobileClipCoarseDiagnostic(
              coarseId: people.id,
              label: people.label,
              score: 0.11,
              probability: 0.03,
            ),
            MobileClipCoarseDiagnostic(
              coarseId: food.id,
              label: food.label,
              score: 0.08,
              probability: 0.028,
            ),
            MobileClipCoarseDiagnostic(
              coarseId: landscape.id,
              label: landscape.label,
              score: 0.01,
              probability: 0.025,
            ),
          ]);

      expect(selected, isNotEmpty);
      expect(selected, hasLength(1));
      expect(selected.map((item) => item.coarseId), contains(people.id));
      expect(
        selected.every((item) => item.coarseId != memoriaOtherCoarseId),
        isTrue,
      );
    },
  );

  test('coarse tag selection still rejects unusably weak scores', () {
    final service = MobileClipTagService();
    final people = memoriaCoarseIdToDefinition['people']!;

    final selected = service
        .selectCoarseCandidatesForTesting(<MobileClipCoarseDiagnostic>[
          MobileClipCoarseDiagnostic(
            coarseId: people.id,
            label: people.label,
            score: 0.02,
            probability: 0.03,
          ),
        ]);

    expect(selected, isEmpty);
  });

  test(
    'fine tag selection keeps relative leaders below old strict thresholds',
    () {
      final service = MobileClipTagService();
      final peopleTag = memoriaCoarseIdToFineLabels['people']!.first;
      final foodTag = memoriaCoarseIdToFineLabels['food_drink']!.first;

      final selected = service.selectFineTagsForTesting(<String, double>{
        peopleTag: 0.11,
        foodTag: 0.08,
        memoriaOtherLabel: 0.01,
      }, topK: 3);

      expect(selected, isNotEmpty);
      expect(selected.first.tag, peopleTag);
      expect(
        selected.map((item) => item.tag),
        isNot(contains(memoriaOtherLabel)),
      );
    },
  );
}
