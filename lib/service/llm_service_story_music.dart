/// 故事配乐生成服务，负责为叙事内容挑选或生成音乐提示。

part of 'llm_service.dart';

extension LLMServiceStoryMusic on LLMService {
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

  List<String> _getFallbackCaptions(int count) {
    return List.generate(count, (index) => "");
  }

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

  Future<String> generateMusicPrompt({
    required List<String> photoTags,
    required String storyTheme,
  }) async {
    final prompt =
        '''
你现在是一个专业的电影配乐师。我有一组照片，主题是 "$storyTheme"。
照片包含的元素有：${photoTags.join(', ')}。
请为我写一段用于 Meta MusicGen AI 生成背景音乐的英文提示词（Prompt）。

要求：
1. 必须是纯英文，不要包含任何中文和多余的解释。
2. 包含具体的音乐流派（如 Lo-Fi, Cinematic, Acoustic Pop）。
3. 包含情绪关键词（如 Upbeat, Melancholy, Chill）。
4. 包含核心乐器（如 Bright Piano, Heavy Bass, Acoustic Guitar）。
5. 包含大致的 BPM（如 90 bpm, 120 bpm）。
6. 【极其重要】必须在提示词的开头加上 "Seamless loop, video game background loop"，确保生成的音乐没有明显的开头淡入和结尾淡出，首尾可以完美无缝衔接。

示例输出：
Seamless loop, video game background loop, upbeat acoustic pop, sunny travel vlog vibe, 120 bpm.
''';

    try {
      print("🚀 [LLM] 正在撰写专属音乐提示词...");
      final result = await generateBlogText(prompt);
      final cleanPrompt =
          (result ?? "Upbeat cinematic acoustic pop, warm vibe, 100 bpm")
              .trim();
      print("🎵 [LLM] 生成的音乐配方: $cleanPrompt");
      return cleanPrompt;
    } catch (e) {
      print("❌ 音乐提示词生成失败，使用兜底提示词: $e");
      return "Chill lofi hip hop beat, warm piano, relaxed vlog vibe, 90 bpm";
    }
  }

  Future<String?> generateAndDownloadMusic(
    String prompt, {
    int duration = 12,
  }) async {
    try {
      print("☁️ [MusicGen] 开始生成 ${duration}s 的专属配乐...");

      // 1. 退回最稳妥的 v1/predictions 经典路由，使用绝对不会 404 的固定版本号
      // 1. 发起生成任务请求 (使用你截图里发现的最新版本)
      final response = await ApiProxyService.instance.post<Map<String, dynamic>>(
        '/v1/replicate/predictions',
        data: {
          // 🌟 从你截图里提取出的完整最新版本号！
          "version":
              "671ac645ce5e552cc63a54a2bbff63fcf798043055d2dac5fc9e36a837eedcfb",
          "input": {
            "prompt": prompt,
            "duration": duration,
            // 🌟 既然是最新版，直接把截图里的高音质参数全拉满！
            "model_version": "stereo-large", // 启用大模型立体声
            "output_format": "mp3", // 直接输出 mp3 格式
            "normalization_strategy": "peak", // 峰值归一化，防止爆音
          },
        },
      );

      if (response.statusCode != 201) {
        print('❌ MusicGen 请求未成功创建: ${response.data}');
        return null;
      }

      // 2. 轮询等待生成完成
      final predictionId = response.data?['id']?.toString();
      if (predictionId == null || predictionId.isEmpty) {
        print('❌ MusicGen 返回缺少 prediction id: ${response.data}');
        return null;
      }
      String? audioUrl;

      print("⏳ [MusicGen] 音乐生成中，正在轮询等待结果...");
      while (true) {
        await Future.delayed(const Duration(seconds: 4));

        final pollResponse = await ApiProxyService.instance
            .get<Map<String, dynamic>>(
              '/v1/replicate/predictions/$predictionId',
            );

        final pollData = pollResponse.data ?? const <String, dynamic>{};
        final status = pollData['status'];

        if (status == 'succeeded') {
          audioUrl = pollData['output'];
          break;
        } else if (status == 'failed' || status == 'canceled') {
          print('❌ MusicGen 生成被服务器判定为失败: $pollData');
          return null;
        }
      }

      // 3. 将生成的 MP3 下载到手机沙盒目录
      if (audioUrl != null) {
        print("📥 [MusicGen] 生成完毕！开始下载: $audioUrl");
        final dir = await getTemporaryDirectory();
        final filePath =
            '${dir.path}/ai_bgm_${DateTime.now().millisecondsSinceEpoch}.mp3';

        await ApiProxyService.instance.download(audioUrl, filePath);

        print("✅ [MusicGen] 专属 BGM 下载成功，路径: $filePath");
        return filePath;
      }
    } catch (e) {
      print("❌ [MusicGen] 代码运行崩溃: $e");
    }
    return null;
  }
}
