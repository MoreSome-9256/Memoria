import 'package:flutter/material.dart';
import 'package:photo_album/service/photo_service.dart';
import 'view/widget_tree.dart';

void main() async {
  // 1. 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 2. 初始化 PhotoService (打开数据库)
  await PhotoService().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智能故事相册',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      home: const WidgetTree(),
    );
  }
}
