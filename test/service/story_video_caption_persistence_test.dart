import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/models/entity/story_entity.dart';

void main() {
  test('round-trips video captions by asset id including empty captions', () {
    final story = StoryEntity();
    story.setVideoCaptions(<String, String>{
      'asset-b': '第二张的字幕',
      'asset-a': '',
    });

    expect(story.videoCaptionByAssetId, <String, String>{
      'asset-b': '第二张的字幕',
      'asset-a': '',
    });
  });

  test('invalid legacy caption payload is treated as unavailable', () {
    final story = StoryEntity()..videoCaptionsJson = 'not-json';
    expect(story.videoCaptionByAssetId, isEmpty);
  });

  test('an explicitly empty caption does not fall back to story prose', () {
    expect(
      StoryEntity.resolveVideoCaption(
        captions: const <String, String>{'asset-a': ''},
        assetId: 'asset-a',
        fallback: '这是故事正文，不应该出现在字幕中',
      ),
      '',
    );
    expect(
      StoryEntity.resolveVideoCaption(
        captions: const <String, String>{},
        assetId: 'legacy-asset',
        fallback: '旧数据仍可使用故事正文兜底',
      ),
      '旧数据仍可使用故事正文兜底',
    );
  });
}
