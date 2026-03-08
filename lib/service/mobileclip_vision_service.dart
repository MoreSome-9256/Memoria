import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

class MobileClipVisionService {
  MobileClipVisionService._internal();

  static final MobileClipVisionService _instance =
      MobileClipVisionService._internal();

  factory MobileClipVisionService() => _instance;

  static const String _modelAssetPath = 'mobileclip_vision_ir9.onnx';
  static const int _inputImageSize = 256;

  OrtSession? _session;
  String? _inputName;
  List<String>? _outputNames;

  Future<void> warmUp() async {
    await _loadSession();
  }

  Future<List<double>> embedImageFile(File imageFile) async {
    if (!imageFile.existsSync()) {
      throw ArgumentError('图片文件不存在: ${imageFile.path}');
    }

    final imageBytes = await imageFile.readAsBytes();
    return embedImageBytes(imageBytes);
  }

  Future<List<double>> embedImageBytes(Uint8List imageBytes) async {
    final session = await _loadSession();
    final input = await compute<Uint8List, Float32List>(
      _preprocessImageForMobileClip,
      imageBytes,
    );

    final inputTensor = OrtValueTensor.createTensorWithDataList(input, <int>[
      1,
      3,
      _inputImageSize,
      _inputImageSize,
    ]);
    final runOptions = OrtRunOptions();

    try {
      final outputs = session.run(runOptions, <String, OrtValue>{
        _inputName!: inputTensor,
      }, _outputNames);
      try {
        if (outputs.isEmpty || outputs.first == null) {
          throw StateError('MobileCLIP ONNX 输出为空');
        }

        final embedding = _flattenOutput(outputs.first!.value);
        if (embedding.isEmpty) {
          throw StateError('MobileCLIP ONNX 输出为空');
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
  }

  Future<OrtSession> _loadSession() async {
    if (_session != null) {
      return _session!;
    }

    OrtEnv.instance.init();
    final modelBytes = (await rootBundle.load(
      _modelAssetPath,
    )).buffer.asUint8List();
    final sessionOptions = OrtSessionOptions();
    sessionOptions.setIntraOpNumThreads(2);
    sessionOptions.setInterOpNumThreads(1);
    sessionOptions.setSessionGraphOptimizationLevel(
      GraphOptimizationLevel.ortEnableAll,
    );

    try {
      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
    } finally {
      sessionOptions.release();
    }

    if (_session!.inputNames.isEmpty) {
      throw StateError('MobileCLIP ONNX 未找到输入张量');
    }
    if (_session!.outputNames.isEmpty) {
      throw StateError('MobileCLIP ONNX 未找到输出张量');
    }

    _inputName = _session!.inputNames.first;
    _outputNames = List<String>.from(_session!.outputNames, growable: false);
    debugPrint('🧠 MobileCLIP ONNX 就绪 input=$_inputName outputs=$_outputNames');
    return _session!;
  }

  List<double> _flattenOutput(Object? output) {
    if (output is num) {
      return <double>[output.toDouble()];
    }
    if (output is List) {
      return output
          .expand<double>((Object? element) => _flattenOutput(element))
          .toList(growable: false);
    }
    throw StateError('无法解析 MobileCLIP ONNX 输出数据: ${output.runtimeType}');
  }

  List<double> _l2Normalize(List<double> vector) {
    final squaredSum = vector.fold<double>(
      0,
      (double sum, double value) => sum + value * value,
    );

    final norm = math.sqrt(squaredSum);
    if (norm == 0) {
      return vector;
    }

    return vector.map((double value) => value / norm).toList(growable: false);
  }
}

const int _mobileClipInputImageSize = 256;
Float32List _preprocessImageForMobileClip(Uint8List imageBytes) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) {
    throw ArgumentError('无法解码图片数据');
  }

  final preprocessed = _preprocessMobileClipImage(decoded);
  return _toMobileClipNchw(preprocessed);
}

img.Image _preprocessMobileClipImage(img.Image source) {
  final baked = img.bakeOrientation(source);
  final resized = _resizeMobileClipShortestSide(
    baked,
    _mobileClipInputImageSize,
  );
  final cropped = _centerCropMobileClipSquare(
    resized,
    _mobileClipInputImageSize,
  );
  return img.copyResize(
    cropped,
    width: _mobileClipInputImageSize,
    height: _mobileClipInputImageSize,
    interpolation: img.Interpolation.linear,
  );
}

img.Image _resizeMobileClipShortestSide(
  img.Image source,
  int targetShortestSide,
) {
  final shortestSide = math.min(source.width, source.height);
  if (shortestSide == targetShortestSide) {
    return source;
  }

  final scale = targetShortestSide / shortestSide;
  final width = (source.width * scale).round();
  final height = (source.height * scale).round();
  return img.copyResize(
    source,
    width: width,
    height: height,
    interpolation: img.Interpolation.linear,
  );
}

img.Image _centerCropMobileClipSquare(img.Image source, int cropSize) {
  final x = ((source.width - cropSize) / 2).floor().clamp(0, source.width);
  final y = ((source.height - cropSize) / 2).floor().clamp(0, source.height);
  final width = math.min(cropSize, source.width - x);
  final height = math.min(cropSize, source.height - y);

  return img.copyCrop(source, x: x, y: y, width: width, height: height);
}

Float32List _toMobileClipNchw(img.Image image) {
  final buffer = Float32List(
    3 * _mobileClipInputImageSize * _mobileClipInputImageSize,
  );

  for (var channel = 0; channel < 3; channel++) {
    final channelOffset =
        channel * _mobileClipInputImageSize * _mobileClipInputImageSize;
    for (var y = 0; y < _mobileClipInputImageSize; y++) {
      for (var x = 0; x < _mobileClipInputImageSize; x++) {
        final pixel = image.getPixel(x, y);
        final value = switch (channel) {
          0 => pixel.r.toDouble() / 255.0,
          1 => pixel.g.toDouble() / 255.0,
          _ => pixel.b.toDouble() / 255.0,
        };
        final index = channelOffset + y * _mobileClipInputImageSize + x;
        buffer[index] = value;
      }
    }
  }

  return buffer;
}
