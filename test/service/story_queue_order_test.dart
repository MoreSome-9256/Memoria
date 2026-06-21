import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/vo/photo.dart';
import 'package:photo_album/service/story_queue_service.dart';

void main() {
  final queue = StoryQueueService();

  setUp(queue.clear);
  tearDown(queue.clear);

  test(
    'reordered queue is the immutable launch order, not timestamp order',
    () {
      queue.addPhotos(<Photo>[
        Photo(id: 'oldest', dateTaken: DateTime(2020)),
        Photo(id: 'newest', dateTaken: DateTime(2026)),
        Photo(id: 'middle', dateTaken: DateTime(2023)),
      ]);

      queue.reorder(2, 0);
      final bundle = queue.buildLaunchBundle();

      expect(bundle.selectedPhotos.map((photo) => photo.id), <String>[
        'middle',
        'oldest',
        'newest',
      ]);
      expect(bundle.event.photos.map((photo) => photo.id), <String>[
        'middle',
        'oldest',
        'newest',
      ]);
    },
  );
}
