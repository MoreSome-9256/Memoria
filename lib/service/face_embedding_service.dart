/// 人脸向量计算服务，负责从图片中提取脸部嵌入向量。

import 'dart:io';
import 'dart:typed_data';

const String kMobileClipFaceEmbeddingModelVersion =
    'mobileclip2_face_baseline_v1';
const String kUnavailableFaceEmbeddingModelVersion =
    'face_embedding_unavailable';

class FaceEmbeddingResult {
  const FaceEmbeddingResult({
    required this.embedding,
    required this.modelVersion,
  });

  final List<double> embedding;
  final String modelVersion;
}

abstract class FaceEmbeddingService {
  const FaceEmbeddingService();

  Future<void> warmUp();
  void resetWarmState();
  Future<FaceEmbeddingResult?> embedFaceCropBytes(Uint8List imageBytes);

  Future<FaceEmbeddingResult?> embedFaceCrop(File imageFile) async {
    if (!imageFile.existsSync()) {
      return null;
    }
    final bytes = await imageFile.readAsBytes();
    return embedFaceCropBytes(bytes);
  }
}
