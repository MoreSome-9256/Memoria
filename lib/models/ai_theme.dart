/// AI 生成主题的轻量数据模型，保存标题、表情符号和相关标识信息。

class AITheme {
  final String id;
  final String emoji;
  final String title;
  final String subtitle;

  AITheme({
    required this.id,
    required this.emoji,
    required this.title,
    required this.subtitle,
  });
}
