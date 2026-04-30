import 'dart:convert';

import 'package:isar/isar.dart';

import '../models/entity/digital_album_book_entity.dart';
import '../models/vo/album_book_models.dart';
import 'photo_service.dart';

class DigitalAlbumBookService {
  const DigitalAlbumBookService();

  Isar get _isar => PhotoService().isar;

  Future<AlbumBookDocument?> loadByStoryId(int storyId) async {
    final entity = await _isar
        .collection<DigitalAlbumBookEntity>()
        .filter()
        .storyIdEqualTo(storyId)
        .findFirst();
    if (entity == null || entity.contentJson.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(entity.contentJson);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return AlbumBookDocument.fromJson(decoded);
  }

  Future<void> save({
    required int storyId,
    required AlbumBookDocument document,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await _isar
        .collection<DigitalAlbumBookEntity>()
        .filter()
        .storyIdEqualTo(storyId)
        .findFirst();

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

    await _isar.writeTxn(() async {
      await _isar.collection<DigitalAlbumBookEntity>().put(entity);
    });
  }

  Future<void> deleteByStoryId(int storyId) async {
    final existing = await _isar
        .collection<DigitalAlbumBookEntity>()
        .filter()
        .storyIdEqualTo(storyId)
        .findFirst();
    if (existing == null) {
      return;
    }
    await _isar.writeTxn(() async {
      await _isar.collection<DigitalAlbumBookEntity>().delete(existing.id);
    });
  }
}
