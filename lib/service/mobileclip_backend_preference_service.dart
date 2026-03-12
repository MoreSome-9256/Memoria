import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MobileClipBackend { onnx, ncnn }

extension MobileClipBackendX on MobileClipBackend {
  String get storageValue => switch (this) {
    MobileClipBackend.onnx => 'onnx',
    MobileClipBackend.ncnn => 'ncnn',
  };

  String get label => switch (this) {
    MobileClipBackend.onnx => 'ONNX',
    MobileClipBackend.ncnn => 'NCNN',
  };

  String get description => switch (this) {
    MobileClipBackend.onnx => '兼容性优先',
    MobileClipBackend.ncnn => '速度优先',
  };

  static MobileClipBackend fromStorageValue(String? value) {
    return switch (value) {
      'ncnn' => MobileClipBackend.ncnn,
      _ => MobileClipBackend.onnx,
    };
  }
}

class MobileClipBackendPreferenceService {
  MobileClipBackendPreferenceService._internal();

  static final MobileClipBackendPreferenceService _instance =
      MobileClipBackendPreferenceService._internal();

  factory MobileClipBackendPreferenceService() => _instance;

  static const String _backendKey = 'mobileclip_backend';

  final ValueNotifier<MobileClipBackend> _backendNotifier =
      ValueNotifier<MobileClipBackend>(MobileClipBackend.onnx);

  SharedPreferences? _preferences;

  ValueListenable<MobileClipBackend> get backendListenable => _backendNotifier;

  Future<void> initialize() async {
    if (_preferences != null) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    _backendNotifier.value = MobileClipBackendX.fromStorageValue(
      preferences.getString(_backendKey),
    );
  }

  Future<MobileClipBackend> getSelectedBackend() async {
    await initialize();
    return _backendNotifier.value;
  }

  Future<void> setSelectedBackend(MobileClipBackend backend) async {
    await initialize();
    if (_backendNotifier.value == backend) {
      return;
    }

    await _preferences!.setString(_backendKey, backend.storageValue);
    _backendNotifier.value = backend;
  }
}