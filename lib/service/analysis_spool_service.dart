import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Spool 目录结构：
/// ```
/// app_files/
///   analysis_spool/
///     spool_version.json       -- 自增版本号，主进程轮询时先检查
///     jobs/
///       <jobId>/
///         manifest.json        -- 主进程写入：要处理的图片列表
///         progress.json        -- 服务进程写入：当前进度
///         done.marker          -- 服务进程写入：计算完成标记
///         tmp/                 -- 不完整的临时文件
///         inputs/              -- 主进程准备好的稳定输入文件
///         results_pending/     -- 服务完成的结果，等待主进程消费
///         results_committed/   -- 主进程已消费并写库的结果
///         results_failed/      -- 主进程消费失败的结果
///         embeddings/          -- embedding 二进制文件 (.f32)
/// ```

/// 一张图片的分析任务项。
class AnalysisSpoolItem {
  final String photoKey;
  final String? contentUri;
  final String? path;
  final int? photoId;
  final int modifiedAt;
  final double? latitude;
  final double? longitude;
  final int width;
  final int height;

  const AnalysisSpoolItem({
    required this.photoKey,
    this.contentUri,
    this.path,
    this.photoId,
    required this.modifiedAt,
    this.latitude,
    this.longitude,
    this.width = 0,
    this.height = 0,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'photoKey': photoKey,
    'contentUri': contentUri,
    'path': path,
    'photoId': photoId,
    'modifiedAt': modifiedAt,
    'latitude': latitude,
    'longitude': longitude,
    'width': width,
    'height': height,
  };

  factory AnalysisSpoolItem.fromJson(Map<String, Object?> json) {
    return AnalysisSpoolItem(
      photoKey: json['photoKey'] as String,
      contentUri: json['contentUri'] as String?,
      path: json['path'] as String?,
      photoId: json['photoId'] as int?,
      modifiedAt: (json['modifiedAt'] as num).toInt(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Job manifest — 由主进程写入，服务进程读取。
class AnalysisJobManifest {
  final String jobId;
  final int createdAt;
  final String mode;
  final List<AnalysisSpoolItem> items;
  final String? modelVersion;

  const AnalysisJobManifest({
    required this.jobId,
    required this.createdAt,
    this.mode = 'full',
    required this.items,
    this.modelVersion,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'jobId': jobId,
    'createdAt': createdAt,
    'mode': mode,
    'items': items.map((i) => i.toJson()).toList(),
    'modelVersion': modelVersion,
  };

  factory AnalysisJobManifest.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'] as List<Object?>;
    return AnalysisJobManifest(
      jobId: json['jobId'] as String,
      createdAt: (json['createdAt'] as num).toInt(),
      mode: (json['mode'] as String?) ?? 'full',
      items: rawItems
          .cast<Map<String, Object?>>()
          .map(AnalysisSpoolItem.fromJson)
          .toList(),
      modelVersion: json['modelVersion'] as String?,
    );
  }

  int get totalItems => items.length;
}

/// 一张图片的分析结果。
class AnalysisSpoolResult {
  final String jobId;
  final String photoKey;
  final int photoId;
  final String status; // succeeded / failed / skipped
  final String? embeddingFile;
  final int embeddingDim;
  final String? modelVersion;
  final String? errorMessage;
  final int startedAt;
  final int finishedAt;

  // 分析数据（仅 succeeded 时有值）
  final List<String> tags;
  final String aiCaption;
  final String ocrText;
  final List<String> ocrTags;
  final bool ocrRequired;
  final bool ocrCompleted;
  final int faceCount;
  final double smileProb;
  final double joyScore;
  final bool faceAnalysisRequired;
  final bool faceAnalysisCompleted;
  final bool isJunk;
  final String? junkCategoryId;

  // 地址信息（高德逆地理编码结果）
  final String? province;
  final String? city;
  final String? district;
  final String? locationName;
  final String? formattedAddress;
  final String? adcode;

  const AnalysisSpoolResult({
    required this.jobId,
    required this.photoKey,
    this.photoId = 0,
    required this.status,
    this.embeddingFile,
    this.embeddingDim = 0,
    this.modelVersion,
    this.errorMessage,
    required this.startedAt,
    required this.finishedAt,
    this.tags = const <String>[],
    this.aiCaption = '',
    this.ocrText = '',
    this.ocrTags = const <String>[],
    this.ocrRequired = false,
    this.ocrCompleted = true,
    this.faceCount = 0,
    this.smileProb = 0.0,
    this.joyScore = 0.0,
    this.faceAnalysisRequired = false,
    this.faceAnalysisCompleted = true,
    this.isJunk = false,
    this.junkCategoryId,
    this.province,
    this.city,
    this.district,
    this.locationName,
    this.formattedAddress,
    this.adcode,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'jobId': jobId,
    'photoKey': photoKey,
    'photoId': photoId,
    'status': status,
    'embeddingFile': embeddingFile,
    'embeddingDim': embeddingDim,
    'modelVersion': modelVersion,
    'errorMessage': errorMessage,
    'startedAt': startedAt,
    'finishedAt': finishedAt,
    'tags': tags,
    'aiCaption': aiCaption,
    'ocrText': ocrText,
    'ocrTags': ocrTags,
    'ocrRequired': ocrRequired,
    'ocrCompleted': ocrCompleted,
    'faceCount': faceCount,
    'smileProb': smileProb,
    'joyScore': joyScore,
    'faceAnalysisRequired': faceAnalysisRequired,
    'faceAnalysisCompleted': faceAnalysisCompleted,
    'isJunk': isJunk,
    'junkCategoryId': junkCategoryId,
    'province': province,
    'city': city,
    'district': district,
    'locationName': locationName,
    'formattedAddress': formattedAddress,
    'adcode': adcode,
  };

  factory AnalysisSpoolResult.fromJson(Map<String, Object?> json) {
    return AnalysisSpoolResult(
      jobId: json['jobId'] as String,
      photoKey: json['photoKey'] as String,
      photoId: (json['photoId'] as num?)?.toInt() ?? 0,
      status: json['status'] as String,
      embeddingFile: json['embeddingFile'] as String?,
      embeddingDim: (json['embeddingDim'] as num?)?.toInt() ?? 0,
      modelVersion: json['modelVersion'] as String?,
      errorMessage: json['errorMessage'] as String?,
      startedAt: (json['startedAt'] as num).toInt(),
      finishedAt: (json['finishedAt'] as num).toInt(),
      tags: (json['tags'] as List<Object?>?)?.cast<String>() ?? <String>[],
      aiCaption: (json['aiCaption'] as String?) ?? '',
      ocrText: (json['ocrText'] as String?) ?? '',
      ocrTags:
          (json['ocrTags'] as List<Object?>?)?.cast<String>() ?? <String>[],
      ocrRequired: (json['ocrRequired'] as bool?) ?? false,
      ocrCompleted: (json['ocrCompleted'] as bool?) ?? true,
      faceCount: (json['faceCount'] as num?)?.toInt() ?? 0,
      smileProb: (json['smileProb'] as num?)?.toDouble() ?? 0.0,
      joyScore: (json['joyScore'] as num?)?.toDouble() ?? 0.0,
      faceAnalysisRequired: (json['faceAnalysisRequired'] as bool?) ?? false,
      faceAnalysisCompleted: (json['faceAnalysisCompleted'] as bool?) ?? true,
      isJunk: (json['isJunk'] as bool?) ?? false,
      junkCategoryId: json['junkCategoryId'] as String?,
      province: json['province'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
      locationName: json['locationName'] as String?,
      formattedAddress: json['formattedAddress'] as String?,
      adcode: json['adcode'] as String?,
    );
  }

  bool get isSucceeded => status == 'succeeded';
  bool get isFailed => status == 'failed';
  bool get isSkipped => status == 'skipped';
}

/// 进度快照 — 服务进程写入，主进程读取用于 UI 展示。
class AnalysisProgressSnapshot {
  final String jobId;
  final String status; // running / paused / finished / failed
  final int total;
  final int processed;
  final int succeeded;
  final int failed;
  final int skipped;
  final int warmUpCompleted;
  final int warmUpTotal;
  final int updatedAt;
  final int? processingStartedAt;
  final String currentStep;

  const AnalysisProgressSnapshot({
    required this.jobId,
    required this.status,
    required this.total,
    required this.processed,
    required this.succeeded,
    required this.failed,
    required this.skipped,
    this.warmUpCompleted = 0,
    this.warmUpTotal = 0,
    required this.updatedAt,
    this.processingStartedAt,
    this.currentStep = '',
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'jobId': jobId,
    'status': status,
    'total': total,
    'processed': processed,
    'succeeded': succeeded,
    'failed': failed,
    'skipped': skipped,
    'warmUpCompleted': warmUpCompleted,
    'warmUpTotal': warmUpTotal,
    'updatedAt': updatedAt,
    'processingStartedAt': processingStartedAt,
    'currentStep': currentStep,
  };

  factory AnalysisProgressSnapshot.fromJson(Map<String, Object?> json) {
    return AnalysisProgressSnapshot(
      jobId: json['jobId'] as String,
      status: json['status'] as String,
      total: (json['total'] as num).toInt(),
      processed: (json['processed'] as num).toInt(),
      succeeded: (json['succeeded'] as num).toInt(),
      failed: (json['failed'] as num).toInt(),
      skipped: (json['skipped'] as num).toInt(),
      warmUpCompleted: (json['warmUpCompleted'] as num?)?.toInt() ?? 0,
      warmUpTotal: (json['warmUpTotal'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num).toInt(),
      processingStartedAt: (json['processingStartedAt'] as num?)?.toInt(),
      currentStep: (json['currentStep'] as String?) ?? '',
    );
  }

  double get fraction => total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;
}

/// 主进程写入、前台服务读取的控制快照。
class AnalysisJobControl {
  final String jobId;
  final bool pauseRequested;
  final bool stopRequested;
  final int updatedAt;

  const AnalysisJobControl({
    required this.jobId,
    this.pauseRequested = false,
    this.stopRequested = false,
    required this.updatedAt,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'jobId': jobId,
    'pauseRequested': pauseRequested,
    'stopRequested': stopRequested,
    'updatedAt': updatedAt,
  };

  factory AnalysisJobControl.fromJson(Map<String, Object?> json) {
    return AnalysisJobControl(
      jobId: json['jobId'] as String,
      pauseRequested: (json['pauseRequested'] as bool?) ?? false,
      stopRequested: (json['stopRequested'] as bool?) ?? false,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  factory AnalysisJobControl.running(String jobId) {
    return AnalysisJobControl(
      jobId: jobId,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  AnalysisJobControl copyWith({bool? pauseRequested, bool? stopRequested}) {
    return AnalysisJobControl(
      jobId: jobId,
      pauseRequested: pauseRequested ?? this.pauseRequested,
      stopRequested: stopRequested ?? this.stopRequested,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Spool 版本信息，用于主进程快速判断是否需要扫描。
class SpoolVersion {
  final int version;
  final int updatedAt;

  const SpoolVersion({required this.version, required this.updatedAt});

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'updatedAt': updatedAt,
  };

  factory SpoolVersion.fromJson(Map<String, Object?> json) {
    return SpoolVersion(
      version: (json['version'] as num).toInt(),
      updatedAt: (json['updatedAt'] as num).toInt(),
    );
  }
}

/// 文件系统级别的 spool 操作。
///
/// 设计原则：
/// - 所有文件写入使用 tmp + fsync + atomic rename
/// - 服务进程不写数据库
/// - 主进程不写 tmp/ 目录
/// - results_pending/ 中的文件视为完整可用
class AnalysisSpoolService {
  AnalysisSpoolService._();
  static final AnalysisSpoolService instance = AnalysisSpoolService._();

  static Directory? _baseDir;

  /// 初始化 spool 目录。
  Future<Directory> get baseDir async {
    if (_baseDir != null) return _baseDir!;
    final appDir = await getApplicationSupportDirectory();
    _baseDir = Directory('${appDir.path}/analysis_spool');
    if (!await _baseDir!.exists()) {
      await _baseDir!.create(recursive: true);
    }
    await Directory('${_baseDir!.path}/jobs').create(recursive: true);
    return _baseDir!;
  }

  // ── Job 目录管理 ──

  String _jobDir(String jobId) => '${_baseDir!.path}/jobs/$jobId';
  String _tmpDir(String jobId) => '${_jobDir(jobId)}/tmp';
  String _pendingDir(String jobId) => '${_jobDir(jobId)}/results_pending';
  String _committedDir(String jobId) => '${_jobDir(jobId)}/results_committed';
  String _failedDir(String jobId) => '${_jobDir(jobId)}/results_failed';
  String _embeddingsDir(String jobId) => '${_jobDir(jobId)}/embeddings';
  String _inputsDir(String jobId) => '${_jobDir(jobId)}/inputs';

  Future<void> ensureJobDirs(String jobId) async {
    await baseDir;
    await Directory(_jobDir(jobId)).create(recursive: true);
    await Directory(_tmpDir(jobId)).create(recursive: true);
    await Directory(_pendingDir(jobId)).create(recursive: true);
    await Directory(_committedDir(jobId)).create(recursive: true);
    await Directory(_failedDir(jobId)).create(recursive: true);
    await Directory(_embeddingsDir(jobId)).create(recursive: true);
    await Directory(_inputsDir(jobId)).create(recursive: true);
  }

  Future<File> inputFileFor({
    required String jobId,
    required String photoKey,
    required String extension,
  }) async {
    await ensureJobDirs(jobId);
    final safeKey = Uri.encodeComponent(photoKey);
    final safeExtension = extension.startsWith('.') ? extension : '.$extension';
    return File('${_inputsDir(jobId)}/$safeKey$safeExtension');
  }

  // ── Manifest 写入/读取（主进程写入，服务进程读取）──

  String _manifestPath(String jobId) => '${_jobDir(jobId)}/manifest.json';

  Future<void> writeManifest(AnalysisJobManifest manifest) async {
    await baseDir; // 确保 _baseDir 初始化
    await ensureJobDirs(manifest.jobId);
    final json = jsonEncode(manifest.toJson());
    final tmpPath = '${_tmpDir(manifest.jobId)}/manifest.json.tmp';
    final file = File(tmpPath);
    await file.writeAsString(json, flush: true);
    await file.rename(_manifestPath(manifest.jobId));
    debugPrint(
      '[spool] manifest 写入 jobId=${manifest.jobId} '
      'items=${manifest.totalItems} mode=${manifest.mode}',
    );
  }

  Future<AnalysisJobManifest?> readManifest(String jobId) async {
    await baseDir;
    final file = File(_manifestPath(jobId));
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return AnalysisJobManifest.fromJson(json);
    } catch (e) {
      debugPrint('[spool] manifest 读取失败 jobId=$jobId: $e');
      return null;
    }
  }

  // ── Progress 写入/读取（服务进程写入，主进程读取）──

  String _progressPath(String jobId) => '${_jobDir(jobId)}/progress.json';

  Future<void> writeProgress(AnalysisProgressSnapshot snapshot) async {
    await baseDir;
    await ensureJobDirs(snapshot.jobId);
    final json = jsonEncode(snapshot.toJson());
    final tmpPath = '${_tmpDir(snapshot.jobId)}/progress.json.tmp';
    final file = File(tmpPath);
    await file.writeAsString(json, flush: true);
    await file.rename(_progressPath(snapshot.jobId));
    await _bumpSpoolVersion();
  }

  Future<AnalysisProgressSnapshot?> readProgress(String jobId) async {
    await baseDir;
    final file = File(_progressPath(jobId));
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return AnalysisProgressSnapshot.fromJson(json);
    } catch (e) {
      debugPrint('[spool] progress 读取失败 jobId=$jobId: $e');
      return null;
    }
  }

  // ── Done marker（服务进程写入）──

  String _doneMarkerPath(String jobId) => '${_jobDir(jobId)}/done.marker';
  String _controlPath(String jobId) => '${_jobDir(jobId)}/control.json';
  String _fileKey(String rawKey) => Uri.encodeComponent(rawKey);
  Future<bool> jobExists(String jobId) async {
    await baseDir;
    return Directory(_jobDir(jobId)).exists();
  }

  Future<void> writeDoneMarker(String jobId) async {
    await baseDir;
    await ensureJobDirs(jobId);
    final tmpPath = '${_tmpDir(jobId)}/done.marker.tmp';
    final file = File(tmpPath);
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'jobId': jobId,
        'finishedAt': DateTime.now().millisecondsSinceEpoch,
      }),
      flush: true,
    );
    await file.rename(_doneMarkerPath(jobId));
    await _bumpSpoolVersion();
    debugPrint('[spool] done.marker 写入 jobId=$jobId');
  }

  Future<bool> hasDoneMarker(String jobId) async {
    await baseDir;
    return File(_doneMarkerPath(jobId)).exists();
  }

  // ── Control 写入/读取（主进程写入，服务进程读取）──

  Future<void> writeControl(AnalysisJobControl control) async {
    await baseDir;
    if (!await Directory(_jobDir(control.jobId)).exists()) {
      debugPrint('[spool] control 写入跳过：job 已不存在 jobId=${control.jobId}');
      return;
    }
    await Directory(_tmpDir(control.jobId)).create(recursive: true);
    final tmpPath = '${_tmpDir(control.jobId)}/control.json.tmp';
    final file = File(tmpPath);
    try {
      await file.writeAsString(jsonEncode(control.toJson()), flush: true);
      if (!await Directory(_jobDir(control.jobId)).exists()) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
        return;
      }
      await file.rename(_controlPath(control.jobId));
      await _bumpSpoolVersion();
    } on PathNotFoundException {
      debugPrint('[spool] control 写入跳过：job 已被清理 jobId=${control.jobId}');
      return;
    }
  }

  Future<AnalysisJobControl> readControl(String jobId) async {
    await baseDir;
    final file = File(_controlPath(jobId));
    if (!await file.exists()) return AnalysisJobControl.running(jobId);
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return AnalysisJobControl.fromJson(json);
    } catch (e) {
      debugPrint('[spool] control 读取失败 jobId=$jobId: $e');
      return AnalysisJobControl.running(jobId);
    }
  }

  Future<void> requestPause(String jobId) async {
    if (!await jobExists(jobId)) return;
    final current = await readControl(jobId);
    await writeControl(
      current.copyWith(pauseRequested: true, stopRequested: false),
    );
  }

  Future<void> requestResume(String jobId) async {
    if (!await jobExists(jobId)) return;
    final current = await readControl(jobId);
    await writeControl(
      current.copyWith(pauseRequested: false, stopRequested: false),
    );
  }

  Future<void> requestStop(String jobId) async {
    if (!await jobExists(jobId)) return;
    final current = await readControl(jobId);
    await writeControl(
      current.copyWith(pauseRequested: false, stopRequested: true),
    );
  }

  // ── Result 写入（服务进程写入）──

  /// 写入单张图片的 result.json（使用 tmp + fsync + atomic rename）。
  Future<String> writeResult(String jobId, AnalysisSpoolResult result) async {
    await baseDir;
    await ensureJobDirs(jobId);
    final json = jsonEncode(result.toJson());
    final key = _fileKey(result.photoKey);
    final tmpPath = '${_tmpDir(jobId)}/$key.json.tmp';
    final pendingPath = '${_pendingDir(jobId)}/$key.json';
    final file = File(tmpPath);
    await file.writeAsString(json, flush: true);
    await file.rename(pendingPath);
    await _bumpSpoolVersion();
    return pendingPath;
  }

  /// 写入 embedding 二进制文件 (.f32)。
  Future<String> writeEmbedding(
    String jobId,
    String photoKey,
    List<double> embedding,
  ) async {
    await baseDir;
    await ensureJobDirs(jobId);
    final buffer = Float64List(embedding.length);
    for (var i = 0; i < embedding.length; i++) {
      buffer[i] = embedding[i];
    }
    final key = _fileKey(photoKey);
    final tmpPath = '${_tmpDir(jobId)}/$key.f32.tmp';
    final embPath = '${_embeddingsDir(jobId)}/$key.f32';
    final file = File(tmpPath);
    await file.writeAsBytes(buffer.buffer.asUint8List(), flush: true);
    await file.rename(embPath);
    return embPath;
  }

  /// 读取 embedding 二进制文件。
  Future<List<double>?> readEmbedding(String jobId, String photoKey) async {
    await baseDir;
    final embPath = '${_embeddingsDir(jobId)}/${_fileKey(photoKey)}.f32';
    final file = File(embPath);
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      final buffer = Float64List.view(bytes.buffer);
      return buffer.toList();
    } catch (e) {
      debugPrint('[spool] embedding 读取失败 photoKey=$photoKey: $e');
      return null;
    }
  }

  // ── Result 消费（主进程读取 + 移动）──

  /// 扫描 results_pending/ 目录，返回所有完整的结果文件路径。
  Future<List<String>> listPendingResults(String jobId) async {
    await baseDir;
    final dir = Directory(_pendingDir(jobId));
    if (!await dir.exists()) return [];
    final files = await dir.list().toList();
    return files
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .where((f) => !f.path.endsWith('_faces.json'))
        .map((f) => f.path)
        .toList();
  }

  /// 读取并解析 result.json。
  Future<AnalysisSpoolResult?> readResultFile(String filePath) async {
    try {
      final json =
          jsonDecode(await File(filePath).readAsString())
              as Map<String, Object?>;
      return AnalysisSpoolResult.fromJson(json);
    } catch (e) {
      debugPrint('[spool] result 读取失败 $filePath: $e');
      return null;
    }
  }

  /// 将 result 从 pending 移动到 committed。
  Future<bool> moveToCommitted(String jobId, String photoKey) async {
    await baseDir;
    await ensureJobDirs(jobId);
    final key = _fileKey(photoKey);
    final src = '${_pendingDir(jobId)}/$key.json';
    final dst = '${_committedDir(jobId)}/$key.json';
    try {
      final srcFile = File(src);
      if (!await srcFile.exists()) {
        return await File(dst).exists();
      }
      await srcFile.rename(dst);
      return true;
    } catch (e) {
      debugPrint('[spool] 移动 committed 失败 photoKey=$photoKey: $e');
      return false;
    }
  }

  /// 将 result 从 pending 移动到 failed。
  Future<bool> moveToFailed(String jobId, String photoKey) async {
    await baseDir;
    await ensureJobDirs(jobId);
    final key = _fileKey(photoKey);
    final src = '${_pendingDir(jobId)}/$key.json';
    final dst = '${_failedDir(jobId)}/$key.json';
    try {
      final srcFile = File(src);
      if (!await srcFile.exists()) {
        return await File(dst).exists();
      }
      await srcFile.rename(dst);
      return true;
    } catch (e) {
      debugPrint('[spool] 移动 failed 失败 photoKey=$photoKey: $e');
      return false;
    }
  }

  // ── Spool 版本号（主进程用于快速判断是否需要扫描）──

  String get _versionPath => '${_baseDir!.path}/spool_version.json';

  Future<void> _bumpSpoolVersion() async {
    await baseDir;
    final current = await readSpoolVersion();
    final next = SpoolVersion(
      version: (current?.version ?? 0) + 1,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final tmpPath = '${_baseDir!.path}/spool_version.json.tmp';
    final file = File(tmpPath);
    await file.writeAsString(jsonEncode(next.toJson()), flush: true);
    await file.rename(_versionPath);
  }

  Future<SpoolVersion?> readSpoolVersion() async {
    await baseDir;
    final file = File(_versionPath);
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return SpoolVersion.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  // ── Job 枚举 ──

  /// 列出所有 job 目录。
  Future<List<String>> listJobs() async {
    await baseDir;
    final dir = Directory('${_baseDir!.path}/jobs');
    if (!await dir.exists()) return [];
    final entries = await dir.list().toList();
    return entries
        .whereType<Directory>()
        .map((d) => d.path.split(Platform.pathSeparator).last)
        .toList();
  }

  /// 清理 job 目录（主进程确认所有结果已消费后调用）。
  Future<void> cleanupJob(String jobId) async {
    await baseDir;
    final dir = Directory(_jobDir(jobId));
    try {
      if (!await dir.exists()) return;
      await dir.delete(recursive: true);
      debugPrint('[spool] job 目录已清理 jobId=$jobId');
    } on PathNotFoundException {
      return;
    }
  }

  // ── 工具方法 ──

  /// 安全的 tmp 文件写入函数。
  static Future<void> atomicWrite(File tmpFile, File targetFile) async {
    await tmpFile.rename(targetFile.path);
  }
}
