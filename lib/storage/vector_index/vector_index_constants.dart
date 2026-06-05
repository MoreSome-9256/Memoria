// 向量索引相关常量，定义嵌入维度、模型版本和相似度参数。

const int kPhotoEmbeddingVectorDimensions = 512;
const int kFaceEmbeddingVectorDimensions = 512;

const String kPhotoEmbeddingModelFamily = 'mobileclip_image';
const String kMobileClip2S2EmbeddingModelVersion =
    '${kPhotoEmbeddingModelFamily}_mobileclip2_litert_fp32_split_v1';

String buildPhotoEmbeddingModelVersion([Object? _]) =>
    kMobileClip2S2EmbeddingModelVersion;

bool isPhotoEmbeddingModelVersion(String modelVersion) {
  return modelVersion.startsWith(kPhotoEmbeddingModelFamily);
}

bool isVideoEmbeddingModelVersion(String modelVersion) {
  return modelVersion == kMobileClip2S2EmbeddingModelVersion;
}
