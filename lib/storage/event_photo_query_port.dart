import '../models/entity/photo_entity.dart';

/// Query port for loading event photos without tying domain logic to a specific DB.
abstract class EventPhotoQueryPort {
  Future<List<PhotoEntity>> findPhotosByIdsSortedByTimestamp(List<int> ids);
}
