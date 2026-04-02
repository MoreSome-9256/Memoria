import 'dart:io';
import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

enum OnnxSessionProviderPreference {
  auto,
  nnapiHardwareOnly,
  nnapiFp16Relaxed,
  xnnpack,
  cpu,
}

class OnnxSessionProviderService {
  const OnnxSessionProviderService._();

  static Future<OnnxSessionLoadResult> createSession({
    required Uint8List modelBytes,
    required int intraOpNumThreads,
    required int interOpNumThreads,
    OnnxSessionProviderPreference preference =
        OnnxSessionProviderPreference.auto,
  }) async {
    OrtEnv.instance.init();

    final attempts = _buildAttempts(preference);
    final failures = <String>[];

    for (final attempt in attempts) {
      final options = OrtSessionOptions();
      try {
        options.setIntraOpNumThreads(intraOpNumThreads);
        options.setInterOpNumThreads(interOpNumThreads);
        options.setSessionGraphOptimizationLevel(
          GraphOptimizationLevel.ortEnableAll,
        );
        attempt.configure(options);

        final session = OrtSession.fromBuffer(modelBytes, options);
        return OnnxSessionLoadResult(
          session: session,
          executionProvider: attempt.provider,
          fallbacks: List<String>.unmodifiable(failures),
        );
      } catch (error) {
        failures.add('${attempt.provider.label}: $error');
      } finally {
        options.release();
      }
    }

    throw StateError(
      'Unable to create ONNX Runtime session. Attempts: ${failures.join(' | ')}',
    );
  }

  static List<_ProviderAttempt> _buildAttempts(
    OnnxSessionProviderPreference preference,
  ) {
    return switch (preference) {
      OnnxSessionProviderPreference.auto =>
        Platform.isAndroid
            ? const <_ProviderAttempt>[
                _ProviderAttempt.nnapiStrict(),
                _ProviderAttempt.nnapiFp16Relaxed(),
                _ProviderAttempt.xnnpack(),
                _ProviderAttempt.cpu(),
              ]
            : const <_ProviderAttempt>[_ProviderAttempt.cpu()],
      OnnxSessionProviderPreference.nnapiHardwareOnly =>
        const <_ProviderAttempt>[_ProviderAttempt.nnapiStrict()],
      OnnxSessionProviderPreference.nnapiFp16Relaxed =>
        const <_ProviderAttempt>[_ProviderAttempt.nnapiFp16Relaxed()],
      OnnxSessionProviderPreference.xnnpack => const <_ProviderAttempt>[
        _ProviderAttempt.xnnpack(),
      ],
      OnnxSessionProviderPreference.cpu => const <_ProviderAttempt>[
        _ProviderAttempt.cpu(),
      ],
    };
  }
}

class OnnxSessionLoadResult {
  const OnnxSessionLoadResult({
    required this.session,
    required this.executionProvider,
    required this.fallbacks,
  });

  final OrtSession session;
  final OnnxExecutionProvider executionProvider;
  final List<String> fallbacks;
}

class OnnxExecutionProvider {
  const OnnxExecutionProvider({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

class _ProviderAttempt {
  const _ProviderAttempt({required this.provider, required this.configure});

  const _ProviderAttempt.nnapiStrict()
    : provider = const OnnxExecutionProvider(
        id: 'nnapi_strict',
        label: 'NNAPI (strict)',
        description:
            'Android NNAPI, disallowing NNAPI CPU devices when supported.',
      ),
      configure = _appendNnapiStrict;

  const _ProviderAttempt.nnapiFp16Relaxed()
    : provider = const OnnxExecutionProvider(
        id: 'nnapi_fp16_relaxed',
        label: 'NNAPI (FP16 relaxed)',
        description:
            'Android NNAPI with FP16 relaxation enabled; some devices may allow NNAPI CPU devices on this path.',
      ),
      configure = _appendNnapiFp16Relaxed;

  const _ProviderAttempt.xnnpack()
    : provider = const OnnxExecutionProvider(
        id: 'xnnpack',
        label: 'XNNPACK',
        description: 'ONNX Runtime XNNPACK CPU acceleration.',
      ),
      configure = _appendXnnpack;

  const _ProviderAttempt.cpu()
    : provider = const OnnxExecutionProvider(
        id: 'cpu',
        label: 'CPU',
        description: 'ONNX Runtime default CPU execution provider.',
      ),
      configure = _appendCpu;

  final OnnxExecutionProvider provider;
  final void Function(OrtSessionOptions options) configure;

  static void _appendNnapiStrict(OrtSessionOptions options) {
    options.appendNnapiProvider(NnapiFlags.cpuDisabled);
  }

  static void _appendNnapiFp16Relaxed(OrtSessionOptions options) {
    options.appendNnapiProvider(NnapiFlags.useFp16);
  }

  static void _appendXnnpack(OrtSessionOptions options) {
    options.appendXnnpackProvider();
  }

  static void _appendCpu(OrtSessionOptions options) {
    options.appendCPUProvider(CPUFlags.useArena);
  }
}
