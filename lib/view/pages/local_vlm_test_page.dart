import 'package:flutter/material.dart';

import 'smol_vlm_description_page.dart';

class LocalVlmTestPage extends StatelessWidget {
  const LocalVlmTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SmolVlmDescriptionPage(
      title: 'Local VLM Test',
      subtitle: '使用 Flutter FFI llama.cpp 包加载 SmolVLM2，只做图片、视频和动态照片的描述性文本输出。',
    );
  }
}
