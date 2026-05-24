import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'litert_inference_service.dart';

class MobileClipLiteRtService {
  MobileClipLiteRtService._internal();

  static final MobileClipLiteRtService _instance =
      MobileClipLiteRtService._internal();

  factory MobileClipLiteRtService() => _instance;
  factory MobileClipLiteRtService.withAccelerator(
    LocalInferenceAccelerator accelerator,
  ) {
    final prevAccelerator = _instance._accelerator;
    _instance._accelerator = accelerator;
    if (_instance._session != null && prevAccelerator != accelerator) {
      _instance._session!.close();
      _instance._session = null;
      _instance._providerLabel = null;
    }
    return _instance;
  }

  static const int inputImageSize = 256;
  static const int tokenLength = 77;
  static const int embeddingDim = 512;
  static const String modelVersion = 'mobileclip2_s2_litert_v1';
  static const String _modelAssetPath =
      'assets/mobileclip2/s2/mobileclip_s2_datacompdr_last.tflite';

  LocalInferenceAccelerator _accelerator = LocalInferenceAccelerator.gpu;
  final LiteRtInferenceService _runtime = const LiteRtInferenceService();

  LiteRtSession? _session;
  String? _providerLabel;

  String get executionProviderLabel => _providerLabel ?? 'Pending session init';

  Future<void> warmUp() async {
    await _loadSession();
  }

  Future<List<double>> embedImageFile(File imageFile) async {
    if (!imageFile.existsSync()) {
      throw ArgumentError('图片文件不存在: ${imageFile.path}');
    }
    return embedImageBytes(await imageFile.readAsBytes());
  }

  Future<List<double>> embedImageBytes(Uint8List imageBytes) async {
    final profile = await profileImageBytes(imageBytes);
    return profile.embedding;
  }

  Future<MobileClipLiteRtPreprocessProfile> profileImageBytesForBenchmark(
    Uint8List imageBytes,
  ) async {
    final payload = await compute<Uint8List, Map<String, Object?>>(
      _preprocessImageForMobileClipLiteRt,
      imageBytes,
    );
    return MobileClipLiteRtPreprocessProfile(
      input: payload['input']! as Float32List,
      decodeMs: (payload['decodeMs']! as num).toDouble(),
      resizeNormalizeMs: (payload['resizeNormalizeMs']! as num).toDouble(),
    );
  }

  Future<Float32List> preprocessImageBytesForBenchmark(
    Uint8List imageBytes,
  ) async {
    final profile = await profileImageBytesForBenchmark(imageBytes);
    return profile.input;
  }

  Future<MobileClipLiteRtEmbeddingProfile> profileImageBytes(
    Uint8List imageBytes,
  ) async {
    final preprocessProfile = await profileImageBytesForBenchmark(imageBytes);
    final runProfile = await profilePreprocessedImageInput(
      preprocessProfile.input,
    );
    return MobileClipLiteRtEmbeddingProfile(
      embedding: runProfile.embedding,
      decodeMs: preprocessProfile.decodeMs,
      resizeNormalizeMs: preprocessProfile.resizeNormalizeMs,
      tensorBuildMs: runProfile.tensorBuildMs,
      inferenceMs: runProfile.inferenceMs,
    );
  }

  Future<List<double>> embedPreprocessedImageInput(Float32List input) async {
    final profile = await profilePreprocessedImageInput(input);
    return profile.embedding;
  }

  Future<MobileClipLiteRtRunProfile> profilePreprocessedImageInput(
    Float32List input,
  ) async {
    final expectedLength = 3 * inputImageSize * inputImageSize;
    if (input.length != expectedLength) {
      throw ArgumentError(
        'MobileCLIP2 LiteRT 图像输入长度应为 $expectedLength，实际为 ${input.length}',
      );
    }

    final session = await _loadSession();
    final tensorWatch = Stopwatch()..start();
    final outputText = _zeroOutputBuffer();
    final outputImage = _zeroOutputBuffer();
    final outputScale = <double>[0];
    tensorWatch.stop();

    final inferenceWatch = Stopwatch()..start();
    session.interpreter.runForMultipleInputs(
      <Object>[
        input.reshape(<int>[1, 3, inputImageSize, inputImageSize]),
        _zeroTokens(),
      ],
      <int, Object>{0: outputText, 1: outputImage, 2: outputScale},
    );
    inferenceWatch.stop();

    return MobileClipLiteRtRunProfile(
      embedding: _l2Normalize(outputImage.first),
      tensorBuildMs: tensorWatch.elapsedMicroseconds / 1000.0,
      inferenceMs: inferenceWatch.elapsedMicroseconds / 1000.0,
    );
  }

  Future<List<double>> embedTextTokens(List<int> tokenIds) async {
    if (tokenIds.length != tokenLength) {
      throw ArgumentError(
        'CLIP 文本输入必须是长度为 $tokenLength 的 Token 数组，当前长度: ${tokenIds.length}',
      );
    }

    final session = await _loadSession();
    final outputText = _zeroOutputBuffer();
    final outputImage = _zeroOutputBuffer();
    final outputScale = <double>[0];
    session.interpreter.runForMultipleInputs(
      <Object>[
        Float32List(
          3 * inputImageSize * inputImageSize,
        ).reshape(<int>[1, 3, inputImageSize, inputImageSize]),
        Int64List.fromList(tokenIds).reshape(<int>[1, tokenLength]),
      ],
      <int, Object>{0: outputText, 1: outputImage, 2: outputScale},
    );
    return _l2Normalize(outputText.first);
  }

  Future<void> dispose() async {
    _session?.close();
    _session = null;
    _providerLabel = null;
  }

  Future<LiteRtSession> _loadSession() async {
    if (_session != null) {
      return _session!;
    }

    final session = await _runtime.createSession(
      LiteRtSessionConfig(
        modelAssetPath: _modelAssetPath,
        modelToken: modelVersion,
        accelerator: _accelerator,
        threads: 2,
      ),
    );
    _session = session;
    _providerLabel = session.providerLabel;
    debugPrint(
      'MobileCLIP2 LiteRT 就绪 model=$_modelAssetPath provider=$_providerLabel',
    );
    return session;
  }

  List<List<double>> _zeroOutputBuffer() => <List<double>>[
    List<double>.filled(embeddingDim, 0),
  ];

  Int64List _zeroTokens() => Int64List(tokenLength);

  List<double> _l2Normalize(List<double> vector) {
    var sumSquares = 0.0;
    for (final value in vector) {
      sumSquares += value * value;
    }
    final norm = math.sqrt(sumSquares);
    if (norm == 0 || norm.isNaN || norm.isInfinite) {
      return vector.map((value) => value.toDouble()).toList(growable: false);
    }
    return vector.map((value) => value / norm).toList(growable: false);
  }
}

Map<String, Object?> _preprocessImageForMobileClipLiteRt(Uint8List imageBytes) {
  final decodeWatch = Stopwatch()..start();
  final decoded = img.decodeImage(imageBytes);
  decodeWatch.stop();
  if (decoded == null) {
    throw ArgumentError('无法解码图片数据');
  }

  final resizeNormalizeWatch = Stopwatch()..start();
  final baked = img.bakeOrientation(decoded);
  final resized = img.copyResize(
    baked,
    width: MobileClipLiteRtService.inputImageSize,
    height: MobileClipLiteRtService.inputImageSize,
    interpolation: img.Interpolation.linear,
  );
  final input = _toNchwImageNet(resized);
  resizeNormalizeWatch.stop();
  return <String, Object?>{
    'input': input,
    'decodeMs': decodeWatch.elapsedMicroseconds / 1000.0,
    'resizeNormalizeMs': resizeNormalizeWatch.elapsedMicroseconds / 1000.0,
  };
}

Float32List _toNchwImageNet(img.Image image) {
  const mean = <double>[0.485, 0.456, 0.406];
  const std = <double>[0.229, 0.224, 0.225];
  const size = MobileClipLiteRtService.inputImageSize;
  final buffer = Float32List(3 * size * size);

  for (var channel = 0; channel < 3; channel++) {
    final channelOffset = channel * size * size;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final pixel = image.getPixel(x, y);
        final raw = switch (channel) {
          0 => pixel.r.toDouble() / 255.0,
          1 => pixel.g.toDouble() / 255.0,
          _ => pixel.b.toDouble() / 255.0,
        };
        buffer[channelOffset + y * size + x] =
            (raw - mean[channel]) / std[channel];
      }
    }
  }
  return buffer;
}

extension _Float32ListShape on Float32List {
  Object reshape(List<int> shape) => reshapeToObject(this, shape);
}

extension _Int64ListShape on Int64List {
  Object reshape(List<int> shape) => reshapeToObject(this, shape);
}

Object reshapeToObject(TypedData data, List<int> shape) {
  if (shape.length == 2 && data is Float32List) {
    final rows = shape[0];
    final cols = shape[1];
    return List<List<double>>.generate(
      rows,
      (row) => List<double>.generate(cols, (col) => data[row * cols + col]),
    );
  }
  if (shape.length == 2 && data is Int64List) {
    final rows = shape[0];
    final cols = shape[1];
    return List<List<int>>.generate(
      rows,
      (row) => List<int>.generate(cols, (col) => data[row * cols + col]),
    );
  }
  if (shape.length == 4 && data is Float32List) {
    final b = shape[0];
    final c = shape[1];
    final h = shape[2];
    final w = shape[3];
    return List.generate(
      b,
      (bi) => List.generate(
        c,
        (ci) => List.generate(
          h,
          (yi) => List<double>.generate(
            w,
            (xi) => data[((bi * c + ci) * h + yi) * w + xi],
          ),
        ),
      ),
    );
  }
  throw ArgumentError('不支持的 LiteRT 输入 shape: $shape');
}

class MobileClipLiteRtPreprocessProfile {
  const MobileClipLiteRtPreprocessProfile({
    required this.input,
    required this.decodeMs,
    required this.resizeNormalizeMs,
  });

  final Float32List input;
  final double decodeMs;
  final double resizeNormalizeMs;
}

class MobileClipLiteRtRunProfile {
  const MobileClipLiteRtRunProfile({
    required this.embedding,
    required this.tensorBuildMs,
    required this.inferenceMs,
  });

  final List<double> embedding;
  final double tensorBuildMs;
  final double inferenceMs;
}

class MobileClipLiteRtEmbeddingProfile {
  const MobileClipLiteRtEmbeddingProfile({
    required this.embedding,
    required this.decodeMs,
    required this.resizeNormalizeMs,
    required this.tensorBuildMs,
    required this.inferenceMs,
  });

  final List<double> embedding;
  final double decodeMs;
  final double resizeNormalizeMs;
  final double tensorBuildMs;
  final double inferenceMs;
}
