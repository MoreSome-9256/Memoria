import 'dart:async';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:photo_album/service/amplify_cognito_config.dart';
import 'package:photo_album/service/cognito_auth_service.dart';
import 'package:photo_album/service/photo_service.dart';
import 'package:photo_album/service/ncnn_mobileclip_native_service.dart';
import 'package:photo_album/view/pages/mobileclip_vector_probe_page.dart';
import 'view/pages/welcome_page.dart';
import 'view/widget_tree.dart';

const bool _mobileClipVectorProbeMode = bool.fromEnvironment(
  'MOBILECLIP_VECTOR_PROBE',
  defaultValue: false,
);

void main() async {
  // 1. 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  await _configureAmplifyAuth();

  // 2. 初始化 PhotoService (打开数据库)
  await PhotoService().init();

  unawaited(
    NcnnMobileClipNativeService().ensureModelInitialized().catchError((error) {
      debugPrint('NCNN init skipped at startup: $error');
    }),
  );

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
          : FutureBuilder<bool>(
              future: const CognitoAuthService().isSignedIn(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.data ?? false) {
                  return const WidgetTree();
                }
                return const WelcomePage();
              },
            ),
    );
  }
}
