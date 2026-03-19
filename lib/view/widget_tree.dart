import 'package:flutter/material.dart';
import 'pages/home_page.dart'; // 🌟 导入刚才新写的首页
import 'pages/album_page.dart';
import 'pages/create_page.dart';
import 'pages/profile_page.dart';
import 'pages/theme_clusters_page.dart';

class WidgetTree extends StatefulWidget {
  const WidgetTree({super.key});

  @override
  State<WidgetTree> createState() => _WidgetTreeState();
}

class _WidgetTreeState extends State<WidgetTree> {
  int _currentIndex = 0; // 默认一打开显示 0（首页）

  // 🌟 去掉 CreatePage 这个“伪占位符”，因为现在它是被 push 出来的
  final List<Widget> _pages = const [
    HomePage(), // 0: 首页
    AlbumPage(), // 1: 相册
    SizedBox(), // 2: 占位用的空盒子，永远不会被渲染，因为我们拦截了 2 的点击
    ThemeClustersPage(), // 3: 主题聚类
    ProfilePage(), // 4: 我的
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      extendBody: true,
      resizeToAvoidBottomInset: false,

      // ==========================================
      // 🌟 核心视觉点 1：中间凸起的悬浮按钮 (FAB)
      // ==========================================
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // 还原设计图的紫粉渐变色
          gradient: LinearGradient(
            colors: [Colors.purpleAccent.shade100, Colors.purple.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () {
            // ====================================================
            // 🚀 神级修改点：不要 setState 切频道了，直接全屏盖上去！
            // ====================================================
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CreatePage(),
                fullscreenDialog: true, // 可选：让它像模态框一样从底部往上弹，更有仪式感
              ),
            );
          },
          backgroundColor: Colors.transparent, // 背景透明，露出外层的渐变色
          elevation: 0,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, size: 36, color: Colors.white),
        ),
      ),

      // ==========================================
      // 🌟 核心视觉点 2：带有凹槽的自定义底部导航栏
      // ==========================================
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(), // 魔法属性：制造完美的弧形凹槽
        notchMargin: 8.0, // 凹槽边缘的呼吸间距
        padding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias, // 抗锯齿裁剪
        child: SizedBox(
          height: 65, // 稍微增加高度，适配现代手机
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home_outlined, Icons.home, '首页', 0),
              _buildNavItem(Icons.image_outlined, Icons.image, '相册', 1),

              const SizedBox(width: 48), // ⚠️ 关键：给中间的巨大加号留出空位

              _buildNavItem(Icons.category_outlined, Icons.category, '主题', 3),
              _buildNavItem(Icons.person_outline, Icons.person, '我的', 4),
            ],
          ),
        ),
      ),
    );
  }

  // 🌟 底部导航栏子项的统一构建方法
  Widget _buildNavItem(
    IconData icon,
    IconData activeIcon,
    String label,
    int index,
  ) {
    final isSelected = _currentIndex == index;
    // 还原设计图：选中时是粉色，未选中时是浅灰色
    final color = isSelected
        ? Colors.pinkAccent.shade200
        : Colors.grey.shade400;

    return InkWell(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      splashColor: Colors.transparent, // 去除点击时的原生水波纹，让交互更高级
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isSelected ? activeIcon : icon, color: color, size: 26),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
