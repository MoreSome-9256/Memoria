import 'dart:convert';
import 'dart:typed_data';

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
       _visionModelName =
         _defaultVisionModelName.isEmpty
           ? (modelName ?? _defaultModelName)
           : _defaultVisionModelName,
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

  static const Set<String> _blockedTitleWords = <String>{
    '采购员',
    '房主',
    '房东',
    '未婚妻',
    '未婚夫',
    '套路',
    '老婆',
    '丈夫',
    '情人',
  };

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
  static const String _defaultVisionModelName = String.fromEnvironment(
    'LLM_VISION_MODEL',
    defaultValue: '',
  );

  final String _apiKey;
  final String _baseUrl;
  final String _apiPath;
  final String _modelName;
  final String _visionModelName;
  final Dio _dio;
  static const String _defaultTextSystemPrompt =
      '你是一个中文摄影故事与标题助手。只能基于输入信息生成，不要编造未提供事实。';

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

    final location =
        event.locationName ??
        event.district ??
        event.city ??
        event.province ??
        '未知地点';
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
8. 如果标签明显偏向截图、文档、课件、聊天、春联、屏幕文字，请把事件理解为“文字/资料/屏幕记录”类画面，禁止凭 OCR 或零散词语推断人物职业、身份、关系和剧情
9. 禁止生成“采购员、房主、未婚妻、套路”这类身份或剧情脑补词

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

      if (_blockedTitleWords.any(cleaned.contains)) {
        continue;
      }

      titles.add(cleaned);
    }

    // 限制返回数量（3-5 个）
    return titles.take(5).toList();
  }

  /// 🛡️ 兜底标题生成（当 LLM 失败时）
  List<String> _getFallbackTitles(EventEntity event) {
    final location =
        event.locationName ??
        event.district ??
        event.city ??
        event.province ??
        '未知地点';
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

    final location =
        event.locationName ??
        event.district ??
        event.city ??
        event.province ??
        '未知地点';

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

  bool get isVisionApiConfigured => isApiKeyConfigured;

  Future<String?> completeText({
    required String prompt,
    String systemPrompt = _defaultTextSystemPrompt,
  }) {
    return _chatCompletion(prompt, systemPrompt: systemPrompt);
  }

  Future<String?> generatePhotoCaption({
    required Uint8List imageBytes,
    required String mimeType,
    required List<String> tags,
    required List<String> ocrTags,
    required String ocrText,
    required String? location,
    required DateTime takenAt,
    required bool isTextHeavy,
    required int faceCount,
  }) async {
    final prompt = _buildPhotoCaptionPrompt(
      tags: tags,
      ocrTags: ocrTags,
      ocrText: ocrText,
      location: location,
      takenAt: takenAt,
      isTextHeavy: isTextHeavy,
      faceCount: faceCount,
    );

    final text = await _multimodalChatCompletion(
      prompt: prompt,
      imageBytes: imageBytes,
      mimeType: mimeType,
    );
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    return text.trim();
  }

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

  Future<String?> _chatCompletion(
    String prompt, {
    String systemPrompt = _defaultTextSystemPrompt,
  }) async {
    final baseUrl = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final apiPath = _apiPath.startsWith('/') ? _apiPath : '/$_apiPath';
    final isChatCompletions = apiPath.contains('/chat/completions');
    final requestBody = _buildRequestBody(
      prompt: prompt,
      systemPrompt: systemPrompt,
      useChatCompletions: isChatCompletions,
    );

    // print('🌐 [LLM REQUEST] POST $baseUrl$apiPath');
    // print('🧾 [LLM REQUEST BODY] ${jsonEncode(requestBody)}');

    final headers = <String, String>{};
    if (_apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer $_apiKey';
    }

    final response = await _dio.post(
      '$baseUrl$apiPath',
      options: Options(headers: headers.isEmpty ? null : headers),
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

  Future<String?> _multimodalChatCompletion({
    required String prompt,
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final baseUrl = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    final apiPath = _apiPath.startsWith('/') ? _apiPath : '/$_apiPath';
    final isChatCompletions = apiPath.contains('/chat/completions');
    final requestBody = _buildVisionRequestBody(
      prompt: prompt,
      imageBytes: imageBytes,
      mimeType: mimeType,
      useChatCompletions: isChatCompletions,
    );

    final response = await _dio.post(
      '$baseUrl$apiPath',
      options: Options(headers: {'Authorization': 'Bearer $_apiKey'}),
      data: requestBody,
    );

    final data = response.data;
    print('📥 [LLM VISION RESPONSE STATUS] ${response.statusCode}');
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final outputText = _extractResponseText(data);
    if (outputText != null && outputText.isNotEmpty) {
      return outputText;
    }

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
    required String systemPrompt,
    required bool useChatCompletions,
  }) {
    if (useChatCompletions) {
      return {
        'model': _modelName,
        // chat/completions 风格
        'messages': [
          {'role': 'system', 'content': systemPrompt},
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
            {'type': 'input_text', 'text': systemPrompt},
            {'type': 'input_text', 'text': prompt},
          ],
        },
      ],
    };
  }

  Map<String, dynamic> _buildVisionRequestBody({
    required String prompt,
    required Uint8List imageBytes,
    required String mimeType,
    required bool useChatCompletions,
  }) {
    const systemText = '你是一个谨慎的中文图片描述助手。只能描述图中可见事实，不要脑补职业、关系、剧情和身份。';
    final imageDataUrl = 'data:$mimeType;base64,${base64Encode(imageBytes)}';

    if (useChatCompletions) {
      return {
        'model': _visionModelName,
        'messages': [
          {'role': 'system', 'content': systemText},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {'url': imageDataUrl},
              },
            ],
          },
        ],
      };
    }

    return {
      'model': _visionModelName,
      'input': [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': systemText},
            {'type': 'input_text', 'text': prompt},
            {'type': 'input_image', 'image_url': imageDataUrl},
          ],
        },
      ],
    };
  }

  String _buildPhotoCaptionPrompt({
    required List<String> tags,
    required List<String> ocrTags,
    required String ocrText,
    required String? location,
    required DateTime takenAt,
    required bool isTextHeavy,
    required int faceCount,
  }) {
    final dateText =
        '${takenAt.month}月${takenAt.day}日 ${takenAt.hour.toString().padLeft(2, '0')}:${takenAt.minute.toString().padLeft(2, '0')}';
    final tagsText = tags.isEmpty ? '无' : tags.join('、');
    final ocrTagsText = ocrTags.isEmpty ? '无' : ocrTags.join('、');
    final trimmedOcr = ocrText.trim();
    final ocrSnippet = trimmedOcr.isEmpty
        ? '无'
        : trimmedOcr.substring(
            0,
            trimmedOcr.length > 80 ? 80 : trimmedOcr.length,
          );

    return '''
请为这张照片写 1 句中文 caption。

已知辅助信息：
- 拍摄时间：$dateText
- 地点：${location ?? '未知地点'}
- 本地视觉标签：$tagsText
- OCR 标签：$ocrTagsText
- OCR 文本片段：$ocrSnippet
- 人脸数量：$faceCount
- 是否疑似文字/截图主导：${isTextHeavy ? '是' : '否'}

硬性要求：
1. 只输出一句中文，不要编号，不要引号，不要解释。
2. 长度控制在 12 到 28 个汉字，最多不超过 36 个字。
3. 只描述图中可以确认的内容，不要猜职业、关系、剧情、身份。
4. 如果画面是截图、文档、票据、课件、屏幕或文字材料，caption 必须按“资料/文档/屏幕内容”来写，禁止把 OCR 词语写成人物设定。
5. 禁止出现“采购员、房主、未婚妻、未婚夫、套路、学生、小伙子、学者、残疾人、同学”等脑补标签词。
6. 如果地点不确定，不要补地名。
''';
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

  /// 🚀 真实接口：向 DeepSeek 发送标签，实时生成故事
  Future<Map<String, dynamic>?> generateStoryAndMusic({
    required int eventId,
    required List<String> tags,
    List<String> ocrTags = const <String>[],
    List<String> ocrHighlights = const <String>[],
    required double joyScore,
    required int photoCount,
    String? location,
    String? date,
    String stylePreference = "治愈风",
    String? photoDetails, // 🌟 新增：接收具体到每一张图的镜头特征
    String? themeTitle, // 🌟 新增：接收用户输入的主题
    String? themeSubtitle, // 🌟 新增：接收用户选择的副标题
  }) async {
    print(
      "☁️ [DeepSeek] 创作中... 地点: $location, 标签: $tags, OCR标签: $ocrTags, OCR线索数: ${ocrHighlights.length}, 欢乐值: $joyScore, 图片数: $photoCount",
    );
    print("🧭 [DeepSeek] 主题: $themeTitle, 副标题: $themeSubtitle");
    print("🚀 [请求发送] 正在携带具体帧画面特征呼叫大模型...");

    // 1. 🎬 终极铁血版：禁止推测，必须基于事实的 Prompt
    final prompt =
        '''
你现在是一位拥有百万粉丝的爆款短视频导演兼金牌编剧（精通小红书、抖音网感）。
请严格基于以下【真实的画面素材记录】，构思短视频/Vlog的剪辑思路和旁白脚本。

【既定背景与要求】
- 核心主题：${themeTitle ?? '未命名回忆'}
- 情感切入点：${themeSubtitle ?? stylePreference}
- 整体时空：${date ?? '某天'} · ${location ?? '某地'}
- 欢乐指数：${joyScore.toStringAsFixed(2)} / 1.0
- 照片总数：$photoCount 张
- 灵感词汇：${tags.isEmpty ? '安静的角落, 时光的碎片' : tags.join(', ')}
- OCR 提取标签：${ocrTags.isEmpty ? '无明显文本标签' : ocrTags.join(', ')}
- OCR 文本线索：${ocrHighlights.isEmpty ? '无' : ocrHighlights.join('；')}
- 情感基调：${joyScore > 0.7 ? '极其欢乐与温暖' : '平静与沉思'} (欢乐指数: ${joyScore.toStringAsFixed(2)})
- 风格偏好：$stylePreference

【🎬 真实镜头分镜表（绝对不许篡改或推测，必须作为客观事实使用）】
${photoDetails ?? '总体画面元素：${tags.join(', ')}'}

补充理解规则：
- 每条“镜头”里如果已经给出一句自然语言画面描述，那一句就是该照片最优先的事实依据；你应该先吃透这句描述，再参考后面的 OCR 与标签补充。
- 只有当镜头描述比较简略时，才使用标签和 OCR 去补足细节，绝不能让离散标签覆盖掉更完整的画面描述。
- 你的任务不是把标签机械拼句子，而是把这些单图描述像珍珠一样串起来，写成时空连续、情绪连贯的回忆片段。

请严格按照以下三个部分，输出结构化的纯文本内容（禁止使用 ** 加粗等 Markdown 语法）：

【一、 素材内容提炼】
（直接陈述客观事实，绝对禁止出现“推测”、“可能”等不确定词汇；若 OCR 提供了明确文本线索，请优先吸收）
- 核心主体：(画面中真实出现了什么人或物)
- 场景环境：(画面所处的真实环境)
- 故事线索：(这组真实照片串联起来的情感脉络)

【硬性约束】
- 如果镜头描述中出现“屏幕、截图、文档、聊天、表格、课件、OCR”等线索，必须按数字内容或文档内容处理，禁止把词语误写成人物职业、亲密关系、社会身份或狗血剧情
- 禁止把零散 OCR 词语脑补成“采购员、房主、未婚妻、套路”等角色设定
- 当地点未知时，就明确写“未知地点”或“室内屏幕/文档场景”，不要擅自补城市

【二、 备选故事脚本】
（请基于真实的镜头分镜表，生成 2 个不同视角的短视频脚本）

⚠️ 核心图文排版要求（生死攸关，千万不能错）：
本次故事共有 $photoCount 张照片。你必须在分镜脚本中，使用 Markdown 图片占位符将这 $photoCount 张照片全部按顺序穿插进去！
占位符格式严格为：![img](0)、![img](1)、![img](2)... 一直到 ![img](${photoCount - 1})。
一个都不能少！并且要和上面【真实镜头分镜表】里的序号一一对应！

故事1：[填写极其吸引人的小红书爆款标题]
- 叙事顺序：(如：开篇引入 -> 细节展现 -> 情感升华)
- 分镜与文案：
  ![img](0) (结合镜头1的客观画面描述)：(走心的配音台词或旁白)
  ![img](1) (结合镜头2的客观画面描述)：(走心的配音台词或旁白)
  ... (继续穿插剩下的占位符)

故事2：[填写带有Vlog网感的治愈系标题]
- 叙事顺序：(填写该故事的发展脉络)
- 分镜与文案：
  ![img](0) (结合镜头1的客观画面描述)：(生活化的配音台词)
  ![img](1) (结合镜头2的客观画面描述)：(生活化的配音台词)
  ... (继续穿插剩下的占位符)

【三、 成片风格总结】
（对上述生成的2个脚本进行一句话的视听风格总结）
- 《故事1标题》：(例如：以轻松日常的文风叙事，配上治愈系Vlog音乐)
- 《故事2标题》：(例如：采用快节奏卡点剪辑，搭配欢快的背景音)

注意：请直接输出从【一、 素材内容提炼】开始的正文，绝对不要输出任何“好的”、“没问题”等前言后语。
''';

    try {
      final realStory = await generateBlogText(prompt);

      print("📜 [绝密档案] DeepSeek 真实输出内容：\n$realStory");

      if (realStory != null && realStory.isNotEmpty) {
        final cleanedStory = realStory.replaceAll('**', '');
        print("✅ DeepSeek 故事生成完毕！");

        return {
          "code": 200,
          "msg": "success",
          "data": {
            "story_title": themeTitle ?? "未命名的记忆",
            "script_content": cleanedStory,
            "bgm_url": "http://127.0.0.1/dummy_music.mp3",
          },
        };
      } else {
        throw Exception("DeepSeek 返回了空数据");
      }
    } catch (e) {
      print("❌ DeepSeek 调用崩溃: $e");
      return null;
    }
  }
  /// 🎬 提取视频台词 (进化版：结合真实的每一帧画面特征)
  Future<List<String>> generateVideoCaptionsFromScript({
    required String narrative,
    required List<String> styleTags,
    required List<String> photoDescriptions, // 🌟 核心：接收每张图的真实描述
  }) async {
    final int photoCount = photoDescriptions.length;

    // 🌟 将传入的图片特征组装成带序号的清晰文本
    final StringBuffer framesInfo = StringBuffer();
    for (int i = 0; i < photoCount; i++) {
      framesInfo.writeln('第 ${i + 1} 张图画面特征：${photoDescriptions[i]}');
    }

    final prompt =
        '''
你是一个精通小红书氛围感的短视频台词编剧。
我现在有一段关于这组照片的整体故事背景，以及总共 $photoCount 张照片的【具体画面特征】。
请你结合整体剧情和每一张图的实际画面，为这 $photoCount 张照片各写一句极简的视频字幕。

【整体故事背景】
$narrative
风格参考：${styleTags.join(', ')}

【各分镜实际画面】(请确保台词与这些画面强相关，贴脸输出！)
$framesInfo

【输出要求（生死攸关，必须遵守）】
1. 必须输出纯 JSON，格式严格为：{"captions": ["第一句", "第二句", ...]}
2. 句子要精炼有网感（单句不超过 15 个字）。
3. captions 数组的长度必须【严格等于 $photoCount】！
4. 🌟 拒绝假大空的抒情模板（如“时光荏苒、定格美好”等），台词必须有画面感，与传入的具体画面特征对应！
5. 不要输出任何 Markdown 标记（如 ```json），直接输出花括号开头的 JSON。
''';

    try {
      print("🎬 [DeepSeek] 正在结合具体画面特征，提炼 $photoCount 句贴脸视频台词...");
      final text = await _chatCompletion(prompt);

      if (text == null || text.trim().isEmpty) {
        return _getFallbackCaptions(photoCount);
      }

      final cleanJson = text.replaceAll(RegExp(r'```json|```'), '').trim();
      final Map<String, dynamic> result = jsonDecode(cleanJson);

      if (result.containsKey('captions') && result['captions'] is List) {
        final List<dynamic> rawCaptions = result['captions'];
        List<String> finalCaptions = rawCaptions
            .map((e) => e.toString())
            .toList();

        if (finalCaptions.length < photoCount) {
          finalCaptions.addAll(
            List.generate(photoCount - finalCaptions.length, (i) => ""),
          );
        } else if (finalCaptions.length > photoCount) {
          finalCaptions = finalCaptions.sublist(0, photoCount);
        }

        print("✅ 贴脸台词提炼成功: $finalCaptions");
        return finalCaptions;
      } else {
        throw const FormatException("JSON 中找不到 captions 数组");
      }
    } catch (e) {
      print("❌ LLM 台词解析失败: $e");
      return _getFallbackCaptions(photoCount);
    }
  }

  /// 🛡️ 台词生成的兜底方案（返回等长的空白字符串列表）
  List<String> _getFallbackCaptions(int count) {
    return List.generate(count, (index) => "");
  }
  /// 📝 生成各平台专属发帖文案
  Future<String> generateSocialMediaCopy({
    required String platform,
    required String title,
    required String subtitle,
    required List<String> captions,
  }) async {
    // 把所有台词拼接起来，让大模型知道视频到底演了啥
    final scriptContent = captions
        .where((e) => e.isNotEmpty && e != '__INTRO__')
        .join('；');

    final prompt =
        '''
你是一个精通各大社交平台爆款逻辑的资深新媒体运营。
用户刚刚通过视频相册工具生成了一支回忆视频，请根据以下视频信息，为【$platform】生成一份专属发帖文案。

【视频信息】
标题：$title
副标题/情感切入点：$subtitle
视频核心台词：$scriptContent

【各平台风格硬性要求】
- 朋友圈：走心、私人化、简短，像对老朋友说话，不要太营销，偶尔加个emoji。
- 小红书：必须有吸睛的标题，大量使用Emoji，注重氛围感、美学和生活方式，结尾带上3-5个相关的Hashtag（如 #日常碎片）。
- 抖音：开篇第一句必须抓人，口语化，情绪饱满，带一点剧情感，带上热门标签。
- B站：带点二次元、整活或Vlog网感，标题有梗，文案互动性强（可以暗示观众一键三连或弹幕互动）。

请直接输出文案内容，不要解释，不要包含 Markdown 的 ``` 标记。
''';

    try {
      print("🚀 [DeepSeek] 正在生成 $platform 发帖文案...");
      // 复用你已经写好的文本生成底层方法
      final text = await generateBlogText(prompt);
      return text ?? '生成文案失败，请手动编辑。';
    } catch (e) {
      print("❌ 文案生成失败: $e");
      return '生成失败，请自己写点什么吧~';
    }
  }
}
