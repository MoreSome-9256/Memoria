import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/view/pages/album_page.dart';
import 'package:photo_album/view/pages/welcome_page.dart';

void main() {
  group('split page compile smoke', () {
    test('AlbumPage facade compiles with its part files', () {
      const page = AlbumPage();

      expect(page, isA<StatefulWidget>());
      expect(page.key, isNull);
    });

    testWidgets('WelcomePage conflict resolution builds the first frame', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: WelcomePage()));

      expect(find.text('智能影记'), findsOneWidget);
      expect(find.text('做自己生活的导演'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
      expect(find.text('注册'), findsOneWidget);
    });
  });
}
