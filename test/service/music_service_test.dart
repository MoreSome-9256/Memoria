import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/music_service.dart';

void main() {
  test('rejects non-positive tempo without looping', () {
    expect(
      MusicService.normalizeAnalysis(<String, dynamic>{
        'bpm': -1,
        'data': const <dynamic>[],
      }),
      isNull,
    );
  });

  test('normalizes tempo and rejects invalid beat points', () {
    final result = MusicService.normalizeAnalysis(<String, dynamic>{
      'bpm': 240,
      'duration_ms': 2000,
      'data': <dynamic>[
        <String, dynamic>{'ms': 1000, 'energy': 2},
        <String, dynamic>{'ms': -1, 'energy': 1},
        <String, dynamic>{'ms': 500, 'energy': -2},
        <String, dynamic>{'ms': 500, 'energy': 0.7},
        <String, dynamic>{'ms': 3000, 'energy': 1},
      ],
    });

    expect(result, isNotNull);
    expect(result!['bpm'], 120.0);
    expect(result['data'], <Map<String, dynamic>>[
      <String, dynamic>{'ms': 500, 'energy': 0.0},
      <String, dynamic>{'ms': 1000, 'energy': 1.0},
    ]);
  });

  test('synthesizes beats when analyzer returns no usable timeline', () {
    final result = MusicService.normalizeAnalysis(<String, dynamic>{
      'bpm': 120,
      'duration_ms': 1200,
      'data': const <dynamic>[],
    });

    expect(result!['data'], <Map<String, dynamic>>[
      <String, dynamic>{'ms': 0, 'energy': 0.2},
      <String, dynamic>{'ms': 500, 'energy': 0.2},
      <String, dynamic>{'ms': 1000, 'energy': 0.2},
    ]);
  });
}
