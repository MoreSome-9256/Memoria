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

  test('tag browser ignores tags before AI analysis completes', () {
    final documentTag =
        memoriaCoarseIdToFineLabels['document_screenshot']!.first;
    final photo = _photo(id: 3, tag: documentTag)..isAiAnalyzed = false;
    final service = AlbumTagBrowserService();

    expect(service.browsableTagsForPhoto(photo), isEmpty);
    expect(service.browsableCoarseIdsForPhoto(photo), isEmpty);
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

  test('tag browser never infers document categories from local signals', () {
    final people = memoriaCoarseIdToDefinition['people']!;
    final document = memoriaCoarseIdToDefinition['document_screenshot']!;
    final peopleTag = memoriaCoarseIdToFineLabels[people.id]!.first;
    final service = AlbumTagBrowserService();
    final photo = _photo(
      id: 1,
      tag: peopleTag,
      path: '/photos/Screenshot_2026-06-14.png',
      width: 1080,
      height: 2400,
      ocrText: '课程课件 试卷 题目 答案 二维码',
    );

    final tags = service.browsableTagsForPhoto(photo);
    final clusters = service.buildCoarseClusters(<PhotoEntity>[photo]);
    final coarseIds = clusters.map((cluster) => cluster.coarseId).toSet();

    expect(tags, <String>[peopleTag]);
    expect(coarseIds, contains(people.id));
    expect(coarseIds, isNot(contains(document.id)));
  });

  test('tag browser exposes document category only from AI visual tags', () {
    final document = memoriaCoarseIdToDefinition['document_screenshot']!;
    final documentTag = memoriaCoarseIdToFineLabels[document.id]!.first;
    final service = AlbumTagBrowserService();
    final photo = _photo(id: 1, tag: documentTag);

    final tags = service.browsableTagsForPhoto(photo);
    final coarseIds = service.browsableCoarseIdsForPhoto(photo);

    expect(tags, <String>[documentTag]);
    expect(coarseIds, contains(document.id));
  });
}
