import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'ai_model_weight_service.dart';
import 'litert_inference_service.dart';

class MobileClipLiteRtService {
  MobileClipLiteRtService._internal();

  static final MobileClipLiteRtService _instance =
      MobileClipLiteRtService._internal();

  factory MobileClipLiteRtService() => _instance;
  factory MobileClipLiteRtService.detachedWithAccelerator(
    LocalInferenceAccelerator accelerator,
  ) {
    return MobileClipLiteRtService._internal().._accelerator = accelerator;
  }

  factory MobileClipLiteRtService.withRuntimeOptions({
    required LocalInferenceAccelerator accelerator,
    required int xnnpackThreadCount,
    required int modelBatchSize,
  }) {
    _instance._configureRuntime(
      accelerator: accelerator,
      xnnpackThreadCount: xnnpackThreadCount,
      modelBatchSize: modelBatchSize,
    );
    return _instance;
  }

  static const int inputImageSize = 256;
  static const int tokenLength = 77;
  static const int embeddingDim = 512;
  static const String modelVersion = 'mobileclip2_s2_fp32_split_tflite_v1';
  static const String _imageModelAssetPath =
      'assets/mobileclip2/s2/mobileclip2_s2_image.tflite';
  static const String _textModelAssetPath =
      'assets/mobileclip2/s2/mobileclip2_s2_text.tflite';

  LocalInferenceAccelerator _accelerator = LocalInferenceAccelerator.xnnpack;
  int _xnnpackThreadCount = 2;
  int _modelBatchSize = 1;
  final LiteRtInferenceService _runtime = const LiteRtInferenceService();

  LiteRtSession? _imageSession;
  LiteRtSession? _textSession;
  String? _imageProviderLabel;
  String? _textProviderLabel;

  String get executionProviderLabel =>
      _imageProviderLabel ?? _textProviderLabel ?? 'Pending session init';

  void _configureRuntime({
    required LocalInferenceAccelerator accelerator,
    int? xnnpackThreadCount,
    int? modelBatchSize,
  }) {
    final nextThreads = _normalizeThreadCount(
      xnnpackThreadCount ?? _xnnpackThreadCount,
    );
    final nextModelBatchSize = _normalizeModelBatchSize(
      modelBatchSize ?? _modelBatchSize,
    );
    final changed =
        _accelerator != accelerator ||
        _xnnpackThreadCount != nextThreads ||
        _modelBatchSize != nextModelBatchSize;
    _accelerator = accelerator;
    _xnnpackThreadCount = nextThreads;
    _modelBatchSize = nextModelBatchSize;
    if (changed) {
      _imageSession?.close();
      _textSession?.close();
      _imageSession = null;
      _textSession = null;
      _imageProviderLabel = null;
      _textProviderLabel = null;
    }
  }

  Future<void> warmUp() async {
    await warmUpImage();
    await warmUpText();
  }

  Future<void> warmUpImage() async {
    await _loadImageSession();
  }

  Future<void> warmUpText() async {
    await _loadTextSession();
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

  Future<List<MobileClipLiteRtRunProfile>> profilePreprocessedImageInputs(
    List<Float32List> inputs,
  ) async {
    if (inputs.isEmpty) {
      return const <MobileClipLiteRtRunProfile>[];
    }
    if (inputs.length == 1) {
      return <MobileClipLiteRtRunProfile>[
        await profilePreprocessedImageInput(inputs.first),
      ];
    }
    final maxBatchSize = math.max(1, _modelBatchSize);
    if (inputs.length > maxBatchSize) {
      final profiles = <MobileClipLiteRtRunProfile>[];
      for (var offset = 0; offset < inputs.length; offset += maxBatchSize) {
        profiles.addAll(
          await profilePreprocessedImageInputs(
            inputs.sublist(
              offset,
              math.min(inputs.length, offset + maxBatchSize),
            ),
          ),
        );
      }
      return profiles;
    }
    final expectedLength = 3 * inputImageSize * inputImageSize;
    for (final input in inputs) {
      if (input.length != expectedLength) {
        throw ArgumentError(
          'MobileCLIP2 LiteRT 图像输入长度应为 $expectedLength，实际为 ${input.length}',
        );
      }
    }

    final session = await _loadImageSession();
    final tensorWatch = Stopwatch()..start();
    final batchSize = inputs.length;
    final batchedInput = Float32List(expectedLength * batchSize);
    for (var i = 0; i < inputs.length; i++) {
      batchedInput.setRange(
        i * expectedLength,
        (i + 1) * expectedLength,
        inputs[i],
      );
    }
    final output = List<List<double>>.generate(
      batchSize,
      (_) => List<double>.filled(embeddingDim, 0),
      growable: false,
    );
    tensorWatch.stop();

    final inferenceWatch = Stopwatch()..start();
    try {
      session.interpreter.resizeInputTensor(0, <int>[
        batchSize,
        3,
        inputImageSize,
        inputImageSize,
      ]);
      session.interpreter.allocateTensors();
      session.interpreter.run(batchedInput.buffer, output);
    } catch (error) {
      debugPrint('MobileCLIP2 image batch=$batchSize 推理失败，回退单张推理: $error');
      try {
        session.interpreter.resizeInputTensor(0, const <int>[
          1,
          3,
          inputImageSize,
          inputImageSize,
        ]);
        session.interpreter.allocateTensors();
      } catch (_) {}
      final profiles = <MobileClipLiteRtRunProfile>[];
      for (final input in inputs) {
        profiles.add(await profilePreprocessedImageInput(input));
      }
      return profiles;
    } finally {
      if (batchSize != 1) {
        try {
          session.interpreter.resizeInputTensor(0, const <int>[
            1,
            3,
            inputImageSize,
            inputImageSize,
          ]);
          session.interpreter.allocateTensors();
        } catch (_) {}
      }
    }
    inferenceWatch.stop();

    final tensorBuildMs = tensorWatch.elapsedMicroseconds / 1000.0;
    final inferenceMs = inferenceWatch.elapsedMicroseconds / 1000.0;
    return output
        .map(
          (embedding) => MobileClipLiteRtRunProfile(
            embedding: _l2Normalize(embedding),
            tensorBuildMs: tensorBuildMs / batchSize,
            inferenceMs: inferenceMs / batchSize,
          ),
        )
        .toList(growable: false);
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

    final session = await _loadImageSession();
    final tensorWatch = Stopwatch()..start();
    final outputImage = _zeroOutputBuffer();
    tensorWatch.stop();

    final inferenceWatch = Stopwatch()..start();
    session.interpreter.run(input.buffer, outputImage);
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

    final session = await _loadTextSession();
    final outputText = _zeroOutputBuffer();
    final tokenBuffer = Int64List.fromList(tokenIds);
    session.interpreter.run(tokenBuffer.buffer, outputText);
    return _l2Normalize(outputText.first);
  }

  Future<void> dispose() async {
    _imageSession?.close();
    _textSession?.close();
    _imageSession = null;
    _textSession = null;
    _imageProviderLabel = null;
    _textProviderLabel = null;
  }

  Future<LiteRtSession> _loadImageSession() async {
    if (_imageSession != null) {
      return _imageSession!;
    }
    await AiModelWeightService.instance.ensureWeightsAvailableForInference(
      AiModelWeightId.mobileclip2LiteRt,
    );

    final session = await _runtime.createSession(
      LiteRtSessionConfig(
        modelAssetPath: _imageModelAssetPath,
        modelToken: '${modelVersion}_image',
        accelerator: _accelerator,
        xnnpackThreadCount: _xnnpackThreadCount,
        modelBatchSize: _modelBatchSize,
      ),
    );
    _imageSession = session;
    _imageProviderLabel = session.providerLabel;
    _validateTensorSpec(
      session,
      expectedInputShape: const <int>[1, 3, inputImageSize, inputImageSize],
      expectedInputType: 'float32',
      expectedOutputShape: const <int>[1, embeddingDim],
      expectedOutputType: 'float32',
      label: 'MobileCLIP2 image',
    );
    debugPrint(
      'MobileCLIP2 image LiteRT 就绪 model=$_imageModelAssetPath provider=$_imageProviderLabel',
    );
    return session;
  }

  Future<LiteRtSession> _loadTextSession() async {
    if (_textSession != null) {
      return _textSession!;
    }
    await AiModelWeightService.instance.ensureWeightsAvailableForInference(
      AiModelWeightId.mobileclip2LiteRt,
    );

    final session = await _runtime.createSession(
      LiteRtSessionConfig(
        modelAssetPath: _textModelAssetPath,
        modelToken: '${modelVersion}_text',
        accelerator: _accelerator,
        xnnpackThreadCount: _xnnpackThreadCount,
        modelBatchSize: _modelBatchSize,
      ),
    );
    _textSession = session;
    _textProviderLabel = session.providerLabel;
    _validateTensorSpec(
      session,
      expectedInputShape: const <int>[1, tokenLength],
      expectedInputType: 'int64',
      expectedOutputShape: const <int>[1, embeddingDim],
      expectedOutputType: 'float32',
      label: 'MobileCLIP2 text',
    );
    debugPrint(
      'MobileCLIP2 text LiteRT 就绪 model=$_textModelAssetPath provider=$_textProviderLabel',
    );
    return session;
  }

  void _validateTensorSpec(
    LiteRtSession session, {
    required List<int> expectedInputShape,
    required String expectedInputType,
    required List<int> expectedOutputShape,
    required String expectedOutputType,
    required String label,
  }) {
    final input = session.interpreter.getInputTensor(0);
    final output = session.interpreter.getOutputTensor(0);
    final inputType = input.type.toString();
    final outputType = output.type.toString();
    if (!_sameShape(input.shape, expectedInputShape) ||
        inputType != expectedInputType ||
        !_sameShape(output.shape, expectedOutputShape) ||
        outputType != expectedOutputType) {
      throw StateError(
        '$label tensor spec mismatch: '
        'input shape=${input.shape} type=$inputType, '
        'output shape=${output.shape} type=$outputType',
      );
    }
  }

  bool _sameShape(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<List<double>> _zeroOutputBuffer() => <List<double>>[
    List<double>.filled(embeddingDim, 0),
  ];

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

  int _normalizeThreadCount(int value) {
    if (value < 1) return 1;
    if (value > 8) return 8;
    return value;
  }

  int _normalizeModelBatchSize(int value) {
    if (value < 1) return 1;
    if (value > 16) return 16;
    return value;
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
  final resizeWidth = baked.width <= baked.height
      ? MobileClipLiteRtService.inputImageSize
      : null;
  final resizeHeight = baked.width > baked.height
      ? MobileClipLiteRtService.inputImageSize
      : null;
  final resized = img.copyResize(
    baked,
    width: resizeWidth,
    height: resizeHeight,
    interpolation: img.Interpolation.cubic,
  );
  final cropped = _centerCrop(resized, MobileClipLiteRtService.inputImageSize);
  final input = _toNchwUnitRgb(cropped);
  resizeNormalizeWatch.stop();
  return <String, Object?>{
    'input': input,
    'decodeMs': decodeWatch.elapsedMicroseconds / 1000.0,
    'resizeNormalizeMs': resizeNormalizeWatch.elapsedMicroseconds / 1000.0,
  };
}

img.Image _centerCrop(img.Image image, int size) {
  if (image.width == size && image.height == size) {
    return image;
  }
  final x = math.max(0, ((image.width - size) / 2).floor());
  final y = math.max(0, ((image.height - size) / 2).floor());
  final width = math.min(size, image.width - x);
  final height = math.min(size, image.height - y);
  return img.copyCrop(image, x: x, y: y, width: width, height: height);
}

Float32List _toNchwUnitRgb(img.Image image) {
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
        buffer[channelOffset + y * size + x] = raw;
      }
    }
  }
  return buffer;
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
