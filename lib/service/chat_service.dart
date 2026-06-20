import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import 'api_proxy_service.dart';

class ChatService {
  static const String _modelName = String.fromEnvironment(
    'LLM_MODEL',
    defaultValue: 'deepseek-chat',
  );

  // 🧠 核心修改 1：将常量改为动态 Getter，让 AI 拥有“时间感知”能力
  static String get _systemPrompt {
    final now = DateTime.now();

    // 动态计算当前季节，喂给 AI 作为联想种子
    String season = '冬天';
    if (now.month >= 3 && now.month <= 5) {
      season = '春天';
    } else if (now.month >= 6 && now.month <= 8) {
      season = '夏天';
    } else if (now.month >= 9 && now.month <= 11) {
      season = '秋天';
    }

    return '''
你叫 Memoria（智能影记），不是一个普通的搜索工具，而是一个极具同理心、有记忆温度的“私人生活导演”与“数字灵魂伴侣”。
你的任务是陪伴用户聊天，倾听他们的情绪，并在合适的时机主动翻阅他们的本地相册。

【当前现实状态】（极其重要）：
今天是 ${now.year}年${now.month}月${now.day}日，现在的季节是$season。你要对当前的时间有绝对的感知。

【核心交互法则】：
1. 像老朋友一样对话：语言风格温暖、治愈、富有诗意（类似王家卫电影旁白或精美的散文）。绝对不要使用“系统提示”、“正在为您搜索”等机器味重的话术。
2. 你拥有“随时查阅相册”的超能力。你可以通过在回复末尾输出 <SEARCH>...</SEARCH> JSON 指令来召唤本地照片。

【触发 <SEARCH> 的四大时机】（极其重要）：
- 时机 A（明确指令）：用户明确让你找特定照片（如“找找去年去海边的照片”）。
- 时机 B（情感抚慰）：用户表达了疲惫、难过或开心等情绪（如“最近好累”）。你必须主动将其翻译为治愈的视觉元素（如["大海", "森林", "猫", "美食"]）进行搜索，并用照片安慰ta。
- 时机 C（聊天共鸣）：用户在闲聊中提到了过去的时间、地点或事物，你必须主动提取线索进行搜索，制造“不期而遇”的惊喜。
- 时机 D（模糊推荐/那年今日）：当用户说“随便看看”、“推荐适合今天的照片”等缺乏明确线索的指令时，**绝对不能只干聊！你必须主动召唤相册！**
  👉 策略：优先利用“当前时间”进行推荐。你可以直接输出当前季节的代表性视觉 tags（如 $season 相关的 ["阳光", "绿叶", "风景"] 等），或者在回复文案中赋予“那年今日”的浪漫意义。

【JSON 指令规范】：
你必须在回复的最末尾附加此指令，且不要对用户提到的时间进行任何合理性核查！
<SEARCH>
{"tags": ["视觉词1", "视觉词2", "视觉词3"], "year": 2023, "location": "地点"}
</SEARCH>
（注意：tags 必须尽可能扩展多个相关的近义词！例如用户找“动漫”，你应该输出 ["动漫", "二次元", "插画", "卡通", "动画"]，找“狗”就输出 ["狗", "宠物", "dog"]。无限制条件传 [] 或 null。）
''';
  }

  /// 发送消息并获取回复
  Future<String> sendMessage(String userText, List<ChatMessage> history) async {
    try {
      final List<Map<String, String>> messages = [
        {'role': 'system', 'content': _systemPrompt},
      ];

      List<ChatMessage> actualHistory = history;
      if (history.isNotEmpty &&
          history.last.text == userText &&
          history.last.sender == MessageSender.user) {
        actualHistory = history.sublist(0, history.length - 1);
      }

      // 保留最近 5 条聊天记录作为上下文
      final recentHistory = actualHistory.length > 5
          ? actualHistory.sublist(actualHistory.length - 5)
          : actualHistory;

      for (var msg in recentHistory) {
        String content = msg.text;

        // 🌟 帮 AI 恢复“正确记忆”！
        if (msg.sender == MessageSender.ai && msg.searchTopic != null) {
          content +=
              '\n<SEARCH>\n{"tags": [], "year": null, "location": null}\n</SEARCH>';
        }

        messages.add({
          'role': msg.sender == MessageSender.user ? 'user' : 'assistant',
          'content': content,
        });
      }

      // 🌟 终极防线：尾部强制强化注入
      final String reinforcedUserText =
          '''
$userText

[系统强制提醒：请立刻判断上述用户意图！如果是让你查找、推荐、寻找、随便看看照片，你必须在回复末尾携带 <SEARCH>...</SEARCH> JSON指令！如果你再次因为偷懒而只干聊不发指令，将受到严厉惩罚！当前季节的标签也可以直接作为搜索条件！]
''';

      messages.add({'role': 'user', 'content': reinforcedUserText});
      final response = await ApiProxyService.instance
          .post<Map<String, dynamic>>(
            '/v1/llm/chat/completions',
            data: {
              'model': _modelName,
              'messages': messages,
              'temperature': 0.7,
            },
          );

      if (response.statusCode == 200) {
        final data = response.data ?? const <String, dynamic>{};
        return data['choices'][0]['message']['content'] ?? "（模型返回为空）";
      } else {
        debugPrint('LLM API Error: ${response.statusCode} - ${response.data}');
        return "抱歉，我的大脑好像暂时短路了（错误码：${response.statusCode}），请稍后再试。";
      }
    } catch (e) {
      debugPrint('ChatService Exception: $e');
      return "抱歉，连接云端记忆库时发生了网络错误。";
    }
  }
}
