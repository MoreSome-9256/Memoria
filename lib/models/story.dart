import 'vo/photo.dart';

class StoryBlock {
  final String text;
  final Photo? photo;

  StoryBlock({required this.text, this.photo});
}

class Story {
  final String id;
  final String title;
  final String subtitle;
  final Photo heroImage;
  final List<StoryBlock> blocks;
  final DateTime createdAt;
  final String eventId;

  Story({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.heroImage,
    required this.blocks,
    required this.createdAt,
    required this.eventId,
  });
}
