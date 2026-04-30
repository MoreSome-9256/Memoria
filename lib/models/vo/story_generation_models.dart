import '../ai_theme.dart';
import '../entity/photo_entity.dart';
import '../entity/story_entity.dart';
import '../event.dart';
import 'photo.dart';

enum StoryGenerationMode {
  deepseekTags,
  localCaptionThenDeepseek,
  localDirectVlm,
}

enum StoryTemplateCategory {
  trending,
  poetry,
  cinematic,
  healing,
}

extension StoryTemplateCategoryX on StoryTemplateCategory {
  String get title {
    switch (this) {
      case StoryTemplateCategory.trending:
        return '热门类';
      case StoryTemplateCategory.poetry:
        return '诗歌类';
      case StoryTemplateCategory.cinematic:
        return '电影旁白类';
      case StoryTemplateCategory.healing:
        return '治愈回忆类';
    }
  }

  String get subtitle {
    switch (this) {
      case StoryTemplateCategory.trending:
        return '更适合有情绪、有金句感的热门表达';
      case StoryTemplateCategory.poetry:
        return '更适合有画面感、留白感和节奏感的写法';
      case StoryTemplateCategory.cinematic:
        return '更适合像旁白一样推进镜头与情绪';
      case StoryTemplateCategory.healing:
        return '更适合温柔、克制、带回忆感的故事';
    }
  }
}

class StoryPromptTemplate {
  const StoryPromptTemplate({
    required this.id,
    required this.category,
    required this.title,
    required this.preview,
    required this.instruction,
  });

  final String id;
  final StoryTemplateCategory category;
  final String title;
  final String preview;
  final String instruction;
}

const List<StoryPromptTemplate> kStoryPromptTemplates = <StoryPromptTemplate>[
  StoryPromptTemplate(
    id: 'trending_spring',
    category: StoryTemplateCategory.trending,
    title: '不只是在写春天',
    preview: '你要描述春天，就不要只描述春天，要写出人被春天轻轻击中的那一下。',
    instruction:
        '请用近年热门图文文案的表达方式来写：不要平铺直叙地介绍季节或场景，而要从照片里的具体瞬间切入，写出“人被某个画面轻轻击中”的感觉。文字要自然、高级、有记忆点，但不能油腻，也不能脱离图片事实。',
  ),
  StoryPromptTemplate(
    id: 'trending_moment',
    category: StoryTemplateCategory.trending,
    title: '把瞬间写成被记住的时刻',
    preview: '把普通画面写成值得收藏的一个瞬间，有情绪起伏，也有可以被记住的句子。',
    instruction:
        '请采用热门生活方式图文里常见的“瞬间感”写法：围绕某个细小画面展开，把普通照片写成值得收藏的时刻。可以有金句，但必须服务于照片本身；要有情绪、有节奏、有回味。',
  ),
  StoryPromptTemplate(
    id: 'poetry_light',
    category: StoryTemplateCategory.poetry,
    title: '像散文诗一样轻轻展开',
    preview: '语言更有留白与韵律，像散文诗，但依然贴着真实画面走。',
    instruction:
        '请用散文诗式的笔触写作，语言要有留白、有节奏、有画面流动感。不要堆砌辞藻，不要故作玄虚，每一段都要紧贴对应图片里真实可见的内容，在真实中写出诗意。',
  ),
  StoryPromptTemplate(
    id: 'poetry_gentle',
    category: StoryTemplateCategory.poetry,
    title: '温柔而克制的诗性表达',
    preview: '不喧闹，不煽情，像把情绪轻轻放进风景和人物之间。',
    instruction:
        '请使用温柔、克制、诗性的表达方式。情绪不要喊出来，而是放进景物、动作、光线和距离里。故事要读起来很美，但依旧必须基于图片事实，不虚构超出照片的信息。',
  ),
  StoryPromptTemplate(
    id: 'cinematic_voiceover',
    category: StoryTemplateCategory.cinematic,
    title: '电影旁白感',
    preview: '像镜头旁白一样推进，一段段把画面、情绪和时间线串起来。',
    instruction:
        '请按照电影旁白的感觉写作。每一段都像镜头切换后的旁白，既描述画面，也推动情绪和时间线往前走。节奏要稳定，语言要有叙事张力，读起来像完整短片的文案。',
  ),
  StoryPromptTemplate(
    id: 'cinematic_montage',
    category: StoryTemplateCategory.cinematic,
    title: '蒙太奇叙事',
    preview: '强调镜头之间的联系，让不同照片之间形成递进和呼应。',
    instruction:
        '请突出镜头与镜头之间的递进、呼应和转场感，把多张照片写成一组有完整起承转合的蒙太奇叙事。每一段都要兼顾画面细节和情绪推进，让整篇故事更像一支完整片子的脚本旁白。',
  ),
  StoryPromptTemplate(
    id: 'healing_memory',
    category: StoryTemplateCategory.healing,
    title: '柔软回忆录',
    preview: '像在回看一段温柔的旧时光，情绪自然，不刻意煽情。',
    instruction:
        '请把整篇故事写成一段柔软的回忆录。重点不是制造戏剧冲突，而是把照片里的温度、陪伴感和生活感慢慢写出来。文字要真诚、松弛、细腻，适合配合相册阅读。',
  ),
  StoryPromptTemplate(
    id: 'healing_growth',
    category: StoryTemplateCategory.healing,
    title: '生活继续生长',
    preview: '把故事写成生活缓慢生长的过程，有细节，也有温柔的力量。',
    instruction:
        '请围绕“生活仍在慢慢生长”的感觉来写。不要写成口号，而要通过照片里的场景、人物状态、天气、光线和动作，把那种温柔向前的力量写出来，让读者读完有被安抚的感觉。',
  ),
];

const Map<String, String> kStoryPromptTemplateExamples = <String, String>{
  'trending_spring':
      '想要描写洱海，我就不只是描写洱海的蓝，而是写那一刻风掠过耳尖时，内心突然安静下来的空灵。那些波光粼粼不是湖水的闪烁，而是生活给忙碌已久的我的一个温柔回眸。在那一秒，我被大自然的宽广轻轻击中，仿佛所有的琐碎都随风散去，只剩下眼底的一抹清澈。',
  'trending_moment':
      '街角的咖啡店，你低头摆弄相机的瞬间，光影恰好落在你的睫毛上。这原本只是普通午后的一秒钟，却因为那一抹专注，成为了我手机里永恒收藏的底片。生活并不总是有大开大合的剧情，但这些有情绪起伏的小碎片，拼凑成了我们最值得被记住的珍贵时刻：只要你在，平淡亦是光芒。',
  'poetry_light':
      '窗外的雨，像未竟的句子，断断续续。石板路上升腾起潮湿的雾气，远山的轮廓在墨色中变得柔和。文字不必太拥挤，留出一点空白给风，给云。镜头里的每一帧画面都贴着真实的脉搏在跳动，像一首散文诗，在慢节奏的韵律中，缓缓铺陈开那些关于远方和归途的念想。',
  'poetry_gentle':
      '并不喧闹。只是看海浪一次次抚摸沙滩，又无声地退去。夕阳将影子拉得很长，把所有的情绪都藏进这橘色的暮霭里。没有煽情的告白，只有风景与人之间那种心照不宣的默契。这种诗性是克制的，像深秋的一片落叶，轻轻安放在岁月的心房，温润、持久，却又如此有力。',
  'cinematic_voiceover':
      '“这是我们出发的第15天。”旁白声响起，镜头从斑驳的城墙推向你灿烂的笑容。画面一段段切分，串联起异乡的街道与归途的夕阳。时间在线性中跳跃，情感在推进中升温。这不只是一叠照片，这是一部关于我们的公路电影，记录着每一场无拘无束的欢笑，和每一个不经意的对望。',
  'cinematic_montage':
      '画面在指尖的触碰与晚霞的余晖中快速切换。这一张是奔跑的脚步，下一张是静止的呼吸，镜头间的内在联系让情感层层递进。像是碎片化的记忆被重新剪辑，每一张照片都在呼应前一秒的悸动。在这场视觉的蒙太奇里，平凡的日子被重塑成极具张力的叙事，每一帧都是下一次精彩的伏笔。',
  'healing_memory':
      '回看这些旧时光，总能闻到老家院子里那股淡淡的草木香。镜头里的笑容很自然，没有刻意的滤镜，只有岁月沉淀后的松弛感。这些柔软的片段，像一张张温暖的手帕，轻轻拂去当下的疲惫。不刻意煽情，却在每一个平凡的角落里，让人感受到被时光善待的温热与从容，那是我们回不去的少年。',
  'healing_growth':
      '阳台上的绿植又长高了一寸，清晨的阳光准时洒在木地板上。生活就在这些微小的细节里，缓慢而坚定地生长着。不需要宏大的叙事，只记下这一餐一饭的烟火气，和每一个为了理想努力的瞬间。文字里蕴含着温柔的力量，它告诉我们：无论世界如何喧嚣，内心的生命力始终在悄悄破土，向阳而生。',
};

String storyPromptTemplateExampleById(String? id) {
  if (id == null || id.trim().isEmpty) {
    return '';
  }
  return kStoryPromptTemplateExamples[id] ?? '';
}

StoryPromptTemplate? storyPromptTemplateById(String? id) {
  if (id == null || id.trim().isEmpty) {
    return null;
  }
  for (final template in kStoryPromptTemplates) {
    if (template.id == id) {
      return template;
    }
  }
  return null;
}

List<StoryPromptTemplate> storyPromptTemplatesForCategory(
  StoryTemplateCategory category,
) {
  return kStoryPromptTemplates
      .where((template) => template.category == category)
      .toList(growable: false);
}

extension StoryGenerationModeX on StoryGenerationMode {
  String get title {
    switch (this) {
      case StoryGenerationMode.deepseekTags:
        return 'DeepSeek 标签故事';
      case StoryGenerationMode.localCaptionThenDeepseek:
        return '本地 VLM Caption + DeepSeek';
      case StoryGenerationMode.localDirectVlm:
        return '本地 VLM 直接读图';
    }
  }

  String get subtitle {
    switch (this) {
      case StoryGenerationMode.deepseekTags:
        return '直接根据标签、OCR、时间和地点生成，速度最快';
      case StoryGenerationMode.localCaptionThenDeepseek:
        return '先逐图补 caption，再交给 DeepSeek 串成故事';
      case StoryGenerationMode.localDirectVlm:
        return '直接由本地 VLM 读图并写故事，不依赖云端';
    }
  }

  bool get requiresLocalVlm {
    switch (this) {
      case StoryGenerationMode.deepseekTags:
        return false;
      case StoryGenerationMode.localCaptionThenDeepseek:
      case StoryGenerationMode.localDirectVlm:
        return true;
    }
  }
}

enum StoryGenerationProgressStatus {
  pending,
  inProgress,
  completed,
  failed,
}

class StoryGenerationProgressStep {
  const StoryGenerationProgressStep({
    required this.id,
    required this.title,
    required this.status,
    this.detail,
    this.bullets = const <String>[],
    this.previewImagePaths = const <String>[],
  });

  final String id;
  final String title;
  final StoryGenerationProgressStatus status;
  final String? detail;
  final List<String> bullets;
  final List<String> previewImagePaths;

  StoryGenerationProgressStep copyWith({
    StoryGenerationProgressStatus? status,
    String? detail,
    List<String>? bullets,
    List<String>? previewImagePaths,
  }) {
    return StoryGenerationProgressStep(
      id: id,
      title: title,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      bullets: bullets ?? this.bullets,
      previewImagePaths: previewImagePaths ?? this.previewImagePaths,
    );
  }
}

class StoryGenerationProgressState {
  const StoryGenerationProgressState({
    required this.steps,
    this.headline,
    this.errorMessage,
    this.isCompleted = false,
  });

  final List<StoryGenerationProgressStep> steps;
  final String? headline;
  final String? errorMessage;
  final bool isCompleted;
}

class StoryGenerationRequest {
  const StoryGenerationRequest({
    required this.event,
    required this.selectedPhotos,
    required this.selectedTheme,
    required this.title,
    required this.subtitle,
    required this.mode,
    required this.isHorizontal,
    required this.targetPlatform,
    this.enableAiMusic = true,
    this.customMusicPath,
    this.enableAutoCaptions = true,
    this.manualCaptionsText,
    this.semanticSearchQuery,
    this.preserveSelectionOrder = false,
    this.storyTemplateId,
  });

  final Event event;
  final List<Photo> selectedPhotos;
  final AITheme selectedTheme;
  final String title;
  final String subtitle;
  final StoryGenerationMode mode;
  final bool isHorizontal;
  final String targetPlatform;
  final bool enableAiMusic;
  final String? customMusicPath;
  final bool enableAutoCaptions;
  final String? manualCaptionsText;
  final String? semanticSearchQuery;
  final bool preserveSelectionOrder;
  final String? storyTemplateId;
}

class StoryGenerationOutput {
  const StoryGenerationOutput({
    required this.story,
    required this.photos,
  });

  final StoryEntity story;
  final List<PhotoEntity> photos;
}
