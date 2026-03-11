import 'package:isar/isar.dart';

import '../models/entity/photo_entity.dart';
import 'event_photo_query_port.dart';

class IsarEventPhotoQueryPort implements EventPhotoQueryPort {
  IsarEventPhotoQueryPort(this._isar);

  final Isar _isar;

  @override
  Future<List<PhotoEntity>> findPhotosByIdsSortedByTimestamp(
    List<int> ids,
  ) async {
    if (ids.isEmpty) {
      return const <PhotoEntity>[];
    }

    return _isar
        .collection<PhotoEntity>()
        .where()
        .anyOf(ids, (q, id) => q.idEqualTo(id))
        .sortByTimestamp()
        .findAll();
  }
}
