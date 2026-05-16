import 'package:flutter/material.dart';
import 'chat_page.dart';

class MemoryAssistantOverlay extends StatefulWidget {
  const MemoryAssistantOverlay({Key? key}) : super(key: key);

  @override
  State<MemoryAssistantOverlay> createState() => _MemoryAssistantOverlayState();
}

class _MemoryAssistantOverlayState extends State<MemoryAssistantOverlay> {
  // 初始位置设定
  double _left = 0;
  double _top = 0;
  bool _isInitialized = false;

  void _updatePosition(DragUpdateDetails details, Size screenSize) {
    setState(() {
      _left += details.delta.dx;
      _top += details.delta.dy;

      // 边界限制，防止球拖出屏幕
      _left = _left.clamp(0.0, screenSize.width - 60.0);
      _top = _top.clamp(0.0, screenSize.height - 60.0);
    });
  }

  void _openChatPanel() {
    debugPrint("🚀 记忆助理被点击了！");
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const ChatPage()));
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // 首次运行根据屏幕大小初始化位置
    if (!_isInitialized) {
      _left = screenSize.width - 80;
      _top = screenSize.height - 200;
      _isInitialized = true;
    }

    return Positioned(
      left: _left,
      top: _top,
      child: GestureDetector(
        onPanUpdate: (details) => _updatePosition(details, screenSize),
        onTap: _openChatPanel,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            // 👇 这里已经换成了你指定的主题色
            color: const Color.fromARGB(255, 255, 64, 129),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color.fromARGB(255, 255, 64, 129).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}
