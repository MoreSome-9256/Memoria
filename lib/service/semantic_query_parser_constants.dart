part of 'semantic_query_parser_service.dart';

const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');
const double _shortRouteCoarseSimilarityThreshold = 0.18;

const String _noteShortRoute =
    '\u77ed\u67e5\u8be2\u76f4\u63a5\u8d70\u8bed\u4e49\u68c0\u7d22\uff0c\u672a\u8c03\u7528 DeepSeek';
const String _noteLocal =
    '\u5f53\u524d\u4f7f\u7528\u672c\u5730\u89c4\u5219\u89e3\u6790\u67e5\u8be2';
const String _noteLlm =
    '\u5f53\u524d\u4f7f\u7528 DeepSeek \u89e3\u6790\u67e5\u8be2';
const String _noteLlmMissing =
    '\u672a\u914d\u7f6e DeepSeek\uff0c\u5df2\u4f7f\u7528\u672c\u5730\u89e3\u6790';
const String _noteLlmFailed =
    'DeepSeek \u89e3\u6790\u5931\u8d25\uff0c\u5df2\u56de\u9000\u5230\u672c\u5730\u89e3\u6790';
const String _noteLlmSupplemented =
    'DeepSeek \u672a\u8fd4\u56de\u6709\u6548\u7684\u6b63\u5411\u8bed\u4e49\uff0c\u5df2\u8865\u5145\u672c\u5730\u8bed\u4e49\u63d0\u793a';
const String _noteFallbackMerged =
    '\u672c\u5730\u89c4\u5219\u5df2\u4f5c\u4e3a\u8865\u5145\u515c\u5e95';

const List<SemanticSearchSemanticItem>
_defaultNegativeSemantics = <SemanticSearchSemanticItem>[
  SemanticSearchSemanticItem(
    text:
        'a screenshot of a text document article chat message email or webpage',
    weight: 0.5,
  ),
  SemanticSearchSemanticItem(
    text:
        'a screenshot of a computer screen software interface programming code or IDE',
    weight: 0.5,
  ),
];

const List<_CoarseSeed> _coarseSeeds = <_CoarseSeed>[
  _CoarseSeed(
    id: 'people',
    labelZh: '\u4eba\u7269',
    labelEn: 'people',
    aliases: <String>[
      '\u4eba',
      '\u4eba\u7269',
      '\u4eba\u50cf',
      '\u8096\u50cf',
      '\u81ea\u62cd',
      '\u5408\u5f71',
      '\u5bb6\u4eba',
      '\u5bb6\u5ead',
    ],
    prototypePrompt: 'a photo of people or human portraits',
    shortPrompts: <String>[
      'a photo of a person or people',
      'a portrait photo of family or friends',
    ],
  ),
  _CoarseSeed(
    id: 'food_drink',
    labelZh: '\u7f8e\u98df\u996e\u54c1',
    labelEn: 'food and drink',
    aliases: <String>[
      '\u5403',
      '\u996d',
      '\u805a\u9910',
      '\u7f8e\u98df',
      '\u996e\u54c1',
      '\u706b\u9505',
      '\u997a\u5b50',
    ],
    prototypePrompt: 'a photo of food dishes dining table or drinks',
    shortPrompts: <String>[
      'a photo of food or dishes',
      'a photo of people eating together at a table',
    ],
  ),
  _CoarseSeed(
    id: 'pets_animals',
    labelZh: '\u5ba0\u7269\u52a8\u7269',
    labelEn: 'pets and animals',
    aliases: <String>['\u5ba0\u7269', '\u732b', '\u72d7', '\u52a8\u7269'],
    prototypePrompt: 'a photo of pets animals cat dog or wildlife',
    shortPrompts: <String>[
      'a photo of a pet animal',
      'a photo of a cat or dog',
    ],
  ),
  _CoarseSeed(
    id: 'flowers_plants',
    labelZh: '\u82b1\u8349\u690d\u7269',
    labelEn: 'flowers and plants',
    aliases: <String>[
      '\u82b1',
      '\u82b1\u8349',
      '\u690d\u7269',
      '\u9c9c\u82b1',
      '\u7eff\u690d',
    ],
    prototypePrompt: 'a photo of flowers blossoms plants or leaves',
    shortPrompts: <String>[
      'a photo of flowers or blossoms',
      'a photo of plants or green leaves',
    ],
  ),
  _CoarseSeed(
    id: 'natural_landscape',
    labelZh: '\u81ea\u7136\u98ce\u5149',
    labelEn: 'natural landscape',
    aliases: <String>[
      '\u98ce\u666f',
      '\u81ea\u7136',
      '\u5c71',
      '\u8349\u539f',
      '\u68ee\u6797',
      '\u96ea\u666f',
    ],
    prototypePrompt:
        'a photo of nature mountains forest snow or outdoor scenery',
    shortPrompts: <String>[
      'a photo of natural scenery',
      'a photo of mountains forest or outdoor landscape',
    ],
  ),
  _CoarseSeed(
    id: 'city_street',
    labelZh: '\u57ce\u5e02\u8857\u666f',
    labelEn: 'city street',
    aliases: <String>[
      '\u57ce\u5e02',
      '\u8857\u666f',
      '\u8857\u9053',
      '\u9ad8\u697c',
      '\u5efa\u7b51',
      '\u90fd\u5e02',
    ],
    prototypePrompt:
        'a photo of city streets tall buildings road or urban landscape',
    shortPrompts: <String>[
      'a photo of a city street',
      'a photo of tall buildings road or urban landscape',
    ],
  ),
  _CoarseSeed(
    id: 'travel_landmark',
    labelZh: '\u65c5\u884c\u5730\u6807',
    labelEn: 'travel landmark',
    aliases: <String>[
      '\u65c5\u884c',
      '\u65c5\u6e38',
      '\u666f\u70b9',
      '\u5730\u6807',
    ],
    prototypePrompt: 'a photo of travel landmarks attractions or sightseeing',
    shortPrompts: <String>[
      'a travel photo of a landmark',
      'a sightseeing photo at a famous place',
    ],
  ),
  _CoarseSeed(
    id: 'beach_water',
    labelZh: '\u6d77\u8fb9\u6c34\u57df',
    labelEn: 'beach and water',
    aliases: <String>[
      '\u6d77',
      '\u6d77\u8fb9',
      '\u6d77\u6ee9',
      '\u6e56',
      '\u6c5f',
      '\u6cb3',
      '\u6c34\u8fb9',
    ],
    prototypePrompt:
        'a photo of beach sea ocean river lake or waterside scenery',
    shortPrompts: <String>[
      'a photo of the beach or seaside',
      'a photo of river lake or water scenery',
    ],
  ),
  _CoarseSeed(
    id: 'sky_sunset',
    labelZh: '\u5929\u7a7a\u65e5\u843d',
    labelEn: 'sky and sunset',
    aliases: <String>[
      '\u5929\u7a7a',
      '\u4e91',
      '\u665a\u971e',
      '\u5915\u9633',
      '\u65e5\u843d',
    ],
    prototypePrompt:
        'a photo of the sky clouds sunset dusk or colorful evening light',
    shortPrompts: <String>[
      'a photo of the sky and clouds',
      'a photo of sunset or evening glow',
    ],
  ),
  _CoarseSeed(
    id: 'festival_celebration',
    labelZh: '\u8282\u65e5\u5e86\u5178',
    labelEn: 'festival celebration',
    aliases: <String>[
      '\u8282\u65e5',
      '\u6625\u8282',
      '\u8fc7\u5e74',
      '\u751f\u65e5',
      '\u70df\u82b1',
    ],
    prototypePrompt:
        'a photo of celebrations festival reunion birthday wedding or fireworks',
    shortPrompts: <String>[
      'a photo of a festival celebration',
      'a reunion or holiday celebration photo',
    ],
  ),
  _CoarseSeed(
    id: 'document_screenshot',
    labelZh: '\u6587\u6863\u622a\u56fe',
    labelEn: 'document screenshot',
    aliases: <String>[
      '\u6587\u6863',
      '\u622a\u56fe',
      '\u8bfe\u4ef6',
      '\u5c4f\u5e55',
      '\u8d44\u6599',
    ],
    prototypePrompt:
        'a screenshot or photo of documents slides notes or text-heavy pages',
    shortPrompts: <String>[
      'a screenshot of a document or slides',
      'a photo of text-heavy notes or study materials',
    ],
  ),
  _CoarseSeed(
    id: 'screen_code',
    labelZh: '\u5c4f\u5e55\u4ee3\u7801',
    labelEn: 'screen code',
    aliases: <String>[
      '\u4ee3\u7801',
      '\u7f16\u7a0b',
      '\u7ec8\u7aef',
      '\u63a7\u5236\u53f0',
      'IDE',
    ],
    prototypePrompt:
        'a screenshot of code terminal development tools or software interface',
    shortPrompts: <String>[
      'a screenshot of code or IDE',
      'a screenshot of terminal or software interface',
    ],
  ),
  _CoarseSeed(
    id: 'medical_related',
    labelZh: '\u533b\u7597\u76f8\u5173',
    labelEn: 'medical related',
    aliases: <String>[
      '\u533b\u9662',
      '\u533b\u751f',
      '\u75c5\u623f',
      '\u4f53\u68c0',
      '\u836f',
    ],
    prototypePrompt:
        'a photo related to hospital clinic medicine or medical scenes',
    shortPrompts: <String>[
      'a photo at a hospital or clinic',
      'a medical related photo',
    ],
  ),
];

final Map<String, _CoarseSeed> _coarseIdToSeed = <String, _CoarseSeed>{
  for (final item in _coarseSeeds) item.id: item,
};
