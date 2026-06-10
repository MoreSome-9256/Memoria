# 检索、聚类与回忆发现策略

## 1. 自然语言语义检索

相册搜索、创作入口和聊天助手复用同一服务。

```text
SemanticPhotoSearchService.search(rawQuery)
  -> _loadAllPhotos()
  -> SemanticQueryParserService.parseQuery(rawQuery)
     -> LLMService.completeText()
     -> 严格 JSON 解析和本地校验
     -> 失败后让 LLM 修复一次
  -> _searchParsedQuery()
```

### 1.1 LLM 查询计划

查询计划拆分为：

- `time_ranges`：日期范围、跨年份重复季节
- `local_time_windows`：早晨、夜晚等本地时间段
- `locations`：标准地点名、别名、地点类型
- `coarse_tags`：粗粒度视觉分类
- `positive_semantics`：高精度视觉语义
- `recall_semantics`：召回层视觉语义
- `negative_semantics`：易混淆负向语义
- `attributes`：人脸数、笑脸、joyScore、媒体类型

规则要求所有视觉语义字段使用英语；地点别名可以保留中文，用于元数据匹配。

“威海海边”应拆为 Weihai 地点硬约束、海岸视觉语义，以及湖泊/河岸/其他城市负向语义。“夏天”在没有年份时，本地规范化为每年 6-10 月。

### 1.2 分层检索和排序

```text
_searchParsedQuery()
  -> 排除未分析照片和 pending/confirmed junk
  -> _filterByMetadata()：时间 / 地点 / 属性硬过滤
  -> _buildSemanticVectors()：positive / recall / negative
  -> _applyTagStrategy()：strict / prefer / optional
  -> _scoreCandidates()
     正向相似度 + recall + 粗标签奖励 + 地点奖励 - 负向惩罚
  -> 分 exactPhotos / relatedPhotos
```

主要阈值：

- 正向参与阈值 0.17
- exact 正向阈值 0.23
- related 语义阈值 0.17
- 最终最低分 0.15
- 每个结果桶最多 240 张

### 1.3 问题

- LLM prompt 要求英语，但 `_readSemanticItems()` 不验证语言；LLM 返回中文时会直接送入 MobileCLIP。
- LLM 未配置或两次解析都失败时，搜索直接失败，没有本地结构化回退。
- `_buildSemanticVectors()` 捕获异常后返回空向量，模型错误可能表现为“没有结果”。
- 属性过滤依赖主扫描当前不稳定生成的 `faceCount`、`smileProb`、`joyScore`。
- 两个底层文本检索 API 允许任意原始文本直接 embedding，属于危险接口。
- 纯元数据查询分支使用 `allPhotos`，绕过普通语义分支的“已分析且非 junk”过滤；时间和地点查询可能返回未分析照片、pending junk 或 confirmed junk。

## 2. 相册标签浏览

标签浏览读取照片已保存的 `aiTags`，不重新计算语义。

```text
AlbumPage
  -> _loadAlbumTagBrowserSourcePhotos()
  -> _buildAlbumTagBrowserData()
  -> AlbumTagBrowserService.buildCoarseClusters()
  -> 按粗分类展示
  -> 进入分类后按细标签和月份过滤
```

可浏览照片要求：

- 不处于 pending/confirmed junk 隔离状态；
- 有 `assetId`、缩略图或 path 中至少一种可渲染来源；
- 至少有一个能映射到 taxonomy 粗分类的标签。

问题：

- taxonomy 映射缺失会直接让已分析照片无法出现在分类浏览里。
- “其他”几乎没有浏览价值。
- 页面数据源使用有界近期窗口，不保证覆盖整个相册。

## 3. 事件聚类

事件聚类是纯时间地点规则，不使用图片语义。

```text
EventService.runClustering()
  -> 读取照片并按时间排序
  -> EventClusterHelper.clusterPhotos()
     -> _initialSplit()
     -> _mergeSameDayTravelClusters()
  -> 重建 EventEntity
  -> 解析事件地点
```

默认规则包括：初始时间间隔 3 小时、同城时间 6 小时、基础距离 8 km、同城距离 20 km、缺少城市信息时的同城距离 45 km。

问题：

- 同一天同地点但内容不同的活动可能被合并。
- 同一活动中途跨越较远地点可能被拆开。
- 没有使用标签或 embedding 辅助事件边界。
- LLM 可以生成事件标题，但事件边界仍然完全是规则结果。

## 4. 主题聚类

主题页固定六个主题：人物、食物、书与课堂、车与出行、风景、宠物。

```text
ThemeClustersPage._loadClustersForCurrentMode()
  -> ThemeClusterService.loadClusters()
  -> _loadPhotos()，最多近期 2400 张
  -> _prepareMobileClip2Embeddings()
     复用已有向量，每次最多新计算 400 张
  -> _buildThemePrototypeVectors()
     每个主题的英语 prompt 向量求平均
  -> 对每张照片计算主题分数
  -> 达到阈值后加入主题
  -> PeopleThemeSubclusterer 或 GenericThemeSubclusterer
  -> 时间线分组
```

`GenericThemeSubclusterer` 使用整图 MobileCLIP embedding 执行 DBSCAN。`PeopleThemeSubclusterer` 先按 `faceCount` 区分单人和多人，再对单人照片的整图 embedding 做 DBSCAN、簇合并和零散样本吸附；它没有使用真正的人脸身份 embedding。

问题：

- 固定 prompt 混合大量概念，平均后主题原型模糊。
- 阈值较低，边界照片容易进入多个主题。
- 混合模式的 OCR/关键词规则依赖当前缺失的数据。
- 人物“身份簇”实际使用整图 embedding，名不副实。
- 只覆盖六类，不能自动发现用户真正独特的新主题。
- 近期 2400 张和每次补算 400 张造成大相册时间窗口偏差。

## 5. 独立人脸聚类

`FaceClusterService` 使用真实人脸 embedding，包含候选过滤、种子簇生长、小簇处理、centroid/cover/member 多阈值合并和 clusterId 回写。

但正式主扫描当前不稳定运行 `FacePipelineService`，所以该能力缺少稳定数据来源。

## 6. 首页“发现”

首页发现不是创作中心推荐，也不使用语义检索。

```text
HomePage.initState()
  -> _loadHeroAssets()
  -> _generateDiscoverCards()
```

“我的相册”背景直接从 `PhotoManager.getAssetPathList(RequestType.common)` 获取 All 相册资源，shuffle 后每 5 秒轮播，不持久化。

首页最多展示两张发现卡片，依次尝试：

1. 时间规则：年度总结、月度总结、往年今日
2. 内容规则：通过标签字符串找宠物、风景、美食；通过 `joyScore > 0.6` 找愉快回忆
3. 地点规则：按 `city ?? province` 分组

问题：

- 与 `CreateRecommendationService` 是两套独立推荐系统。
- 内容规则依赖字符串包含，容易误匹配。
- “愉快回忆”依赖主扫描不稳定生成的 joyScore。
- 没有明确排除 pending junk。
- 一次性读取 All 相册全部资源后 shuffle，大相册成本高。

## 7. 创作推荐 idea

创作中心推荐持久化为 `CreateRecommendationEntity`。

```text
CreateHubPage.initState()
  -> _loadCachedContent()
  -> _refreshRecommendationsInBackground()
     -> CreateRecommendationService.refreshRecommendationsIfNeeded()
        -> 读取全部 PhotoEntity
        -> _buildPresets(now, photos)
        -> 每次最多并发刷新 3 个 preset
        -> _searchPreset()
        -> _mergeRecommendationPhotos()
        -> 写回推荐实体
  -> loadActiveRecommendations()
```

推荐包括季节、笑脸、美食、家庭、朋友、旅行、宠物、节庆、校园、舞台、兴趣、居家、户外、旧时光、美学、工作、搬家、时间回顾和高频地点。

中文推荐名称先在 `RecommendationQueryJsonLibrary` 查找结构化模板。模板视觉语义为英语，直接调用 `SemanticPhotoSearchService.searchWithQuery()`。地点和时间推荐使用元数据查询。模板查找失败时静默退回 `SemanticPhotoSearchService.search(preset.query)`，再次让 LLM 解释中文。

语义推荐只使用 exact 结果，并要求：

- `qualifiedPositiveScore >= 0.22`
- `semanticScore >= 0.16`
- 带粗标签时必须命中粗标签
- 排除 confirmed junk
- 达到 preset 最低照片数量

问题：

- 模板以中文查询字符串为查找键，重命名容易静默失配。
- 模板失配会退回 LLM，性能和稳定性改变。
- 多个英语语义过于抽象，不是可观察画面。
- 推荐模板基本没有负向语义。
- “春日气息”等视觉季节推荐不一定真的拍摄于对应季节。
- 刷新读取全部照片并构建大量 preset，工作较重。
- 时间和地点 preset 会进入纯元数据查询；后续 `_mergeRecommendationPhotos()` 只显式排除 confirmed junk，因此 pending junk 和未分析记录仍可能进入推荐。

## 8. Prompt 语言审计

真正送入 MobileCLIP 的固定 prompt 当前基本都是英语：taxonomy、junk post-filter、主题聚类和推荐模板。

大量中文 prompt 主要用于故事、标题、数字相册和音乐生成，不是图片向量检索，使用中文合理。

真正的语言风险：

1. LLM 动态查询计划没有程序级英语校验。
2. 底层文本检索 API 允许传入任意语言。
3. 英语 prompt 可能过宽、不可观察或缺乏负向对比。
