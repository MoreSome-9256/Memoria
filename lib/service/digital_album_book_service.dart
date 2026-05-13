/// 数字相册书服务，负责书页生成、编辑和持久化协调。

import 'dart:convert';

import '../models/entity/digital_album_book_entity.dart';
import '../models/vo/album_book_models.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';

class DigitalAlbumBookService {
  const DigitalAlbumBookService();

  Box<DigitalAlbumBookEntity> get _box =>
      ObjectBoxService().store.box<DigitalAlbumBookEntity>();

  Future<AlbumBookDocument?> loadByStoryId(int storyId) async {
    final q = _box.query(DigitalAlbumBookEntity_.storyId.equals(storyId)).build();
    final entity = q.findFirst();
    q.close();
    if (entity == null || entity.contentJson.trim().isEmpty) return null;
    final decoded = jsonDecode(entity.contentJson);
    if (decoded is! Map<String, dynamic>) return null;
    return AlbumBookDocument.fromJson(decoded);
  }

  Future<void> save({
    required int storyId,
    required AlbumBookDocument document,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final q = _box.query(DigitalAlbumBookEntity_.storyId.equals(storyId)).build();
    final existing = q.findFirst();
    q.close();

    final entity = existing ?? DigitalAlbumBookEntity();
    entity.storyId = storyId;
    entity.title = document.title;
    entity.subtitle = document.subtitle;
    entity.theme = document.theme;
    entity.pageWidth = document.pageWidth;
    entity.pageHeight = document.pageHeight;
    entity.spreadCount = document.spreads.length;
    entity.layoutSource = document.layoutSource;
    entity.contentJson = document.encodePretty();
    entity.updatedAt = now;
    entity.createdAt = existing?.createdAt ?? now;

    final store = ObjectBoxService().store;
    store.runInTransaction(TxMode.write, () => _box.put(entity));
  }

  Future<void> deleteByStoryId(int storyId) async {
    final q = _box.query(DigitalAlbumBookEntity_.storyId.equals(storyId)).build();
    final existing = q.findFirst();
    q.close();
    if (existing == null) return;
    final store = ObjectBoxService().store;
    store.runInTransaction(TxMode.write, () => _box.remove(existing.id));
  }
}
