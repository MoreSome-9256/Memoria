# 用户界面与创作流程

本文只描述普通用户可见功能，不包含“开发者设置”中的实验页。

## 1. 全局导航和状态

`WidgetTree` 承载首页、相册、中央创作按钮、主题和我的，并在所有页面上叠加统一分析进度横幅和回忆助手。

```text
WidgetTree._handleForegroundProgressChanged()
  -> completed / stopped / failed
  -> AIService.refreshJunkCleanupReportFromDatabase()
  -> 延迟停止 foreground task
```

问题：全局进度与相册页自己的任务提示重复；stopped/failed 时不一定完成 post-filter，却仍刷新 junk 报告。

## 2. 首页 `HomePage`

功能：

- “我的相册”随机背景轮播
- 进入创作中心
- 最多两张“发现”回忆卡片
- 点击发现卡片进入事件详情

```text
initState() -> _loadHeroAssets() + _generateDiscoverCards()
_buildHeroCard() -> CreateHubPage
_buildDiscoverCard() -> EventDetailPage
```

首页发现使用临时 `Map<String, dynamic>`，不是正式推荐实体。问题包括缺少类型约束、与创作推荐重复、依赖标签字符串和 joyScore。

## 3. 相册页 `AlbumPage`

功能：

- 当前分析任务和进度
- 启动、停止、删除分析任务
- 自然语言搜索
- 标签分类浏览
- 按事件浏览
- 低价值候选确认窗口
- 导入、更新、重建、权限管理

搜索调用：

```text
AlbumPage._submitSemanticSearch()
  -> AlbumSearchPage(initialQuery)
  -> SemanticPhotoSearchService.search()
```

标签浏览调用：

```text
_buildAlbumTagBrowserData()
  -> AlbumTagBrowserService.buildCoarseClusters()
  -> _openTagClusterBrowser()
  -> 按细标签、月份浏览
```

低价值候选：

```text
AIService.junkCleanupReportListenable
  -> AlbumPage._onJunkCleanupReportChanged()
  -> _showJunkCleanupDialog()
  -> markCandidatesAsLowValue() 或 markCandidatesAsKept()
```

只要数据库仍存在 `__junk_pending__`，进入相册页后应继续提示。

问题：

- 单页面同时负责权限、扫描、搜索、标签、事件和 junk UI，职责过重。
- `_requestPhotoPermission()` 的失败路径可能连续请求多次权限。
- 标签浏览只加载有界近期数据。
- junk 对话框依赖全局报告刷新时机。

## 4. 创作中心 `CreateHubPage`

功能：

- 原始语义创作入口
- 创作推荐卡片
- 已保存故事预览
- 刷新和忽略推荐

```text
initState()
  -> _loadCachedContent()
  -> _refreshRecommendationsInBackground()

点击描述想找的回忆 -> CreatePage
点击推荐 -> AlbumSearchPage(lockInitialResults: true)
点击故事 -> StoryResultPage.fromStoryEntity()
```

推荐点开后不会重新搜索，而是打开推荐实体中固化的照片 ID。封面加载会 reconcile，但不会立即验证全部推荐照片。

## 5. 原始创作入口 `CreatePage`

```text
_performSearch(query)
  -> SemanticPhotoSearchService.search(query)
  -> 合并 exactPhotos + relatedPhotos
  -> 额外跳过 photo.isProbablyScreenshot
  -> 默认全选结果

_generateStory()
  -> compute(_buildCreateLaunchResult)
  -> 构造虚拟 AITheme 和 Event
  -> ConfigPage
```

问题：

- 单独跳过截图，与统一 junk 确认边界冲突。
- 搜索异常被表现为空结果。
- 默认全选 related，可能带入弱相关照片。
- `_candidateLabels` 只是中文字符串包含，不参与真正语义检索。

## 6. 回忆助手 `ChatPage`

```text
MemoryAssistantOverlay -> ChatPage
ChatPage._handleSend()
  -> _executeLocalSearch(userText)
  -> SemanticPhotoSearchService.search(userText)
  -> 展示结果并可进入创作
```

它主要是“自然语言搜索入口 + 创作跳转”，不是持续多轮推理代理。搜索失败反馈有限。

## 7. 主题页 `ThemeClustersPage`

功能：

- 查看六个固定主题
- 切换纯 embedding / 混合模式
- 刷新聚类
- 查看主题子簇和月份时间线
- 进入故事列表

```text
ThemeClustersPage
  -> ThemeClusterService.loadClusters()
  -> ThemeClusterDetailPage
```

结果没有持久化，每次加载可能变化。“主题聚类”容易被理解为自动发现主题，实际是固定六类分类后再做 DBSCAN。

## 8. “我的”页面 `ProfilePage`

普通用户功能：

- 账号信息
- 相册 AI 模型设定和权重管理
- 相册访问权限和白名单
- 扫描时间与最小分辨率
- 低价值照片回收站
- 缓存管理、关于和退出登录

运行时 AI 设置包括自动分析、自动恢复、是否包含视频、OCR、推理加速器、线程数和 batch 大小。

低价值回收站只展示 `__junk_candidate__`。恢复会移除垃圾状态；显式删除时才请求系统删除原图。

## 9. 故事配置与生成

用户可从创作入口、推荐、标签浏览、搜索结果或故事队列进入 `ConfigPage`。

```text
StoryGenerationOrchestrator.generateStory()
  -> _loadSelectedPhotoEntities()
  -> 按用户顺序或时间排序
  -> _buildMetadataBullets()
  -> _buildPhotoMaterial()
  -> 根据模式：
     A. 本地 VLM caption，再交给 DeepSeek
     B. 本地 VLM 直接多图写故事
     C. 标签/元数据直接交给 DeepSeek
  -> _buildHighlights()
  -> 可选：分析音乐节奏
  -> _buildOutlineBullets()
  -> _generateDeepSeekStory() 或使用本地结果
  -> _saveStory()
  -> StoryResultPage
```

本地 caption 模式最多抽样 12 张，每张由 SmolVLM 独立读取三次，分别关注主体动作、环境构图、文字遮挡；输出英语可见事实，再供中文故事生成使用。

本地直接故事最多抽样 9 张，失败回退 DeepSeek。DeepSeek 接收照片标签、OCR、caption、位置、时间、原始搜索词、模板和音乐分析，输出中文结构化 JSON。

问题：

- 生成进度预览多处使用 `photo.path`，path 为空时可能没有预览。
- 本地 VLM payload 仍含 path，结构上容易重新引入路径依赖。
- 本地直接故事只抽样部分照片，最终逐图 sections 可能对应不准。
- DeepSeek 解析失败会静默使用规则 fallback。
- 自动保存故事只保留最新一条未手动保存记录。

## 10. 故事结果、视频和数字相册

- `StoryResultPage` 展示故事和逐图内容，并进入播放回忆。
- `StoryVideoPage` 与离屏渲染 worker 根据图片、文案、音乐和转场生成预览及导出。
- 数字相册服务负责布局、内容组织、验证和书册展示，不重新检索照片。

风险：

- 动态图片和视频依赖可播放资源准备，临时文件失效会影响预览。
- 导出涉及解码、编码、音乐和缓存，失败点多。
- 逐图文案错位会直接反映到视频字幕。

## 11. 其他普通用户页面

### 11.1 登录与账号

- `WelcomePage`：登录前入口。
- `SignInPage`：通过 Cognito 登录，成功后进入 `WidgetTree`。
- `SignUpPage`：注册账号。
- `ForgotPasswordPage`：密码重置。

认证失败通常由 Amplify/Cognito 异常决定；本地相册能力与云端账号状态在启动协调器中共同初始化。

### 11.2 事件详情

`EventDetailPage` 展示一个 `EventEntity` 的照片、时间、地点和智能标题。事件边界来自时间地点规则聚类，不代表语义上一定属于同一活动。

### 11.3 故事列表与故事队列

- `StoriesPage`：查看已经保存的故事。
- `StoryQueuePage`：查看用户从搜索、标签浏览等入口加入的待创作照片。
- `SelectPhotosPage`：从对话回忆等入口补充选择照片。

故事队列是用户明确选择的临时创作集合，不等同于事件或主题聚类结果。

### 11.4 权限和低价值图片

- `MediaAccessRangePage`：查看系统相册授权状态并选择扫描白名单相册。
- `JunkPhotoTrashPage`：查看 confirmed junk、恢复为普通照片或请求系统删除。

系统媒体权限和应用白名单是两层限制：系统权限外的资源应用不可见；系统权限内但不在白名单的相册不会进入常规扫描。

### 11.5 发布和导出

- `PublishPage`：组织目标平台发布文案和分享。
- `ExportManager`：管理导出任务。
- `DigitalAlbumPage` / `DigitalAlbumBookPage`：展示数字相册和书册形式结果。
