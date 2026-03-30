import '../../service/mobileclip_backend_preference_service.dart';

const int kPhotoEmbeddingVectorDimensions = 512;
const int kFaceEmbeddingVectorDimensions = 512;

const String kPhotoEmbeddingModelFamily = 'mobileclip_image';

String buildPhotoEmbeddingModelVersion(MobileClipBackend backend) {
  return '${kPhotoEmbeddingModelFamily}_${backend.storageValue}_v1';
}
