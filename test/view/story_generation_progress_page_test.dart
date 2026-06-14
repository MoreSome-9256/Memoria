import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/vo/photo.dart';
import 'package:photo_album/utils/media_type_helper.dart';
import 'package:photo_album/view/pages/story_generation_progress_page.dart';
import 'package:photo_album/view/widgets/asset_backed_image.dart';
import 'package:photo_album/view/widgets/media_thumbnail.dart';

void main() {
  test(
    'story progress preview uses asset-backed thumbnail for selected photo',
    () {
      final thumbnailBytes = Uint8List.fromList(<int>[1, 2, 3]);
      final preview = buildStoryGenerationPreviewImage(
        selectedPhotos: <Photo>[
          Photo(
            id: 'asset-42',
            path: '/inaccessible/system/path.jpg',
            dateTaken: DateTime(2026),
            mediaKind: 'dynamicImage',
            thumbnailBytes: thumbnailBytes,
          ),
        ],
        path: '/inaccessible/system/path.jpg',
      );

      expect(preview, isA<MediaThumbnail>());
      final thumbnail = preview as MediaThumbnail;
      expect(thumbnail.assetId, 'asset-42');
      expect(thumbnail.kind, MemoriaMediaKind.dynamicImage);
      expect(thumbnail.thumbnailBytes, same(thumbnailBytes));
      expect(thumbnail.showBadge, isFalse);
    },
  );

  test('story progress preview keeps path fallback for non-album images', () {
    final preview = buildStoryGenerationPreviewImage(
      selectedPhotos: const <Photo>[],
      path: '/temporary/generated-cover.jpg',
    );

    expect(preview, isA<AssetBackedImage>());
  });
}
