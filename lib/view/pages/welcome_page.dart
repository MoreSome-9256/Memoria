import 'package:flutter/material.dart';
import '../widget_tree.dart'; // 登录成功后跳转到这里

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 使用 Stack 堆叠背景和内容
      body: Stack(
        children: [
          // 1. 🖼️ 全屏背景图
          Positioned.fill(
            child: Image.asset(
              'assets/images/welcome_bg.jpg', // 请确保路径正确
              fit: BoxFit.cover,
            ),
          ),

          // 2. 📝 内容层
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30.0), // 整体侧边距
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // 默认让所有东西靠左
                children: [
                  const SizedBox(height: 110),

                  // ==========================================
                  // 1. 🖼️ Logo 区域：强制靠右 (Alignment.centerRight)
                  // ==========================================
                  Align(
                    alignment: Alignment.centerRight,
                    child: Transform.translate(offset: const Offset(15, 20),
                    child: Container(
                        width: 200, // 根据你的设计图调整大小
                        height: 200,
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withOpacity(0.1),
                              blurRadius: 30,
                              offset: const Offset(-10, 10),
                            ),
                          ],
                        ),
                        child: Image.asset('assets/images/logo.png'),
                      ),
                    )
                    
                  ),

                  const SizedBox(height: 85),

                  // ==========================================
                  // 2. 📝 软件名称：保持靠左 (默认对齐)
                  // ==========================================
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFFFFA726), Color(0xFFEC407A)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(Offset.zero & bounds.size),
                    child: const Text(
                      '智能影记',
                      style: TextStyle(
                        fontSize: 45, // 稍微加大一点，气场更强
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // --- 副标题：也跟随标题靠左 ---
                  const Text(
                    '做自己生活的导演',
                    style: TextStyle(
                      fontSize: 20,
                      color: Color(0xFFF48FB1),
                      letterSpacing: 2,
                    ),
                  ),

                  const Spacer(),

                  // --- 3. 底部按钮组 (保持居中或充满宽度) ---
                  _buildStandardButton(
                    context,
                    label: '登录',
                    color: const Color(0xFFF48FB1),
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => const WidgetTree(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _buildStandardButton(
                    context,
                    label: '注册',
                    color: const Color(0xFFB39DDB),
                    onPressed: () {},
                  ),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建按钮的辅助方法
  Widget _buildStandardButton(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(27),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }
}
