/// 应用入口文件。
///
/// 这里负责启动 Flutter 应用，并在首屏展示前完成基础运行时准备：
/// 初始化绑定、配置 Amplify Cognito、启动 ObjectBox、恢复待处理的 AI
/// 分析任务，以及根据登录状态在欢迎页和主应用树之间分流。
///
/// 文件里还定义了一个可通过 `--dart-define` 控制的开关：
/// `MOBILECLIP_VECTOR_PROBE` 会直接进入向量探测页。

import 'dart:async';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:photo_album/service/amplify_cognito_config.dart';
import 'package:photo_album/service/cognito_auth_service.dart';
import 'package:photo_album/service/photo_service.dart';
import 'package:photo_album/service/ai_progress_notification_service.dart';
import 'package:photo_album/storage/objectbox/objectbox_service.dart';
import 'package:photo_album/utils/ocr_policy.dart';
import 'package:photo_album/view/pages/mobileclip_vector_probe_page.dart';
import 'view/pages/welcome_page.dart';
import 'view/widget_tree.dart';

const bool _mobileClipVectorProbeMode = bool.fromEnvironment(
  'MOBILECLIP_VECTOR_PROBE',
  defaultValue: false,
);

void main() async {
  // 保证绑定可用后尽快 runApp，把重初始化放到应用内异步执行。
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 800;
  runApp(const MyApp());
}

Future<void> _configureAmplifyAuth() async {
  try {
    if (Amplify.isConfigured) {
      return;
    }
    await Amplify.addPlugin(AmplifyAuthCognito());
    await Amplify.configure(AmplifyCognitoConfig.build());
  } on FormatException catch (e) {
    debugPrint('Amplify auth skipped: ${e.message}');
  } catch (e) {
    debugPrint('Amplify auth configure failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final _AppStartupCoordinator _startupCoordinator =
      _AppStartupCoordinator();

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
      home: _mobileClipVectorProbeMode
          ? const MobileClipVectorProbePage()
          : FutureBuilder<_LaunchTarget>(
              future: _startupCoordinator.resolveLaunchTarget(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.data == _LaunchTarget.signedIn) {
                  return const WidgetTree();
                }
                return const WelcomePage();
              },
            ),
    );
  }
}

enum _LaunchTarget { signedIn, welcome }

class _AppStartupCoordinator {
  Future<void>? _startupFuture;

  Future<_LaunchTarget> resolveLaunchTarget() async {
    await _ensureStartupComplete();
    final signedIn = await const CognitoAuthService().isSignedIn();
    return signedIn ? _LaunchTarget.signedIn : _LaunchTarget.welcome;
  }

  Future<void> _ensureStartupComplete() {
    if (_startupFuture != null) {
      return _startupFuture!;
    }
    _startupFuture = Future<void>(() async {
      await AIProgressNotificationService().initialize();
      await _configureAmplifyAuth();
      try {
        await ObjectBoxService().init();
      } catch (error) {
        debugPrint(
          'ObjectBox init skipped, falling back to legacy vectors: $error',
        );
      }
      await PhotoService().init();
      await OcrPolicy.init();
    });
    return _startupFuture!;
  }
}
