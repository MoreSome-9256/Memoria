import 'package:dio/dio.dart';
import '../models/entity/event_entity.dart';

/// LLM 服务 - 通过 OpenAI 兼容第三方中转站生成内容
class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal({
    String? apiKey,
    String? baseUrl,
    String? apiPath,
    String? modelName,
    Dio? dio,
  }) : _apiKey = apiKey ?? _defaultApiKey,
       _baseUrl = baseUrl ?? _defaultBaseUrl,
       _apiPath = apiPath ?? _defaultApiPath,
       _modelName = modelName ?? _defaultModelName,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 60),
               sendTimeout: const Duration(seconds: 20),
               contentType: 'application/json',
             ),
           );

  factory LLMService.forTest({
    required String apiKey,
    required String baseUrl,
    String apiPath = '/chat/completions',
    String modelName = 'deepseek-ai/DeepSeek-V3.2',
    Dio? dio,
  }) {
    return LLMService._internal(
      apiKey: apiKey,
      baseUrl: baseUrl,
      apiPath: apiPath,
      modelName: modelName,
      dio: dio,
    );
  }

  // 通过 --dart-define 配置，避免硬编码凭证
  static const String _defaultApiKey = String.fromEnvironment(
    'LLM_API_KEY',
    defaultValue: '',
  );
  static const String _defaultBaseUrl = String.fromEnvironment(
    'LLM_BASE_URL',
    defaultValue: 'https://api-inference.modelscope.cn/v1',
  );
  static const String _defaultApiPath = String.fromEnvironment(
    'LLM_API_PATH',
    defaultValue: '/chat/completions',
  );
  static const String _defaultModelName = String.fromEnvironment(
    'LLM_MODEL',
    defaultValue: 'deepseek-ai/DeepSeek-V3.2',
  );

  final String _apiKey;
  final String _baseUrl;
  final String _apiPath;
  final String _modelName;
  final Dio _dio;

  /// 🎨 核心方法：生成创意标题
  ///
  /// 参数:
  /// - [event]: 事件实体
  /// - [topTags]: 高频标签列表（前5个）
  ///
  /// 返回: 3-5 个博客风格的创意标题列表
  Future<List<String>> generateCreativeTitles(
    EventEntity event,
    List<String> topTags,
  ) async {
    try {
      // 1. 构造 Prompt
      final prompt = _buildPrompt(event, topTags);

      // 2. 调用第三方中转站（OpenAI 兼容）
      final text = await _chatCompletion(prompt);

      // 3. 解析返回结果
      if (text == null || text.isEmpty) {
        print("⚠️ LLM 返回为空，使用兜底逻辑");
        return _getFallbackTitles(event);
      }

      // 4. 清洗文本（去除引号、编号等）
      final titles = _parseResponse(text);

      if (titles.isEmpty) {
        print("⚠️ LLM 解析失败，使用兜底逻辑");
        return _getFallbackTitles(event);
      }

      print("✅ LLM 成功生成 ${titles.length} 个标题");
      return titles;
    } catch (e) {
      print("❌ LLM 调用失败: $e");
      // 网络错误或 API 错误，返回兜底标题
      return _getFallbackTitles(event);
    }
  }

  /// 📝 构造 Prompt
  String _buildPrompt(EventEntity event, List<String> topTags) {
    final date = DateTime.fromMillisecondsSinceEpoch(event.startTime);
    final dateStr =
        '${date.year}年${date.month}月${date.day}日 - ${DateTime.fromMillisecondsSinceEpoch(event.endTime).month}月${DateTime.fromMillisecondsSinceEpoch(event.endTime).day}日';

    final location = event.city ?? event.province ?? '未知地点';
    final season = event.season;
    final tagsStr = topTags.isNotEmpty ? topTags.join(', ') : '无';
    final joyScore = event.joyScore != null
        ? event.joyScore!.toStringAsFixed(2)
        : '未知';

    return '''
你是一个专业的摄影相册文案策划师。请为以下照片事件生成 3 到 5 个简短、富有创意、博客风格的中文标题。

事件信息：
- 时间: $dateStr
- 地点: $location
- 季节: $season
- 主要标签: $tagsStr
- 平均欢乐值: $joyScore (范围 0.0-1.0，越高越快乐)

要求：
1. 标题简洁有力（8-15 个字）
2. 富有情感和画面感
3. 不要使用引号包裹标题
4. 每个标题独占一行
5. 不要添加编号（如 1.、2. 等）
6. 结合地点和标签生成创意标题
7. 可以使用一些诗意或文艺的表达

示例风格：
- 青岛 · 海风与微笑
- 舌尖上的成都
- 夏日海边的慢时光
- 猫咪日记 · 治愈时刻

请生成标题：
''';
  }

  /// 🔍 解析 LLM 返回的文本
  List<String> _parseResponse(String text) {
    // 按行分割
    final lines = text.split('\n');

    // 清洗每一行
    final titles = <String>[];
    for (final line in lines) {
      var cleaned = line.trim();

      // 跳过空行
      if (cleaned.isEmpty) continue;

      // 移除编号（1. 2. 一、二、等）
      cleaned = cleaned.replaceFirst(RegExp(r'^[\d]+\.?\s+'), '');
      cleaned = cleaned.replaceFirst(RegExp(r'^[一二三四五六七八九十]+[、.\s]+'), '');

      // 移除前后引号
      if (cleaned.startsWith('"') || cleaned.startsWith("'")) {
        cleaned = cleaned.substring(1);
      }
      if (cleaned.endsWith('"') || cleaned.endsWith("'")) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
      }

      // 移除多余空格
      cleaned = cleaned.trim();

      // 跳过过长或过短的标题
      if (cleaned.length < 3 || cleaned.length > 30) continue;

      titles.add(cleaned);
    }

    // 限制返回数量（3-5 个）
    return titles.take(5).toList();
  }

  /// 🛡️ 兜底标题生成（当 LLM 失败时）
  List<String> _getFallbackTitles(EventEntity event) {
    final location = event.city ?? event.province ?? '未知地点';
    final dateRange = event.dateRangeText;

    return ['$location · $dateRange', '$location 的记忆', '时光印记 · $location'];
  }

  /// 🧪 测试方法：模拟 LLM 调用（用于开发测试，无需真实 API Key）
  Future<List<String>> generateCreativeTitlesMock(
    EventEntity event,
    List<String> topTags,
  ) async {
    // 模拟网络延迟
    await Future.delayed(const Duration(seconds: 1));

    final location = event.city ?? event.province ?? '未知地点';

    // 根据标签生成模拟标题
    if (topTags.contains('美食')) {
      return [
        '$location · 舌尖上的记忆',
        '美食之旅 · $location',
        '寻味 $location',
        '美食地图 · $location',
      ];
    } else if (topTags.contains('海滩') || topTags.contains('大海')) {
      return ['$location · 海风与阳光', '夏日海边的慢时光', '蓝色记忆 · $location', '海的呼唤'];
    } else if (topTags.contains('猫') || topTags.contains('狗')) {
      return ['毛孩子的快乐时光', '萌宠日记 · $location', '治愈时刻', '毛茸茸的陪伴'];
    } else {
      return [
        '$location · ${event.dateRangeText}',
        '$location 的故事',
        '时光印记',
        '美好瞬间 · $location',
      ];
    }
  }

  /// 📊 检查 API Key 是否已配置
  bool get isApiKeyConfigured =>
      _apiKey.trim().isNotEmpty && _baseUrl.trim().isNotEmpty;

  /// 📝 生成博客文本内容
  ///
  /// 参数:
  /// - [prompt]: 完整的博客生成 Prompt
  ///
  /// 返回: 生成的 Markdown 格式博客正文
  Future<String?> generateBlogText(String prompt) async {
    try {
      final text = await _chatCompletion(prompt);
      if (text == null || text.isEmpty) {
        print("⚠️ LLM 返回为空");
        return null;
      }

      print("✅ LLM 成功生成博客内容");
      return text.trim();
    } catch (e) {
      print("❌ LLM 博客生成失败: $e");
      return null;
    }
  }

  Future<String?> _chatCompletion(String prompt) async {
    final baseUrl = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final apiPath = _apiPath.startsWith('/') ? _apiPath : '/$_apiPath';
    final isChatCompletions = apiPath.contains('/chat/completions');
    final requestBody = _buildRequestBody(
      prompt: prompt,
      useChatCompletions: isChatCompletions,
    );

    // print('🌐 [LLM REQUEST] POST $baseUrl$apiPath');
    // print('🧾 [LLM REQUEST BODY] ${jsonEncode(requestBody)}');

    final response = await _dio.post(
      '$baseUrl$apiPath',
      options: Options(headers: {'Authorization': 'Bearer $_apiKey'}),
      data: requestBody,
    );

    final data = response.data;
    print('📥 [LLM RESPONSE STATUS] ${response.statusCode}');
    // print('📦 [LLM RESPONSE BODY] ${jsonEncode(data)}');
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final outputText = _extractResponseText(data);
    if (outputText != null && outputText.isNotEmpty) {
      return outputText;
    }

    // 兼容部分中转站仍走 chat/completions 返回格式
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      return null;
    }

    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }

    final message = first['message'];
    if (message is! Map<String, dynamic>) {
      return null;
    }

    final content = message['content'];
    if (content is String) {
      return content;
    }

    // 兼容部分中转站返回 content 为数组块
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is Map<String, dynamic> && item['text'] is String) {
          buffer.write(item['text'] as String);
        }
      }
      return buffer.toString();
    }

    return null;
  }

  Map<String, dynamic> _buildRequestBody({
    required String prompt,
    required bool useChatCompletions,
  }) {
    const systemText = '你是一个中文摄影故事与标题助手。只能基于输入信息生成，不要编造未提供事实。';

    if (useChatCompletions) {
      return {
        'model': _modelName,
        // chat/completions 风格
        'messages': [
          {'role': 'system', 'content': systemText},
          {'role': 'user', 'content': prompt},
        ],
      };
    }

    return {
      'model': _modelName,
      // responses 风格
      'input': [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': systemText},
            {'type': 'input_text', 'text': prompt},
          ],
        },
      ],
    };
  }

  String? _extractResponseText(Map<String, dynamic> data) {
    final direct = data['output_text'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }

    final output = data['output'];
    if (output is! List) {
      return null;
    }

    final buffer = StringBuffer();
    for (final item in output) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final content = item['content'];
      if (content is! List) {
        continue;
      }
      for (final part in content) {
        if (part is! Map<String, dynamic>) {
          continue;
        }

        final text = part['text'];
        if (text is String) {
          buffer.write(text);
        }
      }
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }
}
