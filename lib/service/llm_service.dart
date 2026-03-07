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
  // ---------------------------------------------------------
  // 🌟 下方为全新重构：对接团队自研后端的“图文+音乐”综合生成接口
  // ---------------------------------------------------------

  // 🚧 核心开关：等后端兄弟说“接口写好了”，把这里改成 false！
  final bool _useMockBackend = true;

  /// 🚀 临时重构版：绕过未完成的后端，直接用本地 DeepSeek 生成故事
  Future<Map<String, dynamic>?> generateStoryAndMusic({
    required int eventId,
    required List<String> tags,
    required double joyScore,
    required int photoCount,
    String? location, // ➕ 新增地点参数
    String? date, // ➕ 新增时间参数
    String stylePreference = "治愈风",
  }) async {
    print("🚀 [临时接管] 后端没好，直接呼叫 DeepSeek 大模型写小作文...");

    // 1. 📝 构造专门给 DeepSeek 的提示词 (Prompt)
    // 1. 🎬 升级版：AI 导演短视频脚本生成 Prompt
    final prompt =
        '''
你现在是一位拥有百万粉丝的爆款短视频导演兼金牌编剧（精通小红书、抖音网感）。
请根据以下用户上传的图片特征标签，构思短视频/Vlog的剪辑思路和旁白脚本。

地点：$location
时间：$date
素材特征线索：${tags.join('、')}
情感基调：$stylePreference
整体欢乐值：$joyScore（满分1.0，分数决定文风是幽默、治愈还是深沉）

请严格按照以下三个部分，输出结构化的纯文本内容（禁止使用 ** 加粗等 Markdown 语法）：

【一、 素材内容分析】
（根据标签推测并总结出以下三点，语言要像专业的视觉分析报告）
- 主体：(推测画面中主要出现了什么，如：人物、猫咪、建筑等)
- 场景：(推测画面所处环境，如：温馨室内、繁华街道等)
- 事件：(推测正在发生的故事，如：朋友聚餐、萌宠捣乱、独自漫步等)

【二、 备选故事脚本】
（请基于上述分析，生成 2 个不同视角的短视频分镜脚本，必须包含以下要素）

故事1：[填写吸引人的网感标题，如：这个家没我得散！]
- 叙事顺序：(如：发现目标 -> 试探 -> 搞破坏 -> 结局)
- 分镜与文案：
  1. (画面描述)：(配音台词或旁白)
  2. (画面描述)：(配音台词或旁白)
  3. (画面描述)：(配音台词或旁白)

故事2：[填写吸引人的网感标题，如：打工人的周末治愈碎片]
- 叙事顺序：(填写该故事的发展脉络)
- 分镜与文案：
  1. (画面描述)：(配音台词或旁白)
  2. (画面描述)：(配音台词或旁白)
  3. (画面描述)：(配音台词或旁白)

【三、 成片风格总结】
（对上述生成的2个脚本进行一句话的视听风格总结）
- 《故事1标题》：(例如：从戏精萌宠视角叙事，搭配手绘的剪辑风格和欢快的BGM)
- 《故事2标题》：(例如：以轻松日常的文风叙事，配上治愈系Vlog音乐)

注意：
1. 绝对不要输出任何前言后语（如“好的，为您生成”）。
2. 请直接输出从【一、 素材内容分析】开始的正文。
''';

    // 2. 🧠 直接调用本类中已有的真实大模型生成方法
    final realStory = await generateBlogText(prompt);
    // 🌟 新增这行打印：让我们亲眼看看 DeepSeek 到底写了什么神仙句子！
    print("📜 [绝密档案] DeepSeek 真实输出内容：\n$realStory");
    if (realStory != null && realStory.isNotEmpty) {
      // 🌟 新增：暴力清洗掉大模型自作主张加的 Markdown 加粗符号
      final cleanedStory = realStory.replaceAll('**', '');
      print("✅ DeepSeek 故事生成完毕！");
      // 3. 📦 包装成 UI 界面期待的 JSON 格式
      return {
        "code": 200,
        "msg": "success",
        "data": {
          "story_title": "AI 漫游：${tags.isNotEmpty ? tags.first : '美好'}的记忆",
          // 🌟 核心突破：把假文本换成真正的大模型生成内容！
          "script_content": realStory,
          // 🎵 音乐暂时用假的顶着，等后端兄弟把 AI 音乐生成接好
          "bgm_url": "http://127.0.0.1/dummy_music.mp3",
        },
      };
    } else {
      print("❌ DeepSeek 生成失败，降级使用默认文本");
      // 生成失败的兜底防崩溃逻辑
      return {
        "code": 200,
        "msg": "success",
        "data": {
          "story_title": "未命名的记忆",
          "script_content": "时光静好，这段记忆同样珍贵。（AI 生成超时或失败）",
          "bgm_url": "http://127.0.0.1/dummy_music.mp3",
        },
      };
    }
  }
}
