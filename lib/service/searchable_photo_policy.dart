import '../models/entity/photo_entity.dart';
import 'junk_photo_filter_service.dart';

class SearchablePhotoPolicy {
  const SearchablePhotoPolicy._();

  static bool allows(PhotoEntity photo) {
    return photo.isAiAnalyzed &&
        !photo.isAiAnalysisCandidate &&
        !JunkPhotoFilterService.isQuarantined(photo.aiTags);
  }

  static List<PhotoEntity> filter(Iterable<PhotoEntity> photos) {
    return photos.where(allows).toList(growable: false);
  }
}
