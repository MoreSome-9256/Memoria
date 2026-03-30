# 相册语义搜索分析与优化计划

## 1. 相关项目结构

当前“相册 -> 顶部语义搜索”功能主要分布在以下文件中：

- `lib/view/pages/album_page.dart`
  - 相册页顶部搜索框入口。
  - 负责收集用户输入，并跳转到搜索结果页。
- `lib/view/pages/album_search_page.dart`
  - 语义搜索结果页。
  - 负责调用搜索服务、展示解析结果、展示照片网格。
- `lib/service/semantic_photo_search_service.dart`
  - 当前相册语义搜索的核心检索服务。
  - 负责候选照片加载、结构化过滤、向量打分、回退逻辑和最终排序。
- `lib/service/semantic_query_parser_service.dart`
  - 负责把自然语言查询解析为结构化查询对象。
  - 支持本地规则解析，也支持在配置了 LLM 时走 DeepSeek 解析。
- `lib/models/vo/semantic_search_models.dart`
  - 定义语义搜索请求、命中结果和返回结果的数据结构。
- `lib/service/semantic_matching_service.dart`
  - 封装 MobileCLIP 文本向量能力，提供 `embedText` 和余弦相似度计算。
- `lib/models/entity/photo_entity.dart`
  - 检索依赖的数据字段都在这里：`aiTags`、`aiCaption`、`imageEmbedding`、`ocrText`、`ocrTags`、地点字段、时间字段等。

另外，项目中还有一套“创作页”的旧版语义检索逻辑：

- `lib/view/pages/create_page.dart`

这套逻辑和相册搜索已经分叉，属于后续必须收敛的重复实现。

## 2. 当前功能链路

### 2.1 用户入口

在 `AlbumPage` 中，用户点击顶部搜索框右侧按钮或提交输入后，会执行 `_submitSemanticSearch()`：

1. 读取输入框文本。
2. 如果为空，提示用户输入。
3. 跳转到 `AlbumSearchPage(initialQuery: query)`。

`AlbumPage` 本身不做任何搜索，只是入口页。

### 2.2 搜索结果页行为

`AlbumSearchPage` 在 `initState()` 中，如果有初始 query，会自动触发 `_performSearch()`：

1. 调用 `SemanticPhotoSearchService().search(query)`。
2. 成功后展示：
   - 搜索结果照片列表
   - 查询解析摘要
   - DeepSeek / 本地解析来源
   - include/exclude 条件 chip
   - Debug JSON
3. 失败则展示错误态。

### 2.3 当前搜索服务的执行流程

`SemanticPhotoSearchService.search()` 的逻辑可以概括为：

1. 从 Isar 读取所有 `isAiAnalyzed == true` 的照片。
2. 基于这些照片构建地点字典。
3. 用 `SemanticQueryParserService` 把自然语言解析成 `SemanticSearchQuery`。
4. 用结构化条件先过滤一轮候选照片。
5. 如果查询里包含语义意图 / 排除意图 / includeTags / excludeTags，则构建文本向量。
6. 对每一张候选照片计算：
   - 正向语义分
   - 负向语义惩罚
   - include tag 向量分
   - exclude tag 向量惩罚
   - OCR 命中分
   - 文本 boost
   - 新近性 boost
7. 按总分排序。
8. 如果没有达到接受阈值的结果，则退回到标签 / OCR / caption / location 的文本命中回退。

这本质上是一个“混合检索”：

- 结构化过滤
- 向量召回 / 排序
- 标签规则增强
- OCR 文本匹配
- 回退兜底

## 3. 当前查询解析逻辑

### 3.1 本地规则解析

`SemanticQueryParserService._buildLocalFallback()` 主要做这些事：

- 从地点字典里抽取地点词
- 从原始文本里抽取年份 / 去年 / 前年 / 今年 / 上个月 / 最近
- 从 taxonomy 标签表里识别 includeTags / excludeTags
- 通过“截图/屏幕/文档/课件/聊天记录”等关键词推断是否允许截图类内容
- 从引号中提取 OCR 精确词
- 去掉停用词后，剩余内容作为 `semanticQuery`

### 3.2 LLM 解析

如果 `LLMService().isApiKeyConfigured == true`，则会尝试调用 DeepSeek：

- 输出结构化 JSON
- 字段包括：
  - `semantic_query`
  - `negative_semantic_query`
  - `include_tags`
  - `exclude_tags`
  - `include_locations`
  - `exclude_locations`
  - `include_ocr_terms`
  - `exclude_ocr_terms`
  - `allow_screenshots`
  - `start_date`
  - `end_date`

最终结果会和本地规则结果做 merge，而不是完全信任 LLM。

这个设计整体是合理的，因为：

- 没配置 LLM 时仍可工作
- 配置了 LLM 时具备更自然的 query 理解能力
- 本地规则可以兜住一些强约束，比如“不要截图”

## 4. 当前候选过滤逻辑

`_matchesStructuredFilters()` 当前会做硬过滤：

- 排除截图
- 时间范围过滤
- includeLocations 必须命中
- excludeLocations 不能命中
- excludeTags 不能命中
- includeOcrTerms 必须命中
- excludeOcrTerms 不能命中

注意：

- `includeTags` 当前不是硬过滤，只参与后续打分
- `negativeSemanticQuery` 不是硬过滤，只作为惩罚项

这意味着用户输入“海边”时，最终结果不一定真的带“海边标签”，只要向量分足够高也可能进结果。

## 5. 当前打分逻辑

`_scorePhoto()` 当前的主要公式是：

- `score = semanticScore + tagScore + ocrScore + textBoost + recencyBoost - negativePenalty`

各部分来源：

- `semanticScore`
  - query 文本向量 vs 图片向量的余弦相似度
- `tagScore`
  - includeTags 的精确命中
  - include tag prompt 向量与图片向量的相似度
  - taxonomy label 的额外加分
- `ocrScore`
  - OCR 关键词命中比例
- `textBoost`
  - rawQuery 在 caption / location / OCR 中的直接包含
- `recencyBoost`
  - 最近 30 天 +0.03
  - 最近 180 天 +0.015
- `negativePenalty`
  - negative query 向量相似度
  - excludeTags 的向量相似度

结果接受阈值：

- 如果命中 tag 或 OCR，直接接受
- 如果没有 `semanticQuery`，只要 `score > 0` 就接受
- 如果有 `semanticQuery`，则要求 `semanticScore >= 0.08` 或 `score >= 0.08`

## 6. 当前逻辑的合理性分析

### 6.1 合理的地方

当前实现并不是“只做向量检索”，而是一个比较务实的混合方案，这一点是对的。

优点包括：

- 先做结构化过滤，再做向量打分，减少无关候选。
- 本地规则 + LLM 解析双轨并存，鲁棒性较好。
- 支持负向意图、时间、地点、OCR、截图排除等真实用户需求。
- 有 fallback 机制，不会因为向量效果不佳就完全返回空结果。
- 搜索结果页能展示解析摘要和 debug JSON，便于调试。

### 6.2 不够合理的地方

虽然整体方向是对的，但当前实现仍有几个明显问题。

#### 问题 1：`includeTags` 只是软信号，不是强约束

如果用户明确说“找海边照片”，系统把“海边”解析为 includeTags，但当前不会在结构化过滤阶段硬卡住它，只是后面给分。

这会导致：

- 相似画面但标签不准的图进来
- 真正命中标签的图未必排在前面

这在“明确标签意图”的查询下不够符合用户预期。

#### 问题 2：负向语义只是轻惩罚，不够强

当前负向逻辑是减分，不是排除。

例如：

- “海边，但不要截图”
- “聚会，不要自拍”
- “东京旅行，不要餐厅”

只靠一个较弱的 penalty，容易出现用户明确说不要的内容仍然混进结果。

#### 问题 3：文本 boost 太弱且过于粗糙

当前 `textBoost` 只做非常简单的 `contains(rawQuery)`：

- query 很长时，caption 基本不可能完整包含整句
- 没有分词
- 没有 token 级别命中统计
- OCR / caption / location 的文本信号没有被充分利用

这会导致明明 caption 很接近，但因为没有完整包含原句而拿不到应有加分。

#### 问题 4：新近性 boost 是全局固定值，可能污染排序

最近 30 天固定 +0.03，最近 180 天固定 +0.015。

这个 boost 很粗暴，问题在于：

- 某些查询明显是找旧照片，比如“去年毕业”“2022年旅行”
- 某些查询本身不该偏向最近结果
- 近期轻度相关图可能因此排到更前面

新近性应该是可感知 query 意图的，而不是全局恒定开启。

#### 问题 5：每次搜索都全量加载所有已分析照片

`_loadAnalyzedPhotos()` 每次都会：

- 从 Isar 全量读取 `isAiAnalyzed == true` 的照片
- 按时间倒序拉出整个集合

对大图库而言，这会带来：

- 搜索前延迟上升
- 内存占用增大
- 重复计算增多

地点字典有缓存，但照片列表本身没有服务级缓存，也没有增量索引。

#### 问题 6：存在两套分叉的语义搜索实现

`AlbumSearchPage` 用的是 `SemanticPhotoSearchService`。

但 `CreatePage` 里也保留了一套旧实现：

- 自己抽年份
- 自己抽地点
- 自己算向量分
- 自己做 fallback

这会导致：

- 同样一句 query，在两个页面结果可能完全不同
- 逻辑 bug 修复要改两套代码
- 阈值和 ranking 策略难以统一

这是一个很明显的架构问题。

#### 问题 7：结果解释还不够强

现在结果页里单张图只显示：

- 命中 tag
- 命中 OCR term
- 或者照片原有 tags

但没有展示：

- 为什么被排到前面
- 是语义向量命中，还是 OCR 命中，还是地点命中
- 强命中条件是什么

用户很难建立搜索信任感。

## 7. 当前逻辑适合什么阶段

我认为当前实现适合：

- 小到中等图库
- 以“能用”为目标的早期版本
- 需要快速验证自然语言搜图体验的阶段

但如果目标是“长期可扩展、结果稳定、便于调优的语义搜索”，现在的实现还不够稳定，尤其在：

- 大图库性能
- 明确条件查询
- 负向过滤
- 排序可解释性
- 多页面一致性

这几个方向上，仍然需要系统性优化。

## 8. 建议的优化方向

### 8.1 方向一：统一检索内核

目标：

- 相册搜索
- 创作页选图搜索
- 未来其他搜图入口

全部统一使用同一套检索服务。

建议：

- 保留 `SemanticPhotoSearchService` 作为唯一检索入口
- `CreatePage` 迁移到该服务
- 把页面只保留为：
  - query 输入
  - 调用服务
  - 渲染结果

这是最优先的架构优化。

### 8.2 方向二：把“强条件”和“软条件”明确分层

建议把 query 里的条件拆成两类：

- 强条件
  - 时间范围
  - 地点 include / exclude
  - 截图开关
  - OCR 精确词
  - 明确说出的排除标签
- 软条件
  - 语义描述
  - 宽松标签意图
  - caption 文本相似
  - 场景相似

同时为 includeTags 增加“强标签意图”和“弱标签意图”的区分：

- 用户明确说“只看海边”“找海边照片”时，作为硬过滤或强 boost
- 用户只是顺口提到“海边感觉”的时候，作为软信号

### 8.3 方向三：升级为真正的 Hybrid Retrieval

建议把排序拆成多个召回通道，再做统一 rerank：

1. 结构化过滤后的候选集
2. 向量召回分
3. 标签精确命中分
4. OCR / caption / location 文本命中分
5. 负向约束惩罚
6. 可选的新近性 / 质量分

这样做的好处：

- 每一路信号都更可解释
- 更容易调权重
- 更容易做 query-aware 策略

建议不要继续把很多逻辑都塞进一个 `score` 里黑盒相加，而是保留分项并用于调试输出。

### 8.4 方向四：让负向约束更强

建议：

- 对 `excludeTags` 继续保留硬过滤
- 对 `excludeLocations` 做硬过滤
- 对 `negativeSemanticQuery` 加一个阈值型排除：
  - 如果负向相似度高于阈值，直接剔除
  - 而不是只减一点分

否则“不要自拍”“不要截图”“不要夜景”这类查询体验会一直不稳定。

### 8.5 方向五：增强文本检索能力

当前 caption / OCR / location 的文本利用率偏低。

建议：

- 对 rawQuery 做分词或至少 token 拆分
- 对 caption、OCR、location 做统一规范化
- 从“整句 contains”改为“token 命中计数 + 权重”
- 给 OCR 和 caption 分开建分项

这会明显提升：

- 含专有名词的查询
- OCR 场景查询
- 地点 / 活动名称查询
- caption 已经写得比较好的照片

### 8.6 方向六：去掉全局固定新近性偏置

建议把 recency 从“默认 always-on”改成“query-aware”：

- 如果 query 明显是过去时间范围，则不加近期 boost
- 如果 query 没给时间，近期可作为弱排序信号
- 如果 query 含“最近”“近一个月”等，则近期 boost 才显著增强

### 8.7 方向七：做轻量级索引和缓存

建议逐步增加：

- 已分析照片列表缓存
- query -> result 缓存
- tag/location/year/month 的轻量倒排索引
- 搜索前先做候选收缩，再做向量打分

这样可以减少：

- 每次全量扫描
- 每次全量 string contains
- 大图库下的等待时间

### 8.8 方向八：增强结果解释能力

建议在 `SemanticSearchHit` 中补充 explanation 字段，例如：

- `matchedLocation`
- `matchedCaptionTokens`
- `matchedNegativeSignals`
- `rankingReasons`

然后在 UI 上展示：

- “因地点命中：东京”
- “因 OCR 命中：毕业典礼”
- “因语义相似 + 海边标签提升”

这样用户会更信任结果，也更容易调试。

## 9. 推荐的实施顺序

### Phase 1：低风险高收益

优先做：

1. 统一 `CreatePage` 和 `AlbumSearchPage` 的检索服务
2. 去掉重复实现，只保留 `SemanticPhotoSearchService`
3. 为 `SemanticSearchHit` 增加分项说明
4. 增强 `AlbumSearchPage` 的结果解释 UI

这是最值得先做的一步，因为能立刻减少分叉和调试成本。

### Phase 2：提升结果质量

接着做：

1. 明确 hard filter / soft signal 分层
2. 把 includeTags 改造成可区分强弱意图
3. 加强 negative semantic 的排除策略
4. 优化 text matching，从整句 contains 升级到 token 级别匹配

这一阶段会直接改善“搜得准不准”。

### Phase 3：提升性能

最后做：

1. 缓存 analyzed photos
2. 增量维护 location/tag/year 索引
3. 只对候选集做向量打分
4. 加 query cache 和分页

这一阶段主要解决大图库体验。

## 10. 我建议的下一步具体动作

如果下一步开始动代码，我建议按下面顺序推进：

1. 重构 `SemanticPhotoSearchService`
   - 输出更完整的 `SemanticSearchHit`
   - 拆出 `hardFilter / softScore / rerank / fallback`
2. 让 `CreatePage` 改为直接调用 `SemanticPhotoSearchService`
   - 删除页面内部的重复语义检索逻辑
3. 优化 `SemanticQueryParserService`
   - 增加更稳定的 query 意图分类
   - 区分强标签意图和弱标签意图
4. 优化 `AlbumSearchPage`
   - 增加命中原因展示
   - 增加“搜索基于已分析照片”的说明
5. 再做性能层优化
   - 缓存
   - 倒排索引
   - 分页

## 11. 总结

当前相册语义搜索不是从零开始的简单 demo，而是一套已经具备雏形的混合检索系统：

- 有 query 解析
- 有结构化过滤
- 有向量匹配
- 有 OCR / 标签增强
- 有 fallback

整体方向是对的，说明系统已经具备继续演进的基础。

但它目前的主要问题也很明确：

- 逻辑分叉
- 强条件不够强
- 负向约束不够稳
- 文本检索较弱
- 性能上仍偏全量扫描
- 排序解释性不足

下一步最值得做的，不是继续堆更多小修小补，而是先把它整理成一套统一、可解释、可调优的 Hybrid Search 内核。
