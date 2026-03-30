# 语义搜索 JSON 契约与实现流程

## 1. 目标

这份文档用于明确两件事：

1. DeepSeek 在语义搜索场景下应输出什么 JSON
2. 应用收到该 JSON 后，搜索流程应如何执行

后续所有编码都应尽量以这份文档为准，避免：

- 解析字段反复变化
- 检索阶段和解析阶段职责混乱
- “时间/地点/标签/语义”在不同版本中含义不一致

---

## 2. DeepSeek 输出 JSON 的总体原则

DeepSeek 负责做的是：

1. 理解用户查询意图
2. 判断查询类型
3. 生成结构化检索条件
4. 生成“精排语义”和“宽召回语义”
5. 预估该查询合理的结果数量级

DeepSeek 不负责做的是：

1. 不直接决定最终图片是否命中
2. 不直接做数据库检索
3. 不直接做向量相似度计算
4. 不直接决定 UI 展示方式

也就是说：

- DeepSeek 输出的是“检索计划”
- 本地代码执行的是“检索与排序”

---

## 3. DeepSeek 输出 JSON 结构

建议统一输出如下结构：

```json
{
  "query_type": "collection",
  "time_ranges": [
    {
      "start_time_ms": 1735660800000,
      "end_time_ms": 1767196799999,
      "reason": "2025年"
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
      "confidence": 0.86
    },
    {
      "id": "city_street",
      "label_zh": "城市街景",
      "label_en": "city street",
      "confidence": 0.74
    }
  ],
  "tag_strictness": "prefer",
  "positive_semantics": [
    {
      "text": "a travel memory photo",
      "weight": 0.35
    },
    {
      "text": "a sightseeing photo at a landmark",
      "weight": 0.25
    },
    {
      "text": "a travel portrait during a trip",
      "weight": 0.20
    },
    {
      "text": "a city street scene during travel",
      "weight": 0.20
    }
  ],
  "recall_semantics": [
    {
      "text": "a vacation memory photo",
      "weight": 0.22
    },
    {
      "text": "a travel food photo",
      "weight": 0.18
    },
    {
      "text": "a travel group photo",
      "weight": 0.20
    },
    {
      "text": "a scenic photo taken during travel",
      "weight": 0.20
    },
    {
      "text": "a beach or outdoor travel moment",
      "weight": 0.20
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
    "max": 200,
    "confidence": 0.72
  },
  "notes": "旅游照片通常是集合型主题，应扩大召回范围。"
}
```

---

## 4. 各字段含义

### 4.1 `query_type`

表示查询类型，用于决定后续策略。

可选值建议：

- `metadata`
  - 纯时间/地点筛选
  - 例：`2026年的图片`、`上海的图片`
- `attribute`
  - 视觉属性型
  - 例：`绿色上衣`、`红色裙子`
- `concrete`
  - 具体主体/场景型
  - 例：`笑脸`、`花`、`猫`
- `abstract`
  - 抽象情绪/氛围型
  - 例：`春天的气息`、`快乐的时光`
- `collection`
  - 集合主题型
  - 例：`旅游照片`、`校园生活`

作用：

- 决定是否启用强标签限制
- 决定是否需要更宽的召回语义
- 决定结果过少时如何放宽

### 4.2 `time_ranges`

表示用户查询中提取出的时间范围。

字段：

- `start_time_ms`
- `end_time_ms`
- `reason`

含义：

- 用于元数据过滤
- 不参与最终分数

注意：

- 可以有多个时间段
- 如果用户没提时间，就返回空数组

### 4.3 `locations`

表示用户查询中提取出的真实地理位置。

字段：

- `text`
- `type`

`type` 建议值：

- `province`
- `city`
- `district`

含义：

- 只用于元数据过滤
- 不参与最终分数

注意：

- 只保留真实可映射到照片地理元数据的地点
- 不要把“海边、花海、草地、夜景”放进 `locations`

### 4.4 `coarse_tags`

表示 DeepSeek 认为该查询可能覆盖的粗标签集合。

字段：

- `id`
- `label_zh`
- `label_en`
- `confidence`

含义：

- 用于控制候选集
- 不是最终打分项
- 具体是“硬限制”还是“软限制”，由 `tag_strictness` 决定

### 4.5 `tag_strictness`

表示粗标签在当前查询中的限制强度。

可选值建议：

- `strict`
  - 标签必须命中，否则不能进入下一步
  - 适合强指向性查询
  - 例：`代码截图`
- `prefer`
  - 优先使用标签限缩候选集
  - 如果结果为空或太少，可以放宽或取消
  - 默认建议值
- `optional`
  - 标签只作为辅助参考
  - 不应阻塞召回
  - 适合抽象/集合型查询

### 4.6 `positive_semantics`

表示用于最终精排的正向语义。

字段：

- `text`
- `weight`

要求：

- 使用英文
- 使用适合图像 embedding 的短句格式
- 语义更精准、更收敛

作用：

- 用于最终正向语义得分
- 是精确结果排序的核心输入

### 4.7 `recall_semantics`

表示用于宽召回的扩展语义。

字段：

- `text`
- `weight`

要求：

- 使用英文
- 覆盖更宽的近义场景、相关场景、抽象展开

作用：

- 当 `positive_semantics` 召回太少时，补充候选集
- 主要用于“抽象查询”“集合查询”“少结果放宽”

这是后续优化中非常关键的新字段。

### 4.8 `negative_semantics`

表示负向语义，用于惩罚用户不想看到的图片。

字段：

- `text`
- `weight`

作用：

- 从最终语义得分中扣分

注意：

- 如果用户明显在找截图/文档/代码，则负向截图类语义应该为空
- 否则默认建议加入截图/文档类负向语义

### 4.9 `estimated_result_count`

表示 DeepSeek 对该查询“合理结果规模”的估计。

字段：

- `min`
- `max`
- `confidence`

作用：

- 判断当前召回结果是否“过少”
- 触发放宽策略的重要依据

例子：

- `绿色上衣`
  - 可能是 `1 ~ 10`
- `婚礼`
  - 可能是 `1 ~ 20`
- `快乐的时光`
  - 可能是 `20 ~ 200`
- `旅游照片`
  - 可能是 `30 ~ 300`

### 4.10 `notes`

表示 DeepSeek 对本次解析的补充说明。

作用：

- 仅用于调试与开发理解
- 不作为检索逻辑输入

---

## 5. 整个实现流程

完整实现流程建议如下。

### Step 1：识别是否可走本地短查询直搜

适用于：

- `1-4` 个中文字符
- 不含时间/地点/排除条件
- 与某一粗标签语义相似度高于阈值

例如：

- `花`
- `猫`
- `人像`

这一步不调用 DeepSeek。

输出：

- `query_type` 由本地判断
- 构建本地 `coarse_tags`
- 构建本地 `positive_semantics`

### Step 2：复杂查询调用 DeepSeek

适用于：

- 非短查询
- 或短查询无法稳定映射

DeepSeek 输出：

- `query_type`
- `time_ranges`
- `locations`
- `coarse_tags`
- `tag_strictness`
- `positive_semantics`
- `recall_semantics`
- `negative_semantics`
- `estimated_result_count`

### Step 3：纯元数据查询直接走筛选

如果判断：

- `query_type == metadata`

则：

- `coarse_tags = []`
- `positive_semantics = []`
- `recall_semantics = []`
- `negative_semantics = []`

执行方式：

1. 只做时间/地点过滤
2. 过滤结果直接返回
3. 不计算向量得分

### Step 4：时间/地点过滤

对于非纯元数据查询：

1. 若有 `time_ranges`，先做时间过滤
2. 若有 `locations`，再做地点过滤

注意：

- 时间、地点只做过滤，不参与最终分数

### Step 5：粗标签控制候选集

依据 `tag_strictness`：

#### `strict`

- 只保留命中粗标签的图片

#### `prefer`

- 先保留命中粗标签的图片
- 若结果为空或明显过少，可放宽

#### `optional`

- 粗标签只做参考
- 不阻止进入下一步

### Step 6：用 `positive_semantics` 做主语义精排

在当前候选集中：

1. 将 `positive_semantics` 转成文本向量
2. 与图片向量计算相似度
3. 做加权汇总

建议：

- 低于正向参与阈值的语义不参与有效正向分

### Step 7：用 `negative_semantics` 做惩罚

1. 将 `negative_semantics` 转成文本向量
2. 与图片向量计算负向相似度
3. 做加权惩罚

最终主公式建议：

```text
final_score = positive_score - alpha * negative_score
```

其中：

- `positive_score` 仅来自正向语义
- `negative_score` 仅来自负向语义
- 时间/地点/标签都不参与加分

### Step 8：判断结果是否过少

结合：

- 当前命中数量
- `estimated_result_count`

判断是否需要放宽。

建议逻辑：

- 若结果为空，必放宽
- 若结果数量显著低于预估最小值，也应放宽

例如：

- `estimated_result_count.min = 50`
- 当前只搜到 `3`
- 说明召回明显不足，应升级召回策略

### Step 9：按层级放宽

建议按顺序放宽：

#### Level 0：严格模式

- 原始时间/地点
- 原始标签
- `positive_semantics`

#### Level 1：放宽时间/地点

- 标签保持不变
- 继续用 `positive_semantics`

#### Level 2：放宽标签

- `strict -> prefer`
- `prefer -> optional`
- 或直接取消标签限制

#### Level 3：启用 `recall_semantics`

- 使用更宽的召回语义
- 重新做语义检索

#### Level 4：相关结果模式

- 降低严格命中要求
- 明确提示：
  - `未找到您所需的图片，只找到一些相关图片`

### Step 10：返回结果给 UI

结果对象中至少应区分：

- 精确结果
- 相关结果
- 是否使用了放宽策略
- 放宽说明

UI 可以决定是否展示这些信息，但服务层最好保留。

---

## 6. 不同查询类型的处理建议

### 6.1 元数据型

例：

- `2026年的图片`
- `上海的图片`

建议：

- 不做语义计算
- 直接按时间排序返回

### 6.2 属性型

例：

- `绿色上衣`

建议：

- 标签通常为空
- 重点依赖属性语义模板
- `positive_semantics` 应更偏属性描述
- `estimated_result_count` 往往较低

### 6.3 具体型

例：

- `笑脸`
- `花`
- `猫`

建议：

- 可用短查询直搜
- 标签可作为辅助收缩候选
- 但仍以语义为主

### 6.4 抽象型

例：

- `春天的气息`
- `快乐的时光`

建议：

- `tag_strictness = optional`
- `positive_semantics` 收敛
- `recall_semantics` 要更宽

### 6.5 集合型

例：

- `旅游照片`

建议：

- coarse_tags 一定要更宽
- `recall_semantics` 非常重要
- 结果少时必须允许取消标签限制

---

## 7. 后续编码时的关键约束

后续实现请遵守以下原则：

1. 时间、地点只过滤，不加分
2. 粗标签只限缩候选，不加分
3. 最终得分只来自：
   - 正向语义
   - 负向语义
4. `recall_semantics` 不替代 `positive_semantics`
   - 前者偏召回
   - 后者偏精排
5. `estimated_result_count` 用于放宽决策，不直接展示给用户

---

## 8. 最终结论

DeepSeek 未来输出的 JSON，不应只是“把一句话拆成时间地点标签”。

它真正应该提供的是：

1. 查询类型判断
2. 结构化过滤条件
3. 标签限制强度
4. 精排语义
5. 宽召回语义
6. 结果数量预估

本地代码则负责：

1. 过滤
2. 候选控制
3. 语义打分
4. 结果过少时按层级放宽

这样整个系统才能同时兼顾：

- 精准性
- 召回率
- 可解释性
- 可持续迭代性
