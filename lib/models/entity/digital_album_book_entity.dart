import 'package:objectbox/objectbox.dart';

@Entity()
class DigitalAlbumBookEntity {
  @Id()
  int id = 0;

  @Index(unique: true, replace: true)
  late int storyId;

  late String title;
  late String subtitle;
  late String theme;
  late double pageWidth;
  late double pageHeight;
  late int spreadCount;
  late String layoutSource;
  late String contentJson;
  late int createdAt;
  late int updatedAt;
}
