/// 发布页面，提供故事分享和发布相关功能。

import 'dart:ui'; // 🌟 新增：用于实现毛玻璃高斯模糊效果
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../service/llm_service.dart';

class PublishPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<String> captions;
  final String targetPlatform;
  final String exportedVideoPath;
  final Future<String>? generatedCopyFuture;

  const PublishPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.captions,
    required this.targetPlatform,
    required this.exportedVideoPath,
    this.generatedCopyFuture,
  });

  @override
  State<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends State<PublishPage> {
  final TextEditingController _copyController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _generateCopy();
  }

  @override
  void dispose() {
    _copyController.dispose();
    super.dispose();
  }

  Future<void> _generateCopy() async {
    String result = '';

    try {
      // 🌟 2. 核心逻辑：如果上个页面已经开始跑了，我们直接等它现成的结果！
      // 由于导出视频通常比 AI 慢得多，所以这里的 await 几乎会瞬间完成 (0延迟)！
      if (widget.generatedCopyFuture != null) {
        result = await widget.generatedCopyFuture!;
      } else {
        // 兜底逻辑：万一是从别的地方跳转来的没有 Future，就当场现生
        result = await LLMService().generateSocialMediaCopy(
          platform: widget.targetPlatform,
          title: widget.title,
          subtitle: widget.subtitle,
          captions: widget.captions,
        );
      }
    } catch (e) {
      result = 'AI 生成文案时开小差了，请手动写点什么吧~';
    }

    if (mounted) {
      setState(() {
        _copyController.text = result;
        _isLoading = false; // 瞬间变为 false，关闭圈圈！
      });
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _copyController.text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white),
            SizedBox(width: 8),
            Text(
              '✨ 文案已复制，快去惊艳朋友圈吧！',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: Colors.pinkAccent.shade200, // 换成更温柔的猛男粉
        behavior: SnackBarBehavior.floating, // 悬浮样式更现代
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 🌟 1. 移除纯色背景，使用 Stack 来铺满渐变
      body: Stack(
        children: [
          // 🌌 极光渐变背景层 (你可以把这里的颜色换成你首页的同款 Hex 值)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE8DEFF), // 浅紫极光
                  Color(0xFFE1F5FE), // 清透浅蓝
                  Color(0xFFFCE4EC), // 猛男落樱粉
                ],
                stops: [0.1, 0.5, 0.9],
              ),
            ),
          ),

          // 📄 主体内容层
          SafeArea(
            child: Column(
              children: [
                // 自定义透明 AppBar
                AppBar(
                  title: const Text(
                    '🎉 导出成功',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  centerTitle: true,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  iconTheme: const IconThemeData(
                    color: Colors.black87,
                  ), // 保证返回键可见
                ),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(), // 苹果质感的回弹滑动
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 16.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 🌟 顶部成功图标 (加一点梦幻发光阴影)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.green.withValues(alpha: 0.1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.2),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 72,
                          ),
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          '视频已保存到相册！',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'AI 已为您准备好【${widget.targetPlatform}】专属爆款文案',
                          style: TextStyle(color: Colors.black54, fontSize: 15),
                        ),
                        const SizedBox(height: 32),

                        // 🌟 核心升级：毛玻璃 (Glassmorphism) 文案编辑区
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: 12,
                              sigmaY: 12,
                            ), // 调整模糊度
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(
                                  alpha: 0.5,
                                ), // 半透明白底
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withValues(
                                    alpha: 0.8,
                                  ), // 高光描边
                                  width: 1.5,
                                ),
                              ),
                              padding: const EdgeInsets.all(20),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 200,
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            CircularProgressIndicator(
                                              color: Colors.pinkAccent,
                                            ),
                                            SizedBox(height: 20),
                                            Text(
                                              '🤖 AI 正在疯狂查阅小红书爆款指南...',
                                              style: TextStyle(
                                                color: Colors.black54,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : TextField(
                                      controller: _copyController,
                                      maxLines: 12,
                                      cursorColor: Colors.pinkAccent, // 猛男粉光标
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        hintText: '这里是发帖文案...',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        height: 1.6,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // 🌟 底部操作按钮群
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _copyToClipboard,
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text(
                              '一键复制文案',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              backgroundColor: Colors.pinkAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        TextButton(
                          onPressed: () {
                            Navigator.popUntil(
                              context,
                              (route) => route.isFirst,
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            '返回首页',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
