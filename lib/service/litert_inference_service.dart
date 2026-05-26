import 'dart:io';

import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

enum LocalInferenceAccelerator { gpu, npu, coreml, metal, xnnpack, cpu }

extension LocalInferenceAcceleratorX on LocalInferenceAccelerator {
  String get storageValue => switch (this) {
    LocalInferenceAccelerator.gpu => 'gpu',
    LocalInferenceAccelerator.npu => 'npu',
    LocalInferenceAccelerator.coreml => 'coreml',
    LocalInferenceAccelerator.metal => 'metal',
    LocalInferenceAccelerator.xnnpack => 'xnnpack',
    LocalInferenceAccelerator.cpu => 'cpu',
  };

  String get label => switch (this) {
    LocalInferenceAccelerator.gpu => 'GPU',
    LocalInferenceAccelerator.npu => 'NPU',
    LocalInferenceAccelerator.coreml => 'Core ML',
    LocalInferenceAccelerator.metal => 'Metal',
    LocalInferenceAccelerator.xnnpack => 'XNNPACK',
    LocalInferenceAccelerator.cpu => 'Raw CPU',
  };

  String get description => switch (this) {
    LocalInferenceAccelerator.gpu =>
      'Android 使用 TFLite GPU delegate v2；Apple 平台请使用 Metal(GPU)',
    LocalInferenceAccelerator.npu =>
      'Android 预留厂商 NPU delegate 接入',
    LocalInferenceAccelerator.coreml => 'Apple Core ML delegate，优先使用系统加速',
    LocalInferenceAccelerator.metal => 'Apple Metal GPU delegate',
    LocalInferenceAccelerator.xnnpack =>
      'CPU XNNPACK delegate；GPU/NPU 闪退时优先尝试的兼容方案',
    LocalInferenceAccelerator.cpu => '不使用 delegate 的原始 CPU 路径，最稳但最慢',
  };

  static LocalInferenceAccelerator fromStorageValue(String? value) {
    return switch (value) {
      'gpu' => LocalInferenceAccelerator.gpu,
      'npu' => LocalInferenceAccelerator.npu,
      'coreml' => LocalInferenceAccelerator.coreml,
      'metal' => LocalInferenceAccelerator.metal,
      'xnnpack' => LocalInferenceAccelerator.xnnpack,
      'cpu' => LocalInferenceAccelerator.cpu,
      _ => Platform.isIOS || Platform.isMacOS
          ? LocalInferenceAccelerator.coreml
          : LocalInferenceAccelerator.gpu,
    };
  }
}

class LiteRtSessionConfig {
  const LiteRtSessionConfig({
    required this.modelAssetPath,
    required this.modelToken,
    this.accelerator = LocalInferenceAccelerator.gpu,
  });

  final String modelAssetPath;
  final String modelToken;
  final LocalInferenceAccelerator accelerator;
}

class LiteRtSession {
  LiteRtSession._({
    required this.interpreter,
    required this.providerLabel,
    required this.delegates,
  });

  final tfl.Interpreter interpreter;
  final String providerLabel;
  final List<tfl.Delegate> delegates;

  void close() {
    interpreter.close();
    for (final delegate in delegates.reversed) {
      delegate.delete();
    }
  }
}

class LiteRtInferenceService {
  const LiteRtInferenceService();

  Future<LiteRtSession> createSession(LiteRtSessionConfig config) async {
    final attempts = _buildAttempts(config);
    final failures = <String>[];

    for (final attempt in attempts) {
      try {
        final options = tfl.InterpreterOptions();
        options.threads = 1;
        final delegates = await attempt.createDelegates();
        for (final delegate in delegates) {
          options.addDelegate(delegate);
        }
        final interpreter = await tfl.Interpreter.fromAsset(
          config.modelAssetPath,
          options: options,
        );
        interpreter.allocateTensors();
        return LiteRtSession._(
          interpreter: interpreter,
          providerLabel: attempt.label,
          delegates: delegates,
        );
      } catch (error) {
        failures.add('${attempt.label}: $error');
      }
    }

    throw StateError('LiteRT session 创建失败。已尝试: ${failures.join(' | ')}');
  }

  List<_LiteRtProviderAttempt> _buildAttempts(LiteRtSessionConfig config) {
    final fallback = <_LiteRtProviderAttempt>[
      _LiteRtProviderAttempt.xnnpack(),
      _LiteRtProviderAttempt.cpu(),
    ];

    if (Platform.isAndroid) {
      return switch (config.accelerator) {
        LocalInferenceAccelerator.gpu => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.androidGpu(),
          ...fallback,
        ],
        LocalInferenceAccelerator.npu => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.unsupported(
            'Android NPU delegate',
            '厂商 NPU delegate 尚未接入，等待 TFLite accelerator 分发后启用',
          ),
          _LiteRtProviderAttempt.androidGpu(),
          ...fallback,
        ],
        LocalInferenceAccelerator.xnnpack => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.xnnpack(),
          _LiteRtProviderAttempt.cpu(),
        ],
        LocalInferenceAccelerator.cpu => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.cpu(),
        ],
        _ => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.androidGpu(),
          ...fallback,
        ],
      };
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return switch (config.accelerator) {
        LocalInferenceAccelerator.npu ||
        LocalInferenceAccelerator.coreml => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.coreMl(),
          _LiteRtProviderAttempt.metal(),
          ...fallback,
        ],
        LocalInferenceAccelerator.gpu ||
        LocalInferenceAccelerator.metal => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.metal(),
          _LiteRtProviderAttempt.coreMl(),
          ...fallback,
        ],
        LocalInferenceAccelerator.xnnpack => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.xnnpack(),
          _LiteRtProviderAttempt.cpu(),
        ],
        LocalInferenceAccelerator.cpu => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.cpu(),
        ],
      };
    }

    return switch (config.accelerator) {
      LocalInferenceAccelerator.cpu => <_LiteRtProviderAttempt>[
        _LiteRtProviderAttempt.cpu(),
      ],
      _ => fallback,
    };
  }
}

class _LiteRtProviderAttempt {
  const _LiteRtProviderAttempt({
    required this.label,
    required this.createDelegates,
  });

  factory _LiteRtProviderAttempt.androidGpu() {
    return _LiteRtProviderAttempt(
      label: 'TFLite GPU v2',
      createDelegates: () async => <tfl.Delegate>[
        tfl.GpuDelegateV2(
          options: tfl.GpuDelegateOptionsV2(
            isPrecisionLossAllowed: false,
            inferencePriority1: 2,
            inferencePriority2: 0,
            inferencePriority3: 0,
            experimentalFlags: const <int>[1],
          ),
        ),
      ],
    );
  }

  factory _LiteRtProviderAttempt.coreMl() {
    return _LiteRtProviderAttempt(
      label: 'Core ML',
      createDelegates: () async => <tfl.Delegate>[
        tfl.CoreMlDelegate(
          options: tfl.CoreMlDelegateOptions(maxDelegatedPartitions: 0),
        ),
      ],
    );
  }

  factory _LiteRtProviderAttempt.metal() {
    return _LiteRtProviderAttempt(
      label: 'Metal GPU',
      createDelegates: () async => <tfl.Delegate>[
        tfl.GpuDelegate(
          options: tfl.GpuDelegateOptions(allowPrecisionLoss: false),
        ),
      ],
    );
  }

  factory _LiteRtProviderAttempt.cpu() {
    return _LiteRtProviderAttempt(
      label: 'CPU',
      createDelegates: () async => const <tfl.Delegate>[],
    );
  }

  factory _LiteRtProviderAttempt.xnnpack() {
    return _LiteRtProviderAttempt(
      label: 'XNNPACK',
      createDelegates: () async => <tfl.Delegate>[
        tfl.XNNPackDelegate(),
      ],
    );
  }

  factory _LiteRtProviderAttempt.unsupported(String label, String reason) {
    return _LiteRtProviderAttempt(
      label: label,
      createDelegates: () async => throw UnsupportedError(reason),
    );
  }

  final String label;
  final Future<List<tfl.Delegate>> Function() createDelegates;
}
