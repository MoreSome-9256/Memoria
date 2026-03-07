import 'package:flutter/material.dart';
import 'package:photo_album/service/photo_service.dart';
import 'view/widget_tree.dart';
import 'view/pages/welcome_page.dart';

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
      title: '智能影记',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      // home: const WidgetTree(), // 临时测试主页
      home: const WelcomePage(), // 临时测试登录界面
    );
  }
}
