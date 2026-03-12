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
    required this.sample,
    required this.adapterId,
    required this.displayName,
    required this.embedding,
    required this.preprocessMs,
    required this.inferenceMs,
    required this.tagRetrievalMs,
    required this.totalMs,
    required this.rssBeforeBytes,
    required this.rssAfterBytes,
    required this.tags,
  });

  final MobileClipBenchmarkSample sample;
  final String adapterId;
  final String displayName;
  final List<double> embedding;
  final double preprocessMs;
  final double inferenceMs;
  final double tagRetrievalMs;
  final double totalMs;
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
    required this.meanPreprocessMs,
    required this.meanInferenceMs,
    required this.meanTagRetrievalMs,
    required this.meanTotalMs,
    required this.p50TotalMs,
    required this.p90TotalMs,
    required this.maxTotalMs,
    required this.meanRssDeltaBytes,
  });

  final String adapterId;
  final String displayName;
  final int sampleCount;
  final double warmUpMs;
  final double meanPreprocessMs;
  final double meanInferenceMs;
  final double meanTagRetrievalMs;
  final double meanTotalMs;
  final double p50TotalMs;
  final double p90TotalMs;
  final double maxTotalMs;
  final double meanRssDeltaBytes;
}

class MobileClipWorstCaseSample {
  const MobileClipWorstCaseSample({
    required this.sample,
    required this.cosine,
    required this.l2Distance,
    required this.leftTags,
    required this.rightTags,
  });

  final MobileClipBenchmarkSample sample;
  final double cosine;
  final double l2Distance;
  final List<String> leftTags;
  final List<String> rightTags;
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
    required this.worstCases,
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
  final List<MobileClipWorstCaseSample> worstCases;
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