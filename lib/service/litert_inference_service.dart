import 'dart:io';

import 'package:flutter_litert/flutter_litert.dart';
import 'package:path_provider/path_provider.dart';

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
    LocalInferenceAccelerator.cpu => 'CPU',
  };

  String get description => switch (this) {
    LocalInferenceAccelerator.gpu =>
      'Android 使用 LiteRT GPU delegate；iOS 使用 Metal',
    LocalInferenceAccelerator.npu =>
      'iOS 使用 Core ML Neural Engine；Android 预留厂商 delegate 接入',
    LocalInferenceAccelerator.coreml => 'iOS/macOS Core ML delegate',
    LocalInferenceAccelerator.metal => 'iOS/macOS Metal GPU delegate',
    LocalInferenceAccelerator.xnnpack => '优化 CPU delegate，仅作为兼容和调试后备',
    LocalInferenceAccelerator.cpu => '纯 CPU，不建议用于主流程',
  };

  static LocalInferenceAccelerator fromStorageValue(String? value) {
    return switch (value) {
      'gpu' => LocalInferenceAccelerator.gpu,
      'npu' => LocalInferenceAccelerator.npu,
      'coreml' => LocalInferenceAccelerator.coreml,
      'metal' => LocalInferenceAccelerator.metal,
      'xnnpack' => LocalInferenceAccelerator.xnnpack,
      'cpu' => LocalInferenceAccelerator.cpu,
      _ => LocalInferenceAccelerator.gpu,
    };
  }
}

class LiteRtSessionConfig {
  const LiteRtSessionConfig({
    required this.modelAssetPath,
    required this.modelToken,
    this.accelerator = LocalInferenceAccelerator.gpu,
    this.threads = 2,
  });

  final String modelAssetPath;
  final String modelToken;
  final LocalInferenceAccelerator accelerator;
  final int threads;
}

class LiteRtSession {
  LiteRtSession._({
    required this.interpreter,
    required this.providerLabel,
    required this.delegates,
  });

  final Interpreter interpreter;
  final String providerLabel;
  final List<Delegate> delegates;

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
        final options = InterpreterOptions();
        options.threads = config.threads;
        final delegates = await attempt.createDelegates();
        for (final delegate in delegates) {
          options.addDelegate(delegate);
        }
        final interpreter = await Interpreter.fromAsset(
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
      _LiteRtProviderAttempt.xnnpack(config.threads),
      _LiteRtProviderAttempt.cpu(),
    ];

    if (Platform.isAndroid) {
      return switch (config.accelerator) {
        LocalInferenceAccelerator.gpu => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.androidGpu(config),
          ...fallback,
        ],
        LocalInferenceAccelerator.npu => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.unsupported(
            'Android NPU delegate',
            '厂商 NPU delegate 尚未接入，等待 LiteRT accelerator 分发后启用',
          ),
          _LiteRtProviderAttempt.androidGpu(config),
          ...fallback,
        ],
        LocalInferenceAccelerator.xnnpack => fallback,
        LocalInferenceAccelerator.cpu => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.cpu(),
        ],
        _ => <_LiteRtProviderAttempt>[
          _LiteRtProviderAttempt.androidGpu(config),
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
        LocalInferenceAccelerator.xnnpack => fallback,
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

  factory _LiteRtProviderAttempt.androidGpu(LiteRtSessionConfig config) {
    return _LiteRtProviderAttempt(
      label: 'LiteRT GPU',
      createDelegates: () async {
        final cacheDir = await getApplicationSupportDirectory();
        return <Delegate>[
          GpuDelegateV2(
            options: GpuDelegateOptionsV2(
              isPrecisionLossAllowed: true,
              inferencePriority1: 2,
              inferencePriority2: 0,
              inferencePriority3: 0,
              experimentalFlags: const <int>[1, 8],
              serializationDir: cacheDir.path,
              modelToken: config.modelToken,
              maxDelegatePartitions: 8,
            ),
          ),
        ];
      },
    );
  }

  factory _LiteRtProviderAttempt.coreMl() {
    return _LiteRtProviderAttempt(
      label: 'Core ML',
      createDelegates: () async => <Delegate>[
        CoreMlDelegate(
          options: CoreMlDelegateOptions(maxDelegatedPartitions: 0),
        ),
      ],
    );
  }

  factory _LiteRtProviderAttempt.metal() {
    return _LiteRtProviderAttempt(
      label: 'Metal GPU',
      createDelegates: () async => <Delegate>[
        GpuDelegate(options: GpuDelegateOptions(allowPrecisionLoss: true)),
      ],
    );
  }

  factory _LiteRtProviderAttempt.xnnpack(int threads) {
    return _LiteRtProviderAttempt(
      label: 'XNNPACK',
      createDelegates: () async => <Delegate>[
        XNNPackDelegate(options: XNNPackDelegateOptions(numThreads: threads)),
      ],
    );
  }

  factory _LiteRtProviderAttempt.cpu() {
    return _LiteRtProviderAttempt(
      label: 'CPU',
      createDelegates: () async => const <Delegate>[],
    );
  }

  factory _LiteRtProviderAttempt.unsupported(String label, String reason) {
    return _LiteRtProviderAttempt(
      label: label,
      createDelegates: () async => throw UnsupportedError(reason),
    );
  }

  final String label;
  final Future<List<Delegate>> Function() createDelegates;
}
