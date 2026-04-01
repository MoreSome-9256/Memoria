import 'package:isar/isar.dart';

part 'digital_album_book_entity.g.dart';

@Collection()
class DigitalAlbumBookEntity {
  Id id = Isar.autoIncrement;

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
