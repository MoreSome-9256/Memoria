import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/service/photo_attribute_background_service.dart';
import 'package:photo_album/service/unified_analysis_pipeline_service.dart';
import 'package:photo_album/service/app_ai_settings_service.dart';

void main() {
  test('attribute queue coalesces pending tasks by photo id', () {
    final service = PhotoAttributeBackgroundService.instance()
      ..resetForTesting();

    service.enqueueAttributeTaskForTesting(
      photoId: 1,
      types: <PhotoAttributeType>{PhotoAttributeType.location},
    );
    service.enqueueAttributeTaskForTesting(
      photoId: 1,
      types: <PhotoAttributeType>{
        PhotoAttributeType.faceDetection,
        PhotoAttributeType.caption,
      },
    );

    final pending = service.pendingTasksForTesting();
    expect(pending, hasLength(1));
    expect(pending.single.photoId, 1);
    expect(pending.single.types, <PhotoAttributeType>{
      PhotoAttributeType.location,
      PhotoAttributeType.faceDetection,
      PhotoAttributeType.caption,
    });

    service.resetForTesting();
  });

  test('pipeline requests visual attributes only for image photos', () {
    final pipeline = UnifiedAnalysisPipelineService();

    final imageTypes = pipeline.attributeTypesForAnalyzedPhotoForTesting(
      _photo(id: 1, mediaKind: 'image', path: '/photos/1.jpg'),
    );
    final videoTypes = pipeline.attributeTypesForAnalyzedPhotoForTesting(
      _photo(id: 2, mediaKind: 'video', path: '/photos/2.mp4'),
    );

    expect(imageTypes, <PhotoAttributeType>{
      PhotoAttributeType.location,
      PhotoAttributeType.faceDetection,
      PhotoAttributeType.ocr,
      PhotoAttributeType.caption,
    });
    expect(videoTypes, <PhotoAttributeType>{PhotoAttributeType.location});
  });

  test('pipeline honors disabled OCR and face analysis settings', () {
    final pipeline = UnifiedAnalysisPipelineService();
    final types = pipeline.attributeTypesForAnalyzedPhotoForTesting(
      _photo(id: 1, mediaKind: 'image', path: '/photos/1.jpg'),
      settings: AppAiSettings.defaults.copyWith(
        ocrEnabled: false,
        faceAnalysisEnabled: false,
      ),
    );

    expect(types, <PhotoAttributeType>{
      PhotoAttributeType.location,
      PhotoAttributeType.caption,
    });
  });
}

PhotoEntity _photo({
  required int id,
  required String mediaKind,
  required String path,
}) {
  return PhotoEntity()
    ..id = id
    ..assetId = 'asset_$id'
    ..path = path
    ..timestamp = id
    ..width = 1600
    ..height = 1200
    ..mediaKind = mediaKind;
}
