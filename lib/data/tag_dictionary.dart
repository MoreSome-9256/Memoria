/// MobileCLIP 专属高维语义映射字典 (Memoria Master Taxonomy)
///
/// 源数据统一使用：中文标签 -> 英文 Prompt。
/// 需要喂给语义服务时请使用 [memoriaMasterTaxonomyPromptToLabel]。
const Map<String, String> memoriaMasterTaxonomy = {
  // 人物与群体 (People & Portraits)
  '人物': 'a photo of people, portraits, selfies, couples, families or group memories',

  // 物体与特写 (Objects & Close-ups)
  '美食饮品': 'a delicious close-up photo of food, meal, dessert, coffee or drink in a restaurant',
  '宠物': 'a photo of a cute pet, dog, cat, or animal',
  '花卉/植物': 'a photo of beautiful flowers, leaves, trees or vibrant indoor plants',
  '交通工具': 'a photo of a vehicle, car, bus, train, bicycle, motorcycle or airplane',
  '数码/电子产品': 'a photo of gadgets, smartphone, computer screen, camera or electronics',
  '手工': 'a photo of a handmade craft, diy project or handicraft item',

  // 场景与环境 (Scenes & Environments)
  '自然风光': 'a beautiful nature landscape photo, mountains, lakes, or green forests',
  '城市街景': 'a photo of a city street, tall buildings, road or urban landscape',
  '旅游景点': 'a photo of a famous tourist attraction, historic site, monument or scenic spot',
  '演出/表演': 'a photo of a stage performance, concert, exhibition, museum or theater',
  '运动/户外活动': 'a photo of people playing sports, gym, running, or doing outdoor activities',
  '海滩/水景': 'a photo of a beautiful beach, ocean, sea, river or water landscape',
  '天空/晚霞': 'a photo of a beautiful sky, sunset, sunrise, clouds or night sky with stars',

  // 文档与二次元 (Screenshots & Virtual)
  '文档截图': 'a screenshot of a text document, article, chat message, email or webpage',
  '屏幕/代码': 'a screenshot of a computer screen, software interface, programming code or IDE',
  '二次元/动漫': 'an anime style illustration, manga, virtual vtuber or cartoon drawing',
  '表情包/梗图': 'a meme, funny image with text, emoji or internet sticker',
  '海报/图表': 'a photo or screenshot of a chart, graph, slide presentation or graphic design poster',
};

/// 语义匹配服务使用的映射：英文 Prompt -> 中文标签。
final Map<String, String> memoriaMasterTaxonomyPromptToLabel =
    memoriaMasterTaxonomy.map(
      (label, prompt) => MapEntry(prompt, label),
    );

/// 搜索页候选标签可直接使用该列表。
final List<String> memoriaMasterLabels =
    List<String>.unmodifiable(memoriaMasterTaxonomy.keys);
