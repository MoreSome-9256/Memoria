// ONNX 人脸嵌入服务，负责调用 ONNX 模型提取人脸向量。

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'face_embedding_service.dart';

class OnnxFaceEmbeddingService extends FaceEmbeddingService {
  OnnxFaceEmbeddingService({FaceEmbeddingService? fallbackService})
    : _fallbackService = fallbackService;

  static const String _modelFilePathOverride = String.fromEnvironment(
    'FACE_EMBEDDING_ONNX_FILE',
    defaultValue: '',
  );
  static const String _modelAssetPathOverride = String.fromEnvironment(
    'FACE_EMBEDDING_ONNX_ASSET',
    defaultValue: '',
  );
  static const String _modelVersion = String.fromEnvironment(
    'FACE_EMBEDDING_MODEL_VERSION',
    defaultValue: 'arcface_onnx_v1',
  );
  static const String _inputSizeOverride = String.fromEnvironment(
    'FACE_EMBEDDING_INPUT_SIZE',
    defaultValue: '112',
  );
  static const String _inputLayoutOverride = String.fromEnvironment(
    'FACE_EMBEDDING_INPUT_LAYOUT',
    defaultValue: 'nhwc',
  );
  static const String _meanOverride = String.fromEnvironment(
    'FACE_EMBEDDING_MEAN',
    defaultValue: '127.5',
  );
  static const String _stdOverride = String.fromEnvironment(
    'FACE_EMBEDDING_STD',
    defaultValue: '128.0',
  );

  final FaceEmbeddingService? _fallbackService;

  OrtSession? _session;
  String? _inputName;
  List<String>? _outputNames;
  String? _resolvedModelSource;
  bool _warmAttempted = false;
  bool _isAvailable = false;
  String? _unavailableReason;
  Future<void>? _warmUpInFlight;
  Future<void> _inferenceTail = Future<void>.value();

  int get _inputSize => int.tryParse(_inputSizeOverride) ?? 112;
  bool get _isNhwcInput => _inputLayoutOverride.trim().toLowerCase() != 'nchw';
  double get _mean => double.tryParse(_meanOverride) ?? 127.5;
  double get _std => double.tryParse(_stdOverride) ?? 128.0;

  @override
  Future<void> warmUp() async {
    final activeWarmUp = _warmUpInFlight;
    if (activeWarmUp != null) {
      await activeWarmUp;
      return;
    }
    if (_warmAttempted) {
      if (!_isAvailable && _fallbackService != null) {
        await _fallbackService.warmUp();
      }
      return;
    }

    final future = _warmUp();
    _warmUpInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_warmUpInFlight, future)) _warmUpInFlight = null;
    }
  }

  Future<void> _warmUp() async {
    _warmAttempted = true;
    try {
      final session = await _loadSession();
      _isAvailable = true;
      debugPrint(
        '🧠 Face ONNX 就绪 source=$_resolvedModelSource '
        'input=$_inputName outputs=$_outputNames size=$_inputSize layout=${_isNhwcInput ? 'NHWC' : 'NCHW'} '
        'backend=onnx_face_embedding',
      );
      _session = session;
    } catch (error) {
      _isAvailable = false;
      _unavailableReason = error.toString();
      debugPrint(
        '⚠️ Face ONNX 不可用${_fallbackService == null ? "" : "，回退备用人脸向量服务"}: $error '
        'backend=${_fallbackService == null ? "none" : "fallback_face_embedding"}',
      );
      if (_fallbackService != null) {
        await _fallbackService.warmUp();
      }
    }
  }

  @override
  void resetWarmState() {
    _session?.release();
    _session = null;
    _inputName = null;
    _outputNames = null;
    _resolvedModelSource = null;
    _warmAttempted = false;
    _isAvailable = false;
    _unavailableReason = null;
    _warmUpInFlight = null;
    _fallbackService?.resetWarmState();
  }

  @override
  Future<FaceEmbeddingResult?> embedFaceCropBytes(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) {
      return null;
    }
    final previous = _inferenceTail;
    final completer = Completer<void>();
    _inferenceTail = completer.future;
    await previous;
    try {
      return await _embedFaceCropBytesLocked(imageBytes);
    } finally {
      completer.complete();
    }
  }

  Future<FaceEmbeddingResult?> _embedFaceCropBytesLocked(
    Uint8List imageBytes,
  ) async {
    await warmUp();
    if (!_isAvailable) {
      return _fallbackService?.embedFaceCropBytes(imageBytes);
    }

    final session = _session;
    if (session == null) {
      return _fallbackService?.embedFaceCropBytes(imageBytes);
    }

    try {
      final input = _preprocessImageBytes(imageBytes);
      final tensor = OrtValueTensor.createTensorWithDataList(
        input,
        _isNhwcInput
            ? <int>[1, _inputSize, _inputSize, 3]
            : <int>[1, 3, _inputSize, _inputSize],
      );
      final runOptions = OrtRunOptions();
      try {
        final outputs = session.run(runOptions, <String, OrtValue>{
          _inputName!: tensor,
        }, _outputNames);
        try {
          if (outputs.isEmpty || outputs.first == null) {
            return _fallbackService?.embedFaceCropBytes(imageBytes);
          }
          final embedding = _l2Normalize(_flattenOutput(outputs.first!.value));
          if (embedding.isEmpty) {
            return _fallbackService?.embedFaceCropBytes(imageBytes);
          }
          return FaceEmbeddingResult(
            embedding: embedding,
            modelVersion: _modelVersion,
          );
        } finally {
          for (final output in outputs) {
            output?.release();
          }
        }
      } finally {
        runOptions.release();
        tensor.release();
      }
    } catch (error) {
      debugPrint(
        '⚠️ Face ONNX 推理失败${_fallbackService == null ? "" : "，回退备用人脸向量服务"}: $error'
        '${_unavailableReason == null ? '' : ' ($_unavailableReason)'}',
      );
      return _fallbackService?.embedFaceCropBytes(imageBytes);
    }
  }

  Future<OrtSession> _loadSession() async {
    if (_session != null) {
      return _session!;
    }

    final modelBytes = await _loadModelBytes();
    OrtEnv.instance.init();
    final options = OrtSessionOptions();
    options.setIntraOpNumThreads(2);
    options.setInterOpNumThreads(1);
    options.setSessionGraphOptimizationLevel(
      GraphOptimizationLevel.ortEnableAll,
    );

    try {
      _session = OrtSession.fromBuffer(modelBytes, options);
    } finally {
      options.release();
    }

    if (_session!.inputNames.isEmpty || _session!.outputNames.isEmpty) {
      throw StateError('Face ONNX 模型输入/输出张量缺失');
    }

    _inputName = _session!.inputNames.first;
    _outputNames = List<String>.from(_session!.outputNames, growable: false);
    return _session!;
  }

  Future<Uint8List> _loadModelBytes() async {
    final assetPath = _modelAssetPathOverride.trim();
    if (assetPath.isNotEmpty) {
      _resolvedModelSource = assetPath;
      return (await rootBundle.load(assetPath)).buffer.asUint8List();
    }

    final filePath = _modelFilePathOverride.trim();
    if (filePath.isNotEmpty) {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw StateError('FACE_EMBEDDING_ONNX_FILE 指向的模型不存在: $filePath');
      }
      _resolvedModelSource = filePath;
      return file.readAsBytes();
    }

    throw StateError(
      '未配置专用人脸模型，请通过 FACE_EMBEDDING_ONNX_FILE 或 FACE_EMBEDDING_ONNX_ASSET 提供模型',
    );
  }

  Float32List _preprocessImageBytes(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw ArgumentError('Unable to decode face crop bytes');
    }

    final baked = img.bakeOrientation(decoded);
    final resized = img.copyResize(
      baked,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.cubic,
    );

    return _isNhwcInput
        ? _toNhwcInput(resized, mean: _mean, std: _std)
        : _toNchwInput(resized, mean: _mean, std: _std);
  }

  Float32List _toNhwcInput(
    img.Image image, {
    required double mean,
    required double std,
  }) {
    final buffer = Float32List(3 * _inputSize * _inputSize);
    final denom = std == 0 ? 1.0 : std;

    var offset = 0;
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final pixel = image.getPixel(x, y);
        buffer[offset++] = (pixel.r.toDouble() - mean) / denom;
        buffer[offset++] = (pixel.g.toDouble() - mean) / denom;
        buffer[offset++] = (pixel.b.toDouble() - mean) / denom;
      }
    }
    return buffer;
  }

  Float32List _toNchwInput(
    img.Image image, {
    required double mean,
    required double std,
  }) {
    final buffer = Float32List(3 * _inputSize * _inputSize);
    final denom = std == 0 ? 1.0 : std;

    for (var channel = 0; channel < 3; channel++) {
      final channelOffset = channel * _inputSize * _inputSize;
      for (var y = 0; y < _inputSize; y++) {
        for (var x = 0; x < _inputSize; x++) {
          final pixel = image.getPixel(x, y);
          final raw = switch (channel) {
            0 => pixel.r.toDouble(),
            1 => pixel.g.toDouble(),
            _ => pixel.b.toDouble(),
          };
          final index = channelOffset + y * _inputSize + x;
          buffer[index] = (raw - mean) / denom;
        }
      }
    }

    return buffer;
  }

  List<double> _flattenOutput(Object? output) {
    if (output is num) {
      return <double>[output.toDouble()];
    }
    if (output is List) {
      return output
          .expand<double>((element) => _flattenOutput(element))
          .toList(growable: false);
    }
    throw StateError('无法解析 Face ONNX 输出: ${output.runtimeType}');
  }

  List<double> _l2Normalize(List<double> vector) {
    final squared = vector.fold<double>(
      0.0,
      (sum, value) => sum + value * value,
    );
    final norm = math.sqrt(squared);
    if (norm <= 0) {
      return vector;
    }
    return vector.map((value) => value / norm).toList(growable: false);
  }
}
