import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/view/pages/create_page.dart';

void main() {
  test('create search merge keeps screenshots and deduplicates results', () {
    final screenshot = _photo(
      id: 1,
      path: '/photos/Screenshot_2026-06-14.png',
      width: 1080,
      height: 2400,
    );
    final exact = _photo(id: 2);
    final relatedDuplicate = _photo(id: 2);
    final related = _photo(id: 3);

    final merged = mergeCreateSearchPhotosForTesting(
      exactPhotos: <PhotoEntity>[screenshot, exact],
      relatedPhotos: <PhotoEntity>[relatedDuplicate, related],
      maxResults: 10,
    );

    expect(merged.map((photo) => photo.id), <int>[1, 2, 3]);
    expect(
      mergeCreateSearchPhotoIdsForTesting(
        exactPhotos: <PhotoEntity>[screenshot, exact],
        relatedPhotos: <PhotoEntity>[relatedDuplicate, related],
        maxResults: 10,
      ),
      <int>[1, 2, 3],
    );
  });

  test('create search merge respects the result cap', () {
    final merged = mergeCreateSearchPhotosForTesting(
      exactPhotos: <PhotoEntity>[_photo(id: 1), _photo(id: 2)],
      relatedPhotos: <PhotoEntity>[_photo(id: 3)],
      maxResults: 2,
    );

    expect(merged.map((photo) => photo.id), <int>[1, 2]);
    expect(
      mergeCreateSearchPhotoIdsForTesting(
        exactPhotos: <PhotoEntity>[_photo(id: 1), _photo(id: 2)],
        relatedPhotos: <PhotoEntity>[_photo(id: 3)],
        maxResults: 2,
      ),
      <int>[1, 2],
    );
  });
}

PhotoEntity _photo({
  required int id,
  String? path,
  int width = 1600,
  int height = 1200,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = path ?? '/photos/$id.jpg'
    ..timestamp = id
    ..width = width
    ..height = height
    ..isAiAnalyzed = true
    ..aiTags = const <String>['文档'];
}
