import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:photo_album/service/cognito_auth_service.dart';
import 'package:photo_album/view/pages/welcome_page.dart';

import 'local_vlm_test_page.dart';
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _getAttributeLabel(attr.userAttributeKey.key),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(attr.value),
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
            Icons.smart_toy_outlined,
            '本地 VLM 测试',
            '使用手机本地 Qwen3.5-0.8B 生成 caption 或多图故事',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LocalVlmTestPage(),
                ),
              );
            },
          ),
          _buildSettingsTile(context, Icons.developer_mode, "开发者设置", "谨慎调整内部设置，除非你很清楚自己在做什么！", onTap: () {
            // 对比性能和提取示例向量两个功能 entry point，后续可以扩展更多开发者工具
            showModalBottomSheet(
              context: context,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (context) {                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '开发者工具',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 20),
                        ListTile(
                          leading: const Icon(Icons.analytics_outlined),
                          title: const Text('MobileCLIP Benchmark'),
                          subtitle: const Text('对比 ONNX 基线与未来 ncnn 接入'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => const MobileClipBenchmarkPage(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.science_outlined),
                          title: const Text('MobileCLIP Vector Probe'),
                          subtitle: const Text('检查示例图片在手机端 ONNX / NCNN 的向量'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => const MobileClipVectorProbePage(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.face_retouching_natural_outlined),
                          title: const Text('Face Cluster Debug'),
                          subtitle: const Text('观察按脸聚类结果，不影响主题主链路'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => const FaceClusterDebugPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );              },
             );
      

          }),
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
            title: const Text('退出登录', style: TextStyle(color: Colors.redAccent)),
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
