import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalQwenBundledModelPaths {
  const LocalQwenBundledModelPaths({
    required this.modelPath,
  });

  final String modelPath;
}

class LocalQwenBundledModelService {
  LocalQwenBundledModelService._internal();

  static final LocalQwenBundledModelService _instance =
      LocalQwenBundledModelService._internal();

  factory LocalQwenBundledModelService() => _instance;

  LocalQwenBundledModelPaths? _cached;

  Future<LocalQwenBundledModelPaths> ensureReady({
    required String modelAssetPath,
  }) async {
    final cached = _cached;
    if (cached != null && File(cached.modelPath).existsSync()) {
      return cached;
    }

    final supportDir = await getApplicationSupportDirectory();
    final modelFile = File(
      p.join(supportDir.path, 'local_vlm_models', p.basename(modelAssetPath)),
    );

    await _stageAssetIfNeeded(assetPath: modelAssetPath, destination: modelFile);

    final resolved = LocalQwenBundledModelPaths(
      modelPath: modelFile.path,
    );
    _cached = resolved;
    return resolved;
  }

  Future<void> _stageAssetIfNeeded({
    required String assetPath,
    required File destination,
  }) async {
    ByteData data;
    try {
      data = await rootBundle.load(assetPath);
    } catch (error) {
      throw StateError('未找到内置模型资源 $assetPath: $error');
    }

    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    if (destination.existsSync() && destination.lengthSync() == bytes.length) {
      return;
    }

    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes, flush: true);
  }
}