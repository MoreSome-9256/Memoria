import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/photo_entity.dart';
import 'package:photo_album/service/analysis_pipeline_queue.dart';

void main() {
  PhotoEntity photo(String assetId, int timestamp) {
    return PhotoEntity()
      ..assetId = assetId
      ..path = ''
      ..timestamp = timestamp
      ..width = 1
      ..height = 1;
  }

  test(
    'AnalysisPipelineQueue lets producer enqueue without consumer backpressure',
    () async {
      final queue = AnalysisPipelineQueue();
      final itemPhoto = photo('asset-1', 1);

      for (var i = 0; i < 5000; i++) {
        queue.enqueue(
          PipelineQueueItem(
            photoId: i + 1,
            photo: itemPhoto,
            enqueuedAt: DateTime.now(),
          ),
        );
      }

      expect(queue.size, 5000);
      expect((await queue.dequeue())?.photoId, 1);
    },
  );

  test(
    'AnalysisPipelineQueue wakes a waiting consumer and stops on clear',
    () async {
      final queue = AnalysisPipelineQueue();
      final itemPhoto = photo('asset-2', 2);

      final pending = queue.dequeue();
      queue.enqueue(
        PipelineQueueItem(
          photoId: 7,
          photo: itemPhoto,
          enqueuedAt: DateTime.now(),
        ),
      );

      expect((await pending)?.photoId, 7);

      final stopped = queue.dequeue();
      queue.clear();

      expect(await stopped, isNull);
      expect(queue.isClosed, isTrue);
    },
  );
}
