class AIScoreHelper {
  const AIScoreHelper._();

  static const _joyfulTags = {'美食', '日落', '日出', '花朵', '宠物', '猫', '狗'};

  static double calculateJoyScore({
    required int faceCount,
    required double maxSmileProb,
    required List<String> tags,
  }) {
    if (faceCount > 0 && maxSmileProb > 0) {
      return maxSmileProb;
    }

    final hasJoyfulTag = tags.any(_joyfulTags.contains);
    if (hasJoyfulTag) {
      return 0.5;
    }

    return 0.0;
  }
}
