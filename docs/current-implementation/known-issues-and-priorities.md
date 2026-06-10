# 已知问题、设计缺陷与修复优先级

## 不可用的本地 InternVL 实验链

Android 和 iOS 均没有设备原生 InternVL 后端。`OnDeviceInternvlService`
保留故事生成 orchestrator 当前依赖的回退接口，但会直接返回不可用，不再调用
一个未实现的平台通道。彻底删除这些模型与回退分支需要同时收缩故事生成
orchestrator 和相关开发者页面，适合单独处理。

## 1. P0：直接影响正确性

### 1.1 动态语义字段没有强制英语校验

固定 MobileCLIP prompt 基本都是英语，但 LLM 返回的
`positive_semantics`、`recall_semantics`、`negative_semantics`
只检查非空和权重，不检查语言。LLM 偶尔返回中文时，会直接生成中文 MobileCLIP 文本向量，搜索效果无声下降。

建议：结构化查询阶段拒绝视觉语义字段中的 CJK 并触发 repair；最终 `embedText` 边界再次保护。

### 1.2 主扫描没有稳定生成人脸、OCR、笑脸和 joyScore

正式检索、首页“愉快回忆”、主题聚类和故事线索都使用这些字段，但统一扫描当前只执行媒体 embedding、MobileCLIP 标签和异步位置任务。

建议：明确哪些属性属于正式扫描步骤；不准备执行的字段不要继续作为正式筛选条件；UI 不应把缺失值当成真实的零。

### 1.3 标签 taxonomy 映射不完整

细分类只有在映射到已命中的粗分类时才会计算。映射缺失会使细分类永久不可达。

建议添加自动测试：

- 每个细分类必须映射到存在的粗分类；
- 每个映射目标必须存在；
- 每个粗分类至少有一个有效细分类；
- 构建时失败，不允许运行时静默退化。

### 1.4 创作入口仍单独跳过截图

`CreatePage._performSearch()` 明确过滤 `photo.isProbablyScreenshot`，与“低价值只通过统一 post-filter 候选和用户确认处理”的语义冲突。用户明确搜索截图或文档时，创作入口仍会隐藏它们。

建议删除该特殊过滤，只排除 confirmed/pending junk。

### 1.5 纯元数据检索绕过 junk 和分析状态过滤

`SemanticPhotoSearchService._searchParsedQuery()` 的纯元数据分支直接使用
`_filterByMetadata(allPhotos, query)`，没有使用已经构造的“已分析且非隔离 junk”照片集合。

后果：

- 时间和地点搜索可能返回未分析记录；
- pending junk 和 confirmed junk 可能出现在元数据搜索；
- 时间/地点创作推荐只在后续排除 confirmed junk，pending junk 仍可能进入推荐。

建议：所有检索路线先应用统一可检索照片边界，再执行各自的元数据、标签和语义策略。

## 2. P1：效果不稳定或名不副实

### 2.1 post-filter 对相册分布高度敏感

典型失败模式：

- 相册少于 20 张：完全不检测；
- 某类垃圾很多：不再是离群点，全部漏掉；
- 相册非常多样：正常照片也可能成为离群点；
- 真实垃圾超过 5%：剩余候选被硬上限压掉；
- prompt 阈值稍低：多个类别同时产生候选。

建议将“视觉类别是否匹配”和“是否值得清理”拆开，结合绝对置信度、类别 margin、质量信号和相册分布，并对主观类别使用更严格确认策略。

### 2.2 主题聚类不是自动发现主题

当前实际流程是：

```text
六个固定主题分类 -> 主题内 DBSCAN -> 时间线分组
```

它无法发现用户相册中的演唱会、手工作品、健身、特定人物或长期项目等独特主题。

建议：固定主题保留为导航层；真正的发现模式先对全相册向量聚类，再为稳定簇命名。

### 2.3 人物主题子簇不是真正人脸身份聚类

人物主题使用整图 MobileCLIP embedding 区分“身份簇”，背景、服装和环境都会影响结果。

建议：正式身份功能使用 FaceEntity 人脸 embedding；人脸数据不可用时只展示单人/多人，不声称身份簇。

### 2.4 首页发现与创作推荐重复建设

首页发现是本地规则和临时 Map；创作推荐是结构化语义查询和持久化实体。两套系统会给出不一致结果，也重复维护。

建议：首页消费统一推荐实体，只负责展示样式和优先级。

### 2.5 推荐 prompt 英语但过于抽象

“old memories worth revisiting”“visually beautiful photos”等不是稳定可观察的画面描述。

建议拆成可观察视觉证据、时间地点条件和负向语义；“价值”“值得重温”等概念不要直接作为 MobileCLIP prompt。

## 3. P1：权限与媒体访问

### 3.1 `photo_manager` Android 14 limited 状态提前返回

插件 3.9.0 把 `READ_MEDIA_VISUAL_USER_SELECTED` 视为已经满足媒体权限，因此
`requestPermissionExtend(RequestType.all)` 在 limited 状态不会重新展示系统确认流程。

当前“选择更多照片”已改为同时调用
`[Permission.photos, Permission.videos].request()`。`permission_handler` 会把 Android 14
部分访问识别为 limited，并通过一次系统权限请求进入“允许全部 / 修改范围”流程，绕过
`photo_manager` 的提前返回。

仍需真机验证：

- limited -> 点击按钮 -> 系统展示“允许全部 / 修改范围”
- 允许全部 -> 页面刷新为全部访问
- 修改范围 -> 只打开一次系统范围选择
- 取消 -> 不崩溃、不重复弹窗

### 3.2 权限请求分散

权限请求散落于 AlbumPage、MediaAccessRangePage、统一扫描、PhotoScanCoordinator、VLM picker 和 MediaAssetSyncService，并使用不同 RequestType。

建议：页面读取状态与主动申请权限分开；避免仅打开设置页就主动请求权限。

## 4. P2：性能和可维护性

### 4.1 HomePage 读取全部系统相册资源再 shuffle

大相册会一次性构建很大的 `AssetEntity` 列表。建议使用分页随机采样，同时保持“不持久化背景列表”和每 5 秒轮播的产品要求。

### 4.2 CreateRecommendationService 读取全部照片

每次推荐刷新先执行 `photoBox.getAll()`，再构建大量 preset。

建议：时间和地点推荐使用数据库查询；语义推荐共享候选集和向量读取；为模板覆盖建立测试，禁止静默 LLM fallback。

### 4.3 页面和服务职责过重

典型文件：

- `AlbumPage`：权限、扫描、搜索、标签、事件、junk UI
- `CreateRecommendationService`：preset、调度、检索、过滤、持久化
- `ThemeClusterService`：加载、补向量、分类、规则打分、子聚类

不应为了“解耦”继续添加无意义 wrapper。只按真实职责拆分系统权限动作、任务控制、页面展示状态和纯算法函数。

## 5. P2：错误处理和可观测性

### 5.1 搜索失败常被表现为空结果

- CreatePage 捕获异常后返回空列表；
- 聊天检索失败返回 null；
- embedding 构建失败返回空向量。

建议区分零命中、查询解析失败、模型不可用和相册无已分析数据，并记录 query plan、候选数量和各层淘汰数量。

### 5.2 故事生成回退不透明

本地 VLM、DeepSeek、JSON 解析都可能回退规则故事，用户只看到最终文本。

建议保存实际生成路径，并在使用规则 fallback 时显示提示。

## 6. 可删除或重新评估

确认无正式调用后应删除：

- 允许任意原始文本直接 embedding 的底层 search API；
- 与正式扫描重复或已绕开的媒体同步/权限 wrapper；
- 主流程永远不会填充、上层仍当作有效数据使用的字段和规则；
- ProfilePage 中长期注释掉的旧设置入口；
- 旧文档中不再成立的 Isar、Dart define 和旧模型描述。

删除前使用 `rg` 和测试确认真实调用关系，不应为了兼容性继续堆叠无调用 wrapper。

## 7. 推荐实施顺序

1. 真机验证 Android 14+“选择更多照片”单次系统权限流程。
2. 给语义查询计划增加英语字段强校验和 repair。
3. 修复 taxonomy 映射完整性并添加测试。
4. 统一纯元数据和语义检索的可检索照片边界。
5. 删除 CreatePage 截图特殊过滤，统一 junk 边界。
6. 决定 OCR、人脸、joyScore 是否进入正式扫描，并清理无效上层规则。
7. 重做 post-filter 评估和真实样本测试。
8. 合并首页发现与创作推荐的数据源。
9. 将主题页逐步升级为真正的用户相册主题发现。
