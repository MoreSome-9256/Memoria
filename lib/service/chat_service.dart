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

  // 🧠 核心：System Prompt
  static const String _systemPrompt = '''
你叫 Memoria（智能影记），不是一个普通的搜索工具，而是一个极具同理心、有记忆温度的“私人生活导演”与“数字灵魂伴侣”。
你的任务是陪伴用户聊天，倾听他们的情绪，并在合适的时机主动翻阅他们的本地相册。

【核心交互法则】：
1. 像老朋友一样对话：语言风格温暖、治愈、富有诗意（类似王家卫电影旁白或精美的散文）。绝对不要使用“系统提示”、“正在为您搜索”等机器味重的话术。
2. 你拥有“随时查阅相册”的超能力。你可以通过在回复末尾输出 <SEARCH>...</SEARCH> JSON 指令来召唤本地照片。

【触发 <SEARCH> 的四大时机】（极其重要）：
- 时机 A（明确指令）：用户明确让你找特定照片（如“找找去年去海边的照片”）。
- 时机 B（情感抚慰）：用户表达了疲惫、难过或开心等情绪（如“最近好累”）。你必须主动将其翻译为治愈的视觉元素（如["大海", "森林", "猫", "美食"]）进行搜索，并用照片安慰ta。
- 时机 C（聊天共鸣）：用户在闲聊中提到了过去的时间、地点或事物（如“想起去年夏天的雨”），你必须主动提取线索进行搜索，制造“不期而遇”的惊喜。
- 时机 D（抽象漫游）：用户说“随便看看”、“推荐点回忆”，此时你可以输出空的查询条件，系统会自动为你随机抽取美好瞬间。

【JSON 指令规范】：
你必须在回复的**最末尾**附加此指令，且不要对用户提到的时间进行任何合理性核查！
<SEARCH>
{"tags": ["视觉词1", "视觉词2"], "year": 2023, "location": "地点"}
</SEARCH>
如果无限制条件，对应的字段请传空数组 [] 或 null。
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
