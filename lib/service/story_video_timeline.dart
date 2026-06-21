/// Stable timing policy shared by story preview and export.
///
/// Music beats decorate the timeline; they never determine its length. This
/// prevents bad metadata or beat detection from stretching every media item.
class StoryVideoTimeline {
  static const int millisecondsPerSection = 3000;

  static int durationMsForSections(int sectionCount) {
    if (sectionCount <= 0) return 0;
    return sectionCount * millisecondsPerSection;
  }

  static int sectionIndexAt({
    required double timeMs,
    required int sectionCount,
  }) {
    if (sectionCount <= 1) return 0;
    return (timeMs ~/ millisecondsPerSection)
        .clamp(0, sectionCount - 1)
        .toInt();
  }

  /// Proportional mapping for preview when the available fallback audio is
  /// shorter than the planned timeline. Every section still gets equal time.
  static int sectionIndexAtDuration({
    required double timeMs,
    required int sectionCount,
    required int durationMs,
  }) {
    if (sectionCount <= 1 || durationMs <= 0) return 0;
    final progress = (timeMs / durationMs).clamp(0.0, 0.999999);
    return (progress * sectionCount).floor().clamp(0, sectionCount - 1).toInt();
  }
}
