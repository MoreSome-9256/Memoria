/// 个人资料页面，提供设置、调试入口和账户信息展示。

import 'dart:async';
import 'dart:io';

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:photo_album/service/cognito_auth_service.dart';
import 'package:photo_album/service/app_ai_settings_service.dart';
import 'package:photo_album/service/media_access_grant_service.dart';
import 'package:photo_album/service/mobileclip_backend_preference_service.dart';
import 'package:photo_album/service/litert_inference_service.dart';
import 'package:photo_album/service/travel_memory_detector.dart';
import 'package:photo_album/view/pages/welcome_page.dart';

import 'package:photo_album/service/album_selection_preference_service.dart';

import 'face_cluster_debug_page.dart';
import 'junk_photo_trash_page.dart';
import 'mobileclip_benchmark_page.dart';
import 'mobileclip_vector_probe_page.dart';
import '../../service/video_cache_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
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
    int? selectedYear = prefs['minYear'];
    List<int>? selectedPair =
        prefs['minWidth'] != null && prefs['minHeight'] != null
        ? [prefs['minWidth']!, prefs['minHeight']!]
        : null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                    const Text('可选：按时间范围和最小分辨率过滤。默认不开启。'),
                    const SizedBox(height: 12),
                    Text(
                      '最早年份（含）',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<int?>(
                      value: selectedYear,
                      items: <int?>[null, 2000, 2010, 2015, 2020, 2022]
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
                    DropdownButton<List<int>?>(
                      value: selectedPair,
                      items:
                          <List<int>?>[
                                null,
                                [640, 480],
                                [1280, 720],
                                [1920, 1080],
                              ]
                              .map((pair) {
                                final label = pair == null
                                    ? '不限制'
                                    : '${pair[0]} x ${pair[1]}';
                                return DropdownMenuItem<List<int>?>(
                                  value: pair,
                                  child: Text(label),
                                );
                              })
                              .toList(growable: false),
                      onChanged: (pair) => setSheetState(() {
                        selectedPair = pair;
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
                            await _albumSelectionPreferenceService
                                .saveScanPreferences(
                                  minYear: selectedYear,
                                  minWidth: selectedPair?.first,
                                  minHeight: selectedPair?.last,
                                );
                            if (!mounted) return;
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
    final snapshot = await MediaAccessGrantService.instance.loadSnapshot();
    if (!mounted) {
      return;
    }
    setState(() {
      if (!snapshot.hasAnyGrant) {
        _albumSelectionSummary = '未授权任何媒体';
      } else {
        final mediaCount =
            snapshot.selectedAssetIds.length +
            snapshot.selectedFilePaths.length;
        _albumSelectionSummary =
            '已选择 $mediaCount 个媒体，${snapshot.androidTreeUris.length} 个目录';
      }
    });
  }

  Future<void> _showAlbumSelectionSettings() async {
    var snapshot = await MediaAccessGrantService.instance.loadSnapshot();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '授权媒体来源',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    const Text('默认不访问系统相册。只有你在系统界面选择的照片、视频或目录会进入扫描队列。'),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.add_photo_alternate_outlined),
                      title: const Text('选择照片/视频'),
                      subtitle: Text(
                        '已授权 ${snapshot.selectedAssetIds.length + snapshot.selectedFilePaths.length} 个媒体',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final result = await MediaAccessGrantService.instance
                            .pickMedia();
                        snapshot = await MediaAccessGrantService.instance
                            .loadSnapshot();
                        setSheetState(() {});
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            behavior: SnackBarBehavior.floating,
                            content: Text(
                              '新增 ${result.addedAssetIds} 个媒体，当前共 ${result.totalSelectedAssetIds} 个',
                            ),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('重新管理部分照片访问'),
                      subtitle: const Text('调用系统受限相册管理界面'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await MediaAccessGrantService.instance
                            .presentLimitedLibraryPicker();
                        snapshot = await MediaAccessGrantService.instance
                            .loadSnapshot();
                        setSheetState(() {});
                      },
                    ),
                    if (Platform.isAndroid)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.create_new_folder_outlined),
                        title: const Text('添加授权文件夹'),
                        subtitle: Text(
                          '已授权 ${snapshot.androidTreeUris.length} 个目录',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await MediaAccessGrantService.instance
                              .requestAndroidDirectoryGrant();
                          snapshot = await MediaAccessGrantService.instance
                              .loadSnapshot();
                          setSheetState(() {});
                        },
                      ),
                    if (snapshot.androidTreeUris.isNotEmpty)
                      const Divider(height: 24),
                    for (final uri in snapshot.androidTreeUris)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.folder_open_outlined),
                        title: Text(
                          uri,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await MediaAccessGrantService.instance
                                .removeAndroidDirectoryGrant(uri);
                            snapshot = await MediaAccessGrantService.instance
                                .loadSnapshot();
                            setSheetState(() {});
                          },
                        ),
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
            );
          },
        );
      },
    );

    await _refreshAlbumSelectionSummary();
  }

  Future<void> _showModelTypeSettings() async {
    await _backendPreferenceService.initialize();
    var aiSettings = await AppAiSettingsService.instance.load();
    final iosContinuedProcessingSupported =
        !Platform.isIOS || _iosMajorVersion() >= 26;
    if (Platform.isIOS && !iosContinuedProcessingSupported) {
      aiSettings = aiSettings.copyWith(iosContinuedProcessingEnabled: false);
    }
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
                        segments:
                            const <ButtonSegment<LocalInferenceAccelerator>>[
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
                            ],
                        selected: <LocalInferenceAccelerator>{
                          aiSettings.inferenceAccelerator,
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
                        '${aiSettings.inferenceAccelerator.label} · ${aiSettings.inferenceAccelerator.description}',
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
                        title: const Text('本地 VLM 生成描述'),
                        subtitle: const Text('用于优先生成照片/视频描述和视频脚本文案'),
                        value: aiSettings.localVlmDescriptionEnabled,
                        onChanged: (value) {
                          setSheetState(() {
                            aiSettings = aiSettings.copyWith(
                              localVlmDescriptionEnabled: value,
                            );
                          });
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('后台常驻分析服务'),
                        subtitle: Text(
                          Platform.isIOS
                              ? '仅 iOS 26+ 支持，不支持时无法开启'
                              : '仅在你允许后以前台服务处理手动添加的任务',
                        ),
                        value: Platform.isIOS
                            ? aiSettings.iosContinuedProcessingEnabled
                            : aiSettings.androidForegroundServiceEnabled,
                        onChanged:
                            Platform.isIOS && !iosContinuedProcessingSupported
                            ? null
                            : (value) {
                                setSheetState(() {
                                  aiSettings = Platform.isIOS
                                      ? aiSettings.copyWith(
                                          iosContinuedProcessingEnabled: value,
                                        )
                                      : aiSettings.copyWith(
                                          androidForegroundServiceEnabled:
                                              value,
                                        );
                                });
                              },
                      ),
                      if (Platform.isAndroid)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('请求取消电池优化限制'),
                          subtitle: const Text('开启后会引导到系统设置，由用户明确授权'),
                          value: aiSettings.requestUnrestrictedBatteryEnabled,
                          onChanged: (value) {
                            setSheetState(() {
                              aiSettings = aiSettings.copyWith(
                                requestUnrestrictedBatteryEnabled: value,
                              );
                            });
                          },
                        ),
                      const SizedBox(height: 6),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.info_outline),
                        title: const Text('后台运行提醒（Android）'),
                        subtitle: const Text(
                          '如需提高后台继续处理成功率，请不要在最近任务中划掉本应用；建议在系统任务管理里给本应用加锁。',
                        ),
                      ),
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
                              await AppAiSettingsService.instance.save(
                                aiSettings,
                              );
                              if (aiSettings
                                  .requestUnrestrictedBatteryEnabled) {
                                await MediaAccessGrantService.instance
                                    .requestBatteryOptimizationSettings();
                              }
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

  /// 显示缓存管理界面
  Future<void> _showCacheManagement() async {
    // 获取缓存统计信息
    final cacheStats = await VideoCacheService.instance.getCacheStats();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('📁 视频缓存管理'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('缓存统计信息:'),
                const SizedBox(height: 12),
                _buildStatItem('缓存文件数量', '${cacheStats['cacheFileCount']} 个'),
                _buildStatItem('缓存总大小', cacheStats['cacheSizeFormatted']),
                _buildStatItem('导出文件数量', '${cacheStats['exportFileCount']} 个'),
                _buildStatItem('导出总大小', cacheStats['exportSizeFormatted']),
                _buildStatItem('内存缓存数量', '${cacheStats['memoryCacheCount']} 个'),
                const SizedBox(height: 16),
                const Text(
                  '注意:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                const Text(
                  '• 清理缓存会删除所有缓存的视频文件\n'
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
          '这将删除所有缓存的视频文件，但不会影响已导出的视频。\n'
          '下次导出相同内容时需要重新生成视频。',
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
          FutureBuilder<AuthUser?>(
            future: _loadUser(),
            builder: (context, snapshot) {
              final user = snapshot.data;
              return Column(
                children: [
                  Text(
                    user?.username ?? '未登录用户',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    user == null ? '智能故事相册' : '已登录',
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
            Icons.folder_copy_outlined,
            '授权媒体来源',
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
                            if (Platform.isAndroid) ...[
                              ListTile(
                                leading: const Icon(Icons.analytics_outlined),
                                title: const Text('MobileCLIP Benchmark'),
                                subtitle: const Text(
                                  '对比 LiteRT 在 GPU、NPU 与 XNNPACK 上的速度',
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
                            ],
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
            '视频缓存管理',
            '清理导出的视频和缓存文件',
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

  int _iosMajorVersion() {
    final match = RegExp(r'(\d+)').firstMatch(Platform.operatingSystemVersion);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
}
