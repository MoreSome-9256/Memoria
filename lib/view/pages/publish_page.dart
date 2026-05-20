/// 发布页面，提供故事分享和发布相关功能。

import 'dart:ui'; // 🌟 新增：用于实现毛玻璃高斯模糊效果
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../../service/llm_service.dart';
import '../../service/video_cache_service.dart';

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
            Icon(Icons.content_copy, color: Colors.white),
            SizedBox(width: 8),
            Text(
              '📋 文案已复制到剪贴板',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _shareVideo() async {
    try {
      final videoFile = File(widget.exportedVideoPath);
      if (!videoFile.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('❌ 视频文件未找到'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        return;
      }

      // 构建更丰富的分享内容
      String shareText = '📱 ${_copyController.text}\n\n';
      shareText += '🎬 使用「智能影记」制作的回忆视频\n';
      shareText += '#${widget.targetPlatform} #回忆 #故事';
      
      await Share.shareXFiles(
        [XFile(widget.exportedVideoPath)],
        text: shareText,
        subject: '${widget.title} - ${widget.subtitle}',
      );
      
      // 分享成功后的反馈
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  '✨ 分享成功！视频和文案已发送',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('分享失败: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _openVideoFile() async {
    try {
      final videoFile = File(widget.exportedVideoPath);
      if (!videoFile.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('❌ 视频文件未找到'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        return;
      }

      // 📱 获取文件名和目录信息
      final fileName = path.basename(widget.exportedVideoPath);
      
      // 尝试使用 open_file 包打开文件
      final result = await OpenFile.open(widget.exportedVideoPath);
      
      if (mounted) {
        // 根据 open_file 包的文档，OpenResult.type 是字符串
        if (result.type == "done") {
          // 成功打开
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '✅ 正在打开视频文件：$fileName',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade400,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } else if (result.type == "noAppToOpen") {
          // 没有应用可以打开此文件类型
          // 显示导出文件列表，让用户选择
          await _showExportFilesList();
        } else if (result.type == "fileNotFound") {
          // 文件未找到（虽然我们已经检查过）
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('❌ 文件未找到或无法访问'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } else if (result.type == "permissionDenied") {
          // 权限被拒绝
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('🔒 需要文件访问权限'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        } else {
          // 其他错误
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ 打开文件失败: ${result.message}'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失败: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  /// 显示导出文件列表
  Future<void> _showExportFilesList() async {
    final files = await VideoCacheService.instance.getExportFiles();
    
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('📁 导出目录为空'),
            backgroundColor: Colors.orange.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('📁 导出视频文件'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (context, index) {
                final file = files[index];
                return ListTile(
                  leading: const Icon(Icons.video_library),
                  title: Text(file['name']),
                  subtitle: Text('${file['sizeFormatted']} • ${file['dateFormatted']}'),
                  onTap: () async {
                    Navigator.pop(context);
                    await OpenFile.open(file['path']);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
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
                    '🎉 分享你的故事',
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
                            color: Colors.pinkAccent.withValues(alpha: 0.1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.pinkAccent.withValues(alpha: 0.2),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.share,
                            color: Colors.pinkAccent,
                            size: 72,
                          ),
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          '视频已准备好分享！',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'AI 已为您生成【${widget.targetPlatform}】专属文案，一键分享到社交平台',
                          style: TextStyle(color: Colors.black54, fontSize: 15),
                          textAlign: TextAlign.center,
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

                        // 🌟 底部操作按钮群 - 重新设计：分享为主，复制为辅
                        // 📱 主要操作：一键分享视频+文案
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _shareVideo,
                            icon: const Icon(Icons.share_rounded),
                            label: const Text(
                              '一键分享到社交平台',
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
                        const SizedBox(height: 12),

                        // 📋 次要操作：仅复制文案（用于手动编辑）
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _copyToClipboard,
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text(
                              '仅复制文案',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              side: BorderSide(color: Colors.pinkAccent.shade200, width: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              foregroundColor: Colors.pinkAccent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 📁 在文件管理器中打开视频
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _openVideoFile,
                            icon: const Icon(Icons.folder_open_rounded),
                            label: const Text(
                              '在文件管理器中打开',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.deepPurple.shade300,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 📋 管理导出文件
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _showExportFilesList,
                            icon: const Icon(Icons.list_alt_rounded),
                            label: const Text(
                              '查看所有导出文件',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.deepPurple.shade200, width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              foregroundColor: Colors.deepPurple,
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
