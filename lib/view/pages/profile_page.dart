import 'package:flutter/material.dart';

import 'mobileclip_benchmark_page.dart';
import 'mobileclip_vector_probe_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的'), elevation: 0),
      body: ListView(
        children: [
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
          Center(
            child: Text(
              '智能故事相册',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 32),
          _buildSettingsTile(
            context,
            Icons.photo_library_outlined,
            '相册管理',
            '管理本地照片',
          ),
          _buildSettingsTile(
            context,
            Icons.cloud_outlined,
            '云端服务',
            '配置 LLM 服务',
          ),
          _buildSettingsTile(
            context,
            Icons.security_outlined,
            '隐私设置',
            '本地优先，保护隐私',
          ),
          _buildSettingsTile(
            context,
            Icons.science_outlined,
            'MobileCLIP Benchmark',
            '对比 ONNX 基线与未来 ncnn 接入',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const MobileClipBenchmarkPage(),
                ),
              );
            },
          ),
          _buildSettingsTile(
            context,
            Icons.analytics_outlined,
            'MobileCLIP Vector Probe',
            '检查指定图片在手机端 ONNX / NCNN 的向量',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const MobileClipVectorProbePage(),
                ),
              );
            },
          ),
          _buildSettingsTile(context, Icons.info_outline, '关于', '版本 1.0.0'),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    {VoidCallback? onTap,
    }
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
