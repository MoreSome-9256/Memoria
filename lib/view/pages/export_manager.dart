/// 导出管理页面，负责照片和故事导出的操作入口。

import 'package:flutter/material.dart';
import '../../models/vo/story_section.dart';
import 'publish_page.dart';
import 'offscreen_render_worker.dart';

class ExportManager {
  static final ExportManager instance = ExportManager._();
  ExportManager._();

  bool isExporting = false;

  void startBackgroundExport({
    required BuildContext context,
    required String title,
    required String subtitle,
    required List<StorySection> sections,
    required String? customMusicPath,
    required Map<String, dynamic>? dynamicBeatData,
    required String targetPlatform,
    // 🌟 新增：所有视觉状态
    required bool isHorizontal,
    required String currentTextStyle,
    required double textYPosition,
    required double textSize,
    required double textBlurIntensity,
    required double shakeIntensity,
    required double shakeFrequency,
    required double glitchIntensity,
    required bool enableFlash,
    required bool useVignette,
    required bool useGrain,
    required bool useCameraFrame,
    required bool useGlowRing,
    required bool useCloudBorder,
    // 🌟 新增滤镜参数
    required double imageSaturation,
    required String imageFilterType,
    int? storyEntityId,
    /// 若提供，导出完成后直接调起系统分享，不弹"导出成功"对话框
    void Function(String videoPath)? onShareReady,
  }) {
    if (isExporting) return;
    isExporting = true;

    // 🌟 核心修复 1：在一切开始之前，先把最稳定的全局导航器抓在手里！
    // 这样即使当前页面被关了，或者画布被销毁了，我们依然能找到路由。
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    OverlayState overlayState = Overlay.of(context, rootOverlay: true);
    late OverlayEntry overlayEntry;
    // 🌟 核心 1：创建一个极其轻量的响应式变量，用来装进度
    final ValueNotifier<double> progressNotifier = ValueNotifier(0.0);

    overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.01,
                  child: SizedBox(
                    width: 720,
                    height: 1280,
                    child: OffscreenRenderWorker(
                      title: title,
                      subtitle: subtitle,
                      sections: sections,
                      customMusicPath: customMusicPath,
                      dynamicBeatData: dynamicBeatData,
                      targetPlatform: targetPlatform,
                      // 🌟 新增：把状态塞给渲染工
                      isHorizontal: isHorizontal,
                      currentTextStyle: currentTextStyle,
                      textYPosition: textYPosition,
                      textSize: textSize,
                      textBlurIntensity: textBlurIntensity,
                      shakeIntensity: shakeIntensity,
                      shakeFrequency: shakeFrequency,
                      glitchIntensity: glitchIntensity,
                      enableFlash: enableFlash,
                      useVignette: useVignette,
                      useGrain: useGrain,
                      useCameraFrame: useCameraFrame,
                      useGlowRing: useGlowRing,
                      useCloudBorder: useCloudBorder,
                      // 🌟 新增：把参数继续往下传给打工仔
                      imageSaturation: imageSaturation,
                      imageFilterType: imageFilterType,
                       storyEntityId: storyEntityId,
                       onProgress: (p) => progressNotifier.value = p,
                       onComplete: (String finalPath, Future<String>? aiCopy) {
                        if (overlayEntry.mounted) overlayEntry.remove();
                        progressNotifier.dispose();
                        isExporting = false;

                        if (onShareReady != null) {
                          onShareReady(finalPath);
                        } else {
                          _showSuccessDialog(
                            rootNavigator,
                            title,
                            subtitle,
                            targetPlatform,
                            finalPath,
                            aiCopy,
                            sections,
                          );
                        }
                      },
                      onError: (error, stackTrace) {
                        if (overlayEntry.mounted) overlayEntry.remove();
                        progressNotifier.dispose();
                        isExporting = false;
                        ScaffoldMessenger.of(rootNavigator.context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text('视频导出失败：$error'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            // [顶层]：全局悬浮进度小胶囊
            Positioned(
              // 自动避开刘海屏/灵动岛，悬浮在屏幕正上方偏下一点点
              top: MediaQuery.of(overlayContext).padding.top + 16,
              left: 0,
              right: 0,
              child: IgnorePointer(
                // 不要挡住用户在这个区域的点击操作
                child: Center(
                  // 🌟 核心 3：只监听 progressNotifier，单独刷新这个小区域
                  child: ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (context, progress, child) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75), // 半透明黑底
                          borderRadius: BorderRadius.circular(30), // 胶囊形状
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 旋转的粉色小圈圈
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 2.5,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.pinkAccent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // 文字进度
                            Text(
                              '后台渲染中 ${(progress * 100).toInt()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none, // 必须加这个，防止黄线
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    overlayState.insert(overlayEntry);
  }

  // 🌟 核心修复 3：接收 NavigatorState，用它来弹窗和跳转
  void _showSuccessDialog(
    NavigatorState navigator,
    String title,
    String subtitle,
    String platform,
    String videoPath,
    Future<String>? aiCopy,
    List<StorySection> sections,
  ) {
    showDialog(
      // 🌟 用导航器自带的绝对安全的 context 去显示弹窗
      context: navigator.context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("🎉 导出完成！"),
          content: const Text("您的专属回忆视频已经在后台渲染完毕啦，AI 文案也准备好了，快去发布吧！"),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(), // 关掉弹窗
              child: const Text("稍后再说", style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              onPressed: () {
                navigator.pop(); // 先关掉弹窗

                List<String> captions = sections.map((s) => s.text).toList();

                // 🌟 核心修复 4：用全局导航器进行绝对安全的页面跳转！
                navigator.push(
                  MaterialPageRoute(
                    builder: (context) => PublishPage(
                      title: title,
                      subtitle: subtitle,
                      captions: captions,
                      targetPlatform: platform,
                      exportedVideoPath: videoPath,
                      generatedCopyFuture: aiCopy,
                    ),
                  ),
                );
              },
              child: const Text("去发布"),
            ),
          ],
        );
      },
    );
  }
}
