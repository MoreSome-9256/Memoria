import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/vo/photo.dart';
import 'package:photo_album/utils/media_type_helper.dart';
import 'package:photo_album/view/pages/story_generation_progress_page.dart';
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
            dateTaken: DateTime(2026),
            mediaKind: 'dynamicImage',
            thumbnailBytes: thumbnailBytes,
          ),
        ],
        previewAssetRef: 'asset:${Uri.encodeComponent('asset-42')}',
      );

      expect(preview, isA<MediaThumbnail>());
      final thumbnail = preview as MediaThumbnail;
      expect(thumbnail.assetId, 'asset-42');
      expect(thumbnail.kind, MemoriaMediaKind.dynamicImage);
      expect(thumbnail.thumbnailBytes, same(thumbnailBytes));
      expect(thumbnail.showBadge, isFalse);
    },
  );

  test(
    'story progress preview shows placeholder for invalid asset reference',
    () {
      final preview = buildStoryGenerationPreviewImage(
        selectedPhotos: const <Photo>[],
        previewAssetRef: 'invalid-reference',
      );

      expect(preview, isA<ColoredBox>());
    },
  );

  test('story progress preview uses encoded asset id as the only identity', () {
    final firstBytes = Uint8List.fromList(<int>[1]);
    final secondBytes = Uint8List.fromList(<int>[2]);
    final preview = buildStoryGenerationPreviewImage(
      selectedPhotos: <Photo>[
        Photo(
          id: 'asset-first',
          dateTaken: DateTime(2026),
          thumbnailBytes: firstBytes,
        ),
        Photo(
          id: 'asset-second',
          dateTaken: DateTime(2026),
          thumbnailBytes: secondBytes,
        ),
      ],
      previewAssetRef: 'asset:${Uri.encodeComponent('asset-second')}',
    );

    expect(preview, isA<MediaThumbnail>());
    final thumbnail = preview as MediaThumbnail;
    expect(thumbnail.assetId, 'asset-second');
    expect(thumbnail.thumbnailBytes, same(secondBytes));
  });
}
