import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _albumPagePath = 'lib/view/pages/album_page.dart';
const String _tagBrowserPartPath = 'lib/view/pages/album_page_tag_browser.dart';
const String _deferredImagePartPath =
    'lib/view/pages/album_page_deferred_image.dart';

void main() {
  group('AlbumPage split static contract', () {
    test('facade includes the split part files', () {
      final albumPage = File(_albumPagePath).readAsStringSync();

      expect(albumPage, contains("part 'album_page_tag_browser.dart';"));
      expect(albumPage, contains("part 'album_page_deferred_image.dart';"));
    });

    test('split files remain library parts of album_page.dart', () {
      for (final path in <String>[
        _tagBrowserPartPath,
        _deferredImagePartPath,
      ]) {
        final source = File(path).readAsStringSync();
        final firstDirective = source
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .firstWhere(
              (line) =>
                  line.isNotEmpty &&
                  !line.startsWith('//') &&
                  !line.startsWith('/*') &&
                  !line.startsWith('*'),
              orElse: () => '',
            );

        expect(
          firstDirective,
          "part of 'album_page.dart';",
          reason: '$path must be included through album_page.dart',
        );
        expect(
          source,
          isNot(contains(RegExp(r'''^import\s+['"]''', multiLine: true))),
          reason: '$path should not declare imports as a part file',
        );
      }
    });

    test('split files are not imported as standalone libraries', () {
      final directImportPattern = RegExp(
        r'''import\s+['"][^'"]*album_page_(tag_browser|deferred_image)\.dart['"]''',
      );
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where(
            (file) => directImportPattern.hasMatch(file.readAsStringSync()),
          )
          .map((file) => file.path)
          .toList(growable: false);

      expect(
        offenders,
        isEmpty,
        reason: 'AlbumPage split files should only be referenced by part.',
      );
    });
  });
}
