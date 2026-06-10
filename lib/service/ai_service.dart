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

    final allAnalyzed = await PhotoService().loadAnalyzedPhotosForJunkScoring();
    final indexedEmbeddings = _embeddingIndex.readEmbeddingsForPhotos(
      allAnalyzed,
      modelVersion: buildPhotoEmbeddingModelVersion(),
    );
    final embeddings = <int, List<double>>{};
    for (final photo in allAnalyzed) {
      final embedding = photo.imageEmbedding ?? indexedEmbeddings[photo.id];
      if (embedding != null && embedding.isNotEmpty) {
        embeddings[photo.id] = embedding;
      }
    }
    final batch = await _junkPhotoFilterService.evaluateBatch(embeddings);
    final candidates = <JunkPhotoCleanupCandidate>[];
    final stalePendingPhotoIds = <int>[];
    for (final photo in photos) {
      final reasons = batch.decisionFor(photo.id).hits;
      if (reasons.isEmpty) {
        stalePendingPhotoIds.add(photo.id);
        continue;
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
    for (final photoId in stalePendingPhotoIds) {
      PhotoService().updatePhotoInTransaction(photoId, (photo) {
        if (photo == null) return;
        final tags = <String>{...?photo.aiTags}
          ..remove(JunkPhotoFilterService.pendingJunkCandidateTag);
        photo.aiTags = tags.toList(growable: false);
      });
    }

    final report = JunkPhotoCleanupReport.fromCandidates(candidates);
    if (!report.hasCandidates) {
      clearPendingJunkCleanupReport();
      return null;
    }
    replacePendingJunkCleanupReport(report);
    return report;
  }
}
