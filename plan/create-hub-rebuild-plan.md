# “+”创作入口重构方案

## 1. 目标

本次只做方案，不直接编码。

目标是把主界面点击“+”后的当前搜索页，重构成一个新的“创作入口页”，但要满足下面几个原则：

1. 不删除现有 `create_page.dart` 的代码。
2. 新页面必须新建文件实现，再把入口路由切过去。
3. 页面整体视觉风格延续现在的粉白渐变、柔和氛围、卡片化表达。
4. 页面内容从“手动搜图”改成两块：
   - 创作推荐
   - 保存的故事
5. 创作推荐要复用“相册”页顶部那套语义搜索链路，而不是复用当前 `create_page.dart` 里的旧搜索逻辑。
6. 推荐要可保存、可去重、可周期性重刷，不能同一条语句在短时间内反复推荐，也不能搜一次后永远不再更新。

---

## 2. 当前项目结构理解

### 2.1 “+”入口当前链路

当前“+”入口并不在底部 tab 中直接常驻，而是通过 push 页面打开：

- `lib/view/widget_tree.dart`
  - 底部中央 FAB 点击后 `Navigator.push(...) => CreatePage()`
- `lib/view/pages/home_page.dart`
  - 首页中“开始创作”按钮也会 push `CreatePage()`

当前页面文件：

- `lib/view/pages/create_page.dart`

它的特点是：

1. 已经有一套比较明确的视觉语言
   - `Color(0xFFFAFAFA)` 的浅底
   - 顶部粉/紫氛围光斑背景
   - 底部悬浮的大搜索框
   - 搜索完成后是照片九宫格 + “继续”按钮
2. 现在的搜索逻辑是旧链路
   - 页面内自己做实体提取、旧版语义匹配、向量排序
   - 并不是你要复用的“相册页顶部语义搜索”

结论：

- 不能在 `create_page.dart` 上硬改到面目全非。
- 应该保留它，新增一个新页面文件承接新需求。

### 2.2 你指定要复用的语义搜索链路

你要复用的是“相册”页顶部输入框那套链路，当前真实调用链如下：

1. `lib/view/pages/album_page.dart`
   - 顶部 `TextField` 输入后调用 `_submitSemanticSearch()`
2. `_submitSemanticSearch()`
   - push 到 `AlbumSearchPage(initialQuery: query)`
3. `lib/view/pages/album_search_page.dart`
   - `_performSearch()` 中调用 `SemanticPhotoSearchService().search(query)`
4. `lib/service/semantic_photo_search_service.dart`
   - 统一加载照片
   - 调用 `SemanticQueryParserService`
   - 做元数据过滤、语义向量匹配、exact/related 结果整合

所以后续“创作推荐”必须以 `SemanticPhotoSearchService` 为准，而不是继续使用 `CreatePage` 里的旧逻辑。

### 2.3 语义解析里需要注意的边界

`lib/service/semantic_query_parser_service.dart` 的行为不是完全固定“纯本地”：

1. 如果是短查询，可能直接走本地 short semantic route。
2. 如果判断为 metadata-only（例如时间/地点型语句），也会走本地 fallback。
3. 如果不是 metadata-only，并且配置了 DeepSeek API，当前实现可能会尝试走 LLM 解析。

这意味着：

- “月度总结 / 年度总结 / 去年今日 / 同一地点”这类推荐，首版完全可以设计成 metadata-heavy 查询，不依赖云端 API。
- “成长轨迹 / 美学精选 / 兴趣爱好”这类纯语义推荐，首版不建议默认启用，否则可能在部分设备上触发 LLM 解析。

### 2.4 “保存的故事”当前链路

当前保存故事的入口主要在：

- `lib/view/pages/theme_clusters_page.dart`
  - 右上角按钮 push `StoriesPage()`

真实故事数据流如下：

1. `lib/view/pages/stories_page.dart`
   - 调用 `StoryService().getAllStories()`
2. `lib/service/story_service.dart`
   - 从 Isar 读取 `StoryEntity`
3. 打开单篇故事时：
   - `StoryService().loadPhotos(story.photoIds)`
   - push 到 `StoryResultPage.fromStoryEntity(...)`

数据实体是：

- `lib/models/entity/story_entity.dart`

结论：

- “保存的故事”完全可以从 `StoriesPage` 的数据源迁移到新入口页中来。
- 现有 `StoriesPage` 可以保留，作为二级完整列表页；新页面则提供更美观的故事入口。

### 2.5 可复用的推荐经验

`lib/view/pages/home_page.dart` 里已经有一套“规则卡片推荐”逻辑，例如：

- 年度总结
- 月度总结
- 去年今日
- 地点回顾

它说明项目里已经接受“基于时间/地点规则主动推荐”的产品方向。

这对本次需求很有帮助：

- 我们不是从零发明“推荐卡片”
- 而是把“推荐发现”从首页泛推荐，升级为“创作入口中的可创作推荐”
- 同时把底层筛选能力换成统一的语义搜索服务

---

## 3. 总体实现策略

## 3.1 页面替换策略

建议新增页面：

- `lib/view/pages/create_hub_page.dart`

命名理由：

- 它不再只是“搜索页”
- 更像“创作入口 / 创作中枢”
- 也能和旧的 `CreatePage` 明确区分

路由切换方式：

1. 保留 `lib/view/pages/create_page.dart` 原样，不删代码。
2. 修改以下入口改为打开 `CreateHubPage`
   - `lib/view/widget_tree.dart`
   - `lib/view/pages/home_page.dart`

这样满足“替换整个界面，但不删除现在该界面的所有代码”。

## 3.2 新页面的模块划分

新页面建议分成两个主模块：

1. 创作推荐
   - 主动推送的推荐卡片
   - 数据来自统一语义搜索服务
2. 保存的故事
   - 以封面卡片/横向故事列展示
   - 不再只是从“主题”页右上角按钮进入

页面结构建议：

1. 顶部返回按钮，延续当前 create 页的轻盈感
2. 一个主标题区域
   - 例如“开始创作”或“为你准备的故事线索”
3. 创作推荐模块
   - 大卡片 + 封面拼贴 + 标签
4. 保存的故事模块
   - 横向封面带标题，或带下拉排序
5. 整体背景继续沿用当前 create 页的氛围背景

---

## 4. UI 设计方案

## 4.1 风格延续

保留这些视觉要素：

1. 浅色画布 `#FAFAFA`
2. 顶部粉/紫柔焦氛围背景
3. 圆角大卡片
4. 柔和阴影
5. 强调色仍以当前页面的粉紫系为主，不突然改成另一套系统

但页面布局不再是底部大搜索框，而改成“内容先行”的卡片流。

## 4.2 创作推荐的展示方式

建议采用“纵向大卡片流”：

每张推荐卡片包含：

1. 推荐类型标签
   - 月度总结
   - 年度总结
   - 去年今日
   - 同一地点
   - 节假日
2. 标题
   - 例如“你的 2026 年 3 月回顾”
3. 副标题
   - 例如“从 18 张照片里，挑出这个月最值得讲成故事的一组瞬间”
4. 封面拼贴
   - 3 张或 4 张图片拼贴
5. 数量信息
   - 命中 12 张
6. 操作按钮
   - “继续创作”
   - “暂不显示”

首屏建议只展示 2~4 张质量最高的推荐卡片，不要把所有预设都堆出来。

## 4.3 保存的故事展示方式

这里不建议只放一个“查看故事列表”的按钮。

建议设计为：

1. 模块标题：保存的故事
2. 右上角提供一个轻量下拉菜单
   - 最近保存
   - 最近更新
   - 照片数量最多
3. 主体用横向封面卡片列表
   - 每张卡片显示故事封面、标题、日期、照片数
4. 卡片点击直接进入 `StoryResultPage`
5. 最后一个卡片可放“查看全部”

为什么这样设计：

1. 视觉上比单独按钮更完整
2. 用户一眼就能看到自己保存过什么
3. 比下拉框单独占主导更直观
4. 仍然满足你说的“下拉框或者展示封面，请你设计”

我的建议是：封面卡片为主，下拉排序为辅。

---

## 5. 创作推荐的核心逻辑

## 5.1 推荐不是用户搜索，而是系统自动评估

创作推荐的定义：

- 用户进入新页面时，不需要先输入任何内容
- 系统自动检查预定义推荐语句
- 通过统一语义搜索服务去搜索
- 只有当命中结果达到阈值，才把它展示成推荐卡片

这与现在的 `CreatePage` 是完全不同的交互逻辑：

- 现在是“用户提问 -> 系统搜索”
- 新版是“系统先发现 -> 用户决定是否创作”

## 5.2 推荐预设的组织方式

建议新建一个“推荐预设表”，而不是把语句散落在 UI 中。

建议新增一个纯配置文件或 VO：

- `lib/models/vo/create_recommendation_preset.dart`
  或
- `lib/service/create_recommendation_service.dart` 内部静态定义

每个预设建议包含字段：

1. `id`
2. `group`
   - `semantic`
   - `time_space`
3. `titleBuilder`
4. `subtitleBuilder`
5. `queryBuilder(now)`
6. `minPhotoCount`
7. `refreshInterval`
8. `cooldownInterval`
9. `enabledByDefault`
10. `priority`

## 5.3 首版推荐预设建议

### 默认启用的预设

这些推荐默认启用，因为可以稳定走本地 metadata / time-space 逻辑：

1. 月度总结
   - query 示例：`2026年3月的回忆`
   - 阈值：`>= 9`
2. 年度总结
   - query 示例：`2025年的回忆总结`
   - 阈值：`>= 9`
3. 去年今日
   - query 示例：`2025年4月5日的回忆`
   - 阈值：`>= 9`
4. 同一地点
   - query 示例：`在杭州的回忆`
   - 前提：最近高频地点足够集中
   - 阈值：`>= 9`
5. 节假日
   - query 示例：`春节的回忆` / `国庆旅行`
   - 前提：时间窗口命中明显

### 先预留、默认关闭的预设

这些更接近你图里的 AI 语义触发，但首版不建议默认开启：

1. 成长轨迹
2. 美学精选
3. 兴趣爱好

原因：

1. 它们更像纯语义概念，当前 parser 在某些情况下可能会尝试走 LLM 解析。
2. 你明确强调默认不要依赖大模型 API。
3. 这类推荐更适合第二阶段做“本地短路语义模板增强”后再打开。

也就是说：

- 这些预设先在代码结构里留好位置
- 但产品开关默认关闭

## 5.4 推荐命中判定

建议首版采用保守策略：

1. 统一调用 `SemanticPhotoSearchService.search(query)`
2. 以 `exactPhotos` 为主判断推荐是否成立
3. 只有当 `exactPhotos.length >= 9` 时才生成推荐卡片

为什么不用“exact + related >= 9”直接放开：

1. 主动推送比手动搜索更怕噪音
2. 推荐页命中质量必须高一些
3. 月度/年度这类推荐本身以时间约束为主，`exact` 足够好用

后续如要放宽，可以单独对某些预设允许：

- `exactPhotos >= 6 && exactPhotos + relatedPhotos >= 12`

但不建议作为首版默认逻辑。

## 5.5 去重与冷却规则

你特别强调两点：

1. 不能短时间内同一个语句重复搜索
2. 也不能搜索一次后就永远不搜

所以需要两类时间策略：

### A. 搜索间隔

同一个预设的同一条 query，至少间隔 3 天再重新评估一次。

例如：

- 月度总结在 4 月 1 日跑过
- 4 月 2 日、4 月 3 日进入页面时不再重跑
- 4 月 4 日或之后才允许再次评估

### B. 推荐冷却

同一个预设已经产生推荐后，如果推荐内容没有明显变化，不要重复把它当成“新推荐”反复冒出来。

建议规则：

1. 若 query 相同且命中照片签名基本一致，则只更新 `lastCheckedAt`，不重复新建推荐
2. 若 query 相同但新增了明显的新照片，可更新现有推荐卡片内容
3. 若 query 已过期（例如月份切换），则让旧推荐归档，新 query 产生新推荐

---

## 6. 推荐保存与持久化设计

## 6.1 为什么不能只靠内存

如果只存在内存里，会有这些问题：

1. 页面退出后推荐丢失
2. 无法记录“3 天内不要重复搜”
3. 无法判断“这个推荐之前是否已经展示过”
4. 无法在下次打开页面时秒开卡片

所以推荐必须持久化。

## 6.2 建议使用 Isar，而不是只用 SharedPreferences

项目当前核心数据已经广泛使用 Isar。

本需求里的推荐数据也不是一个简单布尔值，而是结构化对象：

1. 预设 ID
2. query
3. 命中照片 ID 列表
4. 封面照片 ID
5. 最近搜索时间
6. 最近推荐时间
7. 下次允许搜索时间
8. 状态

因此建议新增实体：

- `lib/models/entity/create_recommendation_entity.dart`

建议字段：

1. `id`
2. `presetId`
3. `group`
4. `title`
5. `subtitle`
6. `query`
7. `photoIds`
8. `coverPhotoIds`
9. `matchedCount`
10. `createdAt`
11. `updatedAt`
12. `lastCheckedAt`
13. `lastRecommendedAt`
14. `nextCheckAt`
15. `status`
   - `active`
   - `dismissed`
   - `expired`
   - `archived`
16. `resultFingerprint`
   - 用于判断这次结果与上次是否本质相同

## 6.3 推荐服务层

建议新增：

- `lib/service/create_recommendation_service.dart`

职责如下：

1. 加载预设列表
2. 判断哪些预设现在应该被评估
3. 调用 `SemanticPhotoSearchService.search(query)`
4. 判断是否达到推荐阈值
5. 写入/更新 `CreateRecommendationEntity`
6. 产出 UI 可直接消费的推荐列表

这样页面层只负责展示，不自己拼业务逻辑。

---

## 7. “三天一搜”的实现方式

## 7.1 首版不做真后台任务，做“懒触发定时”

当前项目没有现成的 `workmanager` / `background_fetch` 体系。

所以首版建议做成：

1. 用户进入 `CreateHubPage` 时检查
2. App 从后台恢复到前台时，如果当前就在该页，也检查
3. 对每个预设判断 `now >= nextCheckAt`
4. 满足才发起搜索

这已经能满足“定时比如三天”的产品效果，而且更稳：

1. 不引入原生后台任务复杂度
2. 不需要额外平台适配
3. 用户每次来到入口页时，都能看到相对新鲜的推荐

## 7.2 后续可升级成真后台

如果后面你明确要“用户完全不打开 App 也要后台刷新”，再考虑：

1. Android `workmanager`
2. iOS 后台刷新能力

但这不建议作为这次第一阶段的实现目标。

---

## 8. “保存的故事”迁移方案

## 8.1 数据来源

继续复用现有故事服务：

- `StoryService().getAllStories()`
- `StoryService().loadPhotos(...)`

不要重新发明一套故事存储。

## 8.2 展示方式

建议做一个“故事封面横向列表”组件，显示：

1. 封面图
   - 优先取 `story.photoIds.first`
2. 标题
3. 副标题
4. 日期
5. 照片数

右上角加一个排序下拉：

1. 最近保存
2. 最近更新
3. 照片最多

点击故事卡片后：

- 直接打开 `StoryResultPage.fromStoryEntity(...)`

## 8.3 为什么不直接复用 `StoriesPage` 原样嵌进来

`StoriesPage` 当前是一个标准 `ListTile` 列表页，适合作为独立页，不适合直接作为创作入口的核心内容展示。

所以建议：

1. 保留 `StoriesPage` 作为“查看全部”
2. 新入口页做更精致的故事预览组件

---

## 9. 建议新增/修改的文件范围

## 9.1 新增文件

建议至少新增这些文件：

1. `lib/view/pages/create_hub_page.dart`
   - 新创作入口页
2. `lib/service/create_recommendation_service.dart`
   - 推荐评估与持久化
3. `lib/models/entity/create_recommendation_entity.dart`
   - 推荐存储实体

可选新增：

4. `lib/models/vo/create_recommendation_preset.dart`
   - 预设定义
5. `lib/models/vo/create_story_preview_vo.dart`
   - 故事封面展示模型
6. `lib/view/widgets/create_recommendation_card.dart`
7. `lib/view/widgets/story_preview_card.dart`

## 9.2 需要改动的现有文件

1. `lib/view/widget_tree.dart`
   - FAB 跳转从 `CreatePage` 改成 `CreateHubPage`
2. `lib/view/pages/home_page.dart`
   - “开始创作”入口改成 `CreateHubPage`
3. `lib/main.dart` 或页面生命周期相关位置
   - 仅当需要做 App 恢复前台后的推荐刷新联动时再接

## 9.3 明确不动或暂不删除的文件

1. `lib/view/pages/create_page.dart`
   - 保留为旧版页面，不删除
2. `lib/view/pages/stories_page.dart`
   - 继续保留，作为完整列表页

---

## 10. 推荐卡片的点击流转

这里有两种做法。

### 做法 A：点击推荐卡片后，进入 `AlbumSearchPage`

优点：

1. 完整复用你指定的语义搜索结果页
2. 几乎不重复写选图逻辑
3. 自动继承现有“加入故事队列 / 生成故事”流程

缺点：

1. 进入后会重新执行一次搜索
2. 无法直接利用推荐缓存中的 photoIds 做秒开

### 做法 B：点击推荐卡片后，进入一个新的“推荐详情页”

优点：

1. 可以直接展示保存下来的命中照片
2. 页面速度更快
3. 体验更连贯

缺点：

1. 需要新做一套预览页
2. 成本更高

### 本次建议

首版推荐采用做法 A：

- 推荐页负责“发现”
- `AlbumSearchPage` 负责“结果浏览与继续创作”

理由：

1. 风险最低
2. 最符合“必须复用相册页顶部语义搜索链路”的要求
3. 先把主动推荐做对，再做二次体验优化

---

## 11. 实施顺序建议

建议分 5 步做，而不是一口气全塞进一个大页面。

### 第 1 步：完成页面替换骨架

1. 新建 `create_hub_page.dart`
2. 把“+”入口切到新页
3. 先用静态占位把两大模块搭出来

### 第 2 步：接入“保存的故事”

1. 复用 `StoryService().getAllStories()`
2. 做故事封面横滑卡片
3. 支持点击进入故事结果页

### 第 3 步：做推荐实体与推荐服务

1. 新增推荐实体
2. 新增推荐预设
3. 新增推荐刷新逻辑

### 第 4 步：接入创作推荐 UI

1. 推荐卡片渲染
2. 点击跳 `AlbumSearchPage`
3. 支持“暂不显示”或轻量关闭

### 第 5 步：补推荐节流与周期刷新

1. 3 天刷新
2. 同 query 冷却
3. 同结果签名去重

---

## 12. 关键风险与对应处理

## 12.1 风险：某些语义推荐会走 DeepSeek

处理：

1. 首版默认只开 metadata/time-space 推荐
2. 语义型预设先预留、先关掉
3. 真要启用时，再补本地短路规则

## 12.2 风险：主动推荐结果噪音太大

处理：

1. 首版阈值用 `exactPhotos >= 9`
2. 限制首屏只显示高优先级推荐
3. 同 query 冷却 3 天

## 12.3 风险：故事封面取图成本高

处理：

1. 先只取每个故事第一张图做封面
2. 打开故事详情时再完整加载全部照片

## 12.4 风险：用户以为旧搜索被完全删除

处理：

1. 旧 `CreatePage` 代码保留
2. 仅替换入口，不直接删除旧页面
3. 如有必要，可在后续阶段决定是否彻底下线旧页

---

## 13. 我建议的首版产品范围

如果要做得稳、快、可验证，我建议首版范围定为：

1. 新建 `CreateHubPage`，替换“+”入口
2. 页面包含
   - 创作推荐
   - 保存的故事
3. 创作推荐首版默认只启用
   - 月度总结
   - 年度总结
   - 去年今日
   - 可选：同一地点
4. 统一调用 `SemanticPhotoSearchService.search(query)`
5. 推荐结果持久化保存
6. 每 3 天重新评估一次
7. 保存的故事以封面卡片展示，并支持下拉排序

暂不纳入首版的内容：

1. 纯语义型推荐默认启用
2. 真后台任务调度
3. 新的推荐详情页

---

## 14. 最终结论

这次改造最合适的方式不是在 `create_page.dart` 上继续叠逻辑，而是：

1. 保留旧 `CreatePage`
2. 新建 `CreateHubPage`
3. 把“+”入口整体切到新页
4. 新页只做两件事
   - 展示系统主动发现的创作推荐
   - 展示用户已保存的故事

其中“创作推荐”的底层一定复用：

- `AlbumPage` 对应的统一语义搜索链路
- 即 `AlbumSearchPage` + `SemanticPhotoSearchService`

并通过“推荐实体 + 推荐服务 + 3 天重刷 + query 冷却 + 结果去重”来保证：

1. 不重复刷同一句
2. 也不会只搜一次就停掉
3. 推荐结果可以被保存和复用

这套方案和你当前项目结构是兼容的，且首版风险可控。
