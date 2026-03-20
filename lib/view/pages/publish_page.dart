import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 用于剪贴板操作
import '../../service/llm_service.dart';

class PublishPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<String> captions;
  final String targetPlatform;
  final String exportedVideoPath; // 导出的视频路径

  const PublishPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.captions,
    required this.targetPlatform,
    required this.exportedVideoPath,
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
    // 呼叫 AI 生成平台专属文案
    final result = await LLMService().generateSocialMediaCopy(
      platform: widget.targetPlatform,
      title: widget.title,
      subtitle: widget.subtitle,
      captions: widget.captions,
    );

    if (mounted) {
      setState(() {
        _copyController.text = result;
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _copyController.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✨ 文案已复制到剪贴板，快去发帖吧！'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('导出成功'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 🌟 顶部成功提示
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            const Text(
              '视频已保存到相册！',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '已为您准备好【${widget.targetPlatform}】专属发帖文案',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),

            // 🌟 文案编辑区
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: _isLoading
                  ? const SizedBox(
                      height: 200,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('AI 正在冥思苦想中...'),
                          ],
                        ),
                      ),
                    )
                  : TextField(
                      controller: _copyController,
                      maxLines: 12, // 允许多行展示和编辑
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: '这里是发帖文案...',
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.6),
                    ),
            ),
            const SizedBox(height: 24),

            // 🌟 操作按钮
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _copyToClipboard,
                    icon: const Icon(Icons.copy),
                    label: const Text('一键复制文案'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.pinkAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                // 回到应用首页 (假设首页是路由的最底层)
                Navigator.popUntil(context, (route) => route.isFirst);
              },
              child: const Text('返回首页', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}
