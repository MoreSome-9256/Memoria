import 'package:objectbox/objectbox.dart';

enum MessageSender { user, ai }

@Entity()
class ChatMessage {
  ChatMessage({
    this.id = 0,
    required this.text,
    required this.senderIndex,
    required this.timestampMs,
    this.relatedPhotoPaths,
    this.searchTopic,
  });

  factory ChatMessage.create({
    required String text,
    required MessageSender sender,
    required DateTime timestamp,
    List<String>? relatedPhotoPaths,
    String? searchTopic,
  }) {
    return ChatMessage(
      text: text,
      senderIndex: sender.index,
      timestampMs: timestamp.millisecondsSinceEpoch,
      relatedPhotoPaths: relatedPhotoPaths,
      searchTopic: searchTopic,
    );
  }

  @Id()
  int id;

  @Index()
  int timestampMs;

  String text;

  int senderIndex;

  // 存本地路径 String 列表即可满足展示需求
  List<String>? relatedPhotoPaths;

  // 记录这批照片是由哪个搜索词触发的
  String? searchTopic;

  @Transient()
  MessageSender get sender => MessageSender.values[senderIndex];

  set sender(MessageSender value) => senderIndex = value.index;

  @Transient()
  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);

  set timestamp(DateTime value) => timestampMs = value.millisecondsSinceEpoch;
}
