/// Memoria v2 标签库
///
/// 设计目标：
/// 1. 在不修改旧 `tag_dictionary.dart` 的前提下，提供一套更完整的新标签库。
/// 2. 主体维度显著扩容，目标约 100 个，尽量覆盖常见生活相册与世界场景。
/// 3. 维度仍保持克制，避免打标阶段过度复杂：
///    - `subject`：主体是什么
///    - `scene`：发生在哪里
///    - `activity`：正在做什么
///    - `atmosphere`：整体氛围怎样
///    - `media`：图片媒介类型
/// 4. 本文件只定义标签与语义 prompt，不实现“按维度限流”“多标签裁剪”等策略。
library;

enum MemoriaTagDimension {
  subject,
  scene,
  activity,
  atmosphere,
  media,
}

class MemoriaTagDefinition {
  const MemoriaTagDefinition({
    required this.label,
    required this.primaryDimension,
    required this.prompts,
    this.secondaryDimensions = const <MemoriaTagDimension>[],
    this.notes = '',
  });

  final String label;
  final MemoriaTagDimension primaryDimension;
  final List<MemoriaTagDimension> secondaryDimensions;
  final List<String> prompts;
  final String notes;
}

class MemoriaCoarseTagDefinition {
  const MemoriaCoarseTagDefinition({
    required this.id,
    required this.label,
    required this.prompts,
    this.notes = '',
  });

  final String id;
  final String label;
  final List<String> prompts;
  final String notes;
}

const int memoriaCoarseTopK = 2;
const int memoriaFineTopK = 3;
const String memoriaOtherCoarseId = 'other';
const String memoriaOtherLabel = '其他';

const List<MemoriaTagDefinition> memoriaMasterTagDefinitions = <MemoriaTagDefinition>[
  // ---------------------------------------------------------------------------
  // 主体维度 Subject
  //
  // 这里是本次扩充的重点。粒度控制原则：
  // - 优先覆盖“看见什么”，不深入到过细品类
  // - 同一大类下保留少量高频子类，便于搜索和聚类增强
  // - 尽量兼顾人物、动物、食物、物品、交通、建筑、自然元素
  // ---------------------------------------------------------------------------

  // 人物与肖像
  MemoriaTagDefinition(
    label: '人物',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a photo focused on one person', 'a single person portrait'],
    notes: '通用单人主体。',
  ),
  MemoriaTagDefinition(
    label: '老人',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['an elderly person in a photo', 'an old man or old woman portrait'],
    notes: '老年人物主体。',
  ),
  MemoriaTagDefinition(
    label: '儿童',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a child in daily life', 'children in a photo'],
    notes: '儿童主体。',
  ),
  MemoriaTagDefinition(
    label: '婴儿',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a baby or infant in a photo', 'a toddler close-up'],
    notes: '婴幼儿主体。',
  ),
  MemoriaTagDefinition(
    label: '自拍',
    primaryDimension: MemoriaTagDimension.subject,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.media],
    prompts: <String>['a selfie photo', 'a front camera self portrait'],
    notes: '手机自拍、对镜自拍。',
  ),
  MemoriaTagDefinition(
    label: '情侣',
    primaryDimension: MemoriaTagDimension.subject,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.atmosphere],
    prompts: <String>['a couple in a photo', 'two lovers posing together'],
    notes: '情侣、伴侣双人照。',
  ),
  MemoriaTagDefinition(
    label: '合影',
    primaryDimension: MemoriaTagDimension.subject,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.activity],
    prompts: <String>['a group photo', 'multiple people posing together'],
    notes: '多人合照。',
  ),
  MemoriaTagDefinition(
    label: '家庭亲子',
    primaryDimension: MemoriaTagDimension.subject,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.atmosphere],
    prompts: <String>['a family photo with parents and children', 'family daily life together'],
    notes: '家庭成员、亲子互动。',
  ),
  MemoriaTagDefinition(
    label: '婚礼人物',
    primaryDimension: MemoriaTagDimension.subject,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.activity],
    prompts: <String>['bride groom or wedding people', 'people at a wedding ceremony'],
    notes: '婚礼、新娘新郎、婚礼宾客。',
  ),
  MemoriaTagDefinition(
    label: '毕业人像',
    primaryDimension: MemoriaTagDimension.subject,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.activity],
    prompts: <String>['graduation portrait with gown or cap', 'students celebrating graduation'],
    notes: '毕业照、学位服。',
  ),
  MemoriaTagDefinition(
    label: '学生',
    primaryDimension: MemoriaTagDimension.subject,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.scene],
    prompts: <String>['a student in school life', 'young student in classroom or campus'],
    notes: '学生主体。',
  ),

  // 动物
  MemoriaTagDefinition(
    label: '宠物',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a pet in daily life', 'a domestic pet animal'],
    notes: '通用宠物主体。',
  ),
  MemoriaTagDefinition(
    label: '猫',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a cat in a photo', 'a domestic cat close-up'],
    notes: '猫咪主体。',
  ),
  MemoriaTagDefinition(
    label: '狗',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a dog in a photo', 'a domestic dog close-up'],
    notes: '狗狗主体。',
  ),
  MemoriaTagDefinition(
    label: '鸟类',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a bird in a photo', 'birds perched or flying'],
    notes: '鸟、鸽子、鹦鹉等。',
  ),
  MemoriaTagDefinition(
    label: '鱼类水族',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['fish or aquarium animals', 'aquatic fish in water or tank'],
    notes: '鱼、观赏鱼、水族箱。',
  ),
  MemoriaTagDefinition(
    label: '家禽',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['chicken duck goose or other poultry', 'domestic birds in a yard'],
    notes: '鸡鸭鹅等家禽。',
  ),
  MemoriaTagDefinition(
    label: '昆虫',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['an insect close-up', 'butterfly bee dragonfly or bug'],
    notes: '蝴蝶、蜜蜂、蜻蜓等小型昆虫。',
  ),
  MemoriaTagDefinition(
    label: '海洋生物',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['marine animals like dolphin whale jellyfish or coral life', 'sea creatures underwater'],
    notes: '海豚、海龟、水母、珊瑚生态等。',
  ),

  // 食物与饮品
  MemoriaTagDefinition(
    label: '美食',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['delicious food on a table', 'close-up food photography'],
    notes: '通用美食大类。',
  ),
  MemoriaTagDefinition(
    label: '火锅烧烤',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['hotpot barbecue or grilled food', 'people eating hotpot or barbecue'],
    notes: '火锅、烧烤、烤盘。',
  ),
  MemoriaTagDefinition(
    label: '海鲜',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['seafood dishes such as shrimp crab fish', 'a plate of seafood'],
    notes: '鱼虾蟹贝类菜品。',
  ),
  MemoriaTagDefinition(
    label: '水果',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['fresh fruits in a photo', 'fruit platter or fruit close-up'],
    notes: '水果拼盘、果篮、单个水果。',
  ),
  MemoriaTagDefinition(
    label: '蔬菜',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['vegetables salad or greens on a plate', 'fresh vegetables in a photo'],
    notes: '蔬菜、沙拉、轻食配菜。',
  ),
  MemoriaTagDefinition(
    label: '甜点',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['dessert sweets pudding or ice cream', 'a dessert on a plate'],
    notes: '甜品大类。',
  ),
  MemoriaTagDefinition(
    label: '咖啡茶饮',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['coffee tea latte milk tea or cafe drink', 'a cup of coffee or tea'],
    notes: '咖啡、奶茶、茶饮。',
  ),
  MemoriaTagDefinition(
    label: '酒水饮料',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['wine beer cocktail soft drink or bottled beverage', 'drinks in bottles or glasses'],
    notes: '酒水、气泡饮料、瓶装饮品。',
  ),
  MemoriaTagDefinition(
    label: '零食小吃',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['snacks street food or finger food', 'small bites or packaged snacks'],
    notes: '零食、街边小吃。',
  ),

  // 植物与自然物
  MemoriaTagDefinition(
    label: '花卉',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['flowers in bloom', 'a bouquet or close-up flower photo'],
    notes: '鲜花、花束、花海局部。',
  ),
  MemoriaTagDefinition(
    label: '绿植盆栽',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['potted green plants indoors', 'houseplants in pots'],
    notes: '盆栽、室内绿植。',
  ),
  MemoriaTagDefinition(
    label: '树木森林',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['trees woods or forest scenery', 'a photo focused on trees'],
    notes: '树木主体。',
  ),
  MemoriaTagDefinition(
    label: '草地田野',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['grassland meadow or field', 'open green field in nature'],
    notes: '草坪、草原、田野。',
  ),
  MemoriaTagDefinition(
    label: '农作物',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['crops in farmland such as wheat corn rice', 'agricultural plants in a field'],
    notes: '农田、庄稼、作物。',
  ),
  MemoriaTagDefinition(
    label: '山石岩壁',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['rocks cliffs or stone wall in nature', 'mountain rocks and rocky surface'],
    notes: '岩石、石壁、石块主体。',
  ),
  MemoriaTagDefinition(
    label: '沙滩',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['sandy beach close to the sea', 'beach sand and shoreline'],
    notes: '沙滩本体。',
  ),
  MemoriaTagDefinition(
    label: '雪景冰面',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['snow covered ground or icy surface', 'winter snow and ice scenery'],
    notes: '雪地、冰面、霜冻。',
  ),
  MemoriaTagDefinition(
    label: '云朵天空',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['sky with clouds as the main subject', 'cloudscape in the sky'],
    notes: '天空与云层主体。',
  ),
  MemoriaTagDefinition(
    label: '日出日落',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['sunrise or sunset in the sky', 'golden hour sun near horizon'],
    notes: '朝霞、晚霞、日出日落。',
  ),
  MemoriaTagDefinition(
    label: '星空月亮',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['night sky with stars or moon', 'moon and starry sky photo'],
    notes: '夜空、月亮、星轨、星空。',
  ),
  MemoriaTagDefinition(
    label: '河流湖泊',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a river lake or stream as main subject', 'freshwater scenery with water'],
    notes: '河流、湖泊、溪流。',
  ),
  MemoriaTagDefinition(
    label: '大海',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['the sea ocean or waves as main subject', 'open ocean and coastline'],
    notes: '海洋、水面、海浪。',
  ),
  MemoriaTagDefinition(
    label: '高山',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['high mountains and peaks as the main subject', 'mountain ridges and peaks'],
    notes: '高山、雪山、山峰。',
  ),

  // 家居、日常物品、消费物
  MemoriaTagDefinition(
    label: '家具',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['furniture in a room', 'chairs tables beds or cabinets'],
    notes: '通用家具大类。',
  ),
  MemoriaTagDefinition(
    label: '桌椅书桌',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['desks tables and chairs', 'a table or desk setup'],
    notes: '桌子、书桌、椅子。',
  ),
  MemoriaTagDefinition(
    label: '灯具装饰',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['lamps lights or decorative objects', 'indoor lighting and decor'],
    notes: '台灯、吊灯、摆件、装饰。',
  ),
  MemoriaTagDefinition(
    label: '厨房用品',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['kitchen tools and utensils', 'kitchen supplies on a counter'],
    notes: '锅具、砧板、厨房杂物。',
  ),
  MemoriaTagDefinition(
    label: '餐具厨具',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['tableware or cookware', 'plates bowls spoons pots pans'],
    notes: '盘碗杯、锅铲、厨具。',
  ),
  MemoriaTagDefinition(
    label: '家电',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['home appliances in a room', 'appliances such as fridge washer or oven'],
    notes: '家用电器。',
  ),
  MemoriaTagDefinition(
    label: '数码设备',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['digital gadgets and electronics', 'consumer electronics device'],
    notes: '电子设备大类。',
  ),
  MemoriaTagDefinition(
    label: '书籍杂志',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['books magazines or printed reading materials', 'stack of books or open book'],
    notes: '书籍、刊物、杂志。',
  ),
  MemoriaTagDefinition(
    label: '文具',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['stationery notebook journal or planner', 'pens notebooks and paper supplies'],
    notes: '笔、本子、手账本。',
  ),
  MemoriaTagDefinition(
    label: '玩具玩偶',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['toys dolls stuffed animals or figurines', 'a toy or doll close-up'],
    notes: '玩具、玩偶、手办。',
  ),
  MemoriaTagDefinition(
    label: '箱包鞋帽',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['bags shoes hats or luggage', 'fashion accessories like bag and shoes'],
    notes: '包、鞋、帽、行李箱。',
  ),
  MemoriaTagDefinition(
    label: '服饰',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['clothing outfit or apparel display', 'fashion clothing worn by a person'],
    notes: '衣服、穿搭、服装主体。',
  ),
  MemoriaTagDefinition(
    label: '珠宝饰品',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['jewelry watch ring necklace or accessories', 'ornaments and personal accessories'],
    notes: '首饰、手表、项链、耳饰。',
  ),
  MemoriaTagDefinition(
    label: '化妆护肤',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['cosmetics makeup or skincare products', 'beauty products on a table'],
    notes: '护肤品、化妆品。',
  ),
  MemoriaTagDefinition(
    label: '包裹快递',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['package parcel delivery box', 'shipping parcels or cardboard boxes'],
    notes: '快递盒、包裹。',
  ),
  MemoriaTagDefinition(
    label: '节日装饰',
    primaryDimension: MemoriaTagDimension.subject,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.scene],
    prompts: <String>[
      'festive decorations such as lanterns banners red ornaments or celebration decor',
      'holiday decorations in indoor or outdoor space',
    ],
    notes: '灯笼、彩带、横幅、圣诞树、红色装饰等节庆布置。',
  ),
  MemoriaTagDefinition(
    label: '烟花焰火',
    primaryDimension: MemoriaTagDimension.subject,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.scene],
    prompts: <String>[
      'fireworks in the night sky during a celebration',
      'festival fireworks and bright sparks at night',
    ],
    notes: '烟花、焰火、礼花表演。',
  ),
  MemoriaTagDefinition(
    label: '工具机械',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['tools machinery or hardware equipment', 'industrial tools and mechanical parts'],
    notes: '工具箱、扳手、电钻、机械结构。',
  ),
  MemoriaTagDefinition(
    label: '乐器',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['musical instruments in a photo', 'an instrument on stage or in a room'],
    notes: '通用乐器大类。',
  ),
  MemoriaTagDefinition(
    label: '钢琴',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a piano or keyboard instrument', 'piano keys close-up'],
    notes: '钢琴、电子琴。',
  ),
  MemoriaTagDefinition(
    label: '吉他',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['guitar violin cello or string instrument', 'a string instrument in a photo'],
    notes: '吉他、小提琴、大提琴等。',
  ),
  MemoriaTagDefinition(
    label: '鼓类打击乐',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['drums or percussion instruments', 'drum set on a stage'],
    notes: '鼓、打击乐器。',
  ),
  MemoriaTagDefinition(
    label: '管乐器',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['saxophone trumpet flute or wind instrument', 'a wind instrument performance'],
    notes: '萨克斯、长笛、小号等。',
  ),
  MemoriaTagDefinition(
    label: '艺术品',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['artwork sculpture or decorative figurine', 'an art object on display'],
    notes: '装饰画、雕像、小摆件。',
  ),
  MemoriaTagDefinition(
    label: '手工',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>[
      'a handmade craft or diy project',
      'handicraft materials, knitting, clay, origami or handmade work',
    ],
    notes: '手作、DIY、编织、黏土、折纸等。',
  ),

  // 交通
  MemoriaTagDefinition(
    label: '交通工具',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['vehicles in a photo', 'transportation object'],
    notes: '交通工具大类。',
  ),
  MemoriaTagDefinition(
    label: '汽车',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a car in a photo', 'sedan suv or automobile'],
    notes: '小汽车、SUV。',
  ),
  MemoriaTagDefinition(
    label: '自行车电动车',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a bicycle or electric bike', 'two-wheeled bike vehicle'],
    notes: '自行车、电瓶车。',
  ),
  MemoriaTagDefinition(
    label: '摩托车',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a motorcycle or scooter', 'motorbike in a photo'],
    notes: '摩托、机车。',
  ),
  MemoriaTagDefinition(
    label: '公交地铁',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a bus or subway train', 'public transportation vehicle'],
    notes: '公交车、地铁车厢。',
  ),
  MemoriaTagDefinition(
    label: '火车高铁',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a train or high-speed rail', 'railway train on tracks or station'],
    notes: '列车、高铁。',
  ),
  MemoriaTagDefinition(
    label: '飞机',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['an airplane or aircraft', 'a plane on runway or in sky'],
    notes: '飞机主体。',
  ),
  MemoriaTagDefinition(
    label: '船只',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a boat ship or ferry', 'watercraft on sea or river'],
    notes: '船、游艇、渡轮。',
  ),

  // 建筑与场馆
  MemoriaTagDefinition(
    label: '建筑',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a building or architecture as main subject', 'architectural structure in a photo'],
    notes: '建筑总类。',
  ),
  MemoriaTagDefinition(
    label: '住宅民居',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['a house apartment or residential building', 'homes and residential architecture'],
    notes: '民居、住宅、居民楼。',
  ),
  MemoriaTagDefinition(
    label: '商场店铺',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['shopping mall storefront or retail shop', 'commercial store interior or facade'],
    notes: '商场、店铺、商店门头。',
  ),
  MemoriaTagDefinition(
    label: '餐厅咖啡馆',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['restaurant cafe or dining interior', 'a cafe or restaurant scene as place subject'],
    notes: '餐馆、咖啡馆、酒吧室内。',
  ),
  MemoriaTagDefinition(
    label: '学校建筑',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['school building classroom or teaching block', 'campus buildings and school facilities'],
    notes: '教学楼、教室、校园建筑。',
  ),
  MemoriaTagDefinition(
    label: '办公楼宇',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['office building corporate interior or workspace building', 'commercial office architecture'],
    notes: '写字楼、办公室场馆。',
  ),
  MemoriaTagDefinition(
    label: '医院场馆',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['hospital clinic or medical facility', 'medical building or healthcare space'],
    notes: '医院、诊所、医疗空间。',
  ),
  MemoriaTagDefinition(
    label: '酒店旅馆',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['hotel room lobby or guesthouse', 'hotel or homestay interior'],
    notes: '酒店、民宿、旅馆。',
  ),
  MemoriaTagDefinition(
    label: '寺庙',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['temple shrine old building or traditional architecture', 'ancient architecture in a scenic area'],
    notes: '寺庙、古建、传统建筑。',
  ),
  MemoriaTagDefinition(
    label: '桥梁',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['bridge road highway or overpass', 'transport infrastructure like bridge or road'],
    notes: '桥梁、道路、高架。',
  ),
  MemoriaTagDefinition(
    label: '塔楼城堡',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['tower castle pagoda or landmark vertical building', 'castle or tower structure'],
    notes: '塔、城堡、钟楼、宝塔。',
  ),
  MemoriaTagDefinition(
    label: '雕塑',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['statue monument memorial sculpture', 'public sculpture or memorial landmark'],
    notes: '雕塑、纪念碑、纪念性建筑。',
  ),
  MemoriaTagDefinition(
    label: '游乐设施',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['roller coaster ferris wheel carousel or amusement rides', 'theme park ride as main subject'],
    notes: '摩天轮、过山车、旋转木马等。',
  ),
  MemoriaTagDefinition(
    label: '体育设施',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['stadium court track field or sports facility', 'sports venue and athletic infrastructure'],
    notes: '球场、跑道、体育馆。',
  ),
  MemoriaTagDefinition(
    label: '舞台设备',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['stage lighting speakers screens and performance equipment', 'concert stage setup'],
    notes: '舞台灯光、音响、大屏设备。',
  ),

  // 商业、工作与公共空间里的常见主体
  MemoriaTagDefinition(
    label: '展柜商品',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['products displayed in a showcase', 'retail items on shelves or display'],
    notes: '货架商品、展柜陈列。',
  ),
  MemoriaTagDefinition(
    label: '办公工位',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['office desk workspace with monitor keyboard and chair', 'workstation setup in office'],
    notes: '办公桌、工位、桌面空间。',
  ),
  MemoriaTagDefinition(
    label: '药品药盒',
    primaryDimension: MemoriaTagDimension.subject,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.media],
    prompts: <String>[
      'medicine boxes pills blister packs or pharmaceutical products',
      'drugs tablets capsules and medicine packaging on a table',
    ],
    notes: '药盒、药板、药瓶、胶囊等。',
  ),
  MemoriaTagDefinition(
    label: '医疗器械',
    primaryDimension: MemoriaTagDimension.subject,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.scene],
    prompts: <String>[
      'medical equipment devices or healthcare instruments',
      'hospital tools such as monitor scanner wheelchair or treatment device',
    ],
    notes: '检测设备、轮椅、监护仪、诊疗器械等。',
  ),
  MemoriaTagDefinition(
    label: '黑板白板',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['blackboard whiteboard with writing', 'teaching board in classroom or office'],
    notes: '黑板、白板、板书区域。',
  ),
  MemoriaTagDefinition(
    label: '讲台教室',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['classroom podium desks and teaching room', 'a classroom interior as main subject'],
    notes: '教室空间与讲台。',
  ),
  MemoriaTagDefinition(
    label: '厨房餐桌',
    primaryDimension: MemoriaTagDimension.subject,
    prompts: <String>['kitchen counter dining table and home dining area', 'kitchen and dining setup'],
    notes: '厨房台面、餐桌场景主体。',
  ),

  // ---------------------------------------------------------------------------
  // 场景维度 Scene
  // ---------------------------------------------------------------------------
  MemoriaTagDefinition(
    label: '风景',
    primaryDimension: MemoriaTagDimension.scene,
    prompts: <String>['a scenic landscape photo', 'wide natural scenery'],
    notes: '宽泛风景大类。',
  ),
  MemoriaTagDefinition(
    label: '城市街景',
    primaryDimension: MemoriaTagDimension.scene,
    prompts: <String>['an urban street scene', 'city roads and buildings'],
    notes: '城市户外环境。',
  ),
  MemoriaTagDefinition(
    label: '乡村田园',
    primaryDimension: MemoriaTagDimension.scene,
    prompts: <String>['rural countryside scenery', 'village and farmland landscape'],
    notes: '乡村、村落、田园。',
  ),
  MemoriaTagDefinition(
    label: '室内空间',
    primaryDimension: MemoriaTagDimension.scene,
    prompts: <String>['an indoor interior scene', 'inside a room or building'],
    notes: '室内环境总类。',
  ),
  MemoriaTagDefinition(
    label: '校园',
    primaryDimension: MemoriaTagDimension.scene,
    prompts: <String>['a school or university campus scene', 'students in campus environment'],
    notes: '校园环境。',
  ),
  MemoriaTagDefinition(
    label: '公园乐园',
    primaryDimension: MemoriaTagDimension.scene,
    prompts: <String>['a park or amusement park scene', 'outdoor leisure place with rides or greenery'],
    notes: '公园、乐园。',
  ),
  MemoriaTagDefinition(
    label: '舞台演出',
    primaryDimension: MemoriaTagDimension.scene,
    prompts: <String>['a concert stage or theater performance scene', 'stage performance environment'],
    notes: '舞台/演出现场。',
  ),
  MemoriaTagDefinition(
    label: '海边水景',
    primaryDimension: MemoriaTagDimension.scene,
    prompts: <String>['a sea or water landscape scene', 'beach coast river or lake scenery'],
    notes: '海边、水边、大面积水景。',
  ),
  MemoriaTagDefinition(
    label: '山林户外',
    primaryDimension: MemoriaTagDimension.scene,
    prompts: <String>['mountain forest or outdoor wilderness scene', 'nature outdoors with hills and trees'],
    notes: '山林野外场景。',
  ),
  MemoriaTagDefinition(
    label: '夜景',
    primaryDimension: MemoriaTagDimension.scene,
    prompts: <String>['night city or night outdoor scene', 'dark scene with lights at night'],
    notes: '夜间环境。',
  ),
  MemoriaTagDefinition(
    label: '庆典现场',
    primaryDimension: MemoriaTagDimension.scene,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.atmosphere],
    prompts: <String>[
      'festival event scene with crowd decorations and celebration setup',
      'holiday or ceremony venue filled with festive atmosphere',
    ],
    notes: '节庆、典礼、庆典活动现场。',
  ),
  MemoriaTagDefinition(
    label: '医疗场景',
    primaryDimension: MemoriaTagDimension.scene,
    prompts: <String>[
      'hospital ward clinic waiting room pharmacy or healthcare scene',
      'medical environment in hospital or clinic',
    ],
    notes: '医院病房、门诊、候诊区、药房等医疗场景。',
  ),

  // ---------------------------------------------------------------------------
  // 活动维度 Activity
  // ---------------------------------------------------------------------------
  MemoriaTagDefinition(
    label: '运动',
    primaryDimension: MemoriaTagDimension.activity,
    prompts: <String>['sports and exercise in action', 'people playing sports'],
    notes: '运动活动。',
  ),
  MemoriaTagDefinition(
    label: '旅行',
    primaryDimension: MemoriaTagDimension.activity,
    prompts: <String>['travel and sightseeing moments', 'tourism during a trip'],
    notes: '旅行活动。',
  ),
  MemoriaTagDefinition(
    label: '聚餐',
    primaryDimension: MemoriaTagDimension.activity,
    prompts: <String>['people dining together', 'meal gathering with friends or family'],
    notes: '聚餐、饭局。',
  ),
  MemoriaTagDefinition(
    label: '学习工作',
    primaryDimension: MemoriaTagDimension.activity,
    prompts: <String>['studying or office work', 'learning or working at a desk'],
    notes: '学习、办公、写作。',
  ),
  MemoriaTagDefinition(
    label: '表演演奏',
    primaryDimension: MemoriaTagDimension.activity,
    prompts: <String>['performing music dance or stage show', 'a live performance activity'],
    notes: '演出、演奏、舞蹈。',
  ),
  MemoriaTagDefinition(
    label: '露营休闲',
    primaryDimension: MemoriaTagDimension.activity,
    prompts: <String>['camping picnic or outdoor leisure', 'relaxing outdoors in a camp or picnic'],
    notes: '露营、野餐、休闲。',
  ),
  MemoriaTagDefinition(
    label: '生日庆生',
    primaryDimension: MemoriaTagDimension.activity,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.atmosphere],
    prompts: <String>[
      'birthday celebration with cake candles gifts and people',
      'birthday party or blowing candles moment',
    ],
    notes: '生日、蛋糕、蜡烛、庆生画面。',
  ),
  MemoriaTagDefinition(
    label: '节庆仪式',
    primaryDimension: MemoriaTagDimension.activity,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.atmosphere],
    prompts: <String>[
      'festival ritual parade ceremony or traditional celebration activity',
      'people joining a festive or ceremonial event',
    ],
    notes: '节日仪式、巡游、庆典流程、传统民俗活动。',
  ),
  MemoriaTagDefinition(
    label: '就诊检查',
    primaryDimension: MemoriaTagDimension.activity,
    secondaryDimensions: <MemoriaTagDimension>[MemoriaTagDimension.scene],
    prompts: <String>[
      'medical consultation examination treatment or hospital visit',
      'seeing a doctor, receiving treatment or doing a medical check',
    ],
    notes: '就医、检查、诊疗、输液等过程。',
  ),

  // ---------------------------------------------------------------------------
  // 氛围维度 Atmosphere
  // ---------------------------------------------------------------------------
  MemoriaTagDefinition(
    label: '热闹',
    primaryDimension: MemoriaTagDimension.atmosphere,
    prompts: <String>['a lively and crowded atmosphere', 'busy energetic social environment'],
    notes: '人多、热闹。',
  ),
  MemoriaTagDefinition(
    label: '冷清',
    primaryDimension: MemoriaTagDimension.atmosphere,
    prompts: <String>['a quiet sparse empty atmosphere', 'an uncrowded lonely scene'],
    notes: '空、冷清。',
  ),
  MemoriaTagDefinition(
    label: '欢快',
    primaryDimension: MemoriaTagDimension.atmosphere,
    prompts: <String>['a cheerful joyful mood', 'smiling bright pleasant atmosphere'],
    notes: '积极、愉快。',
  ),
  MemoriaTagDefinition(
    label: '安静',
    primaryDimension: MemoriaTagDimension.atmosphere,
    prompts: <String>['a calm peaceful quiet mood', 'a still tranquil atmosphere'],
    notes: '安静、平和。',
  ),
  MemoriaTagDefinition(
    label: '温馨',
    primaryDimension: MemoriaTagDimension.atmosphere,
    prompts: <String>['a warm cozy intimate atmosphere', 'comforting family-like mood'],
    notes: '温暖、有陪伴感。',
  ),
  MemoriaTagDefinition(
    label: '单调',
    primaryDimension: MemoriaTagDimension.atmosphere,
    prompts: <String>['a plain monotonous visual mood', 'simple repetitive scene with little variation'],
    notes: '单一、平淡。',
  ),
  MemoriaTagDefinition(
    label: '浪漫',
    primaryDimension: MemoriaTagDimension.atmosphere,
    prompts: <String>['a romantic atmosphere', 'soft tender and romantic scene'],
    notes: '情侣、晚霞、鲜花等浪漫感。',
  ),
  MemoriaTagDefinition(
    label: '庄重',
    primaryDimension: MemoriaTagDimension.atmosphere,
    prompts: <String>['a formal solemn atmosphere', 'serious and ceremonial mood'],
    notes: '典礼、仪式、正式场合。',
  ),

  // ---------------------------------------------------------------------------
  // 媒介维度 Media
  // ---------------------------------------------------------------------------
  MemoriaTagDefinition(
    label: '文档',
    primaryDimension: MemoriaTagDimension.media,
    prompts: <String>['a printed or photographed document', 'text on paper or worksheet'],
    notes: '纸质文件、书页、试卷等。',
  ),
  MemoriaTagDefinition(
    label: '截屏',
    primaryDimension: MemoriaTagDimension.media,
    prompts: <String>['a mobile phone screenshot', 'a captured app screen image'],
    notes: '手机软件截屏。',
  ),
  MemoriaTagDefinition(
    label: '屏幕代码',
    primaryDimension: MemoriaTagDimension.media,
    prompts: <String>['a screenshot of code or IDE', 'source code on a computer screen'],
    notes: '代码、终端、IDE。',
  ),
  MemoriaTagDefinition(
    label: '海报图表',
    primaryDimension: MemoriaTagDimension.media,
    prompts: <String>['poster chart graph or infographic', 'slide and poster design'],
    notes: '海报、图表、PPT。',
  ),
  MemoriaTagDefinition(
    label: '身份证件',
    primaryDimension: MemoriaTagDimension.media,
    prompts: <String>[
      'identity document such as id card passport residence permit or certificate card',
      'official personal identification document in a photo',
    ],
    notes: '身份证、护照、驾驶证、社保卡等证件。',
  ),
  MemoriaTagDefinition(
    label: '收据小票',
    primaryDimension: MemoriaTagDimension.media,
    prompts: <String>[
      'shopping receipt cashier slip or printed purchase ticket',
      'small paper receipt with transaction text',
    ],
    notes: '超市小票、收据、消费凭条。',
  ),
  MemoriaTagDefinition(
    label: '发票账单',
    primaryDimension: MemoriaTagDimension.media,
    prompts: <String>[
      'invoice bill statement or expense form document',
      'printed invoice receipt or billing paper',
    ],
    notes: '发票、账单、费用单、对账单。',
  ),
  MemoriaTagDefinition(
    label: '病历报告',
    primaryDimension: MemoriaTagDimension.media,
    prompts: <String>[
      'medical record lab report prescription or diagnostic paper document',
      'hospital report sheet prescription or medical paperwork',
    ],
    notes: '处方单、病历、化验单、检查报告。',
  ),
  MemoriaTagDefinition(
    label: '动漫插画',
    primaryDimension: MemoriaTagDimension.media,
    prompts: <String>['anime illustration or cartoon drawing', 'stylized 2d artwork'],
    notes: '动漫、插画、卡通。',
  ),
  MemoriaTagDefinition(
    label: '表情包梗图',
    primaryDimension: MemoriaTagDimension.media,
    prompts: <String>['a meme or funny image with text', 'internet meme or sticker style image'],
    notes: '表情包、梗图。',
  ),
];

final Map<String, String> memoriaMasterTaxonomy = Map<String, String>.unmodifiable(
  <String, String>{
    for (final definition in memoriaMasterTagDefinitions)
      definition.label: definition.prompts.first,
  },
);

final Map<String, String> memoriaMasterTaxonomyPromptToLabel =
    Map<String, String>.unmodifiable(
      <String, String>{
        for (final definition in memoriaMasterTagDefinitions)
          for (final prompt in definition.prompts) prompt: definition.label,
      },
    );

final List<String> memoriaMasterLabels = List<String>.unmodifiable(
  memoriaMasterTagDefinitions.map((definition) => definition.label),
);

final Map<String, MemoriaTagDimension> memoriaMasterLabelToPrimaryDimension =
    Map<String, MemoriaTagDimension>.unmodifiable(
      <String, MemoriaTagDimension>{
        for (final definition in memoriaMasterTagDefinitions)
          definition.label: definition.primaryDimension,
      },
    );

final List<MemoriaTagDefinition> memoriaFineTagDefinitions =
    List<MemoriaTagDefinition>.unmodifiable(memoriaMasterTagDefinitions);

const List<MemoriaCoarseTagDefinition> memoriaCoarseTagDefinitions =
    <MemoriaCoarseTagDefinition>[
      MemoriaCoarseTagDefinition(
        id: 'people',
        label: '人物',
        prompts: <String>[
          'a photo of people, portraits, selfies, couples, families or group memories',
          'single or multiple people in daily life, celebration or commemorative photo',
        ],
        notes: '人物、自拍、合影、家庭照、儿童与纪念照片。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'food_drink',
        label: '美食饮品',
        prompts: <String>[
          'a delicious close-up photo of food meal dessert coffee or drink in a restaurant',
          'food and beverages on a table',
        ],
        notes: '食物、饮料、甜点、聚餐。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'pets_animals',
        label: '宠物/动物',
        prompts: <String>[
          'a photo of a cute pet dog cat or animal',
          'animals birds insects fish or marine life',
        ],
        notes: '宠物、鸟类、水族、昆虫、家禽等。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'flowers_plants',
        label: '花卉/植物',
        prompts: <String>[
          'a photo of beautiful flowers leaves trees or vibrant indoor plants',
          'plants flowers trees or crops as the main subject',
        ],
        notes: '花卉、盆栽、树木、草地、农作物。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'transportation',
        label: '交通工具',
        prompts: <String>[
          'a photo of a vehicle car bus train bicycle motorcycle or airplane',
          'transportation object or moving vehicle',
        ],
        notes: '车、船、飞机、轨道交通。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'digital_electronics',
        label: '数码/电子产品',
        prompts: <String>[
          'a photo of gadgets smartphone computer screen camera or electronics',
          'digital devices and home electronics',
        ],
        notes: '数码设备、消费电子、家电。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'fashion_style',
        label: '服饰穿搭',
        prompts: <String>[
          'fashion clothing bags shoes jewelry or beauty accessories',
          'outfit and fashion accessories display',
        ],
        notes: '衣服、鞋帽、珠宝配饰、美妆。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'life_objects',
        label: '生活物品',
        prompts: <String>[
          'books stationery toys parcels tools and daily objects',
          'everyday objects and household items on a table',
        ],
        notes: '书本文具、玩具、包裹、工具、厨具等。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'natural_landscape',
        label: '自然风光',
        prompts: <String>[
          'a beautiful nature landscape photo mountains lakes or green forests',
          'natural scenery mountains snow rocks and countryside',
        ],
        notes: '山林、乡野、雪景、岩石等自然场景。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'city_street',
        label: '城市街景',
        prompts: <String>[
          'a photo of a city street tall buildings road or urban landscape',
          'urban streets architecture bridges and night city',
        ],
        notes: '城市建筑、道路、街景、桥梁、夜景。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'travel_landmark',
        label: '旅游景点',
        prompts: <String>[
          'a photo of a famous tourist attraction historic site monument or scenic spot',
          'travel landmark ancient architecture or sightseeing place',
        ],
        notes: '寺庙、古建、雕塑、塔楼、景点、旅行打卡。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'performance_show',
        label: '演出/表演',
        prompts: <String>[
          'a photo of a stage performance concert exhibition museum or theater',
          'stage show performance music and instruments',
        ],
        notes: '舞台、演奏、表演、乐器。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'sports_outdoor',
        label: '运动/户外活动',
        prompts: <String>[
          'a photo of people playing sports gym running or doing outdoor activities',
          'sports leisure camping and outdoor action',
        ],
        notes: '运动、体育设施、露营、休闲户外。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'handcraft',
        label: '手工',
        prompts: <String>[
          'a photo of a handmade craft diy project or handicraft item',
          'handmade artwork, craft materials, knitting, clay or origami on a table',
        ],
        notes: '手作、DIY、编织、黏土、折纸等手工内容。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'beach_water',
        label: '海滩/水景',
        prompts: <String>[
          'a photo of a beautiful beach ocean sea river or water landscape',
          'beach shoreline river lake and water scene',
        ],
        notes: '海边、湖泊、河流、海滩、水面。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'sky_sunset',
        label: '天空/晚霞',
        prompts: <String>[
          'a photo of a beautiful sky sunset sunrise clouds or night sky with stars',
          'sky clouds moon stars and sunset scene',
        ],
        notes: '天空、云彩、晚霞、星空、月亮。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'document_screenshot',
        label: '文档截图',
        prompts: <String>[
          'a screenshot of a text document article chat message email or webpage',
          'text-heavy screenshot or photographed paper document',
        ],
        notes: '聊天截图、网页、文档、纸质文件。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'screen_code',
        label: '屏幕/代码',
        prompts: <String>[
          'a screenshot of a computer screen software interface programming code or IDE',
          'screen interface with code terminal or software tools',
        ],
        notes: 'IDE、终端、代码界面、软件面板。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'anime_cartoon',
        label: '二次元/动漫',
        prompts: <String>[
          'an anime style illustration manga virtual vtuber or cartoon drawing',
          'stylized anime artwork',
        ],
        notes: '动漫、插画、二次元。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'meme_sticker',
        label: '表情包/梗图',
        prompts: <String>[
          'a meme funny image with text emoji or internet sticker',
          'internet meme sticker or joke image',
        ],
        notes: '表情包、梗图、搞笑图片。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'poster_chart',
        label: '海报/图表',
        prompts: <String>[
          'a photo or screenshot of a chart graph slide presentation or graphic design poster',
          'poster infographic chart or slide content',
        ],
        notes: '海报、图表、PPT、信息图。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'festival_celebration',
        label: '节日/庆典',
        prompts: <String>[
          'a photo of holiday celebration festival decoration fireworks birthday party or ceremony',
          'festive event with decorations, ritual moments and celebration atmosphere',
        ],
        notes: '节日布置、庆典活动、生日、烟花、仪式现场。',
      ),
      MemoriaCoarseTagDefinition(
        id: 'medical_related',
        label: '医疗相关',
        prompts: <String>[
          'a photo of hospital clinic medicine medical report prescription',
          'medical visit treatment medicine packaging',
        ],
        notes: '医院场景、就诊检查、药品药盒、病历报告、医疗器械。',
      ),
      MemoriaCoarseTagDefinition(
        id: memoriaOtherCoarseId,
        label: memoriaOtherLabel,
        prompts: <String>[],
        notes: '当所有候选标签都低于阈值时的兜底分类。',
      ),
    ];

final Map<String, MemoriaCoarseTagDefinition> memoriaCoarseIdToDefinition =
    Map<String, MemoriaCoarseTagDefinition>.unmodifiable(
      <String, MemoriaCoarseTagDefinition>{
        for (final definition in memoriaCoarseTagDefinitions)
          definition.id: definition,
      },
    );

const Map<String, List<String>> memoriaCoarseIdToFineLabels =
    <String, List<String>>{
      'people': <String>[
        '人物',
        '自拍',
        '老人',
        '情侣',
        '合影',
        '家庭亲子',
        '婚礼人物',
        '毕业人像',
        '婴儿',
        '儿童',
        '学生',
      ],
      'food_drink': <String>[
        '美食',
        '火锅烧烤',
        '海鲜',
        '水果',
        '蔬菜',
        '甜点',
        '咖啡茶饮',
        '酒水饮料',
        '零食小吃',
        '聚餐',
      ],
      'pets_animals': <String>[
        '宠物',
        '猫',
        '狗',
        '鸟类',
        '鱼类水族',
        '家禽',
        '昆虫',
        '海洋生物',
      ],
      'flowers_plants': <String>[
        '花卉',
        '绿植盆栽',
        '树木森林',
        '草地田野',
        '农作物',
      ],
      'transportation': <String>[
        '交通工具',
        '汽车',
        '自行车电动车',
        '摩托车',
        '公交地铁',
        '火车高铁',
        '飞机',
        '船只',
      ],
      'digital_electronics': <String>[
        '数码设备',
        '家电',
      ],
      'fashion_style': <String>[
        '服饰',
        '箱包鞋帽',
        '珠宝饰品',
        '化妆护肤',
      ],
      'life_objects': <String>[
        '家具',
        '桌椅书桌',
        '灯具装饰',
        '厨房用品',
        '餐具厨具',
        '书籍杂志',
        '文具',
        '玩具玩偶',
        '包裹快递',
        '工具机械',
        '展柜商品',
      ],
      'natural_landscape': <String>[
        '山石岩壁',
        '雪景冰面',
        '高山',
        '风景',
        '乡村田园',
        '山林户外',
      ],
      'city_street': <String>[
        '建筑',
        '住宅民居',
        '商场店铺',
        '办公楼宇',
        '医院场馆',
        '桥梁',
        '城市街景',
        '夜景',
      ],
      'travel_landmark': <String>[
        '旅行',
        '寺庙',
        '塔楼城堡',
        '雕塑',
        '艺术品',
      ],
      'performance_show': <String>[
        '乐器',
        '钢琴',
        '吉他',
        '鼓类打击乐',
        '管乐器',
        '舞台设备',
        '舞台演出',
        '表演演奏',
      ],
      'sports_outdoor': <String>[
        '体育设施',
        '运动',
        '露营休闲',
      ],
      'handcraft': <String>[
        '手工',
      ],
      'beach_water': <String>[
        '沙滩',
        '河流湖泊',
        '大海',
        '海边水景',
      ],
      'sky_sunset': <String>[
        '云朵天空',
        '日出日落',
        '星空月亮',
      ],
      'document_screenshot': <String>[
        '文档',
        '截屏',
        '身份证件',
        '收据小票',
        '发票账单',
      ],
      'screen_code': <String>[
        '屏幕代码',
      ],
      'anime_cartoon': <String>[
        '动漫插画',
      ],
      'meme_sticker': <String>[
        '表情包梗图',
      ],
      'poster_chart': <String>[
        '海报图表',
      ],
      'festival_celebration': <String>[
        '节日装饰',
        '烟花焰火',
        '庆典现场',
        '生日庆生',
        '节庆仪式',
      ],
      'medical_related': <String>[
        '医院',
        '药品药盒',
      ],
      memoriaOtherCoarseId: <String>[
        memoriaOtherLabel,
      ],
    };

final Map<String, String> memoriaFineLabelToCoarseId =
    Map<String, String>.unmodifiable(
      <String, String>{
        for (final entry in memoriaCoarseIdToFineLabels.entries)
          for (final label in entry.value) label: entry.key,
      },
    );

final Map<String, String> memoriaLegacyCoarseLabelToCoarseId =
    Map<String, String>.unmodifiable(
      <String, String>{
        for (final definition in memoriaCoarseTagDefinitions)
          definition.label: definition.id,
      },
    );

final Map<String, String> memoriaAlbumTagLabelToCoarseId =
    Map<String, String>.unmodifiable(
      <String, String>{
        ...memoriaLegacyCoarseLabelToCoarseId,
        ...memoriaFineLabelToCoarseId,
      },
    );

final Map<String, List<MemoriaTagDefinition>> memoriaFineDefinitionsByCoarseId =
    Map<String, List<MemoriaTagDefinition>>.unmodifiable(
      <String, List<MemoriaTagDefinition>>{
        for (final definition in memoriaCoarseTagDefinitions)
          definition.id: List<MemoriaTagDefinition>.unmodifiable(
            memoriaMasterTagDefinitions.where(
              (tag) => memoriaFineLabelToCoarseId[tag.label] == definition.id,
            ),
          ),
      },
    );

