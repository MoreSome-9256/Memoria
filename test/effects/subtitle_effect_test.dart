import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/effects/subtitle_effect.dart';

void main() {
  test('export typewriter always reveals the complete subtitle by 800ms', () {
    const textLength = 48;
    expect(
      SubtitleEffectLayer.deterministicVisibleCharacterCount(
        textLength: textLength,
        elapsedMs: 0,
      ),
      0,
    );
    expect(
      SubtitleEffectLayer.deterministicVisibleCharacterCount(
        textLength: textLength,
        elapsedMs: 800,
      ),
      textLength,
    );
    expect(
      SubtitleEffectLayer.deterministicVisibleCharacterCount(
        textLength: textLength,
        elapsedMs: 2800,
      ),
      textLength,
    );
  });
}
