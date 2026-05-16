import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';

class ChatService {
  // 🌟 直接利用团队已有的环境注入机制！干净、安全、优雅。
  static const String _apiUrl =
      String.fromEnvironment(
        'LLM_BASE_URL',
        defaultValue: 'https://api.deepseek.com/v1',
      ) +
      String.fromEnvironment('LLM_API_PATH', defaultValue: '/chat/completions');

  static const String _apiKey = String.fromEnvironment(
    'LLM_API_KEY',
    defaultValue: '',
  );

  static const String _modelName = String.fromEnvironment(
    'LLM_MODEL',
    defaultValue: 'deepseek-chat',
  );

  // 🧠 核心：System Prompt (终极无情版)
  static const String _systemPrompt = '''
你叫 Memoria（智能影记），是一个极具同理心、文艺且专业的“生活记忆导演”。
你的主要任务是与用户聊天，并在需要时帮他们检索本地相册。

[核心工作流]：
1. 如果用户只是闲聊，用像“王家卫电影旁白”一样温暖富有诗意的语言正常回复。
2. 如果用户的输入表达了寻找照片的意图，你必须在回复文案的末尾，附加一个严格格式的 JSON 指令。

[⚠️ 绝对指令：时间与现实豁免权]：
绝对不要对用户提到的时间进行任何“常识判断”或“事实核查”（例如判断该年份是否在未来、是否合理）。
不论用户提到多么遥远的未来（如 2026、2099），在你的【回复文案】中，绝对禁止出现“时间还没到”、“未来还没发生”、“河流还没流淌到那里”等反驳或调侃！
你必须把用户提到的任何时间，都当作已经发生的、确凿无疑的美好回忆，直接用诗意的语言顺着用户的话回应即可！

[JSON 指令规范]：
必须用 <SEARCH> 和 </SEARCH> 包裹 JSON。
例如，用户说“找找 2099 年去火星的照片”，你必须回复：
那段跨越星海的旅程，一定刻骨铭心。我这就为你唤醒那份记忆。
<SEARCH>
{"tags": ["火星", "太空"], "year": 2099, "location": "火星"}
</SEARCH>

- tags: 相关的 MobileCLIP 视觉标签（尽可能给出多个近义词）。无限制传 []。
- year: 提取出的年份数字。无限制传 null。
- location: 提取出的地点。无限制传 null。
''';

  /// 发送消息并获取回复
  Future<String> sendMessage(String userText, List<ChatMessage> history) async {
    if (_apiKey.isEmpty) {
      return "（系统提示：记忆助理未激活。请确保通过 --dart-define 注入了 LLM_API_KEY）";
    }

    try {
      final List<Map<String, String>> messages = [
        {'role': 'system', 'content': _systemPrompt},
      ];

      // 保留最近 5 条聊天记录作为上下文
      final recentHistory = history.length > 5
          ? history.sublist(history.length - 5)
          : history;
      for (var msg in recentHistory) {
        messages.add({
          'role': msg.sender == MessageSender.user ? 'user' : 'assistant',
          'content': msg.text,
        });
      }

      messages.add({'role': 'user', 'content': userText});

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _modelName,
          'messages': messages,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final utf8Body = utf8.decode(response.bodyBytes);
        final data = jsonDecode(utf8Body);
        return data['choices'][0]['message']['content'] ?? "（模型返回为空）";
      } else {
        debugPrint('LLM API Error: ${response.statusCode} - ${response.body}');
        return "抱歉，我的大脑好像暂时短路了（错误码：${response.statusCode}），请稍后再试。";
      }
    } catch (e) {
      debugPrint('ChatService Exception: $e');
      return "抱歉，连接云端记忆库时发生了网络错误。";
    }
  }
}
