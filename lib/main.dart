// 应用入口文件。
//
// 这里负责启动 Flutter 应用，并在首屏展示前完成基础运行时准备：
// 初始化绑定、配置 Amplify Cognito、启动 ObjectBox、恢复待处理的 AI
// 分析任务，以及根据登录状态在欢迎页和主应用树之间分流。
//
// 调试页和 AI 能力开关都从应用设置或开发者入口进入，不在启动时预热模型。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:photo_album/service/album_refresh_service.dart';
import 'package:photo_album/service/amplify_auth_bootstrap_service.dart';
import 'package:photo_album/service/app_ai_settings_service.dart';
import 'package:photo_album/service/cognito_auth_service.dart';
import 'package:photo_album/service/media_permission_service.dart';
import 'package:photo_album/service/photo_service.dart';
import 'package:photo_album/service/ai_progress_notification_service.dart';
import 'package:photo_album/service/unified_analysis_pipeline_service.dart';
import 'package:photo_album/storage/objectbox/objectbox_service.dart';
import 'package:photo_album/utils/ocr_policy.dart';
import 'view/pages/welcome_page.dart';
import 'view/widget_tree.dart';

void main() async {
  // 保证绑定可用后尽快 runApp，把重初始化放到应用内异步执行。
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 800;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智能影记',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 255, 64, 129),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      home: const _StartupGate(),
    );
  }
}

enum _LaunchTarget { signedIn, welcome }

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late final Future<_LaunchTarget> _launchTargetFuture;
  final _AppStartupCoordinator _startupCoordinator = _AppStartupCoordinator();

  @override
  void initState() {
    super.initState();
    _launchTargetFuture = _startupCoordinator.resolveLaunchTarget();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LaunchTarget>(
      future: _launchTargetFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == _LaunchTarget.signedIn) {
          return const WithForegroundTask(child: WidgetTree());
        }
        return const WelcomePage();
      },
    );
  }
}

class _AppStartupCoordinator {
  Future<void>? _startupFuture;
  bool _authConfigured = false;

  Future<_LaunchTarget> resolveLaunchTarget() async {
    await _ensureStartupComplete();
    if (!_authConfigured) {
      return _LaunchTarget.welcome;
    }
    final signedIn = await const CognitoAuthService().tryIsSignedIn();
    return signedIn == false ? _LaunchTarget.welcome : _LaunchTarget.signedIn;
  }

  Future<void> _ensureStartupComplete() {
    if (_startupFuture != null) {
      return _startupFuture!;
    }
    _startupFuture = Future<void>(() async {
      await AIProgressNotificationService().initialize();
      _authConfigured = await AmplifyAuthBootstrapService.ensureConfigured();
      try {
        await ObjectBoxService().init();
      } catch (error) {
        debugPrint('ObjectBox init skipped; vector index unavailable: $error');
      }
      await PhotoService().init();
      final aiSettings = await AppAiSettingsService.instance.load();
      OcrPolicy.setRuntimeEnabled(aiSettings.ocrEnabled);
      debugPrint(
        'OCR policy: ml_kit_enabled=${OcrPolicy.mlKitEnabled} (runtime setting)',
      );
      if (aiSettings.autoAnalyzeNewPhotos) {
        if (await MediaPermissionService.hasAnalysisPermissions()) {
          unawaited(
            AlbumRefreshService().startRefresh(
              clearCacheFirst: false,
              analyzeWithAi: true,
            ),
          );
        }
      } else if (aiSettings.autoResumeAnalysis) {
        if (await MediaPermissionService.hasAnalysisPermissions()) {
          unawaited(
            UnifiedAnalysisPipelineService().startPendingAnalysisCandidates(),
          );
        }
      }
    });
    return _startupFuture!;
  }
}
