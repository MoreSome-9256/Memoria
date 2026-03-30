import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'onnx_session_provider_service.dart';

class MobileClipVisionService {
  MobileClipVisionService._internal({
    OnnxSessionProviderPreference providerPreference =
        OnnxSessionProviderPreference.auto,
  }) : _providerPreference = providerPreference;

  static final MobileClipVisionService _instance =
      MobileClipVisionService._internal();

  factory MobileClipVisionService() => _instance;
  factory MobileClipVisionService.withProviderPreference(
    OnnxSessionProviderPreference providerPreference,
  ) =>
      MobileClipVisionService._internal(providerPreference: providerPreference);

  static const String _defaultModelAssetPath =
      'assets/mobileclip2/s2/vision_model.onnx';
  static const String _modelFilePathOverride = String.fromEnvironment(
    'MOBILECLIP2_ONNX_FILE',
    defaultValue: '',
  );
  static const String _modelAssetPathOverride = String.fromEnvironment(
    'MOBILECLIP2_ONNX_ASSET',
    defaultValue: '',
  );
  static const String _inputImageSizeOverride = String.fromEnvironment(
    'MOBILECLIP_ONNX_INPUT_SIZE',
    defaultValue: '256',
  );

  late final int _inputImageSize = _resolveInputImageSize();
  final OnnxSessionProviderPreference _providerPreference;

  OrtSession? _session;
  String? _inputName;
  List<String>? _outputNames;
  _PreprocessSpec _preprocessSpec = const _PreprocessSpec.mobileclip2();
  OnnxExecutionProvider? _executionProvider;
  List<String> _providerFallbacks = const <String>[];

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
    final profile = await profileImageBytes(imageBytes);
    return profile.embedding;
  }

  Future<Float32List> preprocessImageBytesForBenchmark(
    Uint8List imageBytes,
  ) async {
    final profile = await profileImageBytesForBenchmark(imageBytes);
    return profile.input;
  }

  Future<MobileClipVisionPreprocessProfile> profileImageBytesForBenchmark(
    Uint8List imageBytes,
  ) async {
    final payload =
        await compute<_MobileClipPreprocessRequest, Map<String, Object?>>(
          _preprocessImageForMobileClip,
          _MobileClipPreprocessRequest(
            imageBytes: imageBytes,
            inputImageSize: _inputImageSize,
            mean: _preprocessSpec.mean,
            std: _preprocessSpec.std,
          ),
        );
    return MobileClipVisionPreprocessProfile(
      input: payload['input']! as Float32List,
      decodeMs: (payload['decodeMs']! as num).toDouble(),
      resizeNormalizeMs: (payload['resizeNormalizeMs']! as num).toDouble(),
    );
  }

  Future<MobileClipVisionEmbeddingProfile> profileImageBytes(
    Uint8List imageBytes,
  ) async {
    final preprocessProfile = await profileImageBytesForBenchmark(imageBytes);
    final runProfile = await profilePreprocessedInput(preprocessProfile.input);
    return MobileClipVisionEmbeddingProfile(
      embedding: runProfile.embedding,
      decodeMs: preprocessProfile.decodeMs,
      resizeNormalizeMs: preprocessProfile.resizeNormalizeMs,
      tensorBuildMs: runProfile.tensorBuildMs,
      inferenceMs: runProfile.inferenceMs,
    );
  }

  Future<List<double>> embedPreprocessedInput(Float32List input) async {
    final profile = await profilePreprocessedInput(input);
    return profile.embedding;
  }

  Future<MobileClipVisionRunProfile> profilePreprocessedInput(
    Float32List input,
  ) async {
    final session = await _loadSession();
    final tensorWatch = Stopwatch()..start();
    final inputTensor = OrtValueTensor.createTensorWithDataList(input, <int>[
      1,
      3,
      _inputImageSize,
      _inputImageSize,
    ]);
    tensorWatch.stop();
    final runOptions = OrtRunOptions();

    try {
      final inferenceWatch = Stopwatch()..start();
      final outputs = session.run(runOptions, <String, OrtValue>{
        _inputName!: inputTensor,
      }, _outputNames);
      inferenceWatch.stop();
      try {
        if (outputs.isEmpty || outputs.first == null) {
          throw StateError('MobileCLIP ONNX 输出为空');
        }

        final embedding = _flattenOutput(outputs.first!.value);
        if (embedding.isEmpty) {
          throw StateError('MobileCLIP ONNX 输出为空');
        }

        return MobileClipVisionRunProfile(
          embedding: _l2Normalize(embedding),
          tensorBuildMs: tensorWatch.elapsedMicroseconds / 1000.0,
          inferenceMs: inferenceWatch.elapsedMicroseconds / 1000.0,
        );
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

  int get inputImageSize => _inputImageSize;
  String get executionProviderLabel =>
      _executionProvider?.label ?? 'Pending session init';
  String get executionProviderDescription =>
      _executionProvider?.description ??
      'ONNX Runtime provider has not been initialized yet.';
  List<String> get providerFallbacks =>
      List<String>.unmodifiable(_providerFallbacks);

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
    final modelLoadResult = await _loadModelBytes();
    final modelBytes = modelLoadResult.bytes;
    _preprocessSpec = const _PreprocessSpec.mobileclip2();
    final loadResult = await OnnxSessionProviderService.createSession(
      modelBytes: modelBytes,
      intraOpNumThreads: 2,
      interOpNumThreads: 1,
      preference: _providerPreference,
    );
    _session = loadResult.session;
    _executionProvider = loadResult.executionProvider;
    _providerFallbacks = loadResult.fallbacks;

    if (_session!.inputNames.isEmpty) {
      throw StateError('MobileCLIP ONNX 未找到输入张量');
    }
    if (_session!.outputNames.isEmpty) {
      throw StateError('MobileCLIP ONNX 未找到输出张量');
    }

    _inputName = _session!.inputNames.first;
    _outputNames = List<String>.from(_session!.outputNames, growable: false);
    debugPrint(
      '🧠 MobileCLIP ONNX 就绪 source=${modelLoadResult.source} input=$_inputName outputs=$_outputNames size=$_inputImageSize mean=${_preprocessSpec.mean} std=${_preprocessSpec.std} provider=$executionProviderLabel',
    );
    if (_providerFallbacks.isNotEmpty) {
      debugPrint(
        '⚠️ MobileCLIP ONNX provider fallback chain: ${_providerFallbacks.join(' -> ')}',
      );
    }
    return _session!;
  }

  Future<_ModelLoadResult> _loadModelBytes() async {
    final filePath = _modelFilePathOverride.trim();
    if (filePath.isNotEmpty) {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw StateError('MOBILECLIP2_ONNX_FILE 指向的模型不存在: $filePath');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw StateError('MOBILECLIP2_ONNX_FILE 模型为空: $filePath');
      }
      return _ModelLoadResult(bytes: bytes, source: filePath);
    }

    final assetPath = _modelAssetPathOverride.trim();
    if (assetPath.isNotEmpty) {
      final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
      return _ModelLoadResult(bytes: bytes, source: assetPath);
    }

    final bytes = (await rootBundle.load(
      _defaultModelAssetPath,
    )).buffer.asUint8List();
    return _ModelLoadResult(bytes: bytes, source: _defaultModelAssetPath);
  }

  int _resolveInputImageSize() {
    final parsed = int.tryParse(_inputImageSizeOverride);
    if (parsed == null || parsed <= 0) {
      return 256;
    }
    return parsed;
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

class _ModelLoadResult {
  const _ModelLoadResult({required this.bytes, required this.source});

  final Uint8List bytes;
  final String source;
}

class _PreprocessSpec {
  const _PreprocessSpec({required this.mean, required this.std});

  const _PreprocessSpec.mobileclip2()
    : mean = const <double>[0.0, 0.0, 0.0],
      std = const <double>[1.0, 1.0, 1.0];

  final List<double> mean;
  final List<double> std;
}

class _MobileClipPreprocessRequest {
  const _MobileClipPreprocessRequest({
    required this.imageBytes,
    required this.inputImageSize,
    required this.mean,
    required this.std,
  });

  final Uint8List imageBytes;
  final int inputImageSize;
  final List<double> mean;
  final List<double> std;
}

Map<String, Object?> _preprocessImageForMobileClip(
  _MobileClipPreprocessRequest request,
) {
  final decodeWatch = Stopwatch()..start();
  final decoded = img.decodeImage(request.imageBytes);
  decodeWatch.stop();
  if (decoded == null) {
    throw ArgumentError('无法解码图片数据');
  }

  final resizeNormalizeWatch = Stopwatch()..start();
  final preprocessed = _preprocessMobileClipImage(
    decoded,
    request.inputImageSize,
  );
  final input = _toMobileClipNchw(
    preprocessed,
    request.inputImageSize,
    request.mean,
    request.std,
  );
  resizeNormalizeWatch.stop();
  return <String, Object?>{
    'input': input,
    'decodeMs': decodeWatch.elapsedMicroseconds / 1000.0,
    'resizeNormalizeMs': resizeNormalizeWatch.elapsedMicroseconds / 1000.0,
  };
}

img.Image _preprocessMobileClipImage(img.Image source, int inputImageSize) {
  final baked = img.bakeOrientation(source);
  final resized = _resizeMobileClipShortestSide(baked, inputImageSize);
  final cropped = _centerCropMobileClipSquare(resized, inputImageSize);
  return img.copyResize(
    cropped,
    width: inputImageSize,
    height: inputImageSize,
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

Float32List _toMobileClipNchw(
  img.Image image,
  int inputImageSize,
  List<double> mean,
  List<double> std,
) {
  final buffer = Float32List(3 * inputImageSize * inputImageSize);

  for (var channel = 0; channel < 3; channel++) {
    final channelOffset = channel * inputImageSize * inputImageSize;
    for (var y = 0; y < inputImageSize; y++) {
      for (var x = 0; x < inputImageSize; x++) {
        final pixel = image.getPixel(x, y);
        final raw = switch (channel) {
          0 => pixel.r.toDouble() / 255.0,
          1 => pixel.g.toDouble() / 255.0,
          _ => pixel.b.toDouble() / 255.0,
        };
        final denom = std[channel] == 0 ? 1.0 : std[channel];
        final value = (raw - mean[channel]) / denom;
        final index = channelOffset + y * inputImageSize + x;
        buffer[index] = value;
      }
    }
  }

  return buffer;
}

class MobileClipVisionPreprocessProfile {
  const MobileClipVisionPreprocessProfile({
    required this.input,
    required this.decodeMs,
    required this.resizeNormalizeMs,
  });

  final Float32List input;
  final double decodeMs;
  final double resizeNormalizeMs;

  double get preprocessMs => decodeMs + resizeNormalizeMs;
}

class MobileClipVisionRunProfile {
  const MobileClipVisionRunProfile({
    required this.embedding,
    required this.tensorBuildMs,
    required this.inferenceMs,
  });

  final List<double> embedding;
  final double tensorBuildMs;
  final double inferenceMs;
}

class MobileClipVisionEmbeddingProfile {
  const MobileClipVisionEmbeddingProfile({
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

  double get preprocessMs => decodeMs + resizeNormalizeMs;
}
