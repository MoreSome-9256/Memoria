class MobileClipBenchmarkSample {
  const MobileClipBenchmarkSample({
    required this.photoId,
    required this.assetId,
    required this.path,
    required this.timestamp,
  });

  final int photoId;
  final String assetId;
  final String path;
  final int timestamp;
}

class MobileClipAdapterRunResult {
  const MobileClipAdapterRunResult({
    required this.adapterId,
    required this.displayName,
    required this.embedding,
    required this.elapsedMs,
    required this.rssBeforeBytes,
    required this.rssAfterBytes,
    required this.tags,
  });

  final String adapterId;
  final String displayName;
  final List<double> embedding;
  final double elapsedMs;
  final int rssBeforeBytes;
  final int rssAfterBytes;
  final List<String> tags;

  int get rssDeltaBytes => rssAfterBytes - rssBeforeBytes;
}

class MobileClipAdapterSummary {
  const MobileClipAdapterSummary({
    required this.adapterId,
    required this.displayName,
    required this.sampleCount,
    required this.warmUpMs,
    required this.meanLatencyMs,
    required this.p50LatencyMs,
    required this.p90LatencyMs,
    required this.maxLatencyMs,
    required this.meanRssDeltaBytes,
  });

  final String adapterId;
  final String displayName;
  final int sampleCount;
  final double warmUpMs;
  final double meanLatencyMs;
  final double p50LatencyMs;
  final double p90LatencyMs;
  final double maxLatencyMs;
  final double meanRssDeltaBytes;
}

class MobileClipEmbeddingComparisonSummary {
  const MobileClipEmbeddingComparisonSummary({
    required this.leftAdapterId,
    required this.rightAdapterId,
    required this.sampleCount,
    required this.meanCosine,
    required this.minCosine,
    required this.maxCosine,
    required this.meanL2Distance,
    required this.top1AgreementRate,
    required this.top5OverlapRate,
  });

  final String leftAdapterId;
  final String rightAdapterId;
  final int sampleCount;
  final double meanCosine;
  final double minCosine;
  final double maxCosine;
  final double meanL2Distance;
  final double top1AgreementRate;
  final double top5OverlapRate;
}

class MobileClipBenchmarkReport {
  const MobileClipBenchmarkReport({
    required this.generatedAt,
    required this.sampleCount,
    required this.usesSharedPreprocessing,
    required this.adapterSummaries,
    required this.comparisons,
    required this.warnings,
  });

  final DateTime generatedAt;
  final int sampleCount;
  final bool usesSharedPreprocessing;
  final List<MobileClipAdapterSummary> adapterSummaries;
  final List<MobileClipEmbeddingComparisonSummary> comparisons;
  final List<String> warnings;
}