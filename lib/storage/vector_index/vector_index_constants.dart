// 向量索引相关常量，定义嵌入维度、模型版本和相似度参数。

import '../../service/mobileclip_backend_preference_service.dart';

const int kPhotoEmbeddingVectorDimensions = 512;
const int kFaceEmbeddingVectorDimensions = 512;

const String kPhotoEmbeddingModelFamily = 'mobileclip_image';
const String kVideoEmbeddingModelFamily = 'mobileviclip_video';
const String kMobileViClipSmallVideoEmbeddingModelVersion =
    '${kVideoEmbeddingModelFamily}_small_onnx_v1';

String buildPhotoEmbeddingModelVersion(MobileClipBackend backend) {
  if (backend == MobileClipBackend.ncnn) {
    return '${kPhotoEmbeddingModelFamily}_ncnn_v1';
  }
  return '${kPhotoEmbeddingModelFamily}_${backend.storageValue}_fp32_split_v1';
}

bool isPhotoEmbeddingModelVersion(String modelVersion) {
  return modelVersion.startsWith(kPhotoEmbeddingModelFamily);
}

bool isVideoEmbeddingModelVersion(String modelVersion) {
  return modelVersion.startsWith(kVideoEmbeddingModelFamily) ||
      modelVersion == 'mobileviclip_small_onnx_video_v1';
}
