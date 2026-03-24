// lib/effects/subtitle_effect.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;

// 🌟 新增：用于存储每一层文本的快照数据
class _TextLayerData {
  final String text;
  final double scale;
  final Offset offset;
  final DateTime entryTime;

  _TextLayerData({
    required this.text,
    required this.scale,
    required this.offset,
    required this.entryTime,
  });
}

class SubtitleEffectLayer extends StatefulWidget {
  final String text;
  final String effectType; // 'standard', 'hero', 'cards', 'layered'
  final double yPosition;
  final double fontSize;
  final String fontFamily;
  final double blurIntensity;
  final AnimationController vfxController;

  const SubtitleEffectLayer({
    super.key,
    required this.text,
    required this.effectType,
    required this.yPosition,
    required this.fontSize,
    required this.fontFamily,
    required this.blurIntensity,
    required this.vfxController,
  });

  @override
  State<SubtitleEffectLayer> createState() => _SubtitleEffectLayerState();
}

class _SubtitleEffectLayerState extends State<SubtitleEffectLayer> {
  // 📚 存储历史图层
  final List<_TextLayerData> _layers = [];
  final int _maxLayers = 4;
  int _layerIdx = 0;

  // 预设配置 (参考 TS 脚本)
  final List<double> _scaleOptions = [1.0, 1.35, 0.75, 1.15];
  final List<Offset> _offsetOptions = [
    Offset.zero,
    const Offset(-20, 15),
    const Offset(15, -10),
    const Offset(-10, -20),
  ];

  @override
  void initState() {
    super.initState();
    // 🌟 核心修复 1：初始化时如果已经有歌词，立刻添加第一层
    if (widget.text.isNotEmpty) {
      _internalAddLayer(widget.text);
    }
  }

  @override
  void didUpdateWidget(SubtitleEffectLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🌟 核心修复 2：只有当文字真的变了，才增加新图层
    if (widget.text != oldWidget.text && widget.text.isNotEmpty) {
      setState(() {
        _internalAddLayer(widget.text);
      });
    }
  }
  // 把添加逻辑抽出来，方便 initState 和 didUpdateWidget 共用
  void _internalAddLayer(String newText) {
    final newData = _TextLayerData(
      text: newText,
      scale: _scaleOptions[_layerIdx % _scaleOptions.length],
      offset: _offsetOptions[_layerIdx % _offsetOptions.length],
      entryTime: DateTime.now(),
    );

    _layers.add(newData);
    _layerIdx++;

    if (_layers.length > _maxLayers) {
      _layers.removeAt(0);
    }
  }

  void _addLayer(String newText) {
    setState(() {
      final newData = _TextLayerData(
        text: newText,
        scale: _scaleOptions[_layerIdx % _scaleOptions.length],
        offset: _offsetOptions[_layerIdx % _offsetOptions.length],
        entryTime: DateTime.now(),
      );

      _layers.add(newData);
      _layerIdx++;

      // 保持队列长度
      if (_layers.length > _maxLayers) {
        _layers.removeAt(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment(0, (widget.yPosition * 2) - 1.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: _buildEffectWidget(),
      ),
    );
  }

  Widget _buildEffectWidget() {
    final baseStyle = TextStyle(
      color: Colors.white,
      fontSize: widget.fontSize,
      fontFamily: widget.fontFamily,
      fontWeight: FontWeight.w900, // Layered 模式通常用极粗体
      shadows: const [
        Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 2)),
      ],
      height: 1.5,
      letterSpacing: 2.0,
    );

    switch (widget.effectType) {
      case 'layered':
        // 🌟 核心复刻：多层堆叠特效
        return Stack(
          alignment: Alignment.center,
          children: _layers.asMap().entries.map((entry) {
            int idx = entry.key;
            _TextLayerData layer = entry.value;

            // 计算深度：最新的一层在上面
            bool isNewest = idx == _layers.length - 1;
            int depth = (_layers.length - 1) - idx;

            // 🌟 动态计算目标值
            // 越老的层，透明度按指数级下降
            double targetAlpha = isNewest
                ? 1.0
                : (0.6 - (depth * 0.12)).clamp(0.0, 1.0);
            // 越老的层，模糊度越高
            double targetBlur = isNewest ? 0.0 : (depth * 3.0);
            // 越老的层，稍微缩小一点点营造空间感
            double targetScale = layer.scale * (isNewest ? 1.0 : 0.95);

            return AnimatedPositioned(
              duration: 600.ms,
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              top: 0,
              bottom: 0, // 撑满 Stack 以便居中
              child:
                  Center(
                        child: Transform.translate(
                          offset: layer.offset,
                          child: AnimatedScale(
                            duration: 600.ms,
                            scale: targetScale,
                            curve: Curves.easeOutBack,
                            child: TweenAnimationBuilder<double>(
                              // 🌟 核心：使用 TweenAnimationBuilder 来实现模糊度的平滑过渡
                              tween: Tween<double>(begin: 0, end: targetBlur),
                              duration: 800.ms,
                              builder: (context, blurValue, child) {
                                return ImageFiltered(
                                  imageFilter: ImageFilter.blur(
                                    sigmaX: blurValue,
                                    sigmaY: blurValue,
                                  ),
                                  child: AnimatedOpacity(
                                    duration: 1000.ms,
                                    opacity: targetAlpha,
                                    curve: Curves.easeInOut,
                                    child: Text(
                                      layer.text,
                                      style: baseStyle,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      )
                      // 🌟 只有在刚入场时执行的弹射动画
                      .animate(key: ValueKey('layer_entry_${layer.entryTime}'))
                      .fadeIn(duration: 300.ms)
                      .scale(
                        begin: const Offset(0.4, 0.4),
                        end: const Offset(1, 1),
                        curve: Curves.easeOutBack,
                      ),
            );
          }).toList(),
        );

      case 'hero':
        return AnimatedBuilder(
          animation: widget.vfxController,
          builder: (context, child) {
            final scale = 1.0 + (widget.vfxController.value * 0.1);
            return Transform.scale(scale: scale, child: child);
          },
          child:
              Text(
                    widget.text,
                    key: ValueKey('hero_${widget.text}'),
                    style: baseStyle,
                    textAlign: TextAlign.center,
                  )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .blurXY(begin: widget.blurIntensity, end: 0, duration: 400.ms)
                  .shimmer(duration: 1000.ms, color: Colors.white54),
        );

      case 'cards':
        List<String> chars = widget.text.split('');
        return Wrap(
          key: ValueKey('cards_${widget.text}'),
          alignment: WrapAlignment.center,
          spacing: 8.0,
          runSpacing: 12.0,
          children: chars
              .map((char) {
                if (char.trim().isEmpty) {
                  return SizedBox(width: widget.fontSize * 0.5);
                }
                return Container(
                  padding: EdgeInsets.all(widget.fontSize * 0.2),
                  decoration: BoxDecoration(
                    color: Colors.pinkAccent.withValues(alpha: 0.8),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    char,
                    style: baseStyle.copyWith(
                      shadows: [],
                      color: Colors.white,
                      letterSpacing: 0,
                    ),
                  ),
                );
              })
              .toList()
              .animate(interval: 100.ms)
              .scale(curve: Curves.easeOutBack, duration: 300.ms)
              .fadeIn(duration: 300.ms),
        );
      case 'outline':
        // 🌟 核心复刻：大描边错落跳动字
        List<String> chars = widget.text.split('');
        final double strokeWidth = widget.fontSize * 0.15; // 动态计算描边宽度

        return Wrap(
          key: ValueKey('outline_${widget.text}'),
          alignment: WrapAlignment.center,
          spacing: widget.fontSize * 0.1, // 字符间距
          children: chars
              .asMap()
              .entries
              .map((entry) {
                int i = entry.key;
                String char = entry.value;

                if (char.trim().isEmpty) {
                  return SizedBox(width: widget.fontSize * 0.5);
                }

                // 1. 计算错落的 Y 轴位移 (偶数向上，奇数向下)
                final double staggerY =
                    (i % 2 == 0 ? -1 : 1) * (widget.fontSize * 0.15);

                return Transform.translate(
                  offset: Offset(0, staggerY),
                  child: AnimatedBuilder(
                    animation: widget.vfxController,
                    builder: (context, child) {
                      // 2. 注入节拍跳动 (Beat Pulse)
                      final double beatScale =
                          1.0 + (widget.vfxController.value * 0.06);
                      return Transform.scale(scale: beatScale, child: child);
                    },
                    child: Stack(
                      children: [
                        // 底层：粗描边 (Stroke)
                        Text(
                          char,
                          style: TextStyle(
                            fontSize: widget.fontSize,
                            fontFamily: widget.fontFamily,
                            fontWeight: FontWeight.w900,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = strokeWidth
                              ..color = Colors.white, // 描边颜色
                          ),
                        ),
                        // 顶层：纯色填充 (Fill)
                        Text(
                          char,
                          style: TextStyle(
                            fontSize: widget.fontSize,
                            fontFamily: widget.fontFamily,
                            fontWeight: FontWeight.w900,
                            color:
                                Colors.grey[800], // 填充颜色（参考 TS 的 #e0e0e0 可自行调整）
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              })
              .toList()
              .animate(interval: 150.ms) // 逐字出场间隔
              .fadeIn(duration: 300.ms)
              .slideY(
                begin: 0.8,
                end: 0,
                curve: Curves.easeOutBack,
                duration: 600.ms,
              ) // 向上弹射
              .scale(
                begin: const Offset(0, 0),
                end: const Offset(1, 1),
                curve: Curves.elasticOut,
                duration: 800.ms,
              ), // 弹性缩放
        );
      case 'typewriter':
        // 🌟 核心新增：带闪烁光标的打字机特效
        final int textLen = widget.text.length;
        // 动态计算打字总时长：字越多，打字越久（这里设定每个字大概耗时 120 毫秒）
        final int durationMs = math.max(400, textLen * 120);

        return TweenAnimationBuilder<int>(
          key: ValueKey('typewriter_${widget.text}'),
          tween: IntTween(begin: 0, end: textLen),
          duration: Duration(milliseconds: durationMs),
          builder: (context, charCount, child) {
            // 截取当前应该显示的文字长度
            String visibleText = widget.text.substring(0, charCount);

            return Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: visibleText),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: child!, // 把一直闪烁的光标插在最后面
                  ),
                ],
              ),
              style: baseStyle,
              textAlign: TextAlign.center,
            );
          },
          // 将光标作为独立的 child 传入，保证光标的闪烁动画不会因为文字增加而被打断
          child:
              Text(
                    '_', // 你也可以换成 '|' 或者 '█'
                    style: baseStyle.copyWith(
                      color: Colors.greenAccent, // 给光标加个显眼的荧光绿，更有极客/打字机味
                    ),
                  )
                  .animate(
                    onPlay: (controller) => controller.repeat(reverse: true),
                  )
                  .fade(duration: 350.ms, curve: Curves.easeInOut), // 呼吸闪烁
        );
      case 'strip':
        // 🌟 核心复刻：斜向文字条效果
        final List<String> chars = widget.text.split('');
        final double stripWidth = widget.fontSize * 1.5;
        final double stripHeight = widget.fontSize * (chars.length + 1.5);

        return AnimatedBuilder(
          animation: widget.vfxController,
          builder: (context, child) {
            // 1. 模拟 TS 里的 drift (漂移) 效果
            // 利用 vfxController 的值制造轻微的位移
            final double drift =
                math.sin(widget.vfxController.value * math.pi * 2) * 5;

            return Transform.translate(
              offset: Offset(drift, 0),
              child: Transform.rotate(
                angle: -30 * math.pi / 180, // 固定倾斜 -30 度
                child: child,
              ),
            );
          },
          child:
              Container(
                    key: ValueKey('strip_${widget.text}'),
                    width: stripWidth,
                    height: stripHeight,
                    decoration: BoxDecoration(
                      // 背景条颜色：取一个带透明度的半透明粉色/蓝色，或者自定义
                      color: Colors.pinkAccent.withValues(alpha: 0.85),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(4, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: chars.map((char) {
                        return Text(
                          char,
                          style: baseStyle.copyWith(
                            fontSize: widget.fontSize * 0.8, // 文字稍小一点适配条宽
                            shadows: [], // 文字条通常不需要阴影，靠背景对比
                          ),
                        );
                      }).toList(),
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .scaleY(
                    begin: 0,
                    end: 1,
                    alignment: Alignment.center,
                    duration: 500.ms,
                    curve: Curves.easeOutCubic,
                  )
                  .shimmer(duration: 1200.ms, color: Colors.white24),
        );
      case 'standard':
      default:
        return Text(
              widget.text,
              key: ValueKey('std_${widget.text}'),
              style: baseStyle,
              textAlign: TextAlign.center,
            )
            .animate()
            .fade(duration: 400.ms)
            .slideY(
              begin: 0.5,
              end: 0,
              duration: 400.ms,
              curve: Curves.easeOutBack,
            )
            .shimmer(duration: 800.ms);
    }
  }
}
