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
  final JunkPhotoFilterService _junkPhotoFilterService =
      JunkPhotoFilterService();

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

    final candidates = <JunkPhotoCleanupCandidate>[];
    final recoveredReasonTagsByPhotoId = <int, List<String>>{};
    for (final photo in photos) {
      var reasons = JunkPhotoFilterService.hitsFromTags(
        photo.aiTags ?? const <String>[],
      );
      if (reasons.isEmpty && (photo.imageEmbedding?.isNotEmpty ?? false)) {
        final decision = await _junkPhotoFilterService.evaluatePhoto(
          imageEmbedding: photo.imageEmbedding!,
        );
        reasons = decision.hits;
        final reasonTags = JunkPhotoFilterService.reasonTagsForHits(reasons);
        if (reasonTags.isNotEmpty) {
          recoveredReasonTagsByPhotoId[photo.id] = reasonTags;
        }
      }
      candidates.add(
        JunkPhotoCleanupCandidate(
          photoId: photo.id,
          assetId: photo.assetId,
          path: photo.path,
          timestamp: photo.timestamp,
          reasons: reasons,
        ),
      );
    }

    if (recoveredReasonTagsByPhotoId.isNotEmpty) {
      for (final entry in recoveredReasonTagsByPhotoId.entries) {
        PhotoService().updatePhotoInTransaction(entry.key, (photo) {
          if (photo == null) return;
          final tags = <String>{...?photo.aiTags, ...entry.value};
          photo.aiTags = tags.toList(growable: false);
        });
      }
    }

    final report = JunkPhotoCleanupReport.fromCandidates(candidates);
    replacePendingJunkCleanupReport(report);
    return report;
  }
}
