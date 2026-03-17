import 'package:flutter/material.dart';
import 'dart:math' as math;

class GlitchEffect extends StatelessWidget {
  final Widget child;
  final double intensity; // 对应 GLSL 的 uIntensity (0.0 - 1.0)
  final double time; // 对应 GLSL 的 uTime

  const GlitchEffect({
    super.key,
    required this.child,
    required this.intensity,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    // 强度太低时直接返回原图，节省渲染性能
    if (intensity <= 0.01) return child;

    // 用 time 生成伪随机数种子 (复刻 GLSL 的 hash 函数)
    final random = math.Random((time * 100).floor());

    // 1. Chromatic Aberration (色差偏移量)
    // 稍微缩小一点偏移量，让边缘色散更自然，不至于画面重影太严重
    final rgbOffset = intensity * 10.0;

    // 2. Block Displacement (条带错位逻辑)
    final bool showBand = random.nextDouble() > (1.0 - intensity * 0.8);
    final double bandTop = random.nextDouble() * 0.9;
    final double bandHeight = 0.02 + random.nextDouble() * 0.08 * intensity;
    final double bandShift = (random.nextDouble() - 0.5) * intensity * 40.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 🟩 底层：原视频/图片内容 (保留原始全彩)
        child,

        // 🟦 青色通道偏移 (向右移) - 赛博朋克的精髓是青色而不是纯蓝！
        if (intensity > 0.05)
          Transform.translate(
            offset: Offset(rgbOffset, 0),
            child: Opacity(
              // 随强度动态变化透明度，融合得更高级
              opacity: 0.4 * intensity.clamp(0.0, 1.0),
              child: ColorFiltered(
                // 🌟 核心修复：用 modulate (提取通道)，取代 srcIn (纯色覆盖)
                colorFilter: const ColorFilter.mode(
                  Colors.cyan,
                  BlendMode.modulate,
                ),
                child: child,
              ),
            ),
          ),

        // 🟥 红色通道偏移 (向左移)
        if (intensity > 0.05)
          Transform.translate(
            offset: Offset(-rgbOffset, 0),
            child: Opacity(
              opacity: 0.4 * intensity.clamp(0.0, 1.0),
              child: ColorFiltered(
                colorFilter: const ColorFilter.mode(
                  Colors.red,
                  BlendMode.modulate,
                ),
                child: child,
              ),
            ),
          ),

        // 🔲 故障条带层 (横向切割错位)
        if (showBand)
          Positioned.fill(
            child: ClipPath(
              clipper: _GlitchBandClipper(bandTop, bandHeight),
              child: Transform.translate(
                offset: Offset(bandShift, 0),
                child: child, // 撕裂部分依然是原图的高清切片
              ),
            ),
          ),
      ],
    );
  }
}

// ✂️ 专门用来切出横向条带的裁剪器
class _GlitchBandClipper extends CustomClipper<Path> {
  final double topPercent;
  final double heightPercent;

  _GlitchBandClipper(this.topPercent, this.heightPercent);

  @override
  Path getClip(Size size) {
    final path = Path();
    path.addRect(
      Rect.fromLTWH(
        0,
        size.height * topPercent,
        size.width,
        size.height * heightPercent,
      ),
    );
    return path;
  }

  @override
  bool shouldReclip(_GlitchBandClipper oldClipper) => true;
}
