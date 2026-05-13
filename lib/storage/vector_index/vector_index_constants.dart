/// 向量索引相关常量，定义嵌入维度、模型版本和相似度参数。

import '../../service/mobileclip_backend_preference_service.dart';

const int kPhotoEmbeddingVectorDimensions = 512;
const int kFaceEmbeddingVectorDimensions = 512;

const String kPhotoEmbeddingModelFamily = 'mobileclip_image';

String buildPhotoEmbeddingModelVersion(MobileClipBackend backend) {
  return '${kPhotoEmbeddingModelFamily}_${backend.storageValue}_v1';
}
