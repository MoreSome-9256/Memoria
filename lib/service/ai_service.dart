import 'package:flutter/foundation.dart';

import 'junk_photo_filter_service.dart';
import 'photo_service.dart';
import 'unified_analysis_progress_store.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../storage/vector_index/vector_index_constants.dart';

class AIService {
  AIService._internal();

  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;

  final ValueNotifier<JunkPhotoCleanupReport?> _junkCleanupReportNotifier =
      ValueNotifier<JunkPhotoCleanupReport?>(null);
  final JunkPhotoFilterService _junkPhotoFilterService =
      JunkPhotoFilterService();
  final PhotoEmbeddingIndexRepository _embeddingIndex =
      PhotoEmbeddingIndexRepository();

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
    for (final photo in photos) {
      final embedding =
          photo.imageEmbedding ??
          _embeddingIndex.readEmbeddingForPhoto(
            photo,
            modelVersion: buildPhotoEmbeddingModelVersion(),
          );
      final reasons = embedding == null || embedding.isEmpty
          ? const <JunkPhotoHit>[]
          : (await _junkPhotoFilterService.evaluatePhoto(
              imageEmbedding: embedding,
            )).hits;
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

    final report = JunkPhotoCleanupReport.fromCandidates(candidates);
    replacePendingJunkCleanupReport(report);
    return report;
  }
}
