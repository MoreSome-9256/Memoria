import 'package:flutter/material.dart';

import 'mobileclip_benchmark_page.dart';
import 'mobileclip_vector_probe_page.dart';

import 'mobileclip_benchmark_page.dart';
import 'mobileclip_vector_probe_page.dart';

import 'internvl_lab_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _showInternvlLab = false;

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
          CheckboxListTile(
            value: _showInternvlLab,
            title: const Text('显示 VLM 推理入口'),
            subtitle: const Text('仅用于手机本地多模态推理，避免与正式功能冲突'),
            controlAffinity: ListTileControlAffinity.trailing,
            onChanged: (bool? value) {
              setState(() {
                _showInternvlLab = value ?? false;
              });
            },
          ),
          if (_showInternvlLab)
            _buildSettingsTile(
              context,
              Icons.memory_outlined,
              'VLM 推理',
              '选择图片并自由提问，直接在手机上完成多模态推理',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => const InternvlLabPage(),
                  ),
                );
              },
            ),
          _buildSettingsTile(
            context,
            Icons.info_outline,
            '关于',
            '版本 1.0.0',
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
    {VoidCallback? onTap,
    }
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
