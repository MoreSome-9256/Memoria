/// AI 服务内部使用的模型定义，汇总分析流程中的共享数据结构。

part of 'ai_service.dart';

class _PreparedAnalysisInput {
  const _PreparedAnalysisInput({
    required this.photo,
    required this.file,
    required this.mobileClipBytes,
    required this.usedThumbnail,
    required this.inputSource,
    required this.inputStrategy,
    required this.thumbnailAttempted,
    required this.thumbnailTimedOut,
    required this.fallbackToOriginal,
    required this.fallbackReason,
    required this.loadMs,
    required this.thumbnailReadMs,
    required this.fileReadMs,
  });

  final PhotoEntity photo;
  final File file;
  final Uint8List mobileClipBytes;
  final bool usedThumbnail;
  final String inputSource;
  final String inputStrategy;
  final bool thumbnailAttempted;
  final bool thumbnailTimedOut;
  final bool fallbackToOriginal;
  final String fallbackReason;
  final double loadMs;
  final double thumbnailReadMs;
  final double fileReadMs;
}

class _AiPhotoProcessingRequest {
  const _AiPhotoProcessingRequest({
    required this.photo,
    required this.selectedBackend,
    required this.mobileClipEmbeddingService,
    required this.mobileClipTagService,
    required this.photoCaptionService,
    required this.facePipelineService,
    required this.ocrService,
    required this.faceDetector,
    required this.junkPhotoFilterService,
    required this.skipJunkFilter,
    required this.stopRequested,
  });

  final PhotoEntity photo;
  final MobileClipBackend selectedBackend;
  final MobileClipEmbeddingService mobileClipEmbeddingService;
  final MobileClipTagService mobileClipTagService;
  final PhotoCaptionService photoCaptionService;
  final FacePipelineService facePipelineService;
  final OcrService ocrService;
  final FaceDetector faceDetector;
  final JunkPhotoFilterService junkPhotoFilterService;
  final bool skipJunkFilter;
  final bool stopRequested;
}

class _AiPhotoWriteRequest {
  const _AiPhotoWriteRequest({
    required this.photoId,
    required this.tags,
    required this.imageEmbedding,
    required this.aiCaption,
    required this.ocrText,
    required this.ocrTags,
    required this.faceCount,
    required this.smileProb,
    required this.joyScore,
    required this.skipVectorIndexWrite,
  });

  final int photoId;
  final List<String> tags;
  final List<double> imageEmbedding;
  final String aiCaption;
  final String ocrText;
  final List<String> ocrTags;
  final int faceCount;
  final double smileProb;
  final double joyScore;
  final bool skipVectorIndexWrite;
}

class _PhotoProcessResult {
  const _PhotoProcessResult._({
    required this.didSucceed,
    required this.profile,
    this.eventId,
    this.junkCandidate,
    this.persistenceRequest,
    this.deferredCaptionTask,
  });

  const _PhotoProcessResult.success({
    int? eventId,
    JunkPhotoCleanupCandidate? junkCandidate,
    required _AiPhotoProfile profile,
    _AiPhotoWriteRequest? persistenceRequest,
    _AsyncCaptionTask? deferredCaptionTask,
  }) : this._(
         didSucceed: true,
         profile: profile,
         eventId: eventId,
         junkCandidate: junkCandidate,
         persistenceRequest: persistenceRequest,
         deferredCaptionTask: deferredCaptionTask,
       );

  const _PhotoProcessResult.failed({required _AiPhotoProfile profile})
    : this._(
        didSucceed: false,
        profile: profile,
        eventId: null,
        junkCandidate: null,
        persistenceRequest: null,
        deferredCaptionTask: null,
      );

  final bool didSucceed;
  final _AiPhotoProfile profile;
  final int? eventId;
  final JunkPhotoCleanupCandidate? junkCandidate;
  final _AiPhotoWriteRequest? persistenceRequest;
  final _AsyncCaptionTask? deferredCaptionTask;
}

class _AiPersistenceProfile {
  const _AiPersistenceProfile({
    required this.isarWriteMs,
    required this.objectBoxWriteMs,
  });

  final double isarWriteMs;
  final double objectBoxWriteMs;
}

class _AsyncCaptionTask {
  const _AsyncCaptionTask({
    required this.photoId,
    required this.imageFile,
    required this.deleteImageFileAfterUse,
    required this.captionService,
    required this.visualTags,
    required this.ocrTags,
    required this.ocrText,
    required this.location,
    required this.takenAt,
    required this.isProbablyScreenshot,
    required this.faceCount,
  });

  final int photoId;
  final File imageFile;
  final bool deleteImageFileAfterUse;
  final PhotoCaptionService captionService;
  final List<String> visualTags;
  final List<String> ocrTags;
  final String ocrText;
  final String? location;
  final DateTime takenAt;
  final bool isProbablyScreenshot;
  final int faceCount;
}

class _RuntimeSnapshot {
  const _RuntimeSnapshot({
    required this.isActive,
    required this.total,
    required this.completed,
    required this.failed,
  });

  final bool isActive;
  final int total;
  final int completed;
  final int failed;
}
