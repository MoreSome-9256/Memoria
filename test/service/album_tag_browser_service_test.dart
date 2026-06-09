import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/data/tag_taxonomy_v2.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/service/album_tag_browser_service.dart';
import 'package:photo_album/service/junk_photo_filter_service.dart';

PhotoEntity _photo({
  required int id,
  required String tag,
  String path = '',
  String assetId = 'asset_id',
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = assetId
    ..path = path
    ..timestamp = 1000 + id
    ..width = 1000
    ..height = 1000
    ..isAiAnalyzed = true
    ..aiTags = <String>[tag];
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
}
