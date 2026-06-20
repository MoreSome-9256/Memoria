import '../models/entity/photo_entity.dart';
import '../utils/media_type_helper.dart';
import 'app_ai_settings_service.dart';
import 'junk_photo_filter_service.dart';

class SearchablePhotoPolicy {
  const SearchablePhotoPolicy._();

  static bool allows(PhotoEntity photo, {AppAiSettings? settings}) {
    final coreBoundary =
        photo.isAiAnalyzed &&
        !photo.isAiAnalysisCandidate &&
        !JunkPhotoFilterService.isQuarantined(photo.aiTags);
    if (!coreBoundary || settings == null) return coreBoundary;

    final kind = MediaTypeHelper.fromStorageValue(
      photo.mediaKind,
      path: photo.path,
    );
    if (kind != MemoriaMediaKind.image) return true;
    return photo.isCaptionAnalyzed &&
        (!settings.ocrEnabled || photo.isOcrAnalyzed) &&
        (!settings.faceAnalysisEnabled || photo.isFaceAnalyzed);
  }

  static List<PhotoEntity> filter(
    Iterable<PhotoEntity> photos, {
    AppAiSettings? settings,
  }) {
    return photos
        .where((photo) => allows(photo, settings: settings))
        .toList(growable: false);
  }
}
