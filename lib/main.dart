import 'dart:async';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_album/service/photo_service.dart';
import 'package:photo_album/service/ncnn_mobileclip_native_service.dart';
import 'package:photo_album/view/pages/mobileclip_vector_probe_page.dart';
import 'package:photo_album/service/ncnn_mobileclip_native_service.dart';
import 'package:photo_album/view/pages/mobileclip_vector_probe_page.dart';
import 'view/pages/welcome_page.dart';

const bool _mobileClipVectorProbeMode = bool.fromEnvironment(
  'MOBILECLIP_VECTOR_PROBE',
  defaultValue: false,
);

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

  unawaited(
    NcnnMobileClipNativeService().ensureModelInitialized().catchError((error) {
      debugPrint('NCNN init skipped at startup: $error');
    }),
  );

  // 3. 在调试期打印一份手机本地 InternVL 可行性画像。
  //
  // 这样做的目的是让你每次用真机运行时，都能立刻从终端里看到：
  // - 这台手机 RAM / CPU 是否足够承载 1B Q4 级别多模态模型
  // - 当前仓库缺的是手机性能，还是 Android 原生推理后端
  //
  // 这里不阻塞应用启动，避免影响首屏体验。
  Future<void>(() async {
    await OnDeviceInternvlService().logDiagnostics();
  });

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
          seedColor: const Color.fromARGB(255, 255, 64, 129),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      home: _mobileClipVectorProbeMode
          ? const MobileClipVectorProbePage()
          : const WelcomePage(),
      home: _mobileClipVectorProbeMode
          ? const MobileClipVectorProbePage()
          : const WelcomePage(),
    );
  }
}
