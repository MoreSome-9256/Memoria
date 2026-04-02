import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';

import 'onnx_session_provider_service.dart';

class MobileClipTextService {
  MobileClipTextService._internal();

  static final MobileClipTextService _instance =
      MobileClipTextService._internal();

  factory MobileClipTextService() => _instance;

  // Points to the MobileCLIP2 text ONNX model bundled in assets.
  static const String _defaultModelAssetPath =
      'assets/mobileclip2/s2/text_model.onnx';

  // Optional override for loading model from local file during experiments.
  static const String _modelFilePathOverride = String.fromEnvironment(
    'MOBILECLIP2_TEXT_ONNX_FILE',
    defaultValue: '',
  );

  OrtSession? _session;
  String? _inputName;
  List<String>? _outputNames;
  OnnxExecutionProvider? _executionProvider;
  List<String> _providerFallbacks = const <String>[];

  Future<void> warmUp() async {
    await _loadSession();
  }

  /// Runs text encoder for one CLIP token sequence and returns a 512-D vector.
  Future<List<double>> embedTextTokens(List<int> tokenIds) async {
    if (tokenIds.length != 77) {
      throw ArgumentError(
        'CLIP 文本输入必须是长度为 77 的 Token 数组，当前长度: ${tokenIds.length}',
      );
    }

    final session = await _loadSession();

    // CLIP text encoder input tensor type is int64 with shape [1, 77].
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList(tokenIds),
      <int>[1, 77],
    );
    final runOptions = OrtRunOptions();

    try {
      final outputs = session.run(runOptions, <String, OrtValue>{
        _inputName!: inputTensor,
      }, _outputNames);

      try {
        if (outputs.isEmpty || outputs.first == null) {
          throw StateError('MobileCLIP Text ONNX 输出为空');
        }

        final embedding = _flattenOutput(outputs.first!.value);
        if (embedding.isEmpty) {
          throw StateError('MobileCLIP Text ONNX 输出为空');
        }

        return _l2Normalize(embedding);
      } finally {
        for (final output in outputs) {
          output?.release();
        }
      }
    } finally {
      runOptions.release();
      inputTensor.release();
    }
  }

  Future<void> dispose() async {
    _session?.release();
    _session = null;
    _inputName = null;
    _outputNames = null;
    _executionProvider = null;
    _providerFallbacks = const <String>[];
  }

  Future<OrtSession> _loadSession() async {
    if (_session != null) {
      return _session!;
    }

    OrtEnv.instance.init();
    final modelBytes = await _loadModelBytes();
    final loadResult = await OnnxSessionProviderService.createSession(
      modelBytes: modelBytes,
      intraOpNumThreads: 2,
      interOpNumThreads: 1,
    );
    _session = loadResult.session;
    _executionProvider = loadResult.executionProvider;
    _providerFallbacks = loadResult.fallbacks;

    if (_session!.inputNames.isEmpty) {
      throw StateError('MobileCLIP Text ONNX 未找到输入张量');
    }
    if (_session!.outputNames.isEmpty) {
      throw StateError('MobileCLIP Text ONNX 未找到输出张量');
    }

    _inputName = _session!.inputNames.first;
    _outputNames = List<String>.from(_session!.outputNames, growable: false);
    debugPrint(
      '🧠 MobileCLIP Text ONNX 就绪 input=$_inputName outputs=$_outputNames provider=${_executionProvider?.label ?? 'CPU'}',
    );
    if (_providerFallbacks.isNotEmpty) {
      debugPrint(
        '⚠️ MobileCLIP Text ONNX provider fallback chain: ${_providerFallbacks.join(' -> ')}',
      );
    }
    return _session!;
  }

  Future<Uint8List> _loadModelBytes() async {
    final filePath = _modelFilePathOverride.trim();
    if (filePath.isNotEmpty) {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw StateError('文本模型不存在: $filePath');
      }
      return await file.readAsBytes();
    }

    return (await rootBundle.load(_defaultModelAssetPath)).buffer.asUint8List();
  }

  List<double> _flattenOutput(Object? output) {
    if (output is num) return <double>[output.toDouble()];
    if (output is List) {
      return output
          .expand<double>((Object? element) => _flattenOutput(element))
          .toList(growable: false);
    }
    throw StateError('无法解析 Text ONNX 输出: ${output.runtimeType}');
  }

  List<double> _l2Normalize(List<double> vector) {
    final squaredSum = vector.fold<double>(
      0,
      (double sum, double value) => sum + value * value,
    );
    final norm = math.sqrt(squaredSum);
    if (norm == 0) return vector;
    return vector.map((double value) => value / norm).toList(growable: false);
  }
}
