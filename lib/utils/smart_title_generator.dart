/// 智能标题生成器 - 本地规则引擎
/// 用于在 AI 分析未完成时生成基于规则的标题
class SmartTitleGenerator {
  // 🎊 节日映射表（月-日 -> 节日名称）
  static final Map<String, String> _holidays = {
    '1-1': '新年',
    '2-14': '情人节',
    '3-8': '妇女节',
    '4-5': '清明节',
    '5-1': '劳动节',
    '6-1': '儿童节',
    '8-15': '中秋节', // 农历，这里简化为公历近似
    '9-10': '教师节',
    '10-1': '国庆节',
    '12-25': 'Christmas',
    '12-31': '跨年夜',
  };

  // 🏷️ 标签模板映射（标签 -> 创意标题列表）
  static final Map<String, List<String>> _tagTemplates = {
    // 美食系列
    '美食': ['美食之旅', 'A Bite of {city}', '舌尖上的{city}', 'Foodie Tour'],
    '菜肴': ['美食探索', '美食记忆', 'Culinary Journey'],
    '料理': ['料理时光', '美食寻味'],

    // 宠物系列
    '猫': ['喵星人特辑', 'Meow Special', 'Purrfect Moments', '猫咪日常'],
    '狗': ['汪星人时光', 'Pawsome Days', '毛孩子的快乐'],
    '宠物': ['萌宠记录', 'Pet Tales', '毛孩子日记'],

    // 自然风景
    '海滩': ['海边时光', 'Beachside Memories', '海之韵', 'Coastal Vibes'],
    '大海': ['海的呼唤', 'Ocean Dreams', '蓝色记忆'],
    '山': ['登山之旅', 'Mountain Escape', '山间漫步'],
    '花朵': ['花样年华', 'Blooming Moments', '花海寻梦'],
    '日落': ['落日余晖', 'Sunset Serenade', '黄昏之美'],
    '日出': ['晨光序曲', 'Sunrise Moments', '破晓时分'],

    // 城市旅行
    '建筑': ['城市印象', 'Urban Exploration', '建筑之美'],
    '街道': ['街头漫步', 'Street Wandering', '城市角落'],

    // 人像活动
    '人像': ['欢聚时光', 'Together Forever', '美好时光'],
    '人群': ['热闹时刻', 'Crowd Vibes', '人间烟火'],
    '微笑': ['笑容满溢', 'Smile Collection', '快乐瞬间'],

    // 天气场景
    '天空': ['仰望天空', 'Sky Gazing', '云端漫步'],
    '云': ['云的诗篇', 'Cloudscape', '云卷云舒'],
    '雪': ['冬日仙境', 'Winter Wonderland', '雪域时光'],

    // 节日活动
    '派对': ['派对狂欢', 'Party Time', '欢乐聚会'],
    '音乐会': ['音乐之夜', 'Music Live', '音符飞扬'],
  };

  /// 🎯 核心方法：生成单个标题
  ///
  /// 参数:
  /// - [date]: 事件日期
  /// - [city]: 城市名称
  /// - [province]: 省份名称
  /// - [topTag]: 最高频标签
  /// - [joyScore]: 欢乐值评分 (0.0-1.0)
  ///
  /// 返回: 生成的标题字符串
  static String generate({
    required DateTime date,
    String? city,
    String? province,
    String? topTag,
    double? joyScore,
  }) {
    final location = city ?? province ?? '未知地点';

    // 优先级 1: 节日检查
    final holidayTitle = _checkHoliday(date, location);
    if (holidayTitle != null) return holidayTitle;

    // 优先级 2: 高情感检查
    if (joyScore != null && joyScore > 0.9) {
      return 'Happy Moments in $location';
    }

    // 优先级 3: 标签模板匹配
    if (topTag != null && topTag.isNotEmpty) {
      final tagTitle = _getTagBasedTitle(topTag, location);
      if (tagTitle != null) return tagTitle;
    }

    // 优先级 4: 兜底 - 城市 + 日期
    final dateStr = '${date.month}月${date.day}日';
    return '$location · $dateStr';
  }

  /// 🎊 检查是否为特殊节日
  static String? _checkHoliday(DateTime date, String location) {
    final key = '${date.month}-${date.day}';
    final holiday = _holidays[key];

    if (holiday != null) {
      // 根据节日类型生成不同风格的标题
      if (holiday == 'Christmas') {
        return '🎄 Merry Christmas in $location';
      } else if (holiday == '情人节') {
        return '💕 $holiday · Sweet Memories';
      } else if (holiday == '国庆节') {
        return '🇨🇳 $holiday · $location';
      } else {
        return '$holiday · $location';
      }
    }

    return null;
  }

  /// 🏷️ 基于标签获取创意标题
  static String? _getTagBasedTitle(String tag, String location) {
    final templates = _tagTemplates[tag];
    if (templates == null || templates.isEmpty) return null;

    // 随机选择一个模板（实际上用第一个，保证稳定性）
    final template = templates[0];

    // 如果模板包含 {city} 占位符，替换之
    if (template.contains('{city}')) {
      return template.replaceAll('{city}', location);
    }

    // 否则，将地点加在后面
    return '$location · $template';
  }

  /// 📊 计算分析进度百分比
  ///
  /// 参数:
  /// - [analyzedCount]: 已分析照片数量
  /// - [totalCount]: 总照片数量
  ///
  /// 返回: 进度百分比 (0-100)
  static int calculateProgress(int analyzedCount, int totalCount) {
    if (totalCount == 0) return 0;
    return ((analyzedCount / totalCount) * 100).round();
  }

  /// 🎲 获取标签的所有可用模板（供调试使用）
  static List<String>? getTemplatesForTag(String tag) {
    return _tagTemplates[tag];
  }
}
