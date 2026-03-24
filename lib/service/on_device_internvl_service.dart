import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

int _mapValueToInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

class OnDeviceInternvlImagePayload {
  const OnDeviceInternvlImagePayload({
    required this.path,
    required this.capturedAtIso,
    required this.locationName,
    this.latitude,
    this.longitude,
  });

  final String path;
  final String capturedAtIso;
  final String locationName;
  final double? latitude;
  final double? longitude;

  Map<String, Object> toMap() {
    final map = <String, Object>{
      'path': path,
      'capturedAtIso': capturedAtIso,
      'locationName': locationName,
    };
    if (latitude != null) {
      map['latitude'] = latitude!;
    }
    if (longitude != null) {
      map['longitude'] = longitude!;
    }
    return map;
  }
}
/// 手机本地多模态模型设备画像。
///
/// 这不是“已经集成成功”的运行状态，而是“当前手机硬件适不适合承载本地多模态 Q4 模型”
/// 的诊断结果。它用于回答几个关键问题：
/// 1. RAM 是否可能成为硬瓶颈。
/// 2. CPU 线程应该保守开多少。
/// 3. 当前 App 是否已经具备 NPU 通路。
class OnDeviceInternvlProfile {
  const OnDeviceInternvlProfile({
    required this.primaryAbi,
    required this.supportedAbis,
    required this.totalRamMb,
    required this.memoryClassMb,
    required this.largeMemoryClassMb,
    required this.availableProcessors,
    required this.recommendedThreads,
    required this.recommendedContextSize,
    required this.likelyEnoughRamFor1BQ4,
    required this.likelyEnoughRamForVision,
    required this.npuAvailableThroughApp,
    required this.pressureLevel,
    required this.summary,
  });

  final String primaryAbi;
  final List<String> supportedAbis;
  final int totalRamMb;
  final int memoryClassMb;
  final int largeMemoryClassMb;
  final int availableProcessors;
  final int recommendedThreads;
  final int recommendedContextSize;
  final bool likelyEnoughRamFor1BQ4;
  final bool likelyEnoughRamForVision;
  final bool npuAvailableThroughApp;
  final String pressureLevel;
  final String summary;

  factory OnDeviceInternvlProfile.fromMap(Map<Object?, Object?> map) {
    final supportedAbisRaw = map['supportedAbis'];
    final supportedAbis = supportedAbisRaw is List
        ? supportedAbisRaw.map((item) => item.toString()).toList(growable: false)
        : const <String>[];

    return OnDeviceInternvlProfile(
      primaryAbi: map['primaryAbi']?.toString() ?? '',
      supportedAbis: supportedAbis,
      totalRamMb: _mapValueToInt(map['totalRamMb']),
      memoryClassMb: _mapValueToInt(map['memoryClassMb']),
      largeMemoryClassMb: _mapValueToInt(map['largeMemoryClassMb']),
      availableProcessors: _mapValueToInt(map['availableProcessors']),
      recommendedThreads: _mapValueToInt(map['recommendedThreads']),
      recommendedContextSize: _mapValueToInt(map['recommendedContextSize']),
      likelyEnoughRamFor1BQ4: map['likelyEnoughRamFor1BQ4'] == true,
      likelyEnoughRamForVision: map['likelyEnoughRamForVision'] == true,
      npuAvailableThroughApp: map['npuAvailableThroughApp'] == true,
      pressureLevel: map['pressureLevel']?.toString() ?? 'unknown',
      summary: map['summary']?.toString() ?? 'unknown',
    );
  }

  /// 是否值得继续走“手机本地多模态模型”这条路。
  ///
  /// 这里只做保守判断：
  /// - 至少要能承载 1B Q4 主模型
  /// - ABI 不能是空的
  bool get looksViable => likelyEnoughRamFor1BQ4 && primaryAbi.isNotEmpty;
}

/// 当前仓库对“手机本地多模态模型”原生后端的接入状态。
///
/// 这份状态与硬件画像分开，是因为：
/// - 你的手机可能够强
/// - 但仓库未必已经接好了 Android 原生推理层
class OnDeviceInternvlBackendStatus {
  const OnDeviceInternvlBackendStatus({
    required this.backendIntegrated,
    required this.backendName,
    required this.supportsDirectOnDeviceInternvl,
    required this.reason,
    required this.nextStep,
  });

  final bool backendIntegrated;
  final String backendName;
  final bool supportsDirectOnDeviceInternvl;
  final String reason;
  final String nextStep;

  factory OnDeviceInternvlBackendStatus.fromMap(Map<Object?, Object?> map) {
    return OnDeviceInternvlBackendStatus(
      backendIntegrated: map['backendIntegrated'] == true,
      backendName: map['backendName']?.toString() ?? 'unknown',
      supportsDirectOnDeviceInternvl:
          map['supportsDirectOnDeviceInternvl'] == true,
      reason: map['reason']?.toString() ?? 'unknown',
      nextStep: map['nextStep']?.toString() ?? 'unknown',
    );
  }
}

/// 手机侧本地多模态 CLI 部署状态。
class OnDeviceInternvlCliDeploymentStatus {
  const OnDeviceInternvlCliDeploymentStatus({
    required this.deployedRoot,
    required this.installRoot,
    required this.cliPath,
    required this.modelPath,
    required this.mmprojPath,
    required this.cliExists,
    required this.libDirExists,
    required this.modelExists,
    required this.mmprojExists,
    required this.isRunnable,
    required this.summary,
    required this.missingItems,
  });

  final String deployedRoot;
  final String installRoot;
  final String cliPath;
  final String modelPath;
  final String mmprojPath;
  final bool cliExists;
  final bool libDirExists;
  final bool modelExists;
  final bool mmprojExists;
  final bool isRunnable;
  final String summary;
  final List<String> missingItems;

  factory OnDeviceInternvlCliDeploymentStatus.fromMap(
    Map<Object?, Object?> map,
  ) {
    final missingItemsRaw = map['missingItems'];
    final missingItems = missingItemsRaw is List
        ? missingItemsRaw.map((item) => item.toString()).toList(growable: false)
        : const <String>[];

    return OnDeviceInternvlCliDeploymentStatus(
      deployedRoot: map['deployedRoot']?.toString() ?? '',
      installRoot: map['installRoot']?.toString() ?? '',
      cliPath: map['cliPath']?.toString() ?? '',
      modelPath: map['modelPath']?.toString() ?? '',
      mmprojPath: map['mmprojPath']?.toString() ?? '',
      cliExists: map['cliExists'] == true,
      libDirExists: map['libDirExists'] == true,
      modelExists: map['modelExists'] == true,
      mmprojExists: map['mmprojExists'] == true,
      isRunnable: map['isRunnable'] == true,
      summary: map['summary']?.toString() ?? 'unknown',
      missingItems: missingItems,
    );
  }
}

class OnDeviceInternvlServerDeploymentStatus {
  const OnDeviceInternvlServerDeploymentStatus({
    required this.deployedRoot,
    required this.installRoot,
    required this.serverPath,
    required this.modelPath,
    required this.mmprojPath,
    required this.serverExists,
    required this.libDirExists,
    required this.modelExists,
    required this.mmprojExists,
    required this.isRunnable,
    required this.port,
    required this.serverUrl,
    required this.summary,
    required this.missingItems,
  });

  final String deployedRoot;
  final String installRoot;
  final String serverPath;
  final String modelPath;
  final String mmprojPath;
  final bool serverExists;
  final bool libDirExists;
  final bool modelExists;
  final bool mmprojExists;
  final bool isRunnable;
  final int port;
  final String serverUrl;
  final String summary;
  final List<String> missingItems;

  factory OnDeviceInternvlServerDeploymentStatus.fromMap(
    Map<Object?, Object?> map,
  ) {
    final missingItemsRaw = map['missingItems'];
    final missingItems = missingItemsRaw is List
        ? missingItemsRaw.map((item) => item.toString()).toList(growable: false)
        : const <String>[];

    return OnDeviceInternvlServerDeploymentStatus(
      deployedRoot: map['deployedRoot']?.toString() ?? '',
      installRoot: map['installRoot']?.toString() ?? '',
      serverPath: map['serverPath']?.toString() ?? '',
      modelPath: map['modelPath']?.toString() ?? '',
      mmprojPath: map['mmprojPath']?.toString() ?? '',
      serverExists: map['serverExists'] == true,
      libDirExists: map['libDirExists'] == true,
      modelExists: map['modelExists'] == true,
      mmprojExists: map['mmprojExists'] == true,
      isRunnable: map['isRunnable'] == true,
      port: _mapValueToInt(map['port']),
      serverUrl: map['serverUrl']?.toString() ?? '',
      summary: map['summary']?.toString() ?? 'unknown',
      missingItems: missingItems,
    );
  }
}

class OnDeviceInternvlServerStatus {
  const OnDeviceInternvlServerStatus({
    required this.running,
    required this.reachable,
    required this.ready,
    required this.port,
    required this.host,
    required this.modelAlias,
    required this.serverUrl,
    required this.chatCompletionsUrl,
    required this.pid,
    required this.runtimeServerPath,
    required this.error,
    required this.summary,
  });

  final bool running;
  final bool reachable;
  final bool ready;
  final int port;
  final String host;
  final String modelAlias;
  final String serverUrl;
  final String chatCompletionsUrl;
  final int pid;
  final String runtimeServerPath;
  final String error;
  final String summary;

  factory OnDeviceInternvlServerStatus.fromMap(Map<Object?, Object?> map) {
    return OnDeviceInternvlServerStatus(
      running: map['running'] == true,
      reachable: map['reachable'] == true,
      ready: map['ready'] == true,
      port: _mapValueToInt(map['port']),
      host: map['host']?.toString() ?? '127.0.0.1',
      modelAlias: map['modelAlias']?.toString() ?? 'local-qwen3.5-0.8b-vl',
      serverUrl: map['serverUrl']?.toString() ?? '',
      chatCompletionsUrl: map['chatCompletionsUrl']?.toString() ?? '',
      pid: _mapValueToInt(map['pid']),
      runtimeServerPath: map['runtimeServerPath']?.toString() ?? '',
      error: map['error']?.toString() ?? '',
      summary: map['summary']?.toString() ?? 'unknown',
    );
  }
}

/// 直接执行手机本地 llama-mtmd-cli 后返回的结果。
class OnDeviceInternvlCliResult {
  const OnDeviceInternvlCliResult({
    required this.success,
    required this.answer,
    required this.rawOutput,
    required this.error,
    required this.exitCode,
    required this.durationMs,
  });

  final bool success;
  final String answer;
  final String rawOutput;
  final String error;
  final int exitCode;
  final int durationMs;

  factory OnDeviceInternvlCliResult.fromMap(Map<Object?, Object?> map) {
    return OnDeviceInternvlCliResult(
      success: map['success'] == true,
      answer: map['answer']?.toString() ?? '',
      rawOutput: map['rawOutput']?.toString() ?? '',
      error: map['error']?.toString() ?? '',
      exitCode: _mapValueToInt(map['exitCode']),
      durationMs: _mapValueToInt(map['durationMs']),
    );
  }
}

/// Dart 侧的本地多模态设备诊断服务。
///
/// 当前版本的职责非常明确：
/// 1. 通过平台通道读取 Android 真机硬件画像。
/// 2. 明确返回“仓库当前还没接入本地推理后端”的事实。
/// 3. 在应用启动时输出一份工程上可读的日志，帮助你判断是否值得继续做手机端集成。
///
/// 注意：
/// 这个服务不是 GGUF 推理器本身，它只是“集成前的探测层”。
class OnDeviceInternvlService {
  OnDeviceInternvlService._internal();

  static final OnDeviceInternvlService _instance =
      OnDeviceInternvlService._internal();

  factory OnDeviceInternvlService() => _instance;

  static const MethodChannel _channel = MethodChannel(
    'memoria/on_device_internvl',
  );

  Future<OnDeviceInternvlProfile?> probeDeviceProfile() async {
    if (!Platform.isAndroid) {
      return null;
    }

    final raw = await _channel.invokeMethod<Map<Object?, Object?>>('probeDevice');
    if (raw == null) {
      return null;
    }
    return OnDeviceInternvlProfile.fromMap(raw);
  }

  Future<OnDeviceInternvlBackendStatus?> getBackendStatus() async {
    if (!Platform.isAndroid) {
      return null;
    }

    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getBackendStatus',
    );
    if (raw == null) {
      return null;
    }
    return OnDeviceInternvlBackendStatus.fromMap(raw);
  }

  Future<OnDeviceInternvlServerDeploymentStatus?> getServerDeploymentStatus() async {
    if (!Platform.isAndroid) {
      return null;
    }

    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getServerDeploymentStatus',
    );
    if (raw == null) {
      return null;
    }
    return OnDeviceInternvlServerDeploymentStatus.fromMap(raw);
  }

  Future<OnDeviceInternvlServerStatus?> getServerStatus() async {
    if (!Platform.isAndroid) {
      return null;
    }

    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getServerStatus',
    );
    if (raw == null) {
      return null;
    }
    return OnDeviceInternvlServerStatus.fromMap(raw);
  }

  Future<OnDeviceInternvlServerStatus?> ensureServerStarted({
    required int threads,
    required int contextSize,
  }) async {
    if (!Platform.isAndroid) {
      return null;
    }

    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'ensureServerStarted',
      <String, Object>{
        'threads': threads,
        'contextSize': contextSize,
      },
    );
    if (raw == null) {
      return null;
    }
    return OnDeviceInternvlServerStatus.fromMap(raw);
  }

  Future<OnDeviceInternvlServerStatus?> stopServer() async {
    if (!Platform.isAndroid) {
      return null;
    }

    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'stopServer',
    );
    if (raw == null) {
      return null;
    }
    return OnDeviceInternvlServerStatus.fromMap(raw);
  }

  Future<OnDeviceInternvlCliDeploymentStatus?> getCliDeploymentStatus() async {
    if (!Platform.isAndroid) {
      return null;
    }

    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'getCliDeploymentStatus',
    );
    if (raw == null) {
      return null;
    }
    return OnDeviceInternvlCliDeploymentStatus.fromMap(raw);
  }

  Future<OnDeviceInternvlCliResult?> runCliExperiment({
    required List<OnDeviceInternvlImagePayload> images,
    required String prompt,
    required int threads,
    required int contextSize,
    int maxTokens = 96,
    int timeoutMs = 180000,
  }) async {
    if (!Platform.isAndroid) {
      return null;
    }

    final imagePaths = images
        .map((item) => item.path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    final imageMetadatas = images
        .map((item) => item.toMap())
        .toList(growable: false);
    if (imagePaths.isEmpty) {
      return const OnDeviceInternvlCliResult(
        success: false,
        answer: '',
        rawOutput: '',
        error: '没有可用的图片路径，无法发起推理',
        exitCode: -1,
        durationMs: 0,
      );
    }

    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      'runCliExperiment',
      <String, Object>{
        'imagePath': imagePaths.isEmpty ? '' : imagePaths.first,
        'imagePaths': imagePaths,
        'imageMetadatas': imageMetadatas,
        'prompt': prompt,
        'threads': threads,
        'contextSize': contextSize,
        'maxTokens': maxTokens,
        'timeoutMs': timeoutMs,
      },
    );
    if (raw == null) {
      return null;
    }
    return OnDeviceInternvlCliResult.fromMap(raw);
  }

  /// 在调试启动时输出一份摘要，方便你直接在 `flutter run` 日志里判断：
  /// - 手机 RAM 是否吃紧
  /// - 线程应该压到多少
  /// - 当前仓库到底缺的是“手机性能”还是“原生后端”
  Future<void> logDiagnostics() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      final profile = await probeDeviceProfile();
      final backend = await getBackendStatus();
      final serverDeployment = await getServerDeploymentStatus();
      final serverStatus = await getServerStatus();

      if (profile != null) {
        debugPrint('📱 [Qwen VLM 设备画像] ${profile.summary}');
        debugPrint(
          '📱 [Qwen VLM 设备画像] ABI=${profile.supportedAbis.join(', ')} '
          '推荐ctx=${profile.recommendedContextSize} '
          '推荐线程=${profile.recommendedThreads} '
          '1BQ4可行=${profile.likelyEnoughRamFor1BQ4} '
          '视觉余量=${profile.likelyEnoughRamForVision} '
          'NPU通路=${profile.npuAvailableThroughApp}',
        );
      }

      if (backend != null) {
        debugPrint(
          '📱 [Qwen VLM 后端状态] integrated=${backend.backendIntegrated} '
          'direct=${backend.supportsDirectOnDeviceInternvl} '
          'backend=${backend.backendName}',
        );
        debugPrint('📱 [Qwen VLM 后端状态] ${backend.reason}');
        debugPrint('📱 [Qwen VLM 后端状态] 下一步：${backend.nextStep}');
      }

      if (serverDeployment != null) {
        debugPrint(
          '📱 [Qwen VLM Server 部署] runnable=${serverDeployment.isRunnable} '
          'server=${serverDeployment.serverExists} '
          'model=${serverDeployment.modelExists} '
          'mmproj=${serverDeployment.mmprojExists} '
          'port=${serverDeployment.port}',
        );
        debugPrint('📱 [Qwen VLM Server 部署] ${serverDeployment.summary}');
      }

      if (serverStatus != null) {
        debugPrint(
          '📱 [Qwen VLM Server 状态] running=${serverStatus.running} '
          'reachable=${serverStatus.reachable} pid=${serverStatus.pid}',
        );
        debugPrint('📱 [Qwen VLM Server 状态] ${serverStatus.summary}');
        if (serverStatus.error.isNotEmpty) {
          debugPrint('📱 [Qwen VLM Server 状态] error=${serverStatus.error}');
        }
      }
    } on MissingPluginException {
      debugPrint('⚠️ [Qwen VLM 设备画像] 当前平台未注册 Android 探测通道');
    } catch (error) {
      debugPrint('⚠️ [Qwen VLM 设备画像] 探测失败: $error');
    }
  }
}