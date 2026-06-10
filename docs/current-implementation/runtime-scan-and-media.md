# 运行时、媒体访问与扫描分析管线

## 1. 启动流程

入口为 `lib/main.dart`。

```text
main()
  -> 初始化 Flutter binding 和 foreground task 通信端口
  -> 配置 Flutter 图片内存缓存
  -> runApp(MyApp)
  -> _StartupGate
  -> _AppStartupCoordinator.resolveLaunchTarget()
     -> AIProgressNotificationService.initialize()
     -> _configureAmplifyAuth()
     -> ObjectBoxService.init()
     -> PhotoService.init()
     -> AppAiSettingsService.load()
     -> 设置运行时 OCR 开关
     -> 可选：AlbumRefreshService.startRefresh()
     -> 可选：UnifiedAnalysisPipelineService.startPendingAnalysisCandidates()
  -> 根据登录状态进入 WelcomePage 或 WidgetTree
```

启动阶段不会主动预热全部 AI 模型。若开启“自动分析新照片”，启动后会异步进入统一扫描管线。

风险：

- 自动扫描开始时，用户可能短暂看到数据库旧状态。
- ObjectBox 初始化失败只打印日志并继续，依赖数据库的页面可能更晚才失败。
- 登录状态判断与本地功能初始化在同一个启动协调器中。

## 2. 媒体权限

### 2.1 Android 权限

`AndroidManifest.xml` 声明：

- Android 12 及以下：`READ_EXTERNAL_STORAGE`
- Android 13+：`READ_MEDIA_IMAGES`、`READ_MEDIA_VIDEO`
- Android 14+：`READ_MEDIA_VISUAL_USER_SELECTED`

应用目标 SDK 为 35，编译 SDK 为 36。

### 2.2 Android 14 “选择更多照片”

Android 14 的部分照片访问由三项权限共同决定：

- `READ_MEDIA_IMAGES`
- `READ_MEDIA_VIDEO`
- `READ_MEDIA_VISUAL_USER_SELECTED`

`photo_manager 3.9.0` 的 `requestPermissionExtend()` 在已经拥有
`READ_MEDIA_VISUAL_USER_SELECTED` 时，会错误地提前判断为“已有权限”，所以
`requestPermissionExtend(RequestType.all)` 无法再次展示
“允许全部照片和视频 / 修改已选范围”的系统流程。

当前按钮实现：

```text
AlbumPage / MediaAccessRangePage
  -> Android:
     [Permission.photos, Permission.videos].request()
  -> permission_handler 在一次 ActivityCompat.requestPermissions 中
     请求 READ_MEDIA_IMAGES 和 READ_MEDIA_VIDEO
  -> Android 14 根据 manifest 中声明的
     READ_MEDIA_VISUAL_USER_SELECTED 处理 limited 状态
  -> 系统决定展示全部访问或修改范围流程
  -> 返回后 invalidateScanSessionCache()

  -> 非 Android:
     PhotoManager.presentLimited(type: RequestType.all)
```

按钮只发起一次 `permission_handler` 请求，不再先调用一次权限请求、再调用一次范围选择器。`permission_handler_android 13.0.1` 会把 Android 14 部分访问识别为 `PermissionStatus.limited`，因此不会像当前 `photo_manager` 一样提前返回。

官方行为依据：[Android 14 授予对照片和视频的部分访问权限](https://developer.android.com/about/versions/14/changes/partial-photo-video-access?hl=zh-cn)。官方要求重新选择时在一次操作中重新请求图片、视频和 `READ_MEDIA_VISUAL_USER_SELECTED` 权限。

### 2.3 白名单相册

系统媒体权限决定应用能看到哪些资源；`AlbumSelectionPreferenceService` 保存的相册白名单进一步限制扫描范围。

```text
MediaAccessRangePage
  -> PhotoManager.getAssetPathList(RequestType.common)
  -> 用户勾选相册
  -> AlbumSelectionPreferenceService.saveSelection()
  -> PhotoService.invalidateScanSessionCache()
```

风险：

- `MediaAccessRangePage._loadPermissionAndAlbums()` 会调用权限请求，读取页面状态本身可能触发权限 UI。
- 项目多处分别请求 image、video、common，权限体验不完全统一。
- Android 系统可能根据用户此前拒绝次数决定不重复展示同样的说明框；应用只能正确发起请求，不能强制系统 UI。

## 3. 相册页扫描入口

`AlbumPage._showRefreshOptions()` 提供：

- 导入已授权范围内的新图片
- 仅更新相册缓存
- 添加更多可分析照片
- 重新分析全部
- 一键标记低价值图片
- 管理照片访问权限

实际扫描由 `AlbumRefreshService` 和 `UnifiedAnalysisPipelineService` 负责。

## 4. 统一扫描与 AI 分析

### 4.1 顶层调用链

```text
UnifiedAnalysisPipelineService.startUnifiedPipeline()
  -> runInsideForegroundService()
  -> 增量：_runIncrementalPipeline()
     或全量：_runFullRebuildPipeline()
  -> Future.wait(_runProducer(), _runConsumer())
  -> _onPipelineCompleted()
```

全量重建会先执行 `PhotoService.clearAllCachedData()`。

### 4.2 Producer：扫描和入库

```text
_runProducer()
  -> AppAiSettingsService.load()
  -> _resolveRequestType()
  -> 可选：PhotoManager.requestPermissionExtend()
  -> AlbumSelectionPreferenceService.loadSelection()
  -> _resolveProducerTargetAlbums()
  -> 分页读取 AssetPathEntity.getAssetListPaged()
  -> 去重 asset.id
  -> _buildAndSavePhotoEntity(asset)
     -> PhotoService.buildAndSaveSinglePhoto()
  -> 若未分析、未隔离为 junk、未在活动队列
     -> _handoffBatchToAi()
```

带有 `__junk_pending__` 或 `__junk_candidate__` 的照片不会再次进入 AI 队列。用户将候选标记为保留后会得到 `__junk_kept__`，post-filter 不再重复判定它。

### 4.3 Consumer：逐张分析

```text
_runConsumer()
  -> 读取 AI 设置和 MobileCLIP backend
  -> MobileClipLiteRtService.warmUp()
  -> MobileClipTagService.warmUp()
  -> 循环 queue.dequeue()
  -> _processSinglePhoto()
```

```text
_processSinglePhoto(photo)
  -> 根据 mediaKind 判断 image / dynamicImage / video
  -> _readAnalysisImageInputFromAsset(photo)
     -> AssetEntity.fromId(photo.assetId)
     -> MediaAnalysisImageReader.readAsset(asset)
  -> 图片：MobileClipEmbeddingService.resolvePhotoEmbedding()
  -> 动态图片/视频：MediaEmbeddingService.embedPreparedMediaBytes()
  -> MobileClipTagService.retrieveTags(tagEmbedding)
  -> 更新 imageEmbedding / aiTags / isAiAnalyzed
  -> PhotoEmbeddingIndexRepository.upsertEmbedding()
  -> 异步排队位置属性任务
```

### 4.4 主扫描当前没有执行的分析

统一扫描当前没有直接调用：

- `FacePipelineService` 人脸检测
- `OcrService` OCR
- 图片 caption/VLM 描述
- joyScore 计算

这些字段却被检索、主题聚类、首页发现和故事功能使用，是多个上层功能不稳定的重要原因。

## 5. 图片、动态图片和视频

AI 读取边界：

```text
assetId -> AssetEntity.fromId() -> MediaAnalysisImageReader.readAsset()
```

- Apple Live Photo：由系统资源 subtype 和配套视频资源决定。
- Android Motion Photo：可能是 JPEG/HEIC 内嵌视频；Dart
  `MotionPhotoService` 通过 `AssetEntity.originBytes` 读取原始媒体，在 isolate
  中定位内嵌 MP4，并写入临时缓存供播放器使用。

## 平台代码边界

- Android `MainActivity.kt` 只保留打开系统电池优化管理页的 MethodChannel。
  `permission_handler` 可以负责申请豁免和查询状态，但没有打开该专用管理页的
  Dart API。
- 照片权限、相册读取、缩略图、原始媒体读取和 Motion Photo 解析均由 Dart
  与 Flutter 插件完成。
- 已删除无调用的 Android 目录授权、目录递归扫描、`content://` 字节读取和
  前台任务生命周期调试日志。当前扫描来源仅为 `photo_manager` 系统相册资产。
- iOS 没有自定义 MethodChannel。`AppDelegate.swift` 仅保留 Flutter 插件注册、
  通知 delegate 和 `flutter_foreground_task` 要求的后台 engine 注册。
- 动态图片按 `dynamicImage` 处理，可使用视频帧或静态封面。
- 视频通过缩略图和有限抽帧生成一个媒体向量，不理解完整叙事和音频。

## 6. MobileCLIP 分层打标签

标签定义位于 `tag_taxonomy_v2.dart`，固定 prompt 为英语。

```text
MobileClipTagService.warmUp()
  -> 构建细粒度标签 prototype
  -> 构建粗粒度标签 prototype
  -> 每个标签的 prompt embedding 求平均并 L2 normalize
  -> 写入临时缓存

retrieveTags(imageEmbedding)
  -> retrieveCoarseTagDiagnostics()
  -> 选出置信粗分类
  -> 只在对应细分类中打分
  -> 应用维度阈值、粗分类权重和动态 topK
  -> 无可靠结果时返回“其他”
```

问题：

- 多 prompt 简单平均会稀释差异较大的视觉概念。
- 粗分类先筛选意味着映射缺失的细分类永远无法出现。
- taxonomy 存在细分类未映射、映射指向不存在分类的问题。
- “其他”让照片在标签浏览中几乎没有信息量。

## 7. 低价值图片 post-filter

post-filter 在全部分析结束后执行：

```text
_onPipelineCompleted()
  -> _publishPostFilterJunkReport()
  -> JunkPhotoCleanupService.evaluateAnalyzedPhotosForPending()
  -> AIService.refreshJunkCleanupReportFromDatabase()
```

当前 10 个类别：二维码、梗图、低信息自拍、广告海报、截图、文档、低事件价值图形、严重遮挡/过暗、低价值路牌、严重模糊。

```text
JunkPhotoFilterService.evaluateBatch(all embeddings)
  -> 对每类计算每张照片与最佳英语 prompt 的相似度
  -> significantOutlierIds()
     cutoff = max(绝对阈值, median + lift, median + 3.5 * robustSpread)
  -> 合并类别命中
  -> 最终最多保留整批照片数量的 5% 为候选
```

候选先标记 `__junk_pending__`。用户选择：

- 低价值：转为 `__junk_candidate__`，后续扫描和检索跳过；
- 保留：转为 `__junk_kept__`，以后不再提示。

真正删除系统原图时：

```text
JunkPhotoCleanupService.movePhotosToSystemTrash()
  -> PhotoManager.editor.deleteWithIds(assetIds)
  -> 只对系统确认删除成功的资源移除本地记录和事件引用
```

问题：

- 少于 20 张有效 embedding 时完全不检测。
- 某类垃圾占比高时不再是离群点，可能全部漏掉。
- 全局最多 5% 会压掉真实候选。
- 主观类别误伤风险明显。
- 没有利用 OCR 密度、清晰度、亮度等直接质量信号。

## 8. 扫描结束后的事件聚类

只有分析启用且本次存在 AI 候选时，完成阶段才调用 `EventService.runClustering()`。事件聚类失败不会让整个扫描失败。
