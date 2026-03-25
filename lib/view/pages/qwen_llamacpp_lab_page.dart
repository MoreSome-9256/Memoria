import 'package:flutter/material.dart';

import 'local_vlm_test_page.dart';

/// 兼容旧实验入口语义，统一到 Qwen3.5-0.8B 本地推理页面。
class QwenLlamacppLabPage extends StatelessWidget {
  const QwenLlamacppLabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LocalVlmTestPage();
  }
}
