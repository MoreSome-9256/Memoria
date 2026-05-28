import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum AiModelWeightId {
  mobileclip2LiteRt,
  mobileclipNcnn,
  mobileViClipSmall,
  smolVlm2,
}

extension AiModelWeightIdX on AiModelWeightId {
  String get storageKey => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => 'mobileclip2_litert',
    AiModelWeightId.mobileclipNcnn => 'mobileclip_ncnn',
    AiModelWeightId.mobileViClipSmall => 'mobileviclip_small',
    AiModelWeightId.smolVlm2 => 'smolvlm2',
  };

  String get label => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => 'MobileCLIP2 LiteRT',
    AiModelWeightId.mobileclipNcnn => 'MobileCLIP NCNN',
    AiModelWeightId.mobileViClipSmall => 'MobileViCLIP Small',
    AiModelWeightId.smolVlm2 => 'SmolVLM2 描述模型',
  };

  String get description => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => '图片标签、文本向量和图片语义检索',
    AiModelWeightId.mobileclipNcnn => 'NCNN/Vulkan 方向的图片向量后端',
    AiModelWeightId.mobileViClipSmall => '视频和动态照片的时序向量',
    AiModelWeightId.smolVlm2 => '开发者工具中的图片/视频描述',
  };

  List<String> get relativePaths => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => const <String>[
      'mobileclip2/s2/mobileclip2_s2_image.tflite',
      'mobileclip2/s2/mobileclip2_s2_text.tflite',
    ],
    AiModelWeightId.mobileclipNcnn => const <String>[
      'ncnn/mobileclip_s2/image.param',
      'ncnn/mobileclip_s2/image.bin',
      'ncnn/mobileclip_s2/text.param',
      'ncnn/mobileclip_s2/text.bin',
    ],
    AiModelWeightId.mobileViClipSmall => const <String>[
      'mobileviclip/small/mobileviclip_small.onnx',
    ],
    AiModelWeightId.smolVlm2 => const <String>[
      'smolvlm2/smolvlm2.gguf',
      'smolvlm2/mmproj.gguf',
    ],
  };

  List<String> get downloadUrls => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => const <String>[
      'https://memoria-static-ai-models.earthnpc.online/MobileCLIP2/mobileclip2_s2_image.tflite',
      'https://memoria-static-ai-models.earthnpc.online/MobileCLIP2/mobileclip2_s2_text.tflite',
    ],
    AiModelWeightId.mobileclipNcnn => const <String>[
      'https://memoria-static-ai-models.earthnpc.online/NCNN/mobileclip_s2/image.param',
      'https://memoria-static-ai-models.earthnpc.online/NCNN/mobileclip_s2/image.bin',
      'https://memoria-static-ai-models.earthnpc.online/NCNN/mobileclip_s2/text.param',
      'https://memoria-static-ai-models.earthnpc.online/NCNN/mobileclip_s2/text.bin',
    ],
    AiModelWeightId.mobileViClipSmall => const <String>[
      'https://memoria-static-ai-models.earthnpc.online/MobileViCLIP/mobileviclip_small.onnx',
    ],
    AiModelWeightId.smolVlm2 => const <String>[
      'https://memoria-static-ai-models.earthnpc.online/SmolVLM2/SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
      'https://memoria-static-ai-models.earthnpc.online/SmolVLM2/mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
    ],
  };
}

class AiModelWeightStatus {
  const AiModelWeightStatus({
    required this.id,
    required this.presentFiles,
    required this.missingFiles,
    required this.checkPassed,
  });

  final AiModelWeightId id;
  final List<String> presentFiles;
  final List<String> missingFiles;
  final bool checkPassed;

  bool get hasDownloadedFiles => presentFiles.isNotEmpty;
}

/// 下载状态
enum DownloadState {
  idle,
  downloading,
  paused,
  completed,
  failed,
  canceled,
}

class DownloadProgress {
  const DownloadProgress({
    required this.state,
    required this.progress,
    required this.currentFile,
    required this.totalFiles,
    this.error,
  });

  final DownloadState state;
  final double progress;
  final int currentFile;
  final int totalFiles;
  final String? error;

  double get overallProgress => (currentFile + progress) / totalFiles;
}

class AiModelWeightService {
  AiModelWeightService._();
  static final AiModelWeightService instance = AiModelWeightService._();

  final Map<AiModelWeightId, DownloadTask> _activeTasks = {};
  final Map<AiModelWeightId, void Function(DownloadProgress progress)?> _progressCallbacks = {};
  final Map<AiModelWeightId, bool> _cancelFlags = {};

  Future<bool> ensureWeightsAvailableForInference(AiModelWeightId id) async {
    final root = await modelRootDirectory();
    for (final relativePath in id.relativePaths) {
      final file = File(_join(root.path, relativePath));
      if (!await file.exists()) {
        return false;
      }
    }
    return true;
  }

  Future<Directory> modelRootDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}${Platform.pathSeparator}models');
  }

  Future<List<AiModelWeightStatus>> loadStatuses() async {
    final root = await modelRootDirectory();
    final statuses = <AiModelWeightStatus>[];
    for (final id in AiModelWeightId.values) {
      final present = <String>[];
      final missing = <String>[];
      for (final relativePath in id.relativePaths) {
        final file = File(_join(root.path, relativePath));
        if (await file.exists()) {
          present.add(relativePath);
        } else {
          missing.add(relativePath);
        }
      }
      statuses.add(
        AiModelWeightStatus(
          id: id,
          presentFiles: present,
          missingFiles: missing,
          checkPassed: await ensureWeightsAvailableForInference(id),
        ),
      );
    }
    return statuses;
  }

  Future<void> deleteDownloadedWeights(AiModelWeightId id) async {
    final root = await modelRootDirectory();
    for (final relativePath in id.relativePaths) {
      final file = File(_join(root.path, relativePath));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> downloadWeights(
    AiModelWeightId id, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    if (_activeTasks.containsKey(id)) {
      debugPrint('Download already in progress for ${id.label}');
      return;
    }

    final root = await modelRootDirectory();
    final urls = id.downloadUrls;
    final paths = id.relativePaths;

    if (urls.length != paths.length) {
      throw StateError('URL count does not match path count for ${id.label}');
    }

    _progressCallbacks[id] = onProgress;
    _cancelFlags[id] = false;

    for (var i = 0; i < urls.length; i++) {
      if (_cancelFlags[id] == true) {
        _notifyProgress(id, DownloadState.canceled, 0.0, i, urls.length);
        _cleanup(id);
        return;
      }

      final url = urls[i];
      final relativePath = paths[i];
      final file = File(_join(root.path, relativePath));

      if (await file.exists()) {
        debugPrint('Model file already exists: ${file.path}');
        _notifyProgress(id, DownloadState.completed, 1.0, i + 1, urls.length);
        continue;
      }

      await file.parent.create(recursive: true);

      final task = DownloadTask(
        url: url,
        filename: relativePath.split('/').last,
        directory: file.parent.path,
        baseDirectory: BaseDirectory.root,
        updates: Updates.statusAndProgress,
        requiresWiFi: false,
        retries: 3,
        allowPause: true,
        metaData: id.name,
      );

      _activeTasks[id] = task;
      _notifyProgress(id, DownloadState.downloading, 0.0, i, urls.length);

        try {
        final result = await FileDownloader().download(
          task,
          onProgress: (progress) {
            if (_cancelFlags[id] == true) {
              FileDownloader().cancel(task);
              return;
            }
            _notifyProgress(id, DownloadState.downloading, progress, i, urls.length);
          },
          onStatus: (status) {
            debugPrint('Download status for ${id.label}: $status');
          },
        );

        if (result.status == TaskStatus.complete) {
          _notifyProgress(id, DownloadState.completed, 1.0, i + 1, urls.length);
        } else if (result.status == TaskStatus.canceled) {
          _notifyProgress(id, DownloadState.canceled, 0.0, i, urls.length);
          _cleanup(id);
          return;
        } else if (result.status == TaskStatus.failed) {
          _notifyProgress(id, DownloadState.failed, 0.0, i, urls.length, error: 'Download failed');
          _cleanup(id);
          return;
        }
      } catch (e) {
        _notifyProgress(id, DownloadState.failed, 0.0, i, urls.length, error: e.toString());
        _cleanup(id);
        return;
      }
    }

    _cleanup(id);
  }

  void _notifyProgress(
    AiModelWeightId id,
    DownloadState state,
    double progress,
    int currentFile,
    int totalFiles, {
    String? error,
  }) {
    _progressCallbacks[id]?.call(DownloadProgress(
      state: state,
      progress: progress,
      currentFile: currentFile,
      totalFiles: totalFiles,
      error: error,
    ));
  }

  void _cleanup(AiModelWeightId id) {
    _activeTasks.remove(id);
    _progressCallbacks.remove(id);
    _cancelFlags.remove(id);
  }

  Future<void> cancelDownload(AiModelWeightId id) async {
    final task = _activeTasks[id];
    if (task != null) {
      await FileDownloader().cancel(task);
      _cancelFlags[id] = true;
      _notifyProgress(id, DownloadState.canceled, 0.0, 0, 1);
      _cleanup(id);
      debugPrint('Download canceled for ${id.label}');
    }
  }

  bool isDownloading(AiModelWeightId id) => _activeTasks.containsKey(id);

  String _join(String root, String relativePath) {
    return relativePath
        .split('/')
        .fold(
          root,
          (path, segment) => '$path${Platform.pathSeparator}$segment',
        );
  }
}
