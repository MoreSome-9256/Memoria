import 'package:flutter/material.dart';

import 'smol_vlm_description_page.dart';

class InternvlLabPage extends StatelessWidget {
  const InternvlLabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SmolVlmDescriptionPage(
      title: 'InternVL Lab',
      subtitle: '当前实验入口已切换到 SmolVLM2 FFI 描述模式；不再走 Qwen/InternVL 服务，也不做故事或生成任务。',
    );
  }
}
