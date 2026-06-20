import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('photo-driven presentation surfaces use asset-backed image widgets', () {
    const files = <String>[
      'lib/view/widgets/story_list_item.dart',
      'lib/view/pages/digital_album_page.dart',
      'lib/view/pages/digital_album_book_page.dart',
      'lib/view/pages/story_generation_progress_page.dart',
      'lib/view/pages/story_result_page.dart',
      'lib/view/pages/story_video_page.dart',
      'lib/view/pages/offscreen_render_worker.dart',
      'lib/view/chat/chat_page.dart',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('PathImage('),
        isFalse,
        reason: '$path must not render indexed photos from bare paths',
      );
      expect(
        RegExp(r'Image\.file\([^)]*photo\.path').hasMatch(source),
        isFalse,
        reason: '$path must not render indexed photos with Image.file',
      );
    }
  });
}
