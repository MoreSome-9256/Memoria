import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_album/service/photo_service.dart';
import 'package:photo_album/service/ncnn_mobileclip_native_service.dart';
import 'package:photo_album/view/pages/mobileclip_vector_probe_page.dart';
import 'view/pages/welcome_page.dart';

const bool _mobileClipVectorProbeMode = bool.fromEnvironment(
  'MOBILECLIP_VECTOR_PROBE',
  defaultValue: false,
);

void main() async {
  // 1. 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 初始化 PhotoService (打开数据库)
  await PhotoService().init();

  unawaited(
    NcnnMobileClipNativeService().ensureModelInitialized().catchError((error) {
      debugPrint('NCNN init skipped at startup: $error');
    }),
  );

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
      home: _mobileClipVectorProbeMode
          ? const MobileClipVectorProbePage()
          : const WelcomePage(),
    );
  }
}
