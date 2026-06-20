import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/data/tag_taxonomy_v2.dart';

void main() {
  test('coarse tag ids are unique and mapped ids exist', () {
    final coarseIds = memoriaCoarseTagDefinitions
        .map((definition) => definition.id)
        .toList(growable: false);

    expect(coarseIds.toSet(), hasLength(coarseIds.length));
    expect(coarseIds, contains(memoriaOtherCoarseId));

    final unknownMappedIds = memoriaCoarseIdToFineLabels.keys
        .where((id) => !memoriaCoarseIdToDefinition.containsKey(id))
        .toList(growable: false);

    expect(unknownMappedIds, isEmpty);
  });

  test('every fine taxonomy label maps to exactly one coarse tag', () {
    final masterLabels = memoriaMasterTagDefinitions
        .map((definition) => definition.label)
        .toList(growable: false);
    final mappedLabels = <String>[];

    for (final entry in memoriaCoarseIdToFineLabels.entries) {
      mappedLabels.addAll(entry.value);
    }

    final duplicateMasterLabels = _duplicates(masterLabels);
    final duplicateMappedLabels = _duplicates(mappedLabels);
    final unmappedMasterLabels = masterLabels
        .where((label) => !memoriaFineLabelToCoarseId.containsKey(label))
        .toList(growable: false);
    final mappedLabelsWithoutDefinition = mappedLabels
        .where(
          (label) =>
              label != memoriaOtherLabel &&
              !memoriaMasterTagDefinitions.any(
                (definition) => definition.label == label,
              ),
        )
        .toList(growable: false);

    expect(duplicateMasterLabels, isEmpty);
    expect(duplicateMappedLabels, isEmpty);
    expect(unmappedMasterLabels, isEmpty);
    expect(mappedLabelsWithoutDefinition, isEmpty);
  });

  test('each concrete coarse tag has fine definitions and prompts', () {
    for (final coarse in memoriaCoarseTagDefinitions) {
      final fineDefinitions = memoriaFineDefinitionsByCoarseId[coarse.id];

      expect(fineDefinitions, isNotNull, reason: coarse.id);
      if (coarse.id == memoriaOtherCoarseId) {
        continue;
      }

      expect(fineDefinitions, isNotEmpty, reason: coarse.id);
      expect(coarse.prompts, isNotEmpty, reason: coarse.id);
      for (final fine in fineDefinitions!) {
        expect(fine.prompts, isNotEmpty, reason: fine.label);
      }
    }
  });
}

Set<String> _duplicates(Iterable<String> values) {
  final seen = <String>{};
  final duplicates = <String>{};

  for (final value in values) {
    if (!seen.add(value)) {
      duplicates.add(value);
    }
  }

  return duplicates;
}
