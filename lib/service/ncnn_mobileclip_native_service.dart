// NCNN MobileCLIP 原生服务，封装本地推理桥接与结果转换。

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_model_weight_service.dart';

class NcnnBackendStatus {
  const NcnnBackendStatus({
    required this.libraryLoaded,
    required this.backendAvailable,
    required this.modelInitialized,
    required this.version,
    required this.lastError,
    required this.expectedInputLength,
    required this.expectedOutputLength,
  });

  final bool libraryLoaded;
  final bool backendAvailable;
  final bool modelInitialized;
  final String version;
  final String lastError;
  final int expectedInputLength;
  final int expectedOutputLength;

  bool get canEncode => libraryLoaded && backendAvailable;

  String get summary {
    if (!libraryLoaded) {
      return 'NCNN native library failed to load.';
    }
    if (!modelInitialized) {
      return lastError.isEmpty
          ? 'NCNN model files are not initialized yet.'
          : lastError;
    }
    if (!backendAvailable) {
      return lastError.isEmpty
          ? 'NCNN backend is stubbed and not linked yet.'
          : lastError;
    }
    return 'NCNN backend ready ($version).';
  }
}

class NcnnEncodeProfile {
  const NcnnEncodeProfile({
    required this.embedding,
    required this.preprocessMs,
    required this.inferenceMs,
  });

  final List<double> embedding;
  final double preprocessMs;
  final double inferenceMs;
}

class NcnnMobileClipNativeService {
  NcnnMobileClipNativeService._internal() {
    _initialize();
  }

  static final NcnnMobileClipNativeService _instance =
      NcnnMobileClipNativeService._internal();

  factory NcnnMobileClipNativeService() => _instance;

  static const int _bufferSize = 1024;
  static const String _androidLibraryName = 'libmemoria_ncnn.so';
  static const String _defaultImageParamAssetPath =
      'assets/ncnn/mobileclip_s2/image_encoder.ncnn.param';
  static const String _defaultImageBinAssetPath =
      'assets/ncnn/mobileclip_s2/image_encoder.ncnn.bin';
  static const String _defaultTextParamAssetPath =
      'assets/ncnn/mobileclip_s2/text_encoder.ncnn.param';
  static const String _defaultTextBinAssetPath =
      'assets/ncnn/mobileclip_s2/text_encoder.ncnn.bin';
  static const String _defaultProjectionParamAssetPath =
      'assets/ncnn/mobileclip_s2/projection_layer.ncnn.param';
  static const String _defaultProjectionBinAssetPath =
      'assets/ncnn/mobileclip_s2/projection_layer.ncnn.bin';

  ffi.DynamicLibrary? _library;
  bool _loadAttempted = false;
  String _loadError = '';
  bool _imageModelInitialized = false;
  bool _textModelInitialized = false;

  late final int Function() _isBackendAvailable;
  late final int Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)
  _initImageModel;
  late final int Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)
  _initTextModel;
  late final int Function() _releaseModels;
  late final int Function() _expectedImageInputLength;
  late final int Function() _expectedTextInputLength;
  late final int Function() _expectedOutputLength;
  late final int Function() _warmupImage;
  late final int Function() _warmupText;
  late final int Function(ffi.Pointer<ffi.Char>, int) _getVersion;
  late final int Function(ffi.Pointer<ffi.Char>, int) _getLastError;
  late final int Function(
    ffi.Pointer<ffi.Float>,
    int,
    ffi.Pointer<ffi.Float>,
    int,
  )
  _encodePreprocessed;
  late final int Function(
    ffi.Pointer<ffi.Uint8>,
    int,
    int,
    ffi.Pointer<ffi.Float>,
    int,
  )
  _encodeRgba8888;
  late final int Function(
    ffi.Pointer<ffi.Int32>,
    int,
    ffi.Pointer<ffi.Float>,
    int,
  )
  _encodeTextTokens;

  bool get isLibraryLoaded => _library != null;

  void _initialize() {
    if (_loadAttempted) {
      return;
    }
    _loadAttempted = true;

    if (!Platform.isAndroid) {
      _loadError = 'NCNN FFI bridge currently only targets Android.';
      return;
    }

    try {
      _library = ffi.DynamicLibrary.open(_androidLibraryName);
      _bindFunctions();
    } catch (error) {
      _loadError = error.toString();
      _library = null;
    }
  }

  void _bindFunctions() {
    final library = _library;
    if (library == null) {
      throw StateError('NCNN native library is not loaded.');
    }

    _isBackendAvailable = library
        .lookupFunction<ffi.Int32 Function(), int Function()>(
          'memoria_ncnn_is_backend_available',
        );
    _initImageModel = library
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>),
          int Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)
        >('memoria_ncnn_init_image_model');
    _initTextModel = library
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>),
          int Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)
        >('memoria_ncnn_init_text_model');
    _releaseModels = library
        .lookupFunction<ffi.Int32 Function(), int Function()>(
          'memoria_ncnn_release_models',
        );
    _expectedImageInputLength = library
        .lookupFunction<ffi.Int32 Function(), int Function()>(
          'memoria_ncnn_expected_image_input_length',
        );
    _expectedTextInputLength = library
        .lookupFunction<ffi.Int32 Function(), int Function()>(
          'memoria_ncnn_expected_text_input_length',
        );
    _expectedOutputLength = library
        .lookupFunction<ffi.Int32 Function(), int Function()>(
          'memoria_ncnn_expected_output_length',
        );
    _warmupImage = library.lookupFunction<ffi.Int32 Function(), int Function()>(
      'memoria_ncnn_warmup_image',
    );
    _warmupText = library.lookupFunction<ffi.Int32 Function(), int Function()>(
      'memoria_ncnn_warmup_text',
    );
    _getVersion = library
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Int32),
          int Function(ffi.Pointer<ffi.Char>, int)
        >('memoria_ncnn_get_version');
    _getLastError = library
        .lookupFunction<
          ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Int32),
          int Function(ffi.Pointer<ffi.Char>, int)
        >('memoria_ncnn_get_last_error');
    _encodePreprocessed = library
        .lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Float>,
            ffi.Int32,
            ffi.Pointer<ffi.Float>,
            ffi.Int32,
          ),
          int Function(ffi.Pointer<ffi.Float>, int, ffi.Pointer<ffi.Float>, int)
        >('memoria_ncnn_encode_preprocessed_f32');
    _encodeRgba8888 = library
        .lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Uint8>,
            ffi.Int32,
            ffi.Int32,
            ffi.Pointer<ffi.Float>,
            ffi.Int32,
          ),
          int Function(
            ffi.Pointer<ffi.Uint8>,
            int,
            int,
            ffi.Pointer<ffi.Float>,
            int,
          )
        >('memoria_ncnn_encode_rgba8888');
    _encodeTextTokens = library
        .lookupFunction<
          ffi.Int32 Function(
            ffi.Pointer<ffi.Int32>,
            ffi.Int32,
            ffi.Pointer<ffi.Float>,
            ffi.Int32,
          ),
          int Function(
            ffi.Pointer<ffi.Int32>,
            int,
            ffi.Pointer<ffi.Float>,
            int,
          )
        >('memoria_ncnn_encode_text_tokens');
  }

  NcnnBackendStatus getStatus() {
    _initialize();
    if (_library == null) {
      return NcnnBackendStatus(
        libraryLoaded: false,
        backendAvailable: false,
        modelInitialized: false,
        version: 'unavailable',
        lastError: _loadError,
        expectedInputLength: 0,
        expectedOutputLength: 0,
      );
    }

    final version = _readNativeString(_getVersion);
    final lastError = _readNativeString(_getLastError);
    return NcnnBackendStatus(
      libraryLoaded: true,
      backendAvailable: _isBackendAvailable() == 1,
      modelInitialized: _imageModelInitialized || _textModelInitialized,
      version: version,
      lastError: lastError,
      expectedInputLength: _expectedImageInputLength(),
      expectedOutputLength: _expectedOutputLength(),
    );
  }

  Future<void> ensureImageModelInitialized({
    String paramAssetPath = _defaultImageParamAssetPath,
    String binAssetPath = _defaultImageBinAssetPath,
  }) async {
    final status = getStatus();
    if (!status.libraryLoaded) {
      throw StateError(status.summary);
    }
    if (_imageModelInitialized) {
      return;
    }
    await AiModelWeightService.instance.ensureWeightsAvailableForInference(
      AiModelWeightId.mobileclipNcnn,
    );

    final stagingDirectory = await getApplicationDocumentsDirectory();
    final stagedParam = await _stageAssetToFile(
      assetPath: paramAssetPath,
      destinationPath: '${stagingDirectory.path}/image_encoder.ncnn.param',
    );
    final stagedBin = await _stageAssetToFile(
      assetPath: binAssetPath,
      destinationPath: '${stagingDirectory.path}/image_encoder.ncnn.bin',
    );

    final paramPtr = stagedParam.toNativeUtf8().cast<ffi.Char>();
    final binPtr = stagedBin.toNativeUtf8().cast<ffi.Char>();
    try {
      final code = _initImageModel(paramPtr, binPtr);
      _imageModelInitialized = code == 0;
      if (code != 0) {
        throw StateError(_readNativeString(_getLastError));
      }
    } finally {
      malloc.free(paramPtr);
      malloc.free(binPtr);
    }
  }

  Future<void> ensureTextModelInitialized({
    String paramAssetPath = _defaultTextParamAssetPath,
    String binAssetPath = _defaultTextBinAssetPath,
    String projectionParamAssetPath = _defaultProjectionParamAssetPath,
    String projectionBinAssetPath = _defaultProjectionBinAssetPath,
  }) async {
    final status = getStatus();
    if (!status.libraryLoaded) {
      throw StateError(status.summary);
    }
    if (_textModelInitialized) {
      return;
    }
    await AiModelWeightService.instance.ensureWeightsAvailableForInference(
      AiModelWeightId.mobileclipNcnn,
    );

    final stagingDirectory = await getApplicationDocumentsDirectory();
    final stagedParam = await _stageAssetToFile(
      assetPath: paramAssetPath,
      destinationPath: '${stagingDirectory.path}/text_encoder.ncnn.param',
    );
    final stagedBin = await _stageAssetToFile(
      assetPath: binAssetPath,
      destinationPath: '${stagingDirectory.path}/text_encoder.ncnn.bin',
    );
    await _stageAssetToFile(
      assetPath: projectionParamAssetPath,
      destinationPath:
          '${stagingDirectory.path}/projection_layer.ncnn.param',
    );
    await _stageAssetToFile(
      assetPath: projectionBinAssetPath,
      destinationPath: '${stagingDirectory.path}/projection_layer.ncnn.bin',
    );

    final paramPtr = stagedParam.toNativeUtf8().cast<ffi.Char>();
    final binPtr = stagedBin.toNativeUtf8().cast<ffi.Char>();
    try {
      final code = _initTextModel(paramPtr, binPtr);
      _textModelInitialized = code == 0;
      if (code != 0) {
        throw StateError(_readNativeString(_getLastError));
      }
    } finally {
      malloc.free(paramPtr);
      malloc.free(binPtr);
    }
  }

  Future<double> warmUpImage() async {
    await ensureImageModelInitialized();
    final status = getStatus();
    if (!status.libraryLoaded) {
      throw StateError(status.summary);
    }

    final stopwatch = Stopwatch()..start();
    final code = _warmupImage();
    stopwatch.stop();
    if (code != 0) {
      throw StateError(_readNativeString(_getLastError));
    }
    return stopwatch.elapsedMicroseconds / 1000.0;
  }

  Future<double> warmUpText() async {
    await ensureTextModelInitialized();
    final status = getStatus();
    if (!status.libraryLoaded) {
      throw StateError(status.summary);
    }

    final stopwatch = Stopwatch()..start();
    final code = _warmupText();
    stopwatch.stop();
    if (code != 0) {
      throw StateError(_readNativeString(_getLastError));
    }
    return stopwatch.elapsedMicroseconds / 1000.0;
  }

  Future<void> dispose() async {
    _initialize();
    if (_library == null) {
      _imageModelInitialized = false;
      _textModelInitialized = false;
      return;
    }

    final code = _releaseModels();
    _imageModelInitialized = false;
    _textModelInitialized = false;
    if (code != 0) {
      throw StateError(_readNativeString(_getLastError));
    }
  }

  Future<List<double>> encodePreprocessedInput(Float32List input) async {
    await ensureImageModelInitialized();
    final status = getStatus();
    if (!status.canEncode) {
      throw StateError(status.summary);
    }
    if (input.length != status.expectedInputLength) {
      throw ArgumentError(
        'Unexpected NCNN input length: ${input.length}, expected ${status.expectedInputLength}',
      );
    }

    final inputPtr = malloc.allocate<ffi.Float>(
      input.length * ffi.sizeOf<ffi.Float>(),
    );
    final outputPtr = malloc.allocate<ffi.Float>(
      status.expectedOutputLength * ffi.sizeOf<ffi.Float>(),
    );

    try {
      inputPtr.asTypedList(input.length).setAll(0, input);
      final code = _encodePreprocessed(
        inputPtr,
        input.length,
        outputPtr,
        status.expectedOutputLength,
      );
      if (code != 0) {
        throw StateError(_readNativeString(_getLastError));
      }

      return outputPtr
          .asTypedList(status.expectedOutputLength)
          .map((value) => value.toDouble())
          .toList(growable: false);
    } finally {
      malloc.free(inputPtr);
      malloc.free(outputPtr);
    }
  }

  Future<List<double>> encodeTextTokens(List<int> tokenIds) async {
    await ensureTextModelInitialized();
    final status = getStatus();
    if (!status.canEncode) {
      throw StateError(status.summary);
    }

    final expectedTextLength = _expectedTextInputLength();
    if (tokenIds.length != expectedTextLength) {
      throw ArgumentError(
        'NCNN text encoder expects $expectedTextLength tokens, got ${tokenIds.length}',
      );
    }

    final inputPtr = malloc.allocate<ffi.Int32>(
      tokenIds.length * ffi.sizeOf<ffi.Int32>(),
    );
    final outputPtr = malloc.allocate<ffi.Float>(
      status.expectedOutputLength * ffi.sizeOf<ffi.Float>(),
    );

    try {
      inputPtr
          .asTypedList(tokenIds.length)
          .setAll(0, Int32List.fromList(tokenIds));
      final code = _encodeTextTokens(
        inputPtr,
        tokenIds.length,
        outputPtr,
        status.expectedOutputLength,
      );
      if (code != 0) {
        throw StateError(_readNativeString(_getLastError));
      }

      return outputPtr
          .asTypedList(status.expectedOutputLength)
          .map((value) => value.toDouble())
          .toList(growable: false);
    } finally {
      malloc.free(inputPtr);
      malloc.free(outputPtr);
    }
  }

  Future<List<double>> encodeImageBytes(Uint8List imageBytes) async {
    final profile = await profileEncodeImageBytes(imageBytes);
    return profile.embedding;
  }

  Future<NcnnEncodeProfile> profileEncodeImageBytes(
    Uint8List imageBytes,
  ) async {
    await ensureImageModelInitialized();
    final status = getStatus();
    if (!status.canEncode) {
      throw StateError(status.summary);
    }

    final preprocessWatch = Stopwatch()..start();
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final rgbaData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgbaData == null) {
      image.dispose();
      codec.dispose();
      throw ArgumentError('无法解码图片数据');
    }
    final rgbaBytes = rgbaData.buffer.asUint8List(
      rgbaData.offsetInBytes,
      rgbaData.lengthInBytes,
    );
    preprocessWatch.stop();

    final inputPtr = malloc.allocate<ffi.Uint8>(rgbaBytes.length);
    final outputPtr = malloc.allocate<ffi.Float>(
      status.expectedOutputLength * ffi.sizeOf<ffi.Float>(),
    );

    try {
      inputPtr.asTypedList(rgbaBytes.length).setAll(0, rgbaBytes);
      final inferenceWatch = Stopwatch()..start();
      final code = _encodeRgba8888(
        inputPtr,
        image.width,
        image.height,
        outputPtr,
        status.expectedOutputLength,
      );
      inferenceWatch.stop();
      if (code != 0) {
        throw StateError(_readNativeString(_getLastError));
      }

      final embedding = outputPtr
          .asTypedList(status.expectedOutputLength)
          .map((value) => value.toDouble())
          .toList(growable: false);
      return NcnnEncodeProfile(
        embedding: embedding,
        preprocessMs: preprocessWatch.elapsedMicroseconds / 1000.0,
        inferenceMs: inferenceWatch.elapsedMicroseconds / 1000.0,
      );
    } finally {
      image.dispose();
      codec.dispose();
      malloc.free(inputPtr);
      malloc.free(outputPtr);
    }
  }

  String _readNativeString(
    int Function(ffi.Pointer<ffi.Char>, int) nativeFunction,
  ) {
    final buffer = malloc.allocate<ffi.Char>(_bufferSize);
    try {
      nativeFunction(buffer, _bufferSize);
      return buffer.cast<Utf8>().toDartString();
    } finally {
      malloc.free(buffer);
    }
  }

  Future<String> _stageAssetToFile({
    required String assetPath,
    required String destinationPath,
  }) async {
    final file = File(destinationPath);

    final data = await rootBundle.load(assetPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }
}
