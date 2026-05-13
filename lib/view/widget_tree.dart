/// 应用的主底部导航树，负责在首页、相册、创作、个人页和主题页之间切换。

import 'package:flutter/material.dart';
import '../service/ai_progress_notification_service.dart';
import '../service/ai_service.dart';
import '../service/album_refresh_service.dart';
import 'pages/home_page.dart'; // 🌟 导入刚才新写的首页
import 'pages/album_page.dart';
import 'pages/create_hub_page.dart';
import 'pages/profile_page.dart';
import 'pages/theme_clusters_page.dart';

class WidgetTree extends StatefulWidget {
  const WidgetTree({super.key});

  @override
  State<WidgetTree> createState() => _WidgetTreeState();
}

class _WidgetTreeState extends State<WidgetTree> with WidgetsBindingObserver {
  int _currentIndex = 0; // 默认一打开显示 0（首页）
  bool _progressBannerHidden = false; // 进度条隐藏状态
  int _hiddenRefreshProgressRunId = -1;

  // 🌟 去掉 CreatePage 这个"伪占位符"，因为现在它是被 push 出来的
  final List<Widget> _pages = const [
    HomePage(), // 0: 首页
    AlbumPage(), // 1: 相册
    SizedBox(), // 2: 占位用的空盒子，永远不会被渲染，因为我们拦截了 2 的点击
    ThemeClustersPage(), // 3: 主题聚类
    ProfilePage(), // 4: 我的
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AIProgressNotificationService().bindNavigationHandler(_handleNavigationTarget);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleNavigationTarget(dynamic target) {
    if (!mounted || target is! String) {
      return;
    }
    if (target == 'album' ||
        target == AIProgressNotificationService.navigationAlbum) {
      setState(() {
        _currentIndex = 1;
        _progressBannerHidden = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 每次进入前台或页面变化时，自动显示进度条
    if (state == AppLifecycleState.resumed) {
      setState(() {
        _progressBannerHidden = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _pages[_currentIndex],
          _buildTopProgressOverlay(),
        ],
      ),
      extendBody: false,
      resizeToAvoidBottomInset: false,

      // ==========================================
      // 🌟 核心视觉点 1：中间凸起的悬浮按钮 (FAB)
      // ==========================================
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _buildCenterActionButton(context),

      // ==========================================
      // 🌟 核心视觉点 2：带有凹槽的自定义底部导航栏
      // ==========================================
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(), // 魔法属性：制造完美的弧形凹槽
        notchMargin: 8.0, // 凹槽边缘的呼吸间距
        surfaceTintColor: Colors.transparent,
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

  Widget _buildCenterActionButton(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.pink.shade300, Colors.deepPurple.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Theme.of(context).scaffoldBackgroundColor,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.deepPurple.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateHubPage(),
                  fullscreenDialog: true,
                ),
              );
            },
            child: const Center(
              child: Icon(Icons.add, size: 34, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopProgressOverlay() {
    return ValueListenableBuilder<AlbumRefreshProgress>(
      valueListenable: AlbumRefreshService().progressListenable,
      builder: (context, refreshProgress, _) {
        return ValueListenableBuilder<AIAnalysisProgress>(
          valueListenable: AIService().progressListenable,
          builder: (context, aiProgress, child) {
            if (refreshProgress.isVisible &&
                _hiddenRefreshProgressRunId != refreshProgress.runId) {
              return _TopProgressBanner(
                key: const ValueKey<String>('album-refresh-progress'),
                title: refreshProgress.title,
                message: refreshProgress.message,
                progress: refreshProgress.progress,
                onHide: () {
                  setState(() {
                    _hiddenRefreshProgressRunId = refreshProgress.runId;
                  });
                },
              );
            }
            if (_currentIndex == 1 || !aiProgress.isVisible || _progressBannerHidden) {
              return const SizedBox.shrink();
            }
            return _TopProgressBanner(
              key: const ValueKey<String>('global-ai-progress'),
              title: '后台 AI 正在继续处理',
              message: aiProgress.currentStep,
              progress: aiProgress.fraction,
              onHide: () {
                setState(() {
                  _progressBannerHidden = true;
                });
              },
            );
          },
        );
      },
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
          _progressBannerHidden = false; // 页面切换时重新显示进度条
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

class _TopProgressBanner extends StatelessWidget {
  const _TopProgressBanner({
    super.key,
    required this.title,
    required this.message,
    required this.progress,
    this.onHide,
  });

  final String title;
  final String message;
  final double progress;
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                blurRadius: 14,
                offset: Offset(0, 4),
                color: Color(0x22000000),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ],
              ),
              // 隐藏按钮（仅在有 onHide 回调时显示）
              if (onHide != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: onHide,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
