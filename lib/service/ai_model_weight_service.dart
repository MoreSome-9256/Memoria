import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AiModelWeightId { mobileclip2LiteRt, mobileViClipSmall, smolVlm2 }

extension AiModelWeightIdX on AiModelWeightId {
  String get storageKey => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => 'mobileclip2_litert',
    AiModelWeightId.mobileViClipSmall => 'mobileviclip_small',
    AiModelWeightId.smolVlm2 => 'smolvlm2',
  };

  String get label => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => 'MobileCLIP2 LiteRT',
    AiModelWeightId.mobileViClipSmall => 'MobileViCLIP Small',
    AiModelWeightId.smolVlm2 => 'SmolVLM2 描述模型',
  };

  String get description => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => '图片标签、文本向量和图片语义检索',
    AiModelWeightId.mobileViClipSmall => '视频和动态照片的时序向量',
    AiModelWeightId.smolVlm2 => '开发者工具中的图片/视频描述',
  };

  List<String> get relativePaths => switch (this) {
    AiModelWeightId.mobileclip2LiteRt => const <String>[
      'mobileclip2/s2/mobileclip2_s2_image.tflite',
      'mobileclip2/s2/mobileclip2_s2_text.tflite',
    ],
    AiModelWeightId.mobileViClipSmall => const <String>[
      'mobileviclip/small/mobileviclip_small_vision.onnx',
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
    AiModelWeightId.mobileViClipSmall => const <String>[
      'https://memoria-static-ai-models.earthnpc.online/MobileViCLIP/mobileviclip_small_vision.onnx',
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

class AiModelWeightDownloadSnapshot {
  const AiModelWeightDownloadSnapshot({
    required this.id,
    required this.status,
    required this.progress,
    required this.completedFiles,
    required this.totalFiles,
    required this.message,
    this.currentFile,
    this.error,
  });

  final AiModelWeightId id;
  final TaskStatus status;
  final double progress;
  final int completedFiles;
  final int totalFiles;
  final String message;
  final String? currentFile;
  final String? error;

  bool get isActive =>
      status == TaskStatus.enqueued ||
      status == TaskStatus.running ||
      status == TaskStatus.paused ||
      status == TaskStatus.waitingToRetry;

  bool get canPause => status == TaskStatus.running;
  bool get canResume => status == TaskStatus.paused;
  bool get canCancel => isActive;
}

class AiModelWeightService {
  AiModelWeightService._();
  static final AiModelWeightService instance = AiModelWeightService._();

  static const String _downloadGroup = 'ai_model_weights';

  final FileDownloader _downloader = FileDownloader();
  final ValueNotifier<Map<AiModelWeightId, AiModelWeightDownloadSnapshot>>
  _downloads = ValueNotifier(
    const <AiModelWeightId, AiModelWeightDownloadSnapshot>{},
  );
  final Map<AiModelWeightId, _WeightDownloadSession> _sessions =
      <AiModelWeightId, _WeightDownloadSession>{};
  final Map<String, AiModelWeightId> _taskOwners = <String, AiModelWeightId>{};

  StreamSubscription<TaskUpdate>? _updatesSubscription;
  bool _started = false;

  ValueListenable<Map<AiModelWeightId, AiModelWeightDownloadSnapshot>>
  get downloadsListenable => _downloads;

  Future<bool> ensureWeightsAvailableForInference(AiModelWeightId id) async {
    final root = await modelRootDirectory();
    for (final relativePath in id.relativePaths) {
      final file = File(_join(root.path, relativePath));
      if (!await file.exists() || await file.length() <= 0) {
        return false;
      }
    }
    return true;
  }

  Future<Directory> modelRootDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(_join(docs.path, 'models'));
  }

  Future<List<AiModelWeightStatus>> loadStatuses() async {
    await _ensureDownloaderStarted();
    await _syncTrackedDownloadSnapshots();
    final root = await modelRootDirectory();
    final statuses = <AiModelWeightStatus>[];
    for (final id in AiModelWeightId.values) {
      final present = <String>[];
      final missing = <String>[];
      for (final relativePath in id.relativePaths) {
        final file = File(_join(root.path, relativePath));
        if (await file.exists() && await file.length() > 0) {
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
          checkPassed: missing.isEmpty,
        ),
      );
    }
    return statuses;
  }

  Future<void> deleteDownloadedWeights(AiModelWeightId id) async {
    await cancelDownload(id);
    final root = await modelRootDirectory();
    for (final relativePath in id.relativePaths) {
      final file = File(_join(root.path, relativePath));
      if (await file.exists()) {
        await file.delete();
      }
    }
    _removeSnapshot(id);
  }

  Future<void> downloadWeights(
    AiModelWeightId id, {
    void Function(double progress, TaskStatus status)? onProgress,
  }) async {
    await _ensureDownloaderStarted();
    if (_sessions.containsKey(id)) {
      debugPrint('[weights] ${id.label} download already active');
      return;
    }

    final urls = id.downloadUrls;
    final paths = id.relativePaths;
    if (urls.length != paths.length) {
      throw StateError('URL count does not match path count for ${id.label}');
    }

    final root = await modelRootDirectory();
    final session = _WeightDownloadSession(
      id: id,
      totalFiles: paths.length,
      progressCallback: onProgress,
    );
    _sessions[id] = session;

    try {
      _publish(session, TaskStatus.enqueued, message: '准备下载 ${id.label}');

      for (var i = 0; i < paths.length; i++) {
        if (session.cancelRequested) {
          _publish(session, TaskStatus.canceled, message: '已取消');
          return;
        }

        final relativePath = paths[i];
        final file = File(_join(root.path, relativePath));
        if (await file.exists() && await file.length() > 0) {
          session.completedFiles = i + 1;
          session.currentFileProgress = 0;
          _publish(
            session,
            TaskStatus.running,
            currentFile: relativePath,
            message: '已存在，跳过 ${i + 1}/${paths.length}',
          );
          continue;
        }

        await file.parent.create(recursive: true);
        final task = _buildTask(
          id: id,
          url: urls[i],
          relativePath: relativePath,
        );
        session.currentTask = task;
        session.currentCompleter = Completer<TaskStatus>();
        _taskOwners[task.taskId] = id;

        _publish(
          session,
          TaskStatus.enqueued,
          currentFile: relativePath,
          message: '等待下载 ${i + 1}/${paths.length}',
        );

        final enqueued = await _downloader.enqueue(task);
        if (!enqueued) {
          throw StateError('无法加入下载队列: $relativePath');
        }

        final status = await session.currentCompleter!.future;
        _taskOwners.remove(task.taskId);
        session.currentTask = null;
        session.currentCompleter = null;

        if (status == TaskStatus.complete) {
          if (!await file.exists() || await file.length() <= 0) {
            throw StateError('下载完成但文件不存在或为空: $relativePath');
          }
          session.completedFiles = i + 1;
          session.currentFileProgress = 0;
          _publish(
            session,
            TaskStatus.running,
            currentFile: relativePath,
            message: '已完成 ${i + 1}/${paths.length}',
          );
          continue;
        }

        _publish(session, status, currentFile: relativePath, message: '下载已中断');
        return;
      }

      _publish(session, TaskStatus.complete, message: '下载完成');
    } catch (error) {
      debugPrint('[weights] ${id.label} download failed: $error');
      _publish(
        session,
        TaskStatus.failed,
        message: '下载失败',
        error: error.toString(),
      );
      rethrow;
    } finally {
      if (_downloads.value[id]?.status != TaskStatus.paused) {
        _sessions.remove(id);
      }
    }
  }

  Future<void> pauseDownload(AiModelWeightId id) async {
    final session = _sessions[id];
    final task = session?.currentTask;
    if (task == null) {
      return;
    }
    final paused = await _downloader.pause(task);
    if (!paused) {
      debugPrint('[weights] pause rejected for ${id.label}');
    }
  }

  Future<void> resumeDownload(AiModelWeightId id) async {
    final session = _sessions[id];
    final task = session?.currentTask;
    if (session == null || task == null) {
      return;
    }
    final resumed = await _downloader.resume(task);
    if (resumed) {
      _publish(session, TaskStatus.enqueued, message: '继续下载');
    } else {
      debugPrint('[weights] resume rejected for ${id.label}');
    }
  }

  Future<void> cancelDownload(AiModelWeightId id) async {
    final session = _sessions[id];
    if (session == null) {
      _removeSnapshot(id);
      return;
    }
    session.cancelRequested = true;
    final task = session.currentTask;
    if (task != null) {
      await _downloader.cancel(task);
    }
    if (session.currentCompleter != null &&
        !session.currentCompleter!.isCompleted) {
      session.currentCompleter!.complete(TaskStatus.canceled);
    }
    _publish(session, TaskStatus.canceled, message: '已取消');
    _sessions.remove(id);
  }

  bool isDownloading(AiModelWeightId id) {
    return _downloads.value[id]?.isActive ?? false;
  }

  Future<void> _ensureDownloaderStarted() async {
    if (_updatesSubscription == null) {
      _updatesSubscription = _downloader.updates.listen(_handleTaskUpdate);
      await _downloader.trackTasksInGroup(_downloadGroup);
    }
    if (!_started) {
      _started = true;
      await _downloader.start(
        doTrackTasks: false,
        doRescheduleKilledTasks: false,
      );
    }
  }

  DownloadTask _buildTask({
    required AiModelWeightId id,
    required String url,
    required String relativePath,
  }) {
    final directory = p.posix.join('models', p.posix.dirname(relativePath));
    return DownloadTask(
      url: url,
      filename: p.posix.basename(relativePath),
      directory: directory,
      baseDirectory: BaseDirectory.applicationDocuments,
      group: _downloadGroup,
      updates: Updates.statusAndProgress,
      requiresWiFi: false,
      retries: 5,
      allowPause: true,
      metaData: jsonEncode(<String, Object?>{
        'model': id.name,
        'path': relativePath,
      }),
    );
  }

  void _handleTaskUpdate(TaskUpdate update) {
    final id = _taskOwners[update.task.taskId] ?? _idFromMetadata(update.task);
    if (id == null) {
      return;
    }
    final session = _sessions[id];
    if (session == null || session.currentTask?.taskId != update.task.taskId) {
      return;
    }

    switch (update) {
      case TaskProgressUpdate():
        final progress = update.progress;
        if (progress >= 0 && progress <= 1) {
          session.currentFileProgress = progress;
          _publish(
            session,
            TaskStatus.running,
            currentFile: _pathFromMetadata(update.task),
            message: '正在下载 ${session.completedFiles + 1}/${session.totalFiles}',
          );
        }
      case TaskStatusUpdate():
        final status = update.status;
        _publish(
          session,
          status,
          currentFile: _pathFromMetadata(update.task),
          message: _messageForStatus(status),
          error: update.exception?.description,
        );
        if (status == TaskStatus.paused) {
          return;
        }
        if (session.recoveredOnly) {
          _taskOwners.remove(update.task.taskId);
          if (status == TaskStatus.complete) {
            _sessions.remove(id);
            unawaited(downloadWeights(id));
          } else if (status == TaskStatus.canceled ||
              status == TaskStatus.failed ||
              status == TaskStatus.notFound) {
            _sessions.remove(id);
          }
          return;
        }
        if (status == TaskStatus.complete ||
            status == TaskStatus.canceled ||
            status == TaskStatus.failed ||
            status == TaskStatus.notFound) {
          final completer = session.currentCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.complete(status);
          }
        }
    }
  }

  AiModelWeightId? _idFromMetadata(Task task) {
    try {
      final data = jsonDecode(task.metaData) as Map<String, dynamic>;
      final model = data['model']?.toString();
      for (final id in AiModelWeightId.values) {
        if (id.name == model) {
          return id;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _pathFromMetadata(Task task) {
    try {
      final data = jsonDecode(task.metaData) as Map<String, dynamic>;
      return data['path']?.toString();
    } catch (_) {
      return null;
    }
  }

  String _messageForStatus(TaskStatus status) => switch (status) {
    TaskStatus.enqueued => '等待下载',
    TaskStatus.running => '正在下载',
    TaskStatus.complete => '文件下载完成',
    TaskStatus.notFound => '任务不存在',
    TaskStatus.failed => '下载失败',
    TaskStatus.canceled => '已取消',
    TaskStatus.waitingToRetry => '等待重试',
    TaskStatus.paused => '已暂停',
  };

  Future<void> _syncTrackedDownloadSnapshots() async {
    final records = await _downloader.database.allRecords(
      group: _downloadGroup,
    );
    for (final record in records) {
      if (record.status.isFinalState) {
        continue;
      }
      final task = record.task;
      if (task is! DownloadTask) {
        continue;
      }
      final id = _idFromMetadata(task);
      if (id == null || _sessions.containsKey(id)) {
        continue;
      }
      final currentFile = _pathFromMetadata(task);
      final completedFiles = await _countPresentFilesBefore(id, currentFile);
      final session =
          _WeightDownloadSession(
              id: id,
              totalFiles: id.relativePaths.length,
              recoveredOnly: true,
            )
            ..completedFiles = completedFiles
            ..currentFileProgress = record.progress >= 0 && record.progress <= 1
                ? record.progress
                : 0
            ..currentTask = task;
      _sessions[id] = session;
      _taskOwners[task.taskId] = id;
      _publish(
        session,
        record.status,
        currentFile: currentFile,
        message: _messageForStatus(record.status),
        error: record.exception?.description,
      );
    }
  }

  Future<int> _countPresentFilesBefore(
    AiModelWeightId id,
    String? currentFile,
  ) async {
    if (currentFile == null || currentFile.isEmpty) {
      return 0;
    }
    final currentIndex = id.relativePaths.indexOf(currentFile);
    if (currentIndex <= 0) {
      return 0;
    }
    final root = await modelRootDirectory();
    var present = 0;
    for (final relativePath in id.relativePaths.take(currentIndex)) {
      final file = File(_join(root.path, relativePath));
      if (await file.exists() && await file.length() > 0) {
        present++;
      }
    }
    return present;
  }

  void _publish(
    _WeightDownloadSession session,
    TaskStatus status, {
    String? currentFile,
    required String message,
    String? error,
  }) {
    final total = session.totalFiles <= 0 ? 1 : session.totalFiles;
    final progress = status == TaskStatus.complete
        ? 1.0
        : ((session.completedFiles + session.currentFileProgress) / total)
              .clamp(0.0, 1.0);
    final snapshot = AiModelWeightDownloadSnapshot(
      id: session.id,
      status: status,
      progress: progress,
      completedFiles: status == TaskStatus.complete
          ? session.totalFiles
          : session.completedFiles,
      totalFiles: session.totalFiles,
      currentFile: currentFile,
      message: message,
      error: error,
    );
    _downloads.value = <AiModelWeightId, AiModelWeightDownloadSnapshot>{
      ..._downloads.value,
      session.id: snapshot,
    };
    session.progressCallback?.call(snapshot.progress, status);
  }

  void _removeSnapshot(AiModelWeightId id) {
    if (!_downloads.value.containsKey(id)) {
      return;
    }
    final next = <AiModelWeightId, AiModelWeightDownloadSnapshot>{
      ..._downloads.value,
    }..remove(id);
    _downloads.value = next;
  }

  String _join(String root, String relativePath) {
    return relativePath
        .split('/')
        .fold(
          root,
          (path, segment) => '$path${Platform.pathSeparator}$segment',
        );
  }
}

class _WeightDownloadSession {
  _WeightDownloadSession({
    required this.id,
    required this.totalFiles,
    this.progressCallback,
    this.recoveredOnly = false,
  });

  final AiModelWeightId id;
  final int totalFiles;
  final void Function(double progress, TaskStatus status)? progressCallback;
  final bool recoveredOnly;

  int completedFiles = 0;
  double currentFileProgress = 0;
  DownloadTask? currentTask;
  Completer<TaskStatus>? currentCompleter;
  bool cancelRequested = false;
}
