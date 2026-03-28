# 语义搜索 DeepSeek 提示词规范

## 1. 目的

这份文档用于定义一套可直接用于相册语义搜索解析的 `DeepSeek` 提示词。

目标有 4 个：

1. 让 `DeepSeek` 明确知道自己输出的是“搜索计划 JSON”，不是答案解释。
2. 让 `query_type`、`locations`、`coarse_tags`、`positive_semantics`、`recall_semantics` 的职责边界足够清晰。
3. 减少“标签过窄”“语义过窄”“地点字段不明确”“metadata 查询还在输出语义”的问题。
4. 为后续代码实现提供稳定、严谨、可验证的 JSON 契约。

---

## 2. 提示词设计原则

### 2.1 DeepSeek 负责什么

DeepSeek 负责：

1. 理解用户自然语言查询。
2. 判断查询属于哪种 `query_type`。
3. 抽取时间、地点、粗标签。
4. 生成精排用的 `positive_semantics`。
5. 生成宽召回用的 `recall_semantics`。
6. 生成用户不想要的 `negative_semantics`。
7. 估计合理结果规模 `estimated_result_count`。

### 2.2 DeepSeek 不负责什么

DeepSeek 不负责：

1. 不负责直接判断某张图片是否命中。
2. 不负责数据库过滤。
3. 不负责向量相似度计算。
4. 不负责最终排序。
5. 不负责 UI 展示。

也就是说：

- DeepSeek 输出的是“结构化检索意图”
- 本地代码执行的是“过滤、召回、打分、排序”

---

## 3. 字段边界要求

### 3.1 `query_type`

必须输出以下 5 种之一：

- `metadata`
- `attribute`
- `concrete`
- `abstract`
- `collection`

含义：

- `metadata`
  - 纯时间/地点过滤查询
  - 例子：`2026年的图片`、`上海的图片`
- `attribute`
  - 视觉属性查询
  - 例子：`绿色上衣`、`红色裙子`
- `concrete`
  - 具体主体或具体场景
  - 例子：`花`、`猫`、`笑脸`
- `abstract`
  - 抽象氛围、情绪、季节感
  - 例子：`春天的气息`、`快乐的时光`
- `collection`
  - 集合型主题
  - 例子：`旅游照片`、`校园生活`

### 3.2 `locations`

必须注意：

1. 这里只能输出“真实地理位置名称”。
2. 例如：省、市、区、县。
3. 不要输出经纬度。
4. 不要把“海边、草地、夜景、花海、公园”这类场景词放进 `locations`。

原因：

- 当前相册侧的地点过滤主要依赖照片已逆地理编码后的文本字段：
  - `province`
  - `city`
  - `district`
  - `locationName`
  - `formattedAddress`
- 所以 `locations` 输出的必须是能映射到这些字段的地点名称，而不是抽象场景。

### 3.3 `coarse_tags`

必须满足：

1. 只能从给定粗标签列表中选择。
2. 可以返回多个。
3. 不能凭空创造新粗标签。
4. 对集合查询、抽象查询，不要返回过窄的标签集合。

### 3.4 `tag_strictness`

只能输出：

- `strict`
- `prefer`
- `optional`

约束：

- `strict`
  - 仅用于非常明确、指向性极强的查询
  - 例子：`代码截图`
- `prefer`
  - 默认首选
  - 表示标签优先用于收缩候选，但结果过少时允许放宽
- `optional`
  - 标签只作参考，不应阻塞召回
  - 常用于抽象查询和集合查询

### 3.5 `positive_semantics`

要求：

1. 输出英文。
2. 使用适合图像向量检索的短句。
3. 每一项必须包含：
   - `text`
   - `weight`
4. 不要只给一个极窄表达，尤其对复杂查询不够。

作用：

- 用于最终精排。

### 3.6 `recall_semantics`

要求：

1. 输出英文。
2. 比 `positive_semantics` 更宽。
3. 用于少结果时扩大召回。
4. 对抽象查询、集合查询，必须认真输出，不能空泛。

作用：

- 不用于最严格精排
- 主要用于少结果时的补召回

### 3.7 `negative_semantics`

要求：

1. 输出英文。
2. 表达用户不希望出现的内容。
3. 如果用户没有明确说要找截图/文档/代码，则默认加入截图/文档类负向语义。

### 3.8 `estimated_result_count`

要求：

必须输出：

- `min`
- `max`
- `confidence`

含义：

- `min`
  - 合理结果下限
- `max`
  - 合理结果上限
- `confidence`
  - 对这个估计的信心

注意：

- 抽象查询、集合查询通常应该比具体查询估计更多结果。
- 指向性特别强的查询可以估计得比较少。

---

## 4. 推荐 System Prompt

```text
你是“相册语义搜索解析器”。

你的唯一任务是把用户的自然语言相册搜索语句，转换成结构化 JSON。

你输出的不是答案，不是解释，不是建议，而是“搜索计划”。

严格遵守以下规则：

1. 只输出一个 JSON 对象。
2. 不要输出任何解释、Markdown、代码块标记、前后缀文本。
3. 不要输出多余字段。
4. 所有字段必须符合给定结构。
5. 如果某一字段没有内容，返回空数组或 null 对象，不要省略关键字段。
6. 如果查询属于纯时间/地点过滤，则 query_type 必须为 metadata，并且 coarse_tags、positive_semantics、recall_semantics、negative_semantics 都返回空数组。
7. locations 只能保留真实地理位置名称，例如省、市、区、县；不要输出经纬度；不要把海边、夜景、草地、花海、公园这类场景词放进 locations。
8. coarse_tags 只能从给定的粗标签列表中选择，不能自造标签。
9. positive_semantics、recall_semantics、negative_semantics 必须输出英文短句，并适合图像向量检索。
10. positive_semantics 用于精排，应更准确、更收敛。
11. recall_semantics 用于少结果时的宽召回，应覆盖相关场景、近义场景、同主题子场景。
12. tag_strictness 只能是 strict、prefer、optional 三者之一。
13. 对抽象查询和集合查询，不要把 coarse_tags 和 positive_semantics 设得过窄。
14. estimated_result_count 应根据查询的合理召回规模给出 min、max、confidence。
15. 每个语义项都必须有 text 和 weight，weight 在 0 到 1 之间。
16. 如果用户没有明确要求查找截图、文档、代码界面，则 negative_semantics 中默认加入截图/文档类负向语义。
```

---

## 5. 推荐 User Prompt 模板

```text
请把用户的相册搜索语句解析成 JSON。

你需要输出以下字段：

{
  "query_type": "metadata | attribute | concrete | abstract | collection",
  "time_ranges": [
    {
      "start_time_ms": 0,
      "end_time_ms": 0,
      "reason": ""
    }
  ],
  "locations": [
    {
      "text": "",
      "type": "province | city | district"
    }
  ],
  "coarse_tags": [
    {
      "id": "",
      "label_zh": "",
      "label_en": "",
      "confidence": 0.0
    }
  ],
  "tag_strictness": "strict | prefer | optional",
  "positive_semantics": [
    {
      "text": "",
      "weight": 0.0
    }
  ],
  "recall_semantics": [
    {
      "text": "",
      "weight": 0.0
    }
  ],
  "negative_semantics": [
    {
      "text": "",
      "weight": 0.0
    }
  ],
  "estimated_result_count": {
    "min": 0,
    "max": 0,
    "confidence": 0.0
  },
  "notes": ""
}

字段要求：

1. query_type 必须解释查询本质：
   - metadata：纯时间/地点过滤
   - attribute：颜色、穿着、局部视觉属性
   - concrete：具体主体或具体场景
   - abstract：抽象情绪、氛围、季节感
   - collection：集合型主题

2. time_ranges：
   - 用于时间过滤
   - 可以有多个时间段
   - 无法确定时可以为 null

3. locations：
   - 只保留真实地理位置名称
   - 例如：上海、杭州、西湖区
   - 不要输出坐标
   - 不要把海边、草地、夜景、花海、公园放进去

4. coarse_tags：
   - 只能从给定粗标签列表中选择
   - 可以多个
   - 集合查询和抽象查询不要过窄

5. tag_strictness：
   - strict：必须命中这些粗标签
   - prefer：优先使用这些粗标签，但少结果时可以放宽
   - optional：粗标签仅作辅助，不阻塞召回

6. positive_semantics：
   - 用于最终精排
   - 需更准确、更集中
   - 输出英文短句

7. recall_semantics：
   - 用于少结果时宽召回
   - 需覆盖相关子场景、近义表达、同主题典型内容
   - 输出英文短句

8. negative_semantics：
   - 表示用户不想要的内容
   - 若用户未明确要找截图/文档/代码，则默认加入截图/文档类负向语义

9. estimated_result_count：
   - 估计合理结果规模
   - 抽象查询、集合查询通常比具体查询更多

10. 只输出 JSON，不要解释。

粗标签列表：
{{COARSE_TAGS_JSON}}

用户查询：
{{USER_QUERY}}
```

---

## 6. 旅行例子

### 6.1 用户查询

```text
去年上海旅游照片，不要截图
```

### 6.2 期望解析思路

应该这样理解：

1. `去年`
   - 是明确时间范围
2. `上海`
   - 是真实地点，应放入 `locations`
3. `旅游照片`
   - 不是单一对象，而是集合型主题
   - 应判为 `collection`
4. 旅游照片通常会覆盖：
   - 地标
   - 城市街景
   - 人物合影
   - 美食
   - 旅行中的自然或户外场景
5. `不要截图`
   - 应加入截图类负向语义
   - 并且负向权重可以比默认更明确

### 6.3 推荐输出样例

```json
{
  "query_type": "collection",
  "time_ranges": [
    {
      "start_time_ms": 1704038400000,
      "end_time_ms": 1735660799999,
      "reason": "去年"
    }
  ],
  "locations": [
    {
      "text": "上海",
      "type": "city"
    }
  ],
  "coarse_tags": [
    {
      "id": "travel_landmark",
      "label_zh": "旅行地标",
      "label_en": "travel landmark",
      "confidence": 0.90
    },
    {
      "id": "city_street",
      "label_zh": "城市街景",
      "label_en": "city street",
      "confidence": 0.80
    },
    {
      "id": "people",
      "label_zh": "人物",
      "label_en": "people",
      "confidence": 0.64
    },
    {
      "id": "food_drink",
      "label_zh": "美食饮品",
      "label_en": "food and drink",
      "confidence": 0.52
    }
  ],
  "tag_strictness": "prefer",
  "positive_semantics": [
    {
      "text": "a travel memory photo in shanghai",
      "weight": 0.32
    },
    {
      "text": "a sightseeing photo at a landmark in shanghai",
      "weight": 0.26
    },
    {
      "text": "a city street travel scene in shanghai",
      "weight": 0.22
    },
    {
      "text": "a travel portrait during a trip",
      "weight": 0.20
    }
  ],
  "recall_semantics": [
    {
      "text": "a vacation memory photo",
      "weight": 0.18
    },
    {
      "text": "a scenic photo taken during travel",
      "weight": 0.18
    },
    {
      "text": "a travel group photo",
      "weight": 0.18
    },
    {
      "text": "a travel food photo",
      "weight": 0.16
    },
    {
      "text": "an urban travel moment",
      "weight": 0.15
    },
    {
      "text": "a memorable trip photo in a big city",
      "weight": 0.15
    }
  ],
  "negative_semantics": [
    {
      "text": "a screenshot of a text document article chat message email or webpage",
      "weight": 0.50
    },
    {
      "text": "a screenshot of a computer screen software interface programming code or IDE",
      "weight": 0.50
    }
  ],
  "estimated_result_count": {
    "min": 20,
    "max": 120,
    "confidence": 0.78
  },
  "notes": "旅游照片属于集合型主题，不应只收缩到地标，应覆盖街景、人物和旅行中的其他典型场景。"
}
```

---

## 7. 这份提示词要解决的核心问题

这份提示词重点解决以下问题：

1. 让 `query_type` 不再只是一个字段名，而是有明确判定标准。
2. 明确 `locations` 只能是可映射到地址文本字段的真实地点。
3. 明确 `coarse_tags` 只能从给定标签中选，且对抽象/集合查询不能过窄。
4. 明确 `positive_semantics` 和 `recall_semantics` 的分工。
5. 明确 `metadata` 查询不应该再输出语义项。
6. 明确 `estimated_result_count` 不是装饰字段，而是用于后续放宽策略。

---

## 8. 后续编码建议

后续真正接入代码时，建议按以下顺序：

1. 先替换 `semantic_query_parser_service` 中的 DeepSeek prompt。
2. 再校验 JSON 解析代码是否完整支持：
   - `query_type`
   - `tag_strictness`
   - `recall_semantics`
   - `estimated_result_count`
3. 最后再调检索侧：
   - `metadata` 只过滤
   - `prefer/optional` 标签策略
   - 少结果时启用 `recall_semantics`

