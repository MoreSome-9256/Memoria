import 'package:isar/isar.dart';

// 必须加上这行，稍后用 build_runner 生成
part 'chat_message.g.dart';

enum MessageSender { user, ai }

@collection
class ChatMessage {
  Id id = Isar.autoIncrement;

  @Index()
  final DateTime timestamp;

  final String text;

  @enumerated
  final MessageSender sender;

  // Isar 不支持直接存复杂对象列表，存本地路径(String)最完美
  final List<String>? relatedPhotoPaths;

  // 记录这批照片是由哪个搜索词触发的
  final String? searchTopic;

  ChatMessage({
    required this.text,
    required this.sender,
    required this.timestamp,
    this.relatedPhotoPaths,
    this.searchTopic,
  });
}
