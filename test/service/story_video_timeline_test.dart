import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/story_video_timeline.dart';

void main() {
  test('uses a fixed three-second window for every media section', () {
    expect(StoryVideoTimeline.durationMsForSections(0), 0);
    expect(StoryVideoTimeline.durationMsForSections(1), 3000);
    expect(StoryVideoTimeline.durationMsForSections(6), 18000);

    expect(StoryVideoTimeline.sectionIndexAt(timeMs: 2999, sectionCount: 3), 0);
    expect(StoryVideoTimeline.sectionIndexAt(timeMs: 3000, sectionCount: 3), 1);
    expect(
      StoryVideoTimeline.sectionIndexAt(timeMs: 999999, sectionCount: 3),
      2,
    );

    // Short fallback audio compresses every section equally instead of
    // dropping the tail of the story.
    expect(
      StoryVideoTimeline.sectionIndexAtDuration(
        timeMs: 2500,
        sectionCount: 6,
        durationMs: 15000,
      ),
      1,
    );
  });
}
