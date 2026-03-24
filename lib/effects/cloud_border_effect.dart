import 'dart:math';
import 'package:flutter/material.dart';

// 🌟 核心特效组件
class CloudBorderEffect extends StatefulWidget {
  final Color cloudColor;
  final Color shadowColor;

  const CloudBorderEffect({
    super.key,
    this.cloudColor = Colors.white,
    this.shadowColor = const Color(0x80EAD9EC), // 50%透明度的浅紫阴影
  });

  @override
  State<CloudBorderEffect> createState() => _CloudBorderEffectState();
}

class _CloudBorderEffectState extends State<CloudBorderEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 动画控制器，10秒一个轮回，无限循环，模拟云朵缓慢呼吸
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // 🌟 关键：忽略点击事件，不阻挡底下的视频操作
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            size: Size.infinite,
            painter: _CloudPainter(
              time: _controller.value * pi * 2, // 转换为弧度
              cloudColor: widget.cloudColor,
              shadowColor: widget.shadowColor,
            ),
          );
        },
      ),
    );
  }
}

// 🌟 核心绘制逻辑（完美复刻你提供的 PIXI.js 算法）
class _CloudPainter extends CustomPainter {
  final double time;
  final Color cloudColor;
  final Color shadowColor;

  _CloudPainter({
    required this.time,
    required this.cloudColor,
    required this.shadowColor,
  });

  // 伪随机哈希函数
  double _hash(double n) {
    double x = sin(n * 1321.0914 + 311.7) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final Paint shadowPaint = Paint()..color = shadowColor;
    final Paint mainPaint = Paint()..color = cloudColor;

    final int cloudCount = 4; // 每边云朵团数量
    final int minCircles = 6;
    final int maxCircles = 10;
    final double baseRadius = min(w, h) * 0.15; // 根据屏幕大小自适应云朵半径

    void drawCloud(double x, double y, int seed) {
      int circleCount =
          minCircles +
          (_hash(seed.toDouble()) * (maxCircles - minCircles + 1)).floor();
      double phase = _hash(seed * 31.0) * pi * 2;
      double speed = 0.3 + _hash(seed * 37.0) * 0.4;

      // 计算动画偏移
      double floatX = sin(time * speed * 2 + phase) * 8;
      double floatY = cos(time * speed * 1.5 + phase) * 5;
      double breathe = 1 + sin(time * 2 + phase) * 0.03;

      List<Offset> positions = [];
      List<double> radii = [];

      // 生成小圆的相对位置
      for (int i = 0; i < circleCount; i++) {
        double angle = _hash(seed * 13.0 + i * 7.0) * pi * 2;
        double distance = _hash(seed * 17.0 + i * 11.0) * baseRadius * 1.2;
        double offsetX = cos(angle) * distance;
        double offsetY = sin(angle) * distance * 0.7;
        double radius =
            baseRadius * (0.6 + _hash(seed * 23.0 + i * 19.0) * 0.8);

        positions.add(Offset(offsetX, offsetY));
        radii.add(radius);
      }

      // 画阴影层 (稍微右下偏移)
      for (int i = 0; i < circleCount; i++) {
        canvas.drawCircle(
          Offset(
            x + positions[i].dx + floatX + 6,
            y + positions[i].dy + floatY + 6,
          ),
          radii[i] * breathe,
          shadowPaint,
        );
      }

      // 画主云朵层
      for (int i = 0; i < circleCount; i++) {
        canvas.drawCircle(
          Offset(x + positions[i].dx + floatX, y + positions[i].dy + floatY),
          radii[i] * breathe,
          mainPaint,
        );
      }
    }

    // 在屏幕四周生成云朵
    for (int i = 0; i < cloudCount; i++) {
      drawCloud((i + 0.5) * (w / cloudCount), -20, 42 + i); // 顶边
      drawCloud((i + 0.5) * (w / cloudCount), h + 20, 142 + i); // 底边
      drawCloud(-20, (i + 0.5) * (h / cloudCount), 242 + i); // 左边
      drawCloud(w + 20, (i + 0.5) * (h / cloudCount), 342 + i); // 右边
    }
  }

  @override
  bool shouldRepaint(covariant _CloudPainter oldDelegate) =>
      time != oldDelegate.time;
}
