# 语义搜索方案 v2：LLM 解析驱动的分层检索设计

## 1. 目标

本方案的目标不是把自然语言查询直接粗暴映射成一个 embedding，而是先用 DeepSeek 把查询拆成“可执行的检索意图”，再按层次完成检索：

1. 时间过滤
2. 地点过滤
3. 粗标签收缩候选集
4. 正向语义加权
5. 负向语义惩罚
6. 最终排序与兜底放宽

这是一套“LLM 负责理解意图，检索系统负责稳定执行”的混合搜索方案。

## 2. 对当前思路的判断

### 2.1 结论

你的思路是正确的，而且在当前项目里是可行的。

原因有三点：

1. 项目已经具备实现这条链路所需的核心数据。
2. 你的方案天然把“强条件”和“软语义”区分开了。
3. 你的方案比“直接一句话做 embedding 检索”更适合相册场景。

### 2.2 当前项目里已经具备的基础

当前项目已有这些字段和能力：

- 图片时间：`PhotoEntity.timestamp`
- 图片地点：`province`、`city`、`district`、`locationName`、`formattedAddress`
- 图片标签：`aiTags`
- 图片向量：`imageEmbedding`
- OCR 文本：`ocrText`
- OCR 标签：`ocrTags`
- 截图判断：`isProbablyScreenshot`
- 粗标签定义：`lib/data/tag_taxonomy_v2.dart` 里的 `memoriaCoarseTagDefinitions`

因此，你的方案不是空想，而是能直接映射到现有数据结构上的。

## 3. 这套方案为什么合理

### 3.1 时间和地点应该做硬过滤

用户说“去年春节”“上海”“朝阳区”时，这类条件属于强约束，不应该只做加分。

所以：

- 时间应优先转成时间段列表，然后用于硬过滤。
- 地点应优先映射到现有地点元数据字段，然后用于硬过滤。

这能显著减少候选集，并提升结果稳定性。

### 3.2 粗标签适合做候选集收缩

用户自然语言中的“旅游”“聚餐”“节日”“城市夜景”“宠物”这类概念，本质上不是精确元数据，而是语义类别。

把它们先映射到 `memoriaCoarseTagDefinitions` 的粗标签集合是合理的，因为：

- LLM 不再自由发散到不可控类别
- 检索可以稳定对接你现有标签体系
- 候选集可以快速缩小到相关语义范围

你提出的“只要图片命中标签列表中的任一个粗标签，就进入候选集”也是可行的，这是一个 recall-first 的设计。

### 3.3 正向语义列表比单一语义更适合相册搜索

用户一句话往往包含多个潜在意图。

例如：

- “春节团聚吃饺子的图片”

背后可能包含：

- family reunion during Spring Festival
- people eating dumplings together
- festive dinner at home
- Chinese New Year celebration meal

如果只保留一个 `semantic_query`，很容易丢掉部分语义。

所以把正向语义设计成英文列表是非常合理的。

### 3.4 负向语义列表也很关键

相册搜索里，“不要什么”往往和“想要什么”同样重要。

例如：

- 不要截图
- 不要文档
- 不要单人自拍
- 不要模糊图

把负向语义单独抽出来，并单独计算负向分数，是非常合理的设计。

你提出“默认把文档/截屏设为负向语义”也很适合相册检索产品，因为这类图片通常是噪声。

## 4. 需要补充说明的边界

虽然整体方向正确，但为了后续实现更稳定，有几个点需要明确。

### 4.1 地点要严格限定为“可落到元数据字段的地点”

你这个判断是对的：

- “上海”“杭州”“朝阳区”“西湖”可以算地点
- “海边”“教室感”“夜景里”不应算地点

像“海边”“雪地”“夜景”“商场里”这种更适合进入：

- 粗标签
- 正向语义

而不是进入 location。

否则地点过滤会变得不稳定。

### 4.2 粗标签不要无限扩张

你的思路是让 DeepSeek 解析出“所有可能相关的粗标签”，这在 recall 上是对的，但实现上要避免过宽。

建议：

- 标签可以多给，但要有优先级或置信度
- 最终参与候选过滤的粗标签建议控制在 3 到 6 个左右

否则像“旅游”如果扩成十几个粗标签，候选集会过大，后面的向量排序压力会明显上升。

### 4.3 正向语义用 `max` 是可行的，但要知道它的含义

你提出：

- 将正向语义列表逐个向量化
- 与图片向量算相似度
- 取最大值作为正向分数

这作为第一版是可行的，而且简单稳定。

它的好处是：

- 只要图片很好地匹配其中一种语义表达，就有机会被召回
- 不会因为某个 phrasing 不准而整体失效

但它也有一个局限：

- 如果用户的意图本来是复合的，单纯取 max 会偏向“部分命中”

例如一张图只命中了“吃饺子”，却不含“团聚/春节”氛围，也可能得高分。

因此建议：

- v1 用 `max`
- v2 可考虑加入“多语义覆盖 bonus”

也就是：

- 主分数仍用 `max`
- 如果同一张图同时命中多个正向语义，再给一个轻微加成

### 4.4 负向语义的惩罚应该比现在更强

你提出：

- 负向语义列表逐个算相似度
- 取最大值作为负向分数

这是合理的。

建议最终公式采用：

`S = S_pos - alpha * S_neg`

其中：

- `S_pos = Max(Cosine(image, positive_i))`
- `S_neg = Max(Cosine(image, negative_j))`

这个公式很适合第一版。

同时建议：

- `alpha` 初始可以设为 `0.5 ~ 0.7`
- 对“文档/截图/代码界面”这类默认噪声类负向语义，可以适当提高惩罚权重

## 5. 建议的整体执行流程

这是我对你思路的整理与润色版本，建议作为后续实现的主流程。

### Step 1：读取粗标签体系

系统启动时，从 `lib/data/tag_taxonomy_v2.dart` 中读取：

- `memoriaCoarseTagDefinitions`

对每个粗标签记录：

- `id`
- 中文 `label`
- 英文 `prompts`
- 备注 `notes`

用途：

- 作为 DeepSeek 解析时的受限标签空间
- 作为后续标签过滤的标准集合

### Step 2：用 DeepSeek 解析自然语言查询

输入：

- 用户原始自然语言
- 所有粗标签的中英文信息
- 当前日期

输出一个结构化 JSON，包含：

- `time_ranges`
- `locations`
- `coarse_tags`
- `positive_semantics`
- `negative_semantics`

DeepSeek 的责任不是“直接给结果图”，而是把自然语言转成一个适合检索执行的中间结构。

### Step 3：元数据硬过滤

根据 `time_ranges` 和 `locations`，对图片做第一轮过滤。

规则：

- 时间命中任一时间段即可保留
- 地点命中任一地点即可保留
- 如果用户未提供时间或地点，则该条件不限制

这里得到候选集 A。

### Step 4：粗标签候选收缩

对候选集 A 中的图片，用其 `aiTags` 对应的粗标签进行匹配。

规则：

- 只要图片命中了 `coarse_tags` 中任意一个，就进入候选集 B
- 如果 `coarse_tags` 为空，则跳过这一层

这样做的意义是：

- 保证 recall
- 减少后续语义向量评分的计算量
- 让搜索先落在“类别正确”的图片范围内

### Step 5：正向语义评分

将 `positive_semantics` 中的每条英文语义文本分别向量化。

对每张候选图片：

- 分别计算与每个正向语义的余弦相似度
- 取最大值作为 `S_pos`

即：

`S_pos = Max(Cosine(image, positive_i))`

### Step 6：负向语义惩罚

将 `negative_semantics` 中的每条英文语义分别向量化。

对每张候选图片：

- 分别计算与每个负向语义的余弦相似度
- 取最大值作为 `S_neg`

即：

`S_neg = Max(Cosine(image, negative_j))`

### Step 7：最终排序

最终总分：

`S = S_pos - alpha * S_neg`

建议：

- 初始 `alpha = 0.6`

可选增强项：

- 标签命中 bonus
- OCR 命中 bonus
- 多正向语义覆盖 bonus

但第一版可以先只保留主公式，确保链路清晰。

### Step 8：结果不足时放宽条件

如果候选集过少或最终结果为空，可以分层放宽：

1. 先放宽地点
2. 再放宽时间
3. 保留粗标签和语义排序

并向用户解释：

- “没有完全命中你指定时间和地点的照片”
- “在相近时间找到了类似照片”
- “在相近地点找到了类似照片”

这一步非常适合相册场景，因为用户通常愿意接受“相似记忆”而不只是“精确命中”。

## 6. 推荐 JSON 结构

建议 DeepSeek 输出如下结构：

```json
{
  "time_ranges": [
    {
      "start": "2025-01-28",
      "end": "2025-02-12",
      "reason": "春节"
    }
  ],
  "locations": [
    {
      "text": "北京",
      "type": "city"
    }
  ],
  "coarse_tags": [
    {
      "id": "festival_celebration",
      "label_zh": "节日/庆典",
      "label_en": "festival celebration",
      "confidence": 0.93
    },
    {
      "id": "people",
      "label_zh": "人物",
      "label_en": "people",
      "confidence": 0.88
    },
    {
      "id": "food_drink",
      "label_zh": "美食饮品",
      "label_en": "food and drink",
      "confidence": 0.86
    }
  ],
  "positive_semantics": [
    "a family reunion during Chinese New Year",
    "people eating dumplings together at home",
    "a festive Spring Festival dinner with family",
    "a warm holiday gathering around a dining table"
  ],
  "negative_semantics": [
    "a blurry image",
    "a single person portrait",
    "a screenshot of a mobile phone",
    "a photographed document"
  ],
  "notes": "用户查询重点是春节、团聚、吃饺子；优先家庭聚餐和节日氛围。"
}
```

## 7. 春节团聚吃饺子示例解析

对于查询：

- “春节团聚吃饺子的图片”

合理解析应当是：

- 时间：
  - 春节对应一个春节时间段
  - 如果按产品习惯，也可以扩成“每年春节附近的时间段”，但这属于产品策略，不属于 prompt 本身
- 地点：
  - 没有明确地点，可为空
- 粗标签：
  - `festival_celebration`
  - `people`
  - `food_drink`
- 正向语义：
  - family reunion
  - eating dumplings together
  - festive dinner at home
  - Chinese New Year celebration
- 负向语义：
  - blurry image
  - screenshot
  - document
  - single person portrait

这里最关键的一点是：

“春节”“团聚”“吃饺子”不应该被压缩成一个单句语义，而是应该拆成一组面向图像检索的英文描述。

## 8. DeepSeek 提示词设计

下面这版提示词更适合作为后续实现的基础模板。

### 8.1 系统提示词

```text
你是一个“相册语义搜索查询解析器”。

你的任务不是回答用户问题，而是把用户的中文自然语言查询，解析成一个严格的 JSON，用于后续图片检索。

你必须遵守以下原则：

1. 只输出合法 JSON，不输出 Markdown，不输出解释，不输出多余文本。
2. 你必须优先使用给定的粗标签集合，不能发明新的粗标签 id。
3. 时间必须尽量解析为明确的时间段列表。
4. 地点只保留“能映射到真实地理位置”的地点，如国家、省、市、区县、景点、商圈、学校、园区等。
5. 像“海边、夜景、雪地、聚餐、婚礼氛围”这类不是地理坐标地点的概念，不要放进 location，要放进 coarse_tags 或 positive_semantics。
6. positive_semantics 必须是英文，且每一项都要写成适合图片语义检索的短句，风格类似：
   - "a photo of ..."
   - "people ..."
   - "a scene of ..."
7. negative_semantics 也必须是英文，表示用户不希望出现的图像内容。
8. 如果用户没有明确给出负向条件，也默认加入低质量或噪声图片相关负向语义，例如：
   - screenshot
   - document
   - blurry image
9. coarse_tags 需要尽量覆盖用户意图，但不要无限扩张，通常保留最相关的 3 到 6 个。
10. 如果用户查询包含多个时间条件，time_ranges 输出多个对象。
11. 如果用户查询没有地点，则 locations 返回空数组。
12. confidence 取值范围是 0 到 1。
```

### 8.2 用户提示词模板

```text
今天日期：{today}

下面给你一个相册图片语义搜索任务。

请你根据“用户自然语言查询”与“系统提供的粗标签集合”，输出严格 JSON。

【粗标签集合】
{coarse_tag_catalog}

其中每个粗标签包含：
- id
- 中文名称
- 英文语义提示
- 备注

【用户查询】
{user_query}

请输出 JSON，字段必须严格如下：
{
  "time_ranges": [
    {
      "start": "YYYY-MM-DD",
      "end": "YYYY-MM-DD",
      "reason": "时间段来源说明"
    }
  ],
  "locations": [
    {
      "text": "地点原文",
      "type": "country/province/city/district/poi/area/school/park/landmark"
    }
  ],
  "coarse_tags": [
    {
      "id": "必须来自给定粗标签集合",
      "label_zh": "中文名",
      "label_en": "英文概括",
      "confidence": 0.0
    }
  ],
  "positive_semantics": [
    "英文图片语义短句"
  ],
  "negative_semantics": [
    "英文负向图片语义短句"
  ],
  "notes": "一句简短说明"
}

补充规则：

1. 只输出 JSON。
2. 如果用户没有明确地点，locations 返回 []。
3. 如果用户说“不要截图/不要文档/不要课件/不要聊天记录”，必须把这些内容写入 negative_semantics。
4. 即使用户没有明确提到，也默认加入以下负向语义中的合理项：
   - "a screenshot of a mobile phone"
   - "a photographed document"
   - "a blurry image"
5. positive_semantics 应尽量拆成多个互补语义，而不是只写一句泛化描述。
6. coarse_tags 应覆盖用户主要意图，但不要过多，通常 3 到 6 个即可。
7. 如果查询本身是节日、旅行、聚会这类复合意图，应同时考虑人物、场景、食物、庆典等可能相关的粗标签。
8. 对“海边、夜景、雪地、婚礼氛围、聚餐”等词，不要当作 location。
9. 时间若无法确定到具体日期，可根据常识给出合理时间段，但必须在 notes 中体现依据。
```

## 9. 给实现层的建议

这部分不是代码，而是后续实现时应遵守的执行原则。

### 9.1 v1 建议先做简单稳定版

建议第一版严格按照下面的执行方式：

- 时间、地点：硬过滤
- 粗标签：任一命中即进入候选集
- 正向语义：取最大相似度
- 负向语义：取最大相似度
- 总分：`S = S_pos - 0.6 * S_neg`

这样实现最稳，也最容易调试。

### 9.2 不建议第一版就做得过于复杂

第一版先不要引入太多附加项，例如：

- 复杂学习排序
- 太多启发式 bonus
- 多层 query rewrite
- 过多的 fallback 分支

第一版最重要的是：

- 解析稳定
- 中间结果可观察
- 候选集合理
- 排序可解释

### 9.3 第二版再考虑增强项

在第一版稳定后，再考虑这些增强：

- 多正向语义覆盖 bonus
- OCR 文本 bonus
- 标签精确命中 bonus
- query-aware 的时间放宽策略
- 相似时间 / 相似地点的兜底解释

## 10. 最终建议

如果把你的思路浓缩成一句话，可以表述为：

“先让 DeepSeek 把自然语言拆成时间、地点、粗标签、正向语义和负向语义五类检索信号，再按‘元数据硬过滤 -> 粗标签收缩 -> 向量打分 -> 负向惩罚 -> 兜底放宽’的顺序完成相册语义搜索。”

这是一个逻辑清晰、与当前项目数据结构兼容、并且非常适合移动端相册产品的方案。

从可实施性上看，这套方案已经足够清楚，可以直接作为下一阶段写实现提示词和写代码的基础设计文档。
