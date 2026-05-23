import 'package:shared_preferences/shared_preferences.dart';

class AiSettingsService {
  AiSettingsService._internal();

  static final AiSettingsService _instance = AiSettingsService._internal();
  factory AiSettingsService() => _instance;

  static const String _ocrEnabledKey = 'ai_ocr_enabled';
  static const String _faceDetectionEnabledKey = 'ai_face_detection_enabled';
  static const String _faceDebugCropsKey = 'ai_face_debug_crops';
  static const String _faceWriteEmbeddingKey = 'ai_face_write_embedding';
  static const String _autoResumeKey = 'ai_auto_resume';

  Future<bool> isOcrEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_ocrEnabledKey) ?? false;
  }

  Future<void> setOcrEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ocrEnabledKey, enabled);
  }

  Future<bool> isFaceDetectionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_faceDetectionEnabledKey) ?? false;
  }

  Future<void> setFaceDetectionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_faceDetectionEnabledKey, enabled);
  }

  Future<bool> isAutoResumeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoResumeKey) ?? false;
  }

  Future<void> setAutoResumeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoResumeKey, enabled);
  }

  Future<bool> isDebugCropsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_faceDebugCropsKey) ?? false;
  }

  Future<void> setDebugCropsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_faceDebugCropsKey, enabled);
  }

  Future<bool> isWriteEmbeddingToIsar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_faceWriteEmbeddingKey) ?? true;
  }

  Future<void> setWriteEmbeddingToIsar(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_faceWriteEmbeddingKey, enabled);
  }

  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ocrEnabledKey);
    await prefs.remove(_faceDetectionEnabledKey);
    await prefs.remove(_faceDebugCropsKey);
    await prefs.remove(_faceWriteEmbeddingKey);
    await prefs.remove(_autoResumeKey);
  }
}
