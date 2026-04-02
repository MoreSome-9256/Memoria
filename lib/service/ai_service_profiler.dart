part of 'ai_service.dart';

class _AiPhotoProfile {
  _AiPhotoProfile({required this.photoId, required this.backendLabel});

  final int photoId;
  final String backendLabel;

  String providerLabel = '';
  String outcome = 'unknown';
  String? error;
  String inputSource = 'unknown';
  String inputStrategy = 'thumbnail_first';
  bool usedThumbnail = false;
  bool thumbnailAttempted = false;
  bool thumbnailTimedOut = false;
  bool fallbackToOriginal = false;
  String fallbackReason = 'none';
  String auxiliaryStrategy = 'always_compress';
  String auxiliarySource = 'unknown';
  bool auxiliaryCreated = false;
  bool embeddingCacheHit = false;
  bool captionDeferred = false;
  int inputBytes = 0;
  double inputLoadMs = 0;
  double thumbnailReadMs = 0;
  double fileReadMs = 0;
  double decodeMs = 0;
  double resizeNormalizeMs = 0;
  double tensorBuildMs = 0;
  double inferenceMs = 0;
  double objectBoxWriteMs = 0;
  double junkFilterMs = 0;
  double tagRetrievalMs = 0;
  double auxiliaryFileMs = 0;
  double ocrMs = 0;
  double analysisDecodeMs = 0;
  double faceDetectionMs = 0;
  double facePersistMs = 0;
  double faceExistingReadMs = 0;
  double faceSourceDecodeMs = 0;
  double faceWarmUpMs = 0;
  double faceCropMs = 0;
  double faceDebugCropMs = 0;
  double faceTempFileMs = 0;
  double faceEmbeddingMs = 0;
  double faceIsarWriteMs = 0;
  double faceObjectBoxWriteMs = 0;
  double faceCleanupMs = 0;
  int faceRequestedCount = 0;
  int facePersistedCount = 0;
  double captionMs = 0;
  double isarWriteMs = 0;
  double wallMs = 0;

  double get measuredMs =>
      inputLoadMs +
      decodeMs +
      resizeNormalizeMs +
      tensorBuildMs +
      inferenceMs +
      objectBoxWriteMs +
      junkFilterMs +
      tagRetrievalMs +
      auxiliaryFileMs +
      ocrMs +
      analysisDecodeMs +
      faceDetectionMs +
      facePersistMs +
      captionMs +
      isarWriteMs;

  double get totalMs => wallMs > 0 ? wallMs : measuredMs;

  String toLogLine() {
    final provider = providerLabel.isEmpty ? backendLabel : providerLabel;
    final suffix = error == null ? '' : ' error=$error';
    return 'AI profile photoId=$photoId outcome=$outcome strategy=$inputStrategy '
        'input=$inputSource thumb=$usedThumbnail '
        'thumbAttempted=$thumbnailAttempted thumbTimedOut=$thumbnailTimedOut '
        'fallback=$fallbackToOriginal fallbackReason=$fallbackReason '
        'auxStrategy=$auxiliaryStrategy auxSource=$auxiliarySource '
        'auxCreated=$auxiliaryCreated '
        'cacheHit=$embeddingCacheHit '
        'captionDeferred=$captionDeferred backend="$provider" '
        'bytes=$inputBytes loadMs=${_fmt(inputLoadMs)} '
        'thumbReadMs=${_fmt(thumbnailReadMs)} fileReadMs=${_fmt(fileReadMs)} '
        'decodeMs=${_fmt(decodeMs)} resizeNormMs=${_fmt(resizeNormalizeMs)} '
        'tensorMs=${_fmt(tensorBuildMs)} inferenceMs=${_fmt(inferenceMs)} '
        'junkMs=${_fmt(junkFilterMs)} tagMs=${_fmt(tagRetrievalMs)} '
        'auxMs=${_fmt(auxiliaryFileMs)} ocrMs=${_fmt(ocrMs)} '
        'analysisDecodeMs=${_fmt(analysisDecodeMs)} '
        'faceMs=${_fmt(faceDetectionMs)} faceStoreMs=${_fmt(facePersistMs)} '
        'faceReq=$faceRequestedCount faceOut=$facePersistedCount '
        'faceReadMs=${_fmt(faceExistingReadMs)} '
        'faceDecodeSrcMs=${_fmt(faceSourceDecodeMs)} '
        'faceWarmMs=${_fmt(faceWarmUpMs)} '
        'faceCropMs=${_fmt(faceCropMs)} '
        'faceTempMs=${_fmt(faceTempFileMs)} '
        'faceEmbedMs=${_fmt(faceEmbeddingMs)} '
        'faceStoreIsarMs=${_fmt(faceIsarWriteMs)} '
        'faceStoreObxMs=${_fmt(faceObjectBoxWriteMs)} '
        'faceCleanupMs=${_fmt(faceCleanupMs)} '
        'captionMs=${_fmt(captionMs)} isarMs=${_fmt(isarWriteMs)} '
        'objectBoxMs=${_fmt(objectBoxWriteMs)} wallMs=${_fmt(totalMs)}$suffix';
  }

  static String _fmt(double value) =>
      value.toStringAsFixed(value >= 100 ? 0 : 1);
}

class _AiPipelineRunProfiler {
  _AiPipelineRunProfiler({this.summaryEvery = 8});

  final int summaryEvery;
  final List<_AiPhotoProfile> _profiles = <_AiPhotoProfile>[];
  int _pendingFetchBatches = 0;
  int _pendingFetchCandidates = 0;
  int _pendingFetchScheduled = 0;
  double _pendingFetchMs = 0;

  void recordPendingFetch({
    required double fetchMs,
    required int fetchedCandidates,
    required int scheduledPhotos,
  }) {
    _pendingFetchBatches++;
    _pendingFetchMs += fetchMs;
    _pendingFetchCandidates += fetchedCandidates;
    _pendingFetchScheduled += scheduledPhotos;
  }

  void recordPhoto(_AiPhotoProfile profile) {
    _profiles.add(profile);
    debugPrint(profile.toLogLine());
    if (_profiles.length % summaryEvery == 0) {
      debugPrint(
        _buildSummaryLine(
          label: 'rolling',
          profiles: _profiles,
          includeQueueMetrics: true,
        ),
      );
    }
  }

  void logFinalSummary() {
    if (_profiles.isEmpty && _pendingFetchBatches == 0) {
      return;
    }
    debugPrint(
      _buildSummaryLine(
        label: 'final',
        profiles: _profiles,
        includeQueueMetrics: true,
      ),
    );

    final completedOnly = _profiles
        .where((profile) => profile.outcome == 'completed')
        .toList(growable: false);
    if (completedOnly.isNotEmpty) {
      debugPrint(
        _buildSummaryLine(
          label: 'final.completed-only',
          profiles: completedOnly,
          includeQueueMetrics: false,
        ),
      );
    }

    final cacheMissOnly = _profiles
        .where((profile) => !profile.embeddingCacheHit)
        .toList(growable: false);
    if (cacheMissOnly.isNotEmpty) {
      debugPrint(
        _buildSummaryLine(
          label: 'final.cache-miss-only',
          profiles: cacheMissOnly,
          includeQueueMetrics: false,
        ),
      );
    }
  }

  String _buildSummaryLine({
    required String label,
    required List<_AiPhotoProfile> profiles,
    required bool includeQueueMetrics,
  }) {
    final count = profiles.isEmpty ? 1 : profiles.length;
    final pendingCount = _pendingFetchBatches == 0 ? 1 : _pendingFetchBatches;
    final completedCount = profiles
        .where((profile) => profile.outcome == 'completed')
        .length;
    final junkCount = profiles
        .where((profile) => profile.outcome == 'junk_filtered')
        .length;
    final failedCount = profiles.length - completedCount - junkCount;
    final captionDeferredCount = profiles
        .where((profile) => profile.captionDeferred)
        .length;
    final thumbnailAttemptedCount = profiles
        .where((profile) => profile.thumbnailAttempted)
        .length;
    final thumbnailTimedOutCount = profiles
        .where((profile) => profile.thumbnailTimedOut)
        .length;
    final fallbackToOriginalCount = profiles
        .where((profile) => profile.fallbackToOriginal)
        .length;
    final auxiliaryCreatedCount = profiles
        .where((profile) => profile.auxiliaryCreated)
        .length;
    final wallValues = profiles
        .map((profile) => profile.totalMs)
        .toList(growable: false);
    final strategyMix = _buildBreakdown(
      profiles.map((profile) => profile.inputStrategy),
    );
    final fallbackMix = _buildBreakdown(
      profiles
          .where((profile) => profile.fallbackReason != 'none')
          .map((profile) => profile.fallbackReason),
    );
    final auxiliaryStrategyMix = _buildBreakdown(
      profiles.map((profile) => profile.auxiliaryStrategy),
    );
    final auxiliarySourceMix = _buildBreakdown(
      profiles.map((profile) => profile.auxiliarySource),
    );
    final queuePrefix = includeQueueMetrics
        ? 'queueFetchAvgMs=${_fmt(_pendingFetchMs / pendingCount)} '
              'queueCandidatesAvg=${(_pendingFetchCandidates / pendingCount).toStringAsFixed(1)} '
              'queueScheduledAvg=${(_pendingFetchScheduled / pendingCount).toStringAsFixed(1)} '
        : '';
    return 'AI profile summary[$label] samples=${profiles.length} '
        'completed=$completedCount junk=$junkCount failed=$failedCount '
        'captionDeferred=$captionDeferredCount '
        'strategyMix=$strategyMix thumbAttempted=$thumbnailAttemptedCount '
        'thumbTimedOut=$thumbnailTimedOutCount '
        'fallbackToOriginal=$fallbackToOriginalCount '
        'fallbackMix=$fallbackMix '
        'auxStrategyMix=$auxiliaryStrategyMix '
        'auxSourceMix=$auxiliarySourceMix '
        'auxCreated=$auxiliaryCreatedCount '
        '$queuePrefix'
        'loadAvgMs=${_avg(profiles, (profile) => profile.inputLoadMs, count)} '
        'decodeAvgMs=${_avg(profiles, (profile) => profile.decodeMs, count)} '
        'resizeNormAvgMs=${_avg(profiles, (profile) => profile.resizeNormalizeMs, count)} '
        'tensorAvgMs=${_avg(profiles, (profile) => profile.tensorBuildMs, count)} '
        'inferenceAvgMs=${_avg(profiles, (profile) => profile.inferenceMs, count)} '
        'junkAvgMs=${_avg(profiles, (profile) => profile.junkFilterMs, count)} '
        'tagAvgMs=${_avg(profiles, (profile) => profile.tagRetrievalMs, count)} '
        'auxAvgMs=${_avg(profiles, (profile) => profile.auxiliaryFileMs, count)} '
        'ocrAvgMs=${_avg(profiles, (profile) => profile.ocrMs, count)} '
        'analysisDecodeAvgMs=${_avg(profiles, (profile) => profile.analysisDecodeMs, count)} '
        'faceAvgMs=${_avg(profiles, (profile) => profile.faceDetectionMs, count)} '
        'faceStoreAvgMs=${_avg(profiles, (profile) => profile.facePersistMs, count)} '
        'faceReadAvgMs=${_avg(profiles, (profile) => profile.faceExistingReadMs, count)} '
        'faceDecodeSrcAvgMs=${_avg(profiles, (profile) => profile.faceSourceDecodeMs, count)} '
        'faceWarmAvgMs=${_avg(profiles, (profile) => profile.faceWarmUpMs, count)} '
        'faceCropAvgMs=${_avg(profiles, (profile) => profile.faceCropMs, count)} '
        'faceTempAvgMs=${_avg(profiles, (profile) => profile.faceTempFileMs, count)} '
        'faceEmbedAvgMs=${_avg(profiles, (profile) => profile.faceEmbeddingMs, count)} '
        'faceStoreIsarAvgMs=${_avg(profiles, (profile) => profile.faceIsarWriteMs, count)} '
        'faceStoreObxAvgMs=${_avg(profiles, (profile) => profile.faceObjectBoxWriteMs, count)} '
        'faceCleanupAvgMs=${_avg(profiles, (profile) => profile.faceCleanupMs, count)} '
        'captionAvgMs=${_avg(profiles, (profile) => profile.captionMs, count)} '
        'isarAvgMs=${_avg(profiles, (profile) => profile.isarWriteMs, count)} '
        'objectBoxAvgMs=${_avg(profiles, (profile) => profile.objectBoxWriteMs, count)} '
        'wallAvgMs=${_avg(profiles, (profile) => profile.totalMs, count)} '
        'wallP50Ms=${_fmt(_percentile(wallValues, 0.5))} '
        'wallP90Ms=${_fmt(_percentile(wallValues, 0.9))}';
  }

  String _avg(
    List<_AiPhotoProfile> profiles,
    double Function(_AiPhotoProfile profile) selector,
    int count,
  ) {
    final total = profiles.fold<double>(
      0.0,
      (sum, profile) => sum + selector(profile),
    );
    return _fmt(total / count);
  }

  double _percentile(List<double> values, double percentile) {
    if (values.isEmpty) {
      return 0.0;
    }
    final sorted = List<double>.from(values)..sort();
    final index = ((sorted.length - 1) * percentile).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  String _buildBreakdown(Iterable<String> values) {
    final counts = <String, int>{};
    for (final rawValue in values) {
      final value = rawValue.isEmpty ? 'unknown' : rawValue;
      counts[value] = (counts[value] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      return 'none';
    }
    final entries = counts.entries.toList(growable: false)
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries.map((entry) => '${entry.key}:${entry.value}').join(',');
  }

  static String _fmt(double value) =>
      value.toStringAsFixed(value >= 100 ? 0 : 1);
}
