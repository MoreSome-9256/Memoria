import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'onnx_session_provider_service.dart';

class MobileViClipVideoService {
  MobileViClipVideoService._internal({
    OnnxSessionProviderPreference providerPreference =
        OnnxSessionProviderPreference.androidRecommended,
  }) : _providerPreference = providerPreference;

  static final MobileViClipVideoService _instance =
      MobileViClipVideoService._internal();

  factory MobileViClipVideoService() => _instance;
  factory MobileViClipVideoService.withProviderPreference(
    OnnxSessionProviderPreference providerPreference,
  ) => MobileViClipVideoService._internal(
    providerPreference: providerPreference,
  );

  static const int frameCount = 8;
  static const int inputImageSize = 256;
  static const int embeddingDim = 512;
  static const String modelVersion = 'mobileviclip_small_onnx_video_v1';

  static const String _modelAssetPath =
      'assets/mobileviclip/small/mobileviclip_small.onnx';

  final OnnxSessionProviderPreference _providerPreference;

  OrtSession? _session;
  String? _inputName;
  List<String>? _outputNames;
  OnnxExecutionProvider? _executionProvider;
  List<String> _providerFallbacks = const <String>[];

  Future<void> warmUp() async {
    await _loadSession();
  }

  Future<List<double>> embedFrameFiles(List<File> frameFiles) async {
    final bytes = <Uint8List>[];
    for (final file in frameFiles) {
      if (!file.existsSync()) {
        throw ArgumentError('视频帧文件不存在: ${file.path}');
      }
      bytes.add(await file.readAsBytes());
    }
    return embedFrameBytes(bytes);
  }

  Future<List<double>> embedFrameBytes(List<Uint8List> frames) async {
    final profile = await profileFrameBytes(frames);
    return profile.embedding;
  }

  Future<MobileViClipVideoEmbeddingProfile> profileFrameBytes(
    List<Uint8List> frames,
  ) async {
    final preprocessWatch = Stopwatch()..start();
    final input = await preprocessFrameBytes(frames);
    preprocessWatch.stop();
    final runProfile = await profilePreprocessedInput(input);
    return MobileViClipVideoEmbeddingProfile(
      embedding: runProfile.embedding,
      preprocessMs: preprocessWatch.elapsedMicroseconds / 1000.0,
      tensorBuildMs: runProfile.tensorBuildMs,
      inferenceMs: runProfile.inferenceMs,
    );
  }

  Future<Float32List> preprocessFrameBytes(List<Uint8List> frames) {
    return compute<List<Uint8List>, Float32List>(
      _preprocessMobileViClipFrames,
      frames,
    );
  }

  Future<List<double>> embedPreprocessedInput(Float32List input) async {
    final profile = await profilePreprocessedInput(input);
    return profile.embedding;
  }

  Future<MobileViClipVideoRunProfile> profilePreprocessedInput(
    Float32List input,
  ) async {
    final expectedLength = frameCount * 3 * inputImageSize * inputImageSize;
    if (input.length != expectedLength) {
      throw ArgumentError(
        'MobileViCLIP 输入长度应为 $expectedLength，实际为 ${input.length}',
      );
    }

    final session = await _loadSession();
    final tensorWatch = Stopwatch()..start();
    final inputTensor = OrtValueTensor.createTensorWithDataList(input, <int>[
      1,
      frameCount,
      3,
      inputImageSize,
      inputImageSize,
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
          throw StateError('MobileViCLIP ONNX 输出为空');
        }
        final embedding = _flattenOutput(outputs.first!.value);
        if (embedding.length != embeddingDim) {
          throw StateError('MobileViCLIP ONNX 输出维度异常: ${embedding.length}');
        }
        return MobileViClipVideoRunProfile(
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
    final modelBytes = (await rootBundle.load(
      _modelAssetPath,
    )).buffer.asUint8List();
    final loadResult = await OnnxSessionProviderService.createSession(
      modelBytes: modelBytes,
      intraOpNumThreads: 1,
      interOpNumThreads: 1,
      preference: _providerPreference,
    );
    _session = loadResult.session;
    _executionProvider = loadResult.executionProvider;
    _providerFallbacks = loadResult.fallbacks;

    if (_session!.inputNames.isEmpty) {
      throw StateError('MobileViCLIP ONNX 未找到输入张量');
    }
    if (_session!.outputNames.isEmpty) {
      throw StateError('MobileViCLIP ONNX 未找到输出张量');
    }
    _inputName = _session!.inputNames.first;
    _outputNames = List<String>.from(_session!.outputNames, growable: false);
    debugPrint(
      'MobileViCLIP ONNX 就绪 input=$_inputName outputs=$_outputNames provider=$executionProviderLabel',
    );
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
    if (output is Float32List) {
      return output.map((value) => value.toDouble()).toList(growable: false);
    }
    if (output is Float64List) {
      return output.toList(growable: false);
    }
    throw StateError('不支持的 MobileViCLIP ONNX 输出类型: ${output.runtimeType}');
  }

  List<double> _l2Normalize(List<double> vector) {
    var sumSquares = 0.0;
    for (final value in vector) {
      sumSquares += value * value;
    }
    final norm = math.sqrt(sumSquares);
    if (norm == 0 || norm.isNaN || norm.isInfinite) {
      return vector;
    }
    return vector.map((value) => value / norm).toList(growable: false);
  }
}

Float32List _preprocessMobileViClipFrames(List<Uint8List> frames) {
  if (frames.isEmpty) {
    throw ArgumentError('至少需要一帧用于 MobileViCLIP 视频嵌入');
  }

  final selectedFrames = _sampleFrames(
    frames,
    MobileViClipVideoService.frameCount,
  );
  final frameSize =
      3 *
      MobileViClipVideoService.inputImageSize *
      MobileViClipVideoService.inputImageSize;
  final output = Float32List(MobileViClipVideoService.frameCount * frameSize);
  for (var frameIndex = 0; frameIndex < selectedFrames.length; frameIndex++) {
    final decoded = img.decodeImage(selectedFrames[frameIndex]);
    if (decoded == null) {
      throw ArgumentError('无法解码第 ${frameIndex + 1} 帧');
    }
    final baked = img.bakeOrientation(decoded);
    final resized = img.copyResize(
      baked,
      width: MobileViClipVideoService.inputImageSize,
      height: MobileViClipVideoService.inputImageSize,
      interpolation: img.Interpolation.linear,
    );
    _writeNormalizedFrame(resized, output, frameIndex * frameSize);
  }
  return output;
}

List<Uint8List> _sampleFrames(List<Uint8List> frames, int targetCount) {
  if (frames.length == targetCount) {
    return List<Uint8List>.from(frames, growable: false);
  }
  if (frames.length == 1) {
    return List<Uint8List>.filled(targetCount, frames.first, growable: false);
  }
  return List<Uint8List>.generate(targetCount, (index) {
    final sourceIndex = (index * (frames.length - 1) / (targetCount - 1))
        .round();
    return frames[sourceIndex];
  }, growable: false);
}

void _writeNormalizedFrame(
  img.Image image,
  Float32List output,
  int baseOffset,
) {
  const mean = <double>[0.485, 0.456, 0.406];
  const std = <double>[0.229, 0.224, 0.225];
  const size = MobileViClipVideoService.inputImageSize;
  final channelSize = size * size;

  for (var channel = 0; channel < 3; channel++) {
    final channelOffset = baseOffset + channel * channelSize;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final pixel = image.getPixel(x, y);
        final raw = switch (channel) {
          0 => pixel.r.toDouble() / 255.0,
          1 => pixel.g.toDouble() / 255.0,
          _ => pixel.b.toDouble() / 255.0,
        };
        output[channelOffset + y * size + x] =
            (raw - mean[channel]) / std[channel];
      }
    }
  }
}

class MobileViClipVideoRunProfile {
  const MobileViClipVideoRunProfile({
    required this.embedding,
    required this.tensorBuildMs,
    required this.inferenceMs,
  });

  final List<double> embedding;
  final double tensorBuildMs;
  final double inferenceMs;
}

class MobileViClipVideoEmbeddingProfile {
  const MobileViClipVideoEmbeddingProfile({
    required this.embedding,
    required this.preprocessMs,
    required this.tensorBuildMs,
    required this.inferenceMs,
  });

  final List<double> embedding;
  final double preprocessMs;
  final double tensorBuildMs;
  final double inferenceMs;
}
