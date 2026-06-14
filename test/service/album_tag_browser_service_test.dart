import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/data/tag_taxonomy_v2.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/service/album_tag_browser_service.dart';
import 'package:photo_album/service/junk_photo_filter_service.dart';

PhotoEntity _photo({
  required int id,
  String? tag,
  List<String>? tags,
  String path = '',
  String assetId = 'asset_id',
  int width = 1000,
  int height = 1000,
  String? ocrText,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = assetId
    ..path = path
    ..timestamp = 1000 + id
    ..width = width
    ..height = height
    ..isAiAnalyzed = true
    ..ocrText = ocrText
    ..aiTags = tags ?? <String>[tag!];
}

void main() {
  test(
    'tag browser accepts asset-backed analyzed photos without file paths',
    () {
      final tag = memoriaMasterTagDefinitions.first.label;
      final photo = _photo(id: 1, tag: tag);
      final service = AlbumTagBrowserService();

      expect(photo.path, isEmpty);
      expect(service.hasBrowsableCategory(photo), isTrue);

      final clusters = service.buildCoarseClusters(<PhotoEntity>[photo]);
      expect(clusters, isNotEmpty);
      expect(clusters.single.photoCount, 1);
    },
  );

  test('tag browser excludes confirmed junk photos', () {
    final photo = _photo(id: 2, tag: memoriaMasterTagDefinitions.first.label)
      ..aiTags = <String>[
        memoriaMasterTagDefinitions.first.label,
        JunkPhotoFilterService.junkCandidateTag,
      ];
    final service = AlbumTagBrowserService();

    expect(service.hasBrowsableCategory(photo), isFalse);
    expect(service.buildCoarseClusters(<PhotoEntity>[photo]), isEmpty);
  });

  test('tag browser keeps coarse fallback labels out of other', () {
    final people = memoriaCoarseIdToDefinition['people']!;
    final food = memoriaCoarseIdToDefinition['food_drink']!;
    final landscape = memoriaCoarseIdToDefinition['natural_landscape']!;
    final service = AlbumTagBrowserService();

    final clusters = service.buildCoarseClusters(<PhotoEntity>[
      _photo(id: 1, tag: people.label),
      _photo(id: 2, tag: food.label),
      _photo(id: 3, tag: landscape.label),
    ]);
    final coarseIds = clusters.map((cluster) => cluster.coarseId).toSet();

    expect(coarseIds, contains(people.id));
    expect(coarseIds, contains(food.id));
    expect(coarseIds, contains(landscape.id));
    expect(coarseIds, isNot(contains(memoriaOtherCoarseId)));
  });

  test('tag browser counts pure generic tag combinations only once', () {
    final peopleTag = memoriaCoarseIdToFineLabels['people']!.first;
    final foodTag = memoriaCoarseIdToFineLabels['food_drink']!.first;
    final service = AlbumTagBrowserService();
    final photo = _photo(id: 1, tags: <String>[peopleTag, foodTag]);

    final tags = service.browsableTagsForPhoto(photo);
    final coarseIds = service.browsableCoarseIdsForPhoto(photo);

    expect(tags, <String>[peopleTag]);
    expect(coarseIds, contains('people'));
    expect(coarseIds, isNot(contains('food_drink')));
  });

  test('tag browser uses document signals for low-information coarse tags', () {
    final people = memoriaCoarseIdToDefinition['people']!;
    final food = memoriaCoarseIdToDefinition['food_drink']!;
    final document = memoriaCoarseIdToDefinition['document_screenshot']!;
    final peopleTag = memoriaCoarseIdToFineLabels[people.id]!.first;
    final foodTag = memoriaCoarseIdToFineLabels[food.id]!.first;
    final documentTag = memoriaCoarseIdToFineLabels[document.id]!.first;
    final service = AlbumTagBrowserService();
    final photo = _photo(
      id: 1,
      tags: <String>[peopleTag, foodTag],
      width: 1080,
      height: 2400,
      ocrText: '课程课件 试卷 题目 答案 二维码',
    );

    final tags = service.browsableTagsForPhoto(photo);
    final clusters = service.buildCoarseClusters(<PhotoEntity>[photo]);
    final coarseIds = clusters.map((cluster) => cluster.coarseId).toSet();

    expect(tags, contains(documentTag));
    expect(tags, isNot(contains(peopleTag)));
    expect(tags, isNot(contains(foodTag)));
    expect(coarseIds, contains(document.id));
    expect(coarseIds, isNot(contains(people.id)));
    expect(coarseIds, isNot(contains(food.id)));
  });

  test('tag browser treats low-information tall screenshots as documents', () {
    final peopleTag = memoriaCoarseIdToFineLabels['people']!.first;
    final document = memoriaCoarseIdToDefinition['document_screenshot']!;
    final documentTag = memoriaCoarseIdToFineLabels[document.id]!.first;
    final service = AlbumTagBrowserService();
    final photo = _photo(id: 1, tag: peopleTag, width: 1080, height: 2400);

    final tags = service.browsableTagsForPhoto(photo);
    final coarseIds = service.browsableCoarseIdsForPhoto(photo);

    expect(tags, contains(documentTag));
    expect(coarseIds, contains(document.id));
  });

  test('tag browser lets screenshot evidence override visual fine tags', () {
    final selfieTag = memoriaCoarseIdToFineLabels['people']![1];
    final document = memoriaCoarseIdToDefinition['document_screenshot']!;
    final service = AlbumTagBrowserService();
    final photo = _photo(id: 1, tag: selfieTag, width: 1080, height: 2400);

    final coarseIds = service.browsableCoarseIdsForPhoto(photo);

    expect(coarseIds, contains(document.id));
    expect(coarseIds, isNot(contains('people')));
  });
}
