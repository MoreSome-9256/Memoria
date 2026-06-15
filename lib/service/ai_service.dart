import 'package:flutter/foundation.dart';

import 'junk_photo_filter_service.dart';
import 'photo_service.dart';
import 'unified_analysis_progress_store.dart';

class AIService {
  AIService._internal();

  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;

  final ValueNotifier<JunkPhotoCleanupReport?> _junkCleanupReportNotifier =
      ValueNotifier<JunkPhotoCleanupReport?>(null);
  ValueListenable<JunkPhotoCleanupReport?> get junkCleanupReportListenable =>
      _junkCleanupReportNotifier;

  JunkPhotoCleanupReport? get latestJunkCleanupReport =>
      _junkCleanupReportNotifier.value;

  bool get isAnalyzing =>
      UnifiedAnalysisProgressStore.instance.progress.value.isRunning;

  void replacePendingJunkCleanupReport(JunkPhotoCleanupReport? report) {
    _junkCleanupReportNotifier.value = report;
  }

  void clearPendingJunkCleanupReport() {
    replacePendingJunkCleanupReport(null);
  }

  void unmarkJunkCandidatesAsKept(Iterable<int> photoIds) {
    final ids = photoIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) {
      return;
    }
    final current = latestJunkCleanupReport;
    if (current == null || current.candidates.isEmpty) {
      return;
    }
    final remaining = current.candidates
        .where((candidate) => !ids.contains(candidate.photoId))
        .toList(growable: false);
    replacePendingJunkCleanupReport(
      remaining.isEmpty
          ? null
          : JunkPhotoCleanupReport.fromCandidates(remaining),
    );
  }

  Future<JunkPhotoCleanupReport?> refreshJunkCleanupReportFromDatabase({
    bool replaceExisting = true,
  }) async {
    final current = latestJunkCleanupReport;
    if (!replaceExisting && current != null && current.hasCandidates) {
      return current;
    }

    final photos = await PhotoService().loadPendingJunkCandidatePhotos();
    if (photos.isEmpty) {
      clearPendingJunkCleanupReport();
      return null;
    }

    final candidates = photos
        .map(
          (photo) => JunkPhotoCleanupCandidate(
            photoId: photo.id,
            assetId: photo.assetId,
            path: photo.path,
            timestamp: photo.timestamp,
            reasons: const <JunkPhotoHit>[],
          ),
        )
        .toList(growable: false);

    final report = JunkPhotoCleanupReport.fromCandidates(candidates);
    if (!report.hasCandidates) {
      clearPendingJunkCleanupReport();
      return null;
    }
    replacePendingJunkCleanupReport(report);
    return report;
  }
}
