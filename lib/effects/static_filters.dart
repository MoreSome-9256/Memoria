import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 1. 暗角滤镜 (Vignette)
class VignetteEffect extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const VignetteEffect({super.key, required this.child, required this.enabled});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.0,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.6), // 边缘暗化强度
                ],
                stops: const [0.5, 1.0], // 0.5以内全透明，边缘快速变暗
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 2. 胶片噪点 (Film Grain)
class GrainEffect extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final double time; // 驱动噪点随机跳动

  const GrainEffect({
    super.key,
    required this.child,
    required this.enabled,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    // 使用动画控制器的时间来驱动随机偏移，产生噪点闪烁感
    final random = math.Random((time * 100).floor());

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: Opacity(
            opacity: 0.08, // 噪点非常淡才高级
            child: Transform.translate(
              // 每帧微小的随机偏移，模拟胶片跳动
              offset: Offset(
                random.nextDouble() * 10,
                random.nextDouble() * 10,
              ),
              child: Image.asset(
                'assets/images/noise.png', // 你需要一张细碎白噪点的透明图片
                repeat: ImageRepeat.repeat,
                fit: BoxFit.none,
                // 如果没有图片，可以用装饰填充模拟
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 3. 相机边框滤镜 (Camera Frame)
class CameraFrameEffect extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final bool isHorizontal; // 🌟 核心参数：用来判断横竖屏

  const CameraFrameEffect({
    super.key,
    required this.child,
    required this.enabled,
    required this.isHorizontal,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    // 🌟 动态匹配你的素材路径（请根据你实际的文件名修改这里的字符串）
    String frameImagePath = isHorizontal
        ? 'assets/images/frame_horizontal.png'
        : 'assets/images/frame_vertical.png';

    return Stack(
      fit: StackFit.expand,
      children: [
        child, // 底层的视频画面（带了噪点、暗角等）
        IgnorePointer(
          child: Image.asset(
            frameImagePath,
            fit: BoxFit.fill, // 🌟 fill 会拉伸图片，绝对贴合父组件的四个边角
          ),
        ),
      ],
    );
  }
}

/// 4. 霓虹呼吸光圈 (Glow Ring)
class GlowRingEffect extends StatelessWidget {
  final bool enabled;
  final double time; // 驱动平缓的呼吸感
  final double beatIntensity; // 驱动音乐重音时的脉冲放大

  const GlowRingEffect({
    super.key,
    required this.enabled,
    required this.time,
    required this.beatIntensity,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();

    return IgnorePointer(
      child: CustomPaint(painter: _GlowRingPainter(time, beatIntensity)),
    );
  }
}

class _GlowRingPainter extends CustomPainter {
  final double time;
  final double beatIntensity;

  _GlowRingPainter(this.time, this.beatIntensity);

  @override
  void paint(Canvas canvas, Size size) {
    // 基础尺寸计算
    final double maxSize = math.max(size.width, size.height);
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final Offset center = Offset(cx, cy);

    // 半径参数 (完美复刻 PIXI.js)
    final double r = maxSize * 0.38;
    final double ringWidth = 0.12;
    final double innerR = r * (1 - ringWidth);
    final double outerR = r * (1 + ringWidth);

    // 计算缩放：呼吸动画 (time) + 节拍脉冲 (beat)
    final double pulse = 1.0 + math.sin(time * math.pi * 4.0) * 0.03;
    final double beatPulse = 1.0 + beatIntensity * 0.05;
    final double scale = pulse * beatPulse;

    // 保存画布状态并进行中心缩放
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale);
    canvas.translate(-cx, -cy);

    // 颜色定义 (内蓝外紫)
    const Color colorInner = Color(0xFF4444FF);
    const Color colorOuter = Color(0xFFCC22AA);
    const double glowAlpha = 0.7;

    // 1. 绘制外部发光渐变 (Outer glow)
    final double gradientRadius = outerR * 1.3;
    final Rect gradientRect = Rect.fromCircle(
      center: center,
      radius: gradientRadius,
    );
    final RadialGradient gradient = RadialGradient(
      colors: [
        Colors.transparent,
        colorOuter.withValues(alpha: 0.15),
        colorInner.withValues(alpha: glowAlpha * 0.6),
        colorOuter.withValues(alpha: glowAlpha * 0.4),
        Colors.transparent,
      ],
      // 这里的 stops 完美对应了你原代码的 addColorStop
      stops: const [0.0, 0.5, 0.75, 0.88, 1.0],
    );

    final Paint glowPaint = Paint()
      ..shader = gradient.createShader(gradientRect)
      ..blendMode = BlendMode.screen; // Screen 混合模式让光效更通透
    canvas.drawRect(gradientRect, glowPaint);

    // 2. 绘制主光环 (Ring stroke)
    final Paint strokePaint1 = Paint()
      ..style = PaintingStyle.stroke
      ..color = colorInner.withValues(alpha: 0.5)
      ..strokeWidth = maxSize * ringWidth * 0.08;
    canvas.drawCircle(center, r, strokePaint1);

    // 3. 绘制内测细光环 (Inner ring)
    final Paint strokePaint2 = Paint()
      ..style = PaintingStyle.stroke
      ..color = colorInner.withValues(alpha: 0.25)
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, innerR, strokePaint2);

    // 恢复画布
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlowRingPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.beatIntensity != beatIntensity;
  }
}
