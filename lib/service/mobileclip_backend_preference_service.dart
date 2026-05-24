/// MobileCLIP 后端偏好服务，记录当前可用推理后端及其选择策略。

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MobileClipBackend { mobileclip2LiteRt }

extension MobileClipBackendX on MobileClipBackend {
  String get storageValue => switch (this) {
    MobileClipBackend.mobileclip2LiteRt => 'mobileclip2_litert',
  };

  String get label => switch (this) {
    MobileClipBackend.mobileclip2LiteRt => 'MobileCLIP2 LiteRT',
  };

  String get description => switch (this) {
    MobileClipBackend.mobileclip2LiteRt =>
      'Android 默认 LiteRT GPU；iOS 默认 Metal/Core ML；CPU 仅作显式后备',
  };

  static MobileClipBackend fromStorageValue(String? value) {
    return switch (value) {
      'mobileclip2_litert' => MobileClipBackend.mobileclip2LiteRt,
      'mobileclip2_onnx' => MobileClipBackend.mobileclip2LiteRt,
      _ => MobileClipBackend.mobileclip2LiteRt,
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
      ValueNotifier<MobileClipBackend>(MobileClipBackend.mobileclip2LiteRt);

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
