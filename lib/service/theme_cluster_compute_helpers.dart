/// 主题聚类计算辅助函数，提取共用的向量和评分计算逻辑。

import 'dart:math' as math;

import '../models/entity/photo_entity.dart';
import '../utils/ocr_policy.dart';

class ThemeClusterComputeHelpers {
  const ThemeClusterComputeHelpers._();

  static List<double> meanAndNormalize(List<List<double>> vectors) {
    if (vectors.isEmpty) {
      return const <double>[];
    }

    final dim = vectors.first.length;
    if (dim == 0 || vectors.any((vector) => vector.length != dim)) {
      return const <double>[];
    }

    final mean = List<double>.filled(dim, 0.0);
    for (final vector in vectors) {
      for (var i = 0; i < dim; i++) {
        mean[i] += vector[i];
      }
    }
    for (var i = 0; i < dim; i++) {
      mean[i] /= vectors.length;
    }

    final norm = math.sqrt(
      mean.fold<double>(0.0, (sum, value) => sum + value * value),
    );
    if (norm <= 0) {
      return mean;
    }
    return mean.map((value) => value / norm).toList(growable: false);
  }

  static double cosineSimilarity(List<double> left, List<double> right) {
    if (left.isEmpty || right.isEmpty || left.length != right.length) {
      return 0;
    }

    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;

    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftNorm += left[index] * left[index];
      rightNorm += right[index] * right[index];
    }

    if (leftNorm <= 0 || rightNorm <= 0) {
      return 0;
    }

    return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }

  static Set<String> buildTokenBag(PhotoEntity photo) {
    final tokens = <String>{};

    void addText(String? text) {
      final normalized = text?.trim().toLowerCase();
      if (normalized == null || normalized.isEmpty) {
        return;
      }
      tokens.add(normalized);
      for (final piece in normalized.split(
        RegExp(r'[\s,，。；：、|/\\()\[\]{}_-]+'),
      )) {
        final value = piece.trim();
        if (value.isNotEmpty) {
          tokens.add(value);
        }
      }
    }

    for (final tag in photo.aiTags ?? const <String>[]) {
      addText(tag);
    }
    for (final tag in OcrPolicy.effectiveTags(photo.ocrTags ?? const <String>[])) {
      addText(tag);
    }
    addText(OcrPolicy.effectiveText(photo.ocrText));
    addText(photo.locationName);
    addText(photo.district);
    addText(photo.city);

    return tokens;
  }
}
