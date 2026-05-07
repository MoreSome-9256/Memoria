import 'dart:async';

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:photo_album/service/cognito_auth_service.dart';
import 'package:photo_album/service/mobileclip_backend_preference_service.dart';
import 'package:photo_album/service/ai_service.dart';
import 'package:photo_album/service/travel_memory_detector.dart';
import 'package:photo_album/view/pages/welcome_page.dart';

import 'face_cluster_debug_page.dart';
import 'mobileclip_benchmark_page.dart';
import 'mobileclip_vector_probe_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _auth = const CognitoAuthService();
  final _backendPreferenceService = MobileClipBackendPreferenceService();

  late bool _autoResumeEnabled;

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

  Future<void> _showModelTypeSettings() async {
    await _backendPreferenceService.initialize();
    _autoResumeEnabled = await AIService().getAutoResumePreference();
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
                            value: MobileClipBackend.mobileclip2Onnx,
                            label: Text('MobileCLIP2 ONNX'),
                            icon: Icon(Icons.auto_awesome_outlined),
                          ),
                          ButtonSegment<MobileClipBackend>(
                            value: MobileClipBackend.ncnn,
                            label: Text('NCNN'),
                            icon: Icon(Icons.flash_on_outlined),
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

                      // 自动恢复开关
                      Divider(color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        '启动行为',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启动时自动恢复'),
                        subtitle: const Text('应用启动时自动继续未完成的 AI 打标任务'),
                        value: _autoResumeEnabled,
                        onChanged: (value) {
                          setSheetState(() {
                            _autoResumeEnabled = value;
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
                              await AIService().setAutoResume(
                                _autoResumeEnabled,
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
        content: Text(
          '已设置模型类型为 ${latest.label}，自动恢复 ${_autoResumeEnabled ? '已启用' : '已禁用'}',
        ),
      ),
    );
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
                                '对比 ONNX 在 CPU 与 NNAPI hardware 上的速度',
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
                              subtitle: const Text(
                                '检查示例图片在手机端 ONNX / NCNN 的向量',
                              ),
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
          //   '对比 ONNX 基线与未来 ncnn 接入',
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
          //   '检查指定图片在手机端 ONNX / NCNN 的向量',
          //   onTap: () {
          //     Navigator.of(context).push(
          //       MaterialPageRoute<void>(
          //         builder: (context) => const MobileClipVectorProbePage(),
          //       ),
          //     );
          //   },
          // ),
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
