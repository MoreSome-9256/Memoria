/// 语义查询解析模型，描述解析结果、路由状态和候选条件。

part of 'semantic_query_parser_service.dart';

class _CoarseSeed {
  const _CoarseSeed({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    required this.aliases,
    required this.prototypePrompt,
    required this.shortPrompts,
  });

  final String id;
  final String labelZh;
  final String labelEn;
  final List<String> aliases;
  final String prototypePrompt;
  final List<String> shortPrompts;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label_zh': labelZh,
      'label_en': labelEn,
      'aliases': aliases,
      'prototype_prompt': prototypePrompt,
      'short_prompts': shortPrompts,
    };
  }
}

const List<_CoarseSeed> _coarseSeeds = <_CoarseSeed>[
  _CoarseSeed(
    id: 'people',
    labelZh: '人物',
    labelEn: 'people',
    aliases: <String>['人', '人物', '人像', '肖像', '自拍', '合影', '家人', '家庭'],
    prototypePrompt: 'a photo of people or human portraits',
    shortPrompts: <String>[
      'a photo of a person or people',
      'a portrait photo of family or friends',
    ],
  ),
  _CoarseSeed(
    id: 'food_drink',
    labelZh: '美食饮品',
    labelEn: 'food and drink',
    aliases: <String>['吃', '饭', '聚餐', '美食', '饮品', '火锅', '饺子'],
    prototypePrompt: 'a photo of food dishes dining table or drinks',
    shortPrompts: <String>[
      'a photo of food or dishes',
      'a photo of people eating together at a table',
    ],
  ),
  _CoarseSeed(
    id: 'pets_animals',
    labelZh: '宠物动物',
    labelEn: 'pets and animals',
    aliases: <String>['宠物', '猫', '狗', '动物'],
    prototypePrompt: 'a photo of pets animals cat dog or wildlife',
    shortPrompts: <String>[
      'a photo of a pet animal',
      'a photo of a cat or dog',
    ],
  ),
  _CoarseSeed(
    id: 'flowers_plants',
    labelZh: '花草植物',
    labelEn: 'flowers and plants',
    aliases: <String>['花', '花草', '植物', '鲜花', '绿植'],
    prototypePrompt: 'a photo of flowers blossoms plants or leaves',
    shortPrompts: <String>[
      'a photo of flowers or blossoms',
      'a photo of plants or green leaves',
    ],
  ),
  _CoarseSeed(
    id: 'natural_landscape',
    labelZh: '自然风光',
    labelEn: 'natural landscape',
    aliases: <String>['风景', '自然', '山', '草原', '森林', '雪景'],
    prototypePrompt:
        'a photo of nature mountains forest snow or outdoor scenery',
    shortPrompts: <String>[
      'a photo of natural scenery',
      'a photo of mountains forest or outdoor landscape',
    ],
  ),
  _CoarseSeed(
    id: 'city_street',
    labelZh: '城市街景',
    labelEn: 'city street',
    aliases: <String>['城市', '街景', '街道', '高楼', '建筑', '都市'],
    prototypePrompt:
        'a photo of city streets tall buildings road or urban landscape',
    shortPrompts: <String>[
      'a photo of a city street',
      'a photo of tall buildings road or urban landscape',
    ],
  ),
  _CoarseSeed(
    id: 'travel_landmark',
    labelZh: '旅行地标',
    labelEn: 'travel landmark',
    aliases: <String>['旅行', '旅游', '景点', '地标'],
    prototypePrompt: 'a photo of travel landmarks attractions or sightseeing',
    shortPrompts: <String>[
      'a travel photo of a landmark',
      'a sightseeing photo at a famous place',
    ],
  ),
  _CoarseSeed(
    id: 'beach_water',
    labelZh: '海边水域',
    labelEn: 'beach and water',
    aliases: <String>['海', '海边', '海滩', '湖', '江', '河', '水边'],
    prototypePrompt:
        'a photo of beach sea ocean river lake or waterside scenery',
    shortPrompts: <String>[
      'a photo of the beach or seaside',
      'a photo of river lake or water scenery',
    ],
  ),
  _CoarseSeed(
    id: 'sky_sunset',
    labelZh: '天空日落',
    labelEn: 'sky and sunset',
    aliases: <String>['天空', '云', '晚霞', '夕阳', '日落'],
    prototypePrompt:
        'a photo of the sky clouds sunset dusk or colorful evening light',
    shortPrompts: <String>[
      'a photo of the sky and clouds',
      'a photo of sunset or evening glow',
    ],
  ),
  _CoarseSeed(
    id: 'festival_celebration',
    labelZh: '节日庆典',
    labelEn: 'festival celebration',
    aliases: <String>['节日', '春节', '过年', '生日', '烟花'],
    prototypePrompt:
        'a photo of celebrations festival reunion birthday wedding or fireworks',
    shortPrompts: <String>[
      'a photo of a festival celebration',
      'a reunion or holiday celebration photo',
    ],
  ),
  _CoarseSeed(
    id: 'atmosphere_mood',
    labelZh: '氛围情绪',
    labelEn: 'atmosphere and mood',
    aliases: <String>['氛围', '情绪', '心情', '温馨', '浪漫', '安静', '热闹', '庄重'],
    prototypePrompt:
        'a photo with a clear visual mood such as warm lively quiet romantic or solemn atmosphere',
    shortPrompts: <String>[
      'a photo with a clear emotional atmosphere',
      'a warm quiet lively romantic or solemn memory photo',
    ],
  ),
  _CoarseSeed(
    id: 'document_screenshot',
    labelZh: '文档截图',
    labelEn: 'document screenshot',
    aliases: <String>['文档', '截图', '课件', '屏幕', '资料'],
    prototypePrompt:
        'a screenshot or photo of documents slides notes or text-heavy pages',
    shortPrompts: <String>[
      'a screenshot of a document or slides',
      'a photo of text-heavy notes or study materials',
    ],
  ),
  _CoarseSeed(
    id: 'screen_code',
    labelZh: '屏幕代码',
    labelEn: 'screen code',
    aliases: <String>['代码', '编程', '终端', '控制台', 'IDE'],
    prototypePrompt:
        'a screenshot of code terminal development tools or software interface',
    shortPrompts: <String>[
      'a screenshot of code or IDE',
      'a screenshot of terminal or software interface',
    ],
  ),
  _CoarseSeed(
    id: 'medical_related',
    labelZh: '医疗相关',
    labelEn: 'medical related',
    aliases: <String>['医院', '医生', '病房', '体检', '药'],
    prototypePrompt:
        'a photo related to hospital clinic medicine or medical scenes',
    shortPrompts: <String>[
      'a photo at a hospital or clinic',
      'a medical related photo',
    ],
  ),
];

final Map<String, _CoarseSeed> _coarseSeedById = <String, _CoarseSeed>{
  for (final item in _coarseSeeds) item.id: item,
};
