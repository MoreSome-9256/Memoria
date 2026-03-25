import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalQwenBundledModelPaths {
  const LocalQwenBundledModelPaths({
    required this.modelPath,
    required this.mmprojPath,
  });

  final String modelPath;
  final String mmprojPath;
}

class LocalQwenBundledModelService {
  LocalQwenBundledModelService._internal();

  static final LocalQwenBundledModelService _instance =
      LocalQwenBundledModelService._internal();

  factory LocalQwenBundledModelService() => _instance;

  LocalQwenBundledModelPaths? _cached;

  Future<LocalQwenBundledModelPaths> ensureReady({
    required String modelAssetPath,
    required String mmprojAssetPath,
  }) async {
    final cached = _cached;
    if (cached != null &&
        File(cached.modelPath).existsSync() &&
        File(cached.mmprojPath).existsSync()) {
      return cached;
    }

    final supportDir = await getApplicationSupportDirectory();
    final modelFile = File(
      p.join(supportDir.path, 'local_vlm_models', p.basename(modelAssetPath)),
    );
    final mmprojFile = File(
      p.join(supportDir.path, 'local_vlm_models', p.basename(mmprojAssetPath)),
    );

    await _stageAssetIfNeeded(assetPath: modelAssetPath, destination: modelFile);
    await _stageAssetIfNeeded(
      assetPath: mmprojAssetPath,
      destination: mmprojFile,
    );

    final resolved = LocalQwenBundledModelPaths(
      modelPath: modelFile.path,
      mmprojPath: mmprojFile.path,
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