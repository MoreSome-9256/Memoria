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
                  Colors.black.withOpacity(0.6), // 边缘暗化强度
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
