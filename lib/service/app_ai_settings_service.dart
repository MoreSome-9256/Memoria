import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'litert_inference_service.dart';

class AppAiSettings {
  const AppAiSettings({
    required this.ocrEnabled,
    required this.faceAnalysisEnabled,
    required this.includeVideos,
    required this.mobileViClipEnabled,
    required this.localVlmDescriptionEnabled,
    required this.androidForegroundServiceEnabled,
    required this.requestUnrestrictedBatteryEnabled,
    required this.iosContinuedProcessingEnabled,
    required this.inferenceAccelerator,
    required this.autoResumeAnalysis,
    required this.autoAnalyzeNewPhotos,
  });

  static const defaults = AppAiSettings(
    ocrEnabled: false,
    faceAnalysisEnabled: false,
    includeVideos: false,
    mobileViClipEnabled: false,
    localVlmDescriptionEnabled: true,
    androidForegroundServiceEnabled: false,
    requestUnrestrictedBatteryEnabled: false,
    iosContinuedProcessingEnabled: false,
    inferenceAccelerator: LocalInferenceAccelerator.gpu,
    autoResumeAnalysis: false,
    autoAnalyzeNewPhotos: false,
  );

  final bool ocrEnabled;
  final bool faceAnalysisEnabled;
  final bool includeVideos;
  final bool mobileViClipEnabled;
  final bool localVlmDescriptionEnabled;
  final bool androidForegroundServiceEnabled;
  final bool requestUnrestrictedBatteryEnabled;
  final bool iosContinuedProcessingEnabled;
  final LocalInferenceAccelerator inferenceAccelerator;
  final bool autoResumeAnalysis;
  final bool autoAnalyzeNewPhotos;

  AppAiSettings copyWith({
    bool? ocrEnabled,
    bool? faceAnalysisEnabled,
    bool? includeVideos,
    bool? mobileViClipEnabled,
    bool? localVlmDescriptionEnabled,
    bool? androidForegroundServiceEnabled,
    bool? requestUnrestrictedBatteryEnabled,
    bool? iosContinuedProcessingEnabled,
    LocalInferenceAccelerator? inferenceAccelerator,
    bool? autoResumeAnalysis,
    bool? autoAnalyzeNewPhotos,
  }) {
    return AppAiSettings(
      ocrEnabled: ocrEnabled ?? this.ocrEnabled,
      faceAnalysisEnabled: faceAnalysisEnabled ?? this.faceAnalysisEnabled,
      includeVideos: includeVideos ?? this.includeVideos,
      mobileViClipEnabled: mobileViClipEnabled ?? this.mobileViClipEnabled,
      localVlmDescriptionEnabled:
          localVlmDescriptionEnabled ?? this.localVlmDescriptionEnabled,
      androidForegroundServiceEnabled:
          androidForegroundServiceEnabled ??
          this.androidForegroundServiceEnabled,
      requestUnrestrictedBatteryEnabled:
          requestUnrestrictedBatteryEnabled ??
          this.requestUnrestrictedBatteryEnabled,
      iosContinuedProcessingEnabled:
          iosContinuedProcessingEnabled ?? this.iosContinuedProcessingEnabled,
      inferenceAccelerator: inferenceAccelerator ?? this.inferenceAccelerator,
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
    await prefs.setBool(
      _localVlmDescriptionKey,
      settings.localVlmDescriptionEnabled,
    );
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
      localVlmDescriptionEnabled:
          prefs.getBool(_localVlmDescriptionKey) ??
          AppAiSettings.defaults.localVlmDescriptionEnabled,
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
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS)) {
      return switch (accelerator) {
        LocalInferenceAccelerator.gpu => LocalInferenceAccelerator.metal,
        LocalInferenceAccelerator.npu => LocalInferenceAccelerator.coreml,
        _ => accelerator,
      };
    }
    return accelerator;
  }
}
