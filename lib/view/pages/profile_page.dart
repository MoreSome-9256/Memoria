// 个人资料页面，提供设置、调试入口和账户信息展示。

import 'dart:async';
import 'dart:io';

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:photo_album/service/cognito_auth_service.dart';
import 'package:photo_album/service/app_ai_settings_service.dart';
import 'package:photo_album/service/media_access_grant_service.dart';
import 'package:photo_album/service/mobileclip_backend_preference_service.dart';
import 'package:photo_album/service/litert_inference_service.dart';
import 'package:photo_album/service/photo_service.dart';
import 'package:photo_album/service/travel_memory_detector.dart';
import 'package:photo_album/view/pages/welcome_page.dart';

import 'package:photo_album/service/album_selection_preference_service.dart';

import 'face_cluster_debug_page.dart';
import 'internvl_lab_page.dart';
import 'junk_photo_trash_page.dart';
import 'local_vlm_test_page.dart';
import 'media_access_range_page.dart';
import 'media_vector_similarity_test_page.dart';
import 'mobileclip_benchmark_page.dart';
import 'mobileclip_vector_probe_page.dart';
import '../../service/video_cache_service.dart';
import 'ai_model_weights_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfileIdentity {
  const _ProfileIdentity({required this.displayName, required this.isSignedIn});

  final String displayName;
  final bool isSignedIn;
}

class _ProfilePageState extends State<ProfilePage> {
  final _auth = const CognitoAuthService();
  final _backendPreferenceService = MobileClipBackendPreferenceService();
  final _albumSelectionPreferenceService = AlbumSelectionPreferenceService();

  String _albumSelectionSummary = '未授权任何媒体';

  Future<AuthUser?> _loadUser() async {
    try {
      final signedIn = await _auth.isSignedIn();
      if (!signedIn) {
        return null;
      }
      return Amplify.Auth.getCurrentUser();
    } catch (_) {
      return null;
    }
  }

  Future<_ProfileIdentity> _loadProfileIdentity() async {
    final user = await _loadUser();
    if (user == null) {
      return const _ProfileIdentity(displayName: '未登录用户', isSignedIn: false);
    }
    final attributes = await _loadAttributes();
    String? name;
    if (attributes != null) {
      for (final attr in attributes) {
        if (attr.userAttributeKey.key == 'name' &&
            attr.value.trim().isNotEmpty) {
          name = attr.value.trim();
          break;
        }
      }
    }
    return _ProfileIdentity(
      displayName: name ?? user.username,
      isSignedIn: true,
    );
  }

  Future<List<AuthUserAttribute>?> _loadAttributes() async {
    try {
      return await Amplify.Auth.fetchUserAttributes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const WelcomePage()),
      (_) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _refreshAlbumSelectionSummary();
  }

  Future<void> _showScanPreferences() async {
    final prefs = await _albumSelectionPreferenceService.loadScanPreferences();
    int? selectedYear = prefs.minYear;
    String selectedResolutionKey = prefs.hasMinResolution
        ? '${prefs.minWidth}x${prefs.minHeight}'
        : 'none';
    int? selectedMinPixels = prefs.minPixels;
    var excludeExtremeAspectRatios = prefs.excludeExtremeAspectRatios;
    const resolutionOptions = <String, List<int>?>{
      'none': null,
      '320x320': <int>[320, 320],
      '640x480': <int>[640, 480],
      '1280x720': <int>[1280, 720],
      '1920x1080': <int>[1920, 1080],
    };
    const minPixelOptions = <int?>[null, 300000, 1000000, 2000000, 4000000];

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final nowYear = DateTime.now().year;
            final yearItems = <int?>[
              null,
              for (var year = nowYear; year >= 1990; year--) year,
            ];
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '扫描筛选',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text('可选：在读取图片时先过滤明显不适合进入分析队列的项目。默认不限制。'),
                    const SizedBox(height: 12),
                    Text(
                      '最早年份（含）',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<int?>(
                      value: selectedYear,
                      items: yearItems
                          .map(
                            (y) => DropdownMenuItem<int?>(
                              value: y,
                              child: Text(y == null ? '不限制' : y.toString()),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (v) => setSheetState(() => selectedYear = v),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '最小分辨率（宽 x 高）',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      value:
                          resolutionOptions.containsKey(selectedResolutionKey)
                          ? selectedResolutionKey
                          : 'none',
                      items: resolutionOptions.entries
                          .map((entry) {
                            final pair = entry.value;
                            final label = pair == null
                                ? '不限制'
                                : '${pair[0]} x ${pair[1]}';
                            return DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(label),
                            );
                          })
                          .toList(growable: false),
                      onChanged: (key) => setSheetState(() {
                        selectedResolutionKey = key ?? 'none';
                      }),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '最小像素总量',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<int?>(
                      value: selectedMinPixels,
                      items: minPixelOptions
                          .map((pixels) {
                            final label = pixels == null
                                ? '不限制'
                                : pixels >= 1000000
                                ? '${pixels ~/ 1000000} MP'
                                : '${(pixels / 1000000).toStringAsFixed(1)} MP';
                            return DropdownMenuItem<int?>(
                              value: pixels,
                              child: Text(label),
                            );
                          })
                          .toList(growable: false),
                      onChanged: (pixels) => setSheetState(() {
                        selectedMinPixels = pixels;
                      }),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('排除超宽/超长图片'),
                      subtitle: const Text('过滤长截图、横幅、拼接图等极端宽高比项目'),
                      value: excludeExtremeAspectRatios,
                      onChanged: (value) => setSheetState(() {
                        excludeExtremeAspectRatios = value;
                      }),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () async {
                            final selectedPair =
                                resolutionOptions[selectedResolutionKey];
                            await _albumSelectionPreferenceService
                                .saveScanPreferences(
                                  minYear: selectedYear,
                                  minWidth: selectedPair?[0],
                                  minHeight: selectedPair?[1],
                                  minPixels: selectedMinPixels,
                                  excludeExtremeAspectRatios:
                                      excludeExtremeAspectRatios,
                                );
                            PhotoService().invalidateScanSessionCache();
                            if (!context.mounted) return;
                            Navigator.pop(context);
                          },
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _refreshAlbumSelectionSummary() async {
    await MediaAccessGrantService.instance.loadSnapshot();
    if (!mounted) {
      return;
    }
    setState(() {
      _albumSelectionSummary = '使用系统相册（全部照片）';
    });
  }

  Future<void> _showAlbumSelectionSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const MediaAccessRangePage()),
    );
    await _refreshAlbumSelectionSummary();
  }

  Future<void> _showModelTypeSettings() async {
    await _backendPreferenceService.initialize();
    var aiSettings = await AppAiSettingsService.instance.load();
    var batteryOptimizationAllowed = Platform.isAndroid
        ? await MediaAccessGrantService.instance
              .isIgnoringBatteryOptimizations()
        : false;
    if (!mounted) {
      return;
    }

    var selected = _backendPreferenceService.backendListenable.value;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isApplePlatform = Platform.isIOS || Platform.isMacOS;
            final acceleratorSegments = isApplePlatform
                ? const <ButtonSegment<LocalInferenceAccelerator>>[
                    ButtonSegment<LocalInferenceAccelerator>(
                      value: LocalInferenceAccelerator.coreml,
                      label: Text('Core ML'),
                      icon: Icon(Icons.auto_awesome),
                    ),
                    ButtonSegment<LocalInferenceAccelerator>(
                      value: LocalInferenceAccelerator.metal,
                      label: Text('Metal'),
                      icon: Icon(Icons.memory_outlined),
                    ),
                    ButtonSegment<LocalInferenceAccelerator>(
                      value: LocalInferenceAccelerator.xnnpack,
                      label: Text('XNNPACK'),
                      icon: Icon(Icons.tune_outlined),
                    ),
                    ButtonSegment<LocalInferenceAccelerator>(
                      value: LocalInferenceAccelerator.cpu,
                      label: Text('CPU'),
                      icon: Icon(Icons.memory),
                    ),
                  ]
                : const <ButtonSegment<LocalInferenceAccelerator>>[
                    ButtonSegment<LocalInferenceAccelerator>(
                      value: LocalInferenceAccelerator.gpu,
                      label: Text('GPU'),
                      icon: Icon(Icons.memory_outlined),
                    ),
                    ButtonSegment<LocalInferenceAccelerator>(
                      value: LocalInferenceAccelerator.npu,
                      label: Text('NPU'),
                      icon: Icon(Icons.developer_board_outlined),
                    ),
                    ButtonSegment<LocalInferenceAccelerator>(
                      value: LocalInferenceAccelerator.xnnpack,
                      label: Text('XNNPACK'),
                      icon: Icon(Icons.tune_outlined),
                    ),
                    ButtonSegment<LocalInferenceAccelerator>(
                      value: LocalInferenceAccelerator.cpu,
                      label: Text('CPU'),
                      icon: Icon(Icons.memory),
                    ),
                  ];
            final availableAccelerators = acceleratorSegments
                .map((segment) => segment.value)
                .toSet();
            final selectedAccelerator =
                availableAccelerators.contains(aiSettings.inferenceAccelerator)
                ? aiSettings.inferenceAccelerator
                : LocalInferenceAccelerator.xnnpack;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI 模型设置',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'AI 模型如何表现的相关配置。改动会应用到后续 AI 扫描任务，模型在首次调用时按需加载。',
                      ),
                      const SizedBox(height: 20),

                      // 模型类型
                      Text(
                        '模型类型',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<MobileClipBackend>(
                        segments: const <ButtonSegment<MobileClipBackend>>[
                          ButtonSegment<MobileClipBackend>(
                            value: MobileClipBackend.mobileclip2LiteRt,
                            label: Text('MobileCLIP2 LiteRT'),
                            icon: Icon(Icons.auto_awesome_outlined),
                          ),
                          ButtonSegment<MobileClipBackend>(
                            value: MobileClipBackend.ncnn,
                            label: Text('NCNN FFI'),
                            icon: Icon(Icons.memory_outlined),
                          ),
                        ],
                        selected: <MobileClipBackend>{selected},
                        onSelectionChanged: (selection) {
                          setSheetState(() {
                            selected = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '当前选择: ${selected.label} · ${selected.description}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '端侧加速器',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<LocalInferenceAccelerator>(
                        segments: acceleratorSegments,
                        selected: <LocalInferenceAccelerator>{
                          selectedAccelerator,
                        },
                        onSelectionChanged: (selection) {
                          setSheetState(() {
                            aiSettings = aiSettings.copyWith(
                              inferenceAccelerator: selection.first,
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${selectedAccelerator.label} · ${selectedAccelerator.description}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                      if (selectedAccelerator == LocalInferenceAccelerator.npu)
                        Text(
                          'Android NPU 不再走已弃用 NNAPI。官方 LiteRT NPU 需要 CompiledModel、PODAI/AI Pack 和厂商运行时；当前 Android 会回退到 XNNPACK，Apple 平台使用 Core ML。',
                          style: TextStyle(
                            color: Colors.orange[800],
                            fontSize: 12,
                          ),
                        ),
                      if (selectedAccelerator ==
                          LocalInferenceAccelerator.xnnpack) ...[
                        const SizedBox(height: 12),
                        Text(
                          'XNNPACK 线程数：${aiSettings.xnnpackThreadCount}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Slider(
                          value: aiSettings.xnnpackThreadCount.toDouble(),
                          min: 1,
                          max: 8,
                          divisions: 7,
                          label: '${aiSettings.xnnpackThreadCount}',
                          onChanged: (value) {
                            setSheetState(() {
                              aiSettings = aiSettings.copyWith(
                                xnnpackThreadCount: value.round(),
                              );
                            });
                          },
                        ),
                      ],
                      Text(
                        '默认建议 XNNPACK；GPU 保留用于定位 delegate 差异，NPU 仅在已支持的平台走原生实现。',
                        style: TextStyle(
                          color: Colors.orange[800],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'AI 模型 batch size：${aiSettings.analysisBatchSize}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Slider(
                        value: aiSettings.analysisBatchSize.toDouble(),
                        min: 1,
                        max: 16,
                        divisions: 15,
                        label: '${aiSettings.analysisBatchSize}',
                        onChanged: (value) {
                          setSheetState(() {
                            aiSettings = aiSettings.copyWith(
                              analysisBatchSize: value.round(),
                            );
                          });
                        },
                      ),
                      Text(
                        '控制模型内部 batch 参数；后台任务提交不再按 24 个项目切片，而是把本轮待分析项目一次性提交。',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                      const SizedBox(height: 20),

                      Divider(color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        '运行能力',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('OCR 文字识别'),
                        subtitle: const Text('只在你手动添加的分析任务中按需运行'),
                        value: aiSettings.ocrEnabled,
                        onChanged: (value) {
                          setSheetState(() {
                            aiSettings = aiSettings.copyWith(ocrEnabled: value);
                          });
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('人脸聚类与表情分析'),
                        subtitle: const Text('只随同一套图片分析任务执行'),
                        value: aiSettings.faceAnalysisEnabled,
                        onChanged: (value) {
                          setSheetState(() {
                            aiSettings = aiSettings.copyWith(
                              faceAnalysisEnabled: value,
                            );
                          });
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('允许引入视频和动态照片'),
                        subtitle: const Text('开启后选择器和后续分析允许包含视频资源'),
                        value: aiSettings.includeVideos,
                        onChanged: (value) {
                          setSheetState(() {
                            aiSettings = aiSettings.copyWith(
                              includeVideos: value,
                            );
                          });
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('MobileViClip 视频标签'),
                        subtitle: const Text(
                          '模型资产可用时用于视频、Live Photo 和 motion 内容',
                        ),
                        value: aiSettings.mobileViClipEnabled,
                        onChanged: (value) {
                          setSheetState(() {
                            aiSettings = aiSettings.copyWith(
                              mobileViClipEnabled: value,
                            );
                          });
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('后台常驻分析服务'),
                        subtitle: Text(
                          Platform.isIOS
                              ? '使用 iOS Background App Refresh 调度；系统可能每隔一段时间给短后台窗口，强制关闭 App 后会停止'
                              : '仅在你允许后以前台服务处理手动添加的任务',
                        ),
                        value: Platform.isIOS
                            ? aiSettings.iosContinuedProcessingEnabled
                            : aiSettings.androidForegroundServiceEnabled,
                        onChanged: (value) {
                          setSheetState(() {
                            aiSettings = Platform.isIOS
                                ? aiSettings.copyWith(
                                    iosContinuedProcessingEnabled: value,
                                  )
                                : aiSettings.copyWith(
                                    androidForegroundServiceEnabled: value,
                                  );
                          });
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('检测到未完成的任务自动继续'),
                        subtitle: const Text('下次打开 App 时，如果有中断的分析任务则自动恢复'),
                        value: aiSettings.autoResumeAnalysis,
                        onChanged: (value) {
                          setSheetState(() {
                            aiSettings = aiSettings.copyWith(
                              autoResumeAnalysis: value,
                            );
                          });
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('自动分析最新的全部图片'),
                        subtitle: const Text('新图片出现后自动开始分析，无需手动触发'),
                        value: aiSettings.autoAnalyzeNewPhotos,
                        onChanged: (value) {
                          setSheetState(() {
                            aiSettings = aiSettings.copyWith(
                              autoAnalyzeNewPhotos: value,
                            );
                          });
                        },
                      ),
                      if (Platform.isAndroid)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.battery_saver_outlined),
                          title: const Text('电池优化限制'),
                          subtitle: Text(
                            batteryOptimizationAllowed
                                ? '系统已允许后台分析不受电池优化限制。需要撤回时会打开系统设置。'
                                : '允许后，长时间分析任务更不容易被系统中断。',
                          ),
                          trailing: FilledButton(
                            onPressed: () async {
                              if (batteryOptimizationAllowed) {
                                await MediaAccessGrantService.instance
                                    .openBatteryOptimizationSettings();
                                return;
                              }
                              await _requestBatteryOptimizationAccess();
                              final latest = await MediaAccessGrantService
                                  .instance
                                  .isIgnoringBatteryOptimizations();
                              setSheetState(() {
                                batteryOptimizationAllowed = latest;
                              });
                            },
                            child: Text(
                              batteryOptimizationAllowed ? '撤回允许' : '请求允许',
                            ),
                          ),
                        ),
                      if (Platform.isAndroid) const SizedBox(height: 6),
                      const SizedBox(height: 24),

                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () async {
                              await _backendPreferenceService
                                  .setSelectedBackend(selected);
                              final settingsToSave = aiSettings.copyWith(
                                inferenceAccelerator: selectedAccelerator,
                              );
                              await AppAiSettingsService.instance.save(
                                settingsToSave,
                              );
                              if (!context.mounted) {
                                return;
                              }
                              Navigator.pop(context);
                            },
                            child: const Text('保存'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted) {
      return;
    }
    final latest = _backendPreferenceService.backendListenable.value;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('已保存 ${latest.label} 与运行时 AI 设置'),
      ),
    );
  }

  Future<void> _requestBatteryOptimizationAccess() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('允许后台分析继续运行'),
          content: const Text('系统会弹出授权窗口。只有你明确允许后，长时间分析任务才更不容易被电池优化中断。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('请求允许'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    var granted = false;
    try {
      granted = await MediaAccessGrantService.instance
          .requestIgnoreBatteryOptimizations();
    } catch (_) {
      granted = false;
    }
    if (!mounted) {
      return;
    }
    if (granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('已允许后台分析降低电池优化限制。'),
        ),
      );
      return;
    }

    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('还没有完成授权'),
          content: const Text('如果刚才关闭了系统授权窗口，可以进入电池优化设置，手动允许本 App 不受限制。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('稍后处理'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('打开系统设置'),
            ),
          ],
        );
      },
    );
    if (openSettings == true) {
      await MediaAccessGrantService.instance.openBatteryOptimizationSettings();
    }
  }

  /// 显示缓存管理界面
  Future<void> _showCacheManagement() async {
    // 获取缓存统计信息
    final videoStats = await VideoCacheService.instance.getCacheStats();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('📁 缓存管理'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('缓存统计信息:'),
                const SizedBox(height: 12),
                _buildStatItem('视频缓存数量', '${videoStats['cacheFileCount']} 个'),
                _buildStatItem('视频缓存大小', videoStats['cacheSizeFormatted']),
                _buildStatItem('导出文件数量', '${videoStats['exportFileCount']} 个'),
                _buildStatItem('导出总大小', videoStats['exportSizeFormatted']),
                _buildStatItem('视频内存缓存', '${videoStats['memoryCacheCount']} 个'),
                const SizedBox(height: 16),
                const Text(
                  '注意:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                const Text(
                  '• 缩略图路径随相册缓存写入数据库，不在这里清理\n'
                  '• 清理缓存只会删除缓存的视频文件\n'
                  '• 清理导出文件会删除所有导出的视频\n'
                  '• 这些操作不可恢复，请谨慎操作',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _clearCacheOnly();
              },
              child: const Text('仅清理缓存'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _clearAllCacheAndExports();
              },
              child: const Text('清理全部'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  /// 仅清理缓存文件
  Future<void> _clearCacheOnly() async {
    final confirmed = await _showConfirmationDialog(
      '清理缓存',
      '确定要清理所有缓存文件吗？\n\n'
          '这将删除视频缓存，但不会清理相册缩略图。\n'
          '下次导出相同内容时需要重新生成视频缓存。',
    );

    if (!confirmed) return;

    try {
      await VideoCacheService.instance.clearAllCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 缓存已清理'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 清理失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 清理所有缓存和导出文件
  Future<void> _clearAllCacheAndExports() async {
    final confirmed = await _showConfirmationDialog(
      '清理全部',
      '确定要清理所有缓存和导出文件吗？\n\n'
          '这将删除：\n'
          '• 所有缓存的视频文件\n'
          '• 所有已导出的视频文件\n\n'
          '这个操作不可恢复！',
    );

    if (!confirmed) return;

    try {
      // 清理缓存
      await VideoCacheService.instance.clearAllCache();

      // 清理导出目录
      final exportsDir = await VideoCacheService.instance.getExportsDirectory();
      if (await exportsDir.exists()) {
        await exportsDir.delete(recursive: true);
        // 重新创建空目录
        await exportsDir.create(recursive: true);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 所有文件已清理'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ 清理失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 显示确认对话框
  Future<bool> _showConfirmationDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('确定清理'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _showTravelMemoryDebug() async {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('正在检测最近 180 天的旅行记忆...'),
      ),
    );

    try {
      final summary = await TravelMemoryService().buildDebugSummary(
        lookbackDays: 180,
      );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('旅行记忆检测'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                child: SelectableText(
                  '$summary\n\n公开截图、博客或 issue 前，请替换城市、区县、adcode 与地点名称。',
                ),
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
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('旅行记忆检测失败: $error'),
        ),
      );
    }
  }

  void _showAccountDetails() async {
    final attributes = await _loadAttributes();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '账号详情',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                if (attributes == null)
                  const Center(child: CircularProgressIndicator())
                else
                  ...attributes.map((attr) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        // 如果文字换行了，让它们顶部对齐会更好看
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getAttributeLabel(attr.userAttributeKey.key),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 16), // 给 Key 和 Value 之间留点呼吸空间
                          // 🌟 核心修复：用 Expanded 占据剩余所有空间，防止溢出
                          Expanded(
                            child: Text(
                              attr.value,
                              textAlign: TextAlign.right, // 保持靠右对齐的视觉效果
                              // 如果你不想让它换行，而是想显示省略号，可以解开下面两行的注释：
                              // overflow: TextOverflow.ellipsis,
                              // maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getAttributeLabel(String key) {
    switch (key) {
      case 'email':
        return '电子邮箱';
      case 'name':
        return '姓名';
      case 'sub':
        return 'UUID';
      case 'email_verified':
        return '邮箱已验证';
      default:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的'), elevation: 0),
      body: ListView(
        children: <Widget>[
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 50,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              Icons.person,
              size: 50,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<_ProfileIdentity>(
            future: _loadProfileIdentity(),
            builder: (context, snapshot) {
              final identity = snapshot.data;
              return Column(
                children: [
                  Text(
                    identity?.displayName ?? '未登录用户',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    identity?.isSignedIn == true ? '已登录' : '智能故事相册',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
          _buildSettingsTile(
            context,
            Icons.person_outline,
            '账号信息',
            '查看当前登录状态与详情',
            onTap: _showAccountDetails,
          ),
          _buildSettingsTile(
            context,
            Icons.tune,
            '相册 AI 模型设定',
            '切换模型及其运作形式',
            onTap: _showModelTypeSettings,
          ),
          _buildSettingsTile(
            context,
            Icons.storage_outlined,
            'AI 模型权重',
            '查看、删除或下载本地模型文件',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const AiModelWeightsPage(),
                ),
              );
            },
          ),
          _buildSettingsTile(
            context,
            Icons.folder_copy_outlined,
            '相册访问权限',
            _albumSelectionSummary,
            onTap: _showAlbumSelectionSettings,
          ),
          _buildSettingsTile(
            context,
            Icons.filter_alt_outlined,
            '扫描时间与分辨率',
            '按时间范围和最小分辨率过滤扫描（可选）',
            onTap: _showScanPreferences,
          ),
          _buildSettingsTile(
            context,
            Icons.recycling,
            '低价值照片回收站',
            '查看已标记的低质量图片，并恢复为普通照片',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const JunkPhotoTrashPage(),
                ),
              );
            },
          ),
          _buildSettingsTile(
            context,
            Icons.developer_mode,
            "开发者设置",
            "谨慎调整内部设置，除非你很清楚自己在做什么！",
            onTap: () {
              // 对比性能和提取示例向量两个功能 entry point，后续可以扩展更多开发者工具
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (context) {
                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '开发者工具',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 20),
                            ListTile(
                              leading: const Icon(Icons.analytics_outlined),
                              title: const Text('MobileCLIP Benchmark'),
                              subtitle: const Text(
                                '对比 LiteRT/NCNN 路径，标签主路径默认使用 XNNPACK',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) =>
                                        const MobileClipBenchmarkPage(),
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.science_outlined),
                              title: const Text('MobileCLIP Vector Probe'),
                              subtitle: const Text('检查示例图片在手机端 LiteRT 的向量'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) =>
                                        const MobileClipVectorProbePage(),
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.compare_arrows),
                              title: const Text('媒体向量相似度测试'),
                              subtitle: const Text('从系统文件选择图片/视频，计算向量和文本相似度'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) =>
                                        const MediaVectorSimilarityTestPage(),
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.psychology_outlined),
                              title: const Text('Local VLM Test'),
                              subtitle: const Text(
                                'SmolVLM2 FFI 图片/视频描述，不做生成任务',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) =>
                                        const LocalVlmTestPage(),
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.bug_report_outlined),
                              title: const Text('InternVL Lab'),
                              subtitle: const Text('SmolVLM2 描述实验入口'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) =>
                                        const InternvlLabPage(),
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(
                                Icons.face_retouching_natural_outlined,
                              ),
                              title: const Text('Face Cluster Debug'),
                              subtitle: const Text('观察按脸聚类结果，不影响主题主链路'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (context) =>
                                        const FaceClusterDebugPage(),
                                  ),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.travel_explore),
                              title: const Text('旅行记忆检测'),
                              subtitle: const Text('按城市停留轨迹检测最近 180 天的旅行候选'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.of(context).pop();
                                unawaited(_showTravelMemoryDebug());
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          // _buildSettingsTile(
          //   context,
          //   Icons.photo_library_outlined,
          //   '相册管理',
          //   '管理本地照片',
          // ),
          // _buildSettingsTile(
          //   context,
          //   Icons.cloud_outlined,
          //   '云端服务',
          //   '配置 LLM 服务',
          // ),
          // _buildSettingsTile(
          //   context,
          //   Icons.security_outlined,
          //   '隐私设置',
          //   '本地优先，保护隐私',
          // ),
          // _buildSettingsTile(
          //   context,
          //   Icons.science_outlined,
          //   'MobileCLIP Benchmark',
          //   '对比 ONNX 基线性能',
          //   onTap: () {
          //     Navigator.of(context).push(
          //       MaterialPageRoute<void>(
          //         builder: (context) => const MobileClipBenchmarkPage(),
          //       ),
          //     );
          //   },
          // ),
          // _buildSettingsTile(
          //   context,
          //   Icons.analytics_outlined,
          //   'MobileCLIP Vector Probe',
          //   '检查指定图片在手机端 ONNX 的向量',
          //   onTap: () {
          //     Navigator.of(context).push(
          //       MaterialPageRoute<void>(
          //         builder: (context) => const MobileClipVectorProbePage(),
          //       ),
          //     );
          //   },
          // ),
          _buildSettingsTile(
            context,
            Icons.storage,
            '缓存管理',
            '清理缩略图、视频缓存和导出文件',
            onTap: _showCacheManagement,
          ),
          _buildSettingsTile(context, Icons.info_outline, '关于', '版本 1.0.0'),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              '退出登录',
              style: TextStyle(color: Colors.redAccent),
            ),
            subtitle: const Text('从当前设备登出账号'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _signOut,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle, {
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
