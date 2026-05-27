import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'litert_inference_service.dart';

class AppAiSettings {
  const AppAiSettings({
    required this.ocrEnabled,
    required this.faceAnalysisEnabled,
    required this.includeVideos,
    required this.mobileViClipEnabled,
    required this.androidForegroundServiceEnabled,
    required this.requestUnrestrictedBatteryEnabled,
    required this.iosContinuedProcessingEnabled,
    required this.inferenceAccelerator,
    required this.xnnpackThreadCount,
    required this.analysisBatchSize,
    required this.autoResumeAnalysis,
    required this.autoAnalyzeNewPhotos,
  });

  static const defaults = AppAiSettings(
    ocrEnabled: true,
    faceAnalysisEnabled: true,
    includeVideos: true,
    mobileViClipEnabled: true,
    androidForegroundServiceEnabled: true,
    requestUnrestrictedBatteryEnabled: true,
    iosContinuedProcessingEnabled: true,
    inferenceAccelerator: LocalInferenceAccelerator.xnnpack,
    xnnpackThreadCount: 2,
    analysisBatchSize: 1,
    autoResumeAnalysis: true,
    autoAnalyzeNewPhotos: true,
  );

  final bool ocrEnabled;
  final bool faceAnalysisEnabled;
  final bool includeVideos;
  final bool mobileViClipEnabled;
  final bool androidForegroundServiceEnabled;
  final bool requestUnrestrictedBatteryEnabled;
  final bool iosContinuedProcessingEnabled;
  final LocalInferenceAccelerator inferenceAccelerator;
  final int xnnpackThreadCount;

  /// AI model batch size. It no longer controls how many media items are
  /// submitted as one analysis task.
  final int analysisBatchSize;
  final bool autoResumeAnalysis;
  final bool autoAnalyzeNewPhotos;

  AppAiSettings copyWith({
    bool? ocrEnabled,
    bool? faceAnalysisEnabled,
    bool? includeVideos,
    bool? mobileViClipEnabled,
    bool? androidForegroundServiceEnabled,
    bool? requestUnrestrictedBatteryEnabled,
    bool? iosContinuedProcessingEnabled,
    LocalInferenceAccelerator? inferenceAccelerator,
    int? xnnpackThreadCount,
    int? analysisBatchSize,
    bool? autoResumeAnalysis,
    bool? autoAnalyzeNewPhotos,
  }) {
    return AppAiSettings(
      ocrEnabled: ocrEnabled ?? this.ocrEnabled,
      faceAnalysisEnabled: faceAnalysisEnabled ?? this.faceAnalysisEnabled,
      includeVideos: includeVideos ?? this.includeVideos,
      mobileViClipEnabled: mobileViClipEnabled ?? this.mobileViClipEnabled,
      androidForegroundServiceEnabled:
          androidForegroundServiceEnabled ??
          this.androidForegroundServiceEnabled,
      requestUnrestrictedBatteryEnabled:
          requestUnrestrictedBatteryEnabled ??
          this.requestUnrestrictedBatteryEnabled,
      iosContinuedProcessingEnabled:
          iosContinuedProcessingEnabled ?? this.iosContinuedProcessingEnabled,
      inferenceAccelerator: inferenceAccelerator ?? this.inferenceAccelerator,
      xnnpackThreadCount: xnnpackThreadCount ?? this.xnnpackThreadCount,
      analysisBatchSize: analysisBatchSize ?? this.analysisBatchSize,
      autoResumeAnalysis: autoResumeAnalysis ?? this.autoResumeAnalysis,
      autoAnalyzeNewPhotos: autoAnalyzeNewPhotos ?? this.autoAnalyzeNewPhotos,
    );
  }
}

class AppAiSettingsService {
  AppAiSettingsService._();
  static final AppAiSettingsService instance = AppAiSettingsService._();

  static const _ocrKey = 'ai_settings_ocr_enabled';
  static const _faceKey = 'ai_settings_face_enabled';
  static const _includeVideosKey = 'ai_settings_include_videos';
  static const _mobileViClipKey = 'ai_settings_mobileviclip_enabled';
  static const _localVlmDescriptionKey =
      'ai_settings_local_vlm_description_enabled';
  static const _androidForegroundServiceKey =
      'ai_settings_android_foreground_service_enabled';
  static const _requestUnrestrictedBatteryKey =
      'ai_settings_request_unrestricted_battery_enabled';
  static const _iosContinuedProcessingKey =
      'ai_settings_ios_continued_processing_enabled';
  static const _inferenceAcceleratorKey = 'ai_settings_inference_accelerator';
  static const _xnnpackThreadCountKey = 'ai_settings_xnnpack_thread_count';
  static const _analysisBatchSizeKey = 'ai_settings_analysis_batch_size';
  static const _modelBatchSizeKey = 'ai_settings_model_batch_size';
  static const _autoResumeKey = 'ai_settings_auto_resume';
  static const _autoAnalyzeNewKey = 'ai_settings_auto_analyze_new';

  final ValueNotifier<AppAiSettings> notifier = ValueNotifier<AppAiSettings>(
    AppAiSettings.defaults,
  );

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    if (_prefs != null) {
      return;
    }
    _prefs = await SharedPreferences.getInstance();
    notifier.value = _read();
  }

  Future<AppAiSettings> load() async {
    await initialize();
    return notifier.value;
  }

  Future<void> save(AppAiSettings settings) async {
    await initialize();
    final prefs = _prefs!;
    await prefs.setBool(_ocrKey, settings.ocrEnabled);
    await prefs.setBool(_faceKey, settings.faceAnalysisEnabled);
    await prefs.setBool(_includeVideosKey, settings.includeVideos);
    await prefs.setBool(_mobileViClipKey, settings.mobileViClipEnabled);
    await prefs.remove(_localVlmDescriptionKey);
    await prefs.setBool(
      _androidForegroundServiceKey,
      settings.androidForegroundServiceEnabled,
    );
    await prefs.setBool(
      _requestUnrestrictedBatteryKey,
      settings.requestUnrestrictedBatteryEnabled,
    );
    await prefs.setBool(
      _iosContinuedProcessingKey,
      settings.iosContinuedProcessingEnabled,
    );
    await prefs.setString(
      _inferenceAcceleratorKey,
      settings.inferenceAccelerator.storageValue,
    );
    await prefs.setInt(
      _xnnpackThreadCountKey,
      _normalizeXnnpackThreadCount(settings.xnnpackThreadCount),
    );
    await prefs.setInt(
      _modelBatchSizeKey,
      _normalizeModelBatchSize(settings.analysisBatchSize),
    );
    await prefs.remove(_analysisBatchSizeKey);
    await prefs.setBool(_autoResumeKey, settings.autoResumeAnalysis);
    await prefs.setBool(_autoAnalyzeNewKey, settings.autoAnalyzeNewPhotos);
    notifier.value = settings;
  }

  AppAiSettings _read() {
    final prefs = _prefs!;
    return AppAiSettings(
      ocrEnabled: prefs.getBool(_ocrKey) ?? AppAiSettings.defaults.ocrEnabled,
      faceAnalysisEnabled:
          prefs.getBool(_faceKey) ?? AppAiSettings.defaults.faceAnalysisEnabled,
      includeVideos:
          prefs.getBool(_includeVideosKey) ??
          AppAiSettings.defaults.includeVideos,
      mobileViClipEnabled:
          prefs.getBool(_mobileViClipKey) ??
          AppAiSettings.defaults.mobileViClipEnabled,
      androidForegroundServiceEnabled:
          prefs.getBool(_androidForegroundServiceKey) ??
          AppAiSettings.defaults.androidForegroundServiceEnabled,
      requestUnrestrictedBatteryEnabled:
          prefs.getBool(_requestUnrestrictedBatteryKey) ??
          AppAiSettings.defaults.requestUnrestrictedBatteryEnabled,
      iosContinuedProcessingEnabled:
          prefs.getBool(_iosContinuedProcessingKey) ??
          AppAiSettings.defaults.iosContinuedProcessingEnabled,
      inferenceAccelerator: _normalizeAcceleratorForPlatform(
        LocalInferenceAcceleratorX.fromStorageValue(
          prefs.getString(_inferenceAcceleratorKey),
        ),
      ),
      xnnpackThreadCount: _normalizeXnnpackThreadCount(
        prefs.getInt(_xnnpackThreadCountKey) ??
            AppAiSettings.defaults.xnnpackThreadCount,
      ),
      analysisBatchSize: _normalizeModelBatchSize(
        prefs.getInt(_modelBatchSizeKey) ??
            AppAiSettings.defaults.analysisBatchSize,
      ),
      autoResumeAnalysis:
          prefs.getBool(_autoResumeKey) ??
          AppAiSettings.defaults.autoResumeAnalysis,
      autoAnalyzeNewPhotos:
          prefs.getBool(_autoAnalyzeNewKey) ??
          AppAiSettings.defaults.autoAnalyzeNewPhotos,
    );
  }

  LocalInferenceAccelerator _normalizeAcceleratorForPlatform(
    LocalInferenceAccelerator accelerator,
  ) {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return switch (accelerator) {
        LocalInferenceAccelerator.gpu => LocalInferenceAccelerator.metal,
        LocalInferenceAccelerator.npu => LocalInferenceAccelerator.coreml,
        _ => accelerator,
      };
    }
    return accelerator;
  }

  static int _normalizeModelBatchSize(int value) {
    if (value < 1) return 1;
    if (value > 16) return 16;
    return value;
  }

  static int _normalizeXnnpackThreadCount(int value) {
    if (value < 1) return 1;
    if (value > 8) return 8;
    return value;
  }
}
