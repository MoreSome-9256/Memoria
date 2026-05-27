/// AI 分析主编排服务，协调照片处理、标签、向量、人脸和 OCR 流程。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/tag_taxonomy_v2.dart';
import '../models/entity/face_entity.dart';
import '../models/entity/photo_entity.dart';
import '../objectbox.g.dart';
import '../storage/objectbox/objectbox_service.dart';
import '../storage/vector_index/face_embedding_index_repository.dart';
import '../storage/vector_index/photo_embedding_index_repository.dart';
import '../storage/vector_index/vector_index_constants.dart';
import '../utils/ai_score_helper.dart';
import '../utils/face_crop_util.dart';
import '../utils/media_type_helper.dart';
import '../utils/ocr_policy.dart';
import '../utils/tag_sanitizer.dart';
import 'ai_background_task_service.dart';
import 'ai_progress_notification_service.dart';
import 'analysis_spool_progress_notifier.dart';
import 'analysis_spool_service.dart';
import 'app_ai_settings_service.dart';
import 'event_service.dart';
import 'face_embedding_service.dart';
import 'face_pipeline_service.dart';
import 'junk_photo_filter_service.dart';
import 'onnx_face_embedding_service.dart';
import 'media_access_grant_service.dart';
import 'mobileclip_backend_preference_service.dart';
import 'mobileclip_embedding_service.dart';
import 'mobileclip_tag_service.dart';
import 'ocr_service.dart';
import 'photo_caption_service.dart';
import 'photo_service.dart';

part 'ai_service_progress.dart';
part 'ai_service_input.dart';
part 'ai_service_auxiliary.dart';
part 'ai_service_models.dart';
part 'ai_service_profiler.dart';
part 'ai_service_lifecycle.dart';
part 'ai_service_pipeline.dart';
part 'ai_service_pipeline_runner.dart';
part 'ai_service_photo_processing.dart';
part 'ai_service_photo_processor.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal() {
    if (uiIntegrationEnabled) {
      _progressNotifier.addListener(_syncProgressNotification);
      AIProgressNotificationService().bindActionHandler(
        _handleForegroundAction,
      );
      _startRuntimeProgressPolling();
    }
  }

  static bool uiIntegrationEnabled = true;

  static const Set<String> _blockedVisualTags = <String>{
    'Screenshot',
    'Cool',
    'Glasses',
    'Goggles',
    'Selfie',
    '截图',
    '自拍',
  };
  static const ThumbnailSize _mobileClipThumbnailSize = ThumbnailSize.square(
    384,
  );
  static const String _analysisInputStrategyOverride = String.fromEnvironment(
    'AI_ANALYSIS_INPUT_STRATEGY',
    defaultValue: 'thumbnail_first',
  );
  static const String _analysisThumbnailTimeoutMsOverride =
      String.fromEnvironment(
        'AI_ANALYSIS_THUMBNAIL_TIMEOUT_MS',
        defaultValue: '120',
      );
  static const String _analysisAuxiliaryStrategyOverride =
      String.fromEnvironment(
        'AI_ANALYSIS_AUXILIARY_STRATEGY',
        defaultValue: 'always_compress',
      );
  static const int _minFaceDetectorInputSize = 32;
  static const String _autoResumeKey = 'ai_auto_resume';
  static const String _runtimeActiveKey = 'ai_runtime_active';
  static const String _runtimeHeartbeatAtKey = 'ai_runtime_heartbeat_at';
  static const String _runtimeTotalKey = 'ai_runtime_total';
  static const String _runtimeCompletedKey = 'ai_runtime_completed';
  static const String _runtimeFailedKey = 'ai_runtime_failed';
  static const String _runtimeStepKey = 'ai_runtime_step';
  static const String _runtimeElapsedMsKey = 'ai_runtime_elapsed_ms';
  static const String _runtimeWarmUpCompletedKey =
      'ai_runtime_warmup_completed';
  static const String _runtimeWarmUpTotalKey = 'ai_runtime_warmup_total';
  static const String _runtimePausedKey = 'ai_runtime_paused';
  static const String _runtimeStoppingKey = 'ai_runtime_stopping';
  static const String _manualStopPendingKey = 'ai_manual_stop_pending';

  final ValueNotifier<AIAnalysisProgress> _progressNotifier =
      ValueNotifier<AIAnalysisProgress>(AIAnalysisProgress.idle());
  final ValueNotifier<JunkPhotoCleanupReport?> _junkCleanupReportNotifier =
      ValueNotifier<JunkPhotoCleanupReport?>(null);
  final JunkPhotoFilterService _junkPhotoFilterService =
      JunkPhotoFilterService();
  final PhotoEmbeddingIndexRepository _photoEmbeddingIndexRepository =
      PhotoEmbeddingIndexRepository();
  final Set<int> _junkFilterBypassPhotoIds = <int>{};
  final Map<String, Future<SpoolConsumeReport>> _activeSpoolConsumes =
      <String, Future<SpoolConsumeReport>>{};
  static final _AnalysisInputConfig _analysisInputConfig =
      _AnalysisInputConfig.resolve(
        strategyLabel: _analysisInputStrategyOverride,
        thumbnailTimeoutMsLabel: _analysisThumbnailTimeoutMsOverride,
      );
  static final _AnalysisAuxiliaryConfig _analysisAuxiliaryConfig =
      _AnalysisAuxiliaryConfig.resolve(
        strategyLabel: _analysisAuxiliaryStrategyOverride,
      );

  bool _isAnalyzing = false;
  bool _pauseRequested = false;
  bool _stopRequested = false;
  int _inflightCount = 0;
  Completer<void>? _analysisCompleter;
  int _lastRuntimeHeartbeatPersistAtMs = 0;
  Timer? _runtimeProgressPoller;

  ValueListenable<AIAnalysisProgress> get progressListenable =>
      _progressNotifier;
  ValueListenable<JunkPhotoCleanupReport?> get junkCleanupReportListenable =>
      _junkCleanupReportNotifier;
  bool get isAnalyzing {
    final progress = _progressNotifier.value;
    return _isAnalyzing ||
        progress.isRunning ||
        progress.isPaused ||
        progress.isStopping;
  }

  JunkPhotoCleanupReport? get latestJunkCleanupReport =>
      _junkCleanupReportNotifier.value;
}
