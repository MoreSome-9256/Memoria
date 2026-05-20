import 'package:objectbox/objectbox.dart';

enum MessageSender { user, ai }

@Entity()
class ChatMessage {
  ChatMessage({
    required this.text,
    required MessageSender sender,
    required DateTime timestamp,
    this.relatedPhotoPaths,
    this.searchTopic,
  })  : senderIndex = sender.index,
        timestampMs = timestamp.millisecondsSinceEpoch;

  @Id()
  int id = 0;

  @Index()
  int timestampMs;

  String text;

  int senderIndex;

  // 存本地路径 String 列表即可满足展示需求
  List<String>? relatedPhotoPaths;

  // 记录这批照片是由哪个搜索词触发的
  String? searchTopic;

  MessageSender get sender => MessageSender.values[senderIndex];

  set sender(MessageSender value) => senderIndex = value.index;

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);
}
