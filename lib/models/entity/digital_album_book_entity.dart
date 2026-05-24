/// 数字相册书的 ObjectBox 实体，保存版式、内容和设计相关配置。

import 'package:objectbox/objectbox.dart';

@Entity()
class DigitalAlbumBookEntity {
  @Id()
  int id = 0;

  @Unique(onConflict: ConflictStrategy.replace)
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
