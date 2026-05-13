/// MobileCLIP 后端偏好服务，记录当前可用推理后端及其选择策略。

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MobileClipBackend { mobileclip2Onnx, ncnn }

extension MobileClipBackendX on MobileClipBackend {
  String get storageValue => switch (this) {
    MobileClipBackend.mobileclip2Onnx => 'mobileclip2_onnx',
    MobileClipBackend.ncnn => 'ncnn',
  };

  String get label => switch (this) {
    MobileClipBackend.mobileclip2Onnx => 'MobileCLIP2 ONNX',
    MobileClipBackend.ncnn => 'NCNN',
  };

  String get description => switch (this) {
    MobileClipBackend.mobileclip2Onnx =>
      'Android 优先使用 NNAPI hardware，失败时回退到 XNNPACK/CPU',
    MobileClipBackend.ncnn => '兼容性优先，推理更快但模型更弱',
  };

  static MobileClipBackend fromStorageValue(String? value) {
    return switch (value) {
      'mobileclip2_onnx' => MobileClipBackend.mobileclip2Onnx,
      'ncnn' => MobileClipBackend.ncnn,
      _ => MobileClipBackend.mobileclip2Onnx,
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
      ValueNotifier<MobileClipBackend>(MobileClipBackend.mobileclip2Onnx);

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
