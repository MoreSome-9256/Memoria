# Memoria (智能影记) 项目架构与功能完整文档

> 项目名称: Memoria / 智能影记  
> 技术栈: Flutter (Dart 3.10.3+), Isar, ObjectBox, Riverpod  
> 入口文件: `lib/main.dart`  
> 路由方式: Navigator.push (无 go_router, 无命名路由)

---

## 目录

<!-- TOC -->
- [1. 项目总体架构](#1-项目总体架构)
- [2. 启动流程](#2-启动流程)
- [3. 数据层 — Models & Entities](#3-数据层--models--entities)
- [4. 存储层 — Storage](#4-存储层--storage)
- [5. 认证模块 (Auth)](#5-认证模块-auth)
- [6. 照片扫描与管理 (Photo Service)](#6-照片扫描与管理-photo-service)
- [7. AI 分析管线 (AI Pipeline)](#7-ai-分析管线-ai-pipeline)
- [8. 事件聚类 (Event Clustering)](#8-事件聚类-event-clustering)
- [9. 语义搜索 (Semantic Search)](#9-语义搜索-semantic-search)
- [10. 主题聚类 (Theme Clusters)](#10-主题聚类-theme-clusters)
- [11. 人脸聚类 (Face Clustering)](#11-人脸聚类-face-clustering)
- [12. 故事生成 (Story Generation)](#12-故事生成-story-generation)
- [13. 视频生成与特效 (Video Generation & Effects)](#13-视频生成与特效-video-generation--effects)
- [14. 数字相册 (Digital Album)](#14-数字相册-digital-album)
- [15. 推荐引擎 (Recommendation Engine)](#15-推荐引擎-recommendation-engine)
- [16. 垃圾照片清理 (Junk Photo Cleanup)](#16-垃圾照片清理-junk-photo-cleanup)
- [17. 旅行记忆检测 (Travel Memory Detection)](#17-旅行记忆检测-travel-memory-detection)
- [18. 音乐生成 (Music Generation)](#18-音乐生成-music-generation)
- [19. 创作中心 (Create Hub)](#19-创作中心-create-hub)
- [20. LLM 集成服务](#20-llm-集成服务)
- [21. 视频转场特效资源](#21-视频转场特效资源)
- [22. 工具与调试页 (Developer Tools)](#22-工具与调试页-developer-tools)
- [23. UI 页面清单](#23-ui-页面清单)
- [24. 配置系统](#24-配置系统)
- [25. 关键数据流图](#25-关键数据流图)
- [26. 环境要求与构建](#26-环境要求与构建)
<!-- /TOC -->

---

## 1. 项目总体架构

Memoria 是一个"智能影记"应用,核心能力是通过 AI 对本地照片进行语义理解、自动聚类、故事化生成和视频制作。

### 1.1 分层架构

```
┌─────────────────────────────────────────────────┐
│  View Layer (lib/view/)                         │
│  Pages / Widgets / WidgetTree                   │
├─────────────────────────────────────────────────┤
│  Service Layer (lib/service/)                   │
│  80+ 服务类: AI Pipeline, Search, Story, Auth   │
├─────────────────────────────────────────────────┤
│  Utils Layer (lib/utils/)                       │
│  Clustering, Filtering, Tag Sanitization, OCR   │
├─────────────────────────────────────────────────┤
│  Models Layer (lib/models/)                     │
│  Entities (Isar), Value Objects                │
├─────────────────────────────────────────────────┤
│  Storage Layer (lib/storage/)                   │
│  Isar (业务数据) + ObjectBox (向量索引 HNSW)    │
├─────────────────────────────────────────────────┤
│  Assets / Config / 3rd-party Models             │
└─────────────────────────────────────────────────┘
```

### 1.2 技术选型

| 组件 | 技术 | 用途 |
|------|------|------|
| 主框架 | Flutter 3.x + Dart 3.10.3+ | 跨平台 UI |
| 业务数据库 | Isar (v3) | Photo, Face, Event, Story 实体 |
| 向量索引 | ObjectBox (HNSW) | 512维 embedding 近似最近邻搜索 |
| 状态管理 | Riverpod + StatefulWidget 本地状态 | 页面状态 |
| 用户认证 | AWS Amplify + Cognito | 登录/注册/密码重置 |
| 照片读取 | photo_manager | 系统相册读取 |
| AI 推理 | LiteRT + onnxruntime (人脸) | MobileCLIP2 S2 与人脸模型推理 |
| 人脸检测 | Google ML Kit | 人脸检测与特征点 |
| OCR | Google ML Kit (默认禁用) | 文字识别 |
| 视频编码 | FlutterQuickVideoEncoder | 硬件加速视频渲染 |
| 音频处理 | FFmpeg | 音视频合成 |
| 音乐生成 | MusicGen (外部服务) | AI 音乐生成 |
| 地图 | - | 通过 GPS 坐标、地址字段存储位置 |

---

## 2. 启动流程

**文件:** `lib/main.dart` (149 行)

### 2.1 `main()` 函数

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}
```

### 2.2 Dart-Define 开关

通过 `--dart-define` 传入的编译开关:

- `MOBILECLIP_VECTOR_PROBE` — 设为 `true` 时直接跳转到 `MobileClipVectorProbePage` (向量探测调试页)
- `ENABLE_STARTUP_MOBILECLIP_WARMUP` — 启动时预热 MobileCLIP (8 秒延迟)
- `ENABLE_ML_KIT_OCR` — 启用 ML Kit OCR (默认禁用)

### 2.3 `MyApp` StatelessWidget

- `MaterialApp` with 粉色主题 (`Color(0xFFEC407A)`, `useMaterial3: true`)
- 通过 `_AppStartupCoordinator` 决定首页:
  - `signedIn` → `WidgetTree` (主界面)
  - 否则 → `WelcomePage` (欢迎页)
- Probe 模式 → `MobileClipVectorProbePage`

### 2.4 启动协调器 `_AppStartupCoordinator`

启动时序 (resolve 方法):

1. 初始化 `AIProgressNotificationService` (单例, 负责 AI 进度通知流)
2. 配置 Amplify Auth (Cognito)
3. 检查当前认证状态
4. 初始化 `ObjectBoxService` (向量数据库)
5. 初始化 `PhotoService` (照片库扫描)
6. 延迟 800ms 后调度 `_resumePendingAiAnalysis()` — 恢复未完成的 AI 分析
7. 日志输出 OCR 策略状态

---

## 3. 数据层 — Models & Entities

**目录:** `lib/models/`

### 3.1 Isar 实体 (Entity)

所有实体使用 Isar `@Collection` 注解, 自动生成 `.g.dart`。

#### `PhotoEntity` — `lib/models/entity/photo_entity.dart`

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `Id` (自动递增) | 主键 |
| `assetId` | `String` (唯一) | 系统相册 asset ID |
| `path` | `String?` | 文件路径 |
| `timestamp` | `int?` | 拍摄时间戳 (ms) |
| `width`, `height` | `int` | 尺寸 |
| `latitude`, `longitude` | `double?` | GPS 坐标 |
| `province`, `city`, `district`, `locationName`, `formattedAddress`, `adcode` | `String?` | 位置信息 |
| `isLocationProcessed` | `bool` | 位置是否已处理 |
| `aiTags` | `List<String>?` | AI 视觉标签 (JSON 存为字符串列表) |
| `isAiAnalyzed` | `bool` | AI 分析是否完成 |
| `aiCaption` | `String?` | AI 生成的描述文字 |
| `imageEmbedding` | `List<double>?` | 图像 embedding 向量 (旧版, 512维) |
| `ocrText` | `String?` | OCR 文字 |
| `ocrTags` | `List<String>?` | OCR 标签 |
| `faceCount` | `int` | 检测到的人脸数 |
| `smileProb` | `double` | 微笑概率 |
| `joyScore` | `double` | 喜悦分数 |
| `eventId` | `int?` | 所属事件 ID |

**Getters:**
- `aspectRatio` — `width / height` (防止除零)
- `isProbablyScreenshot` — 根据宽高比推断是否为截图

#### `FaceEntity` — `lib/models/entity/face_entity.dart`

关键字段: `id`, `photoId`, `assetId`, `faceIndex`, 人脸框 (`left/top/right/bottom`), `roll/yaw`, `smilingProbability`, `leftEyeOpenProbability`, `rightEyeOpenProbability`, `debugCropPath`, `embedding` (512维), `embeddingModelVersion`, `qualityScore`, `clusterId` (人脸聚类ID), `isPrimaryFace`, `createdAt`, `updatedAt`

Getters: `width`, `height`, `area` (人脸框面积)

#### `EventEntity` — `lib/models/entity/event_entity.dart`

| 字段 | 说明 |
|------|------|
| `title` | 事件标题 |
| `startTime`, `endTime` | 时间范围 |
| `avgLatitude`, `avgLongitude` | 平均 GPS |
| `city`, `province`, `district`, `locationName`, `formattedAddress` | 位置 |
| `photoIds` | `List<int>?` 照片 ID 列表 |
| `coverPhotoId` | 封面照片 ID |
| `tags` | `List<String>?` 标签 |
| `photoCount` | 照片数 |
| `joyScore` | 喜悦分数 |
| `aiThemes` | `List<AITheme>?` AI 生成的主题 (带 emoji) |
| `isLlmGenerated` | 是否由 LLM 生成标题 |
| `analyzedPhotoCount` | 已分析的照片数 |

Getters: `season`, `year`, `location`, `dateRangeText`

Factory: `EventEntity.fromPhotos(photos)` — 从照片列表创建事件
方法: `toUIModel()`, `toPreviewModel()` — 转换为 UI 模型

#### `StoryEntity` — `lib/models/entity/story_entity.dart`

字段: `id`, `title`, `subtitle`, `content` (Markdown), `createdAt`, `updatedAt`, `isHorizontal`, `targetPlatform`, `eventId`, `photoIds`, `photoCount`, `isLlmGenerated`

核心方法:
- `create(title, subtitle, sections, ...)` — 从 StorySection 列表创建
- `parseToSections(photos)` — 将 Markdown content 解析为 StorySection 列表 (正则匹配 `![img](index)` 占位符)
- `sectionsToMarkdown(sections)` — 反向: StorySection → Markdown

#### `DigitalAlbumBookEntity`

存储数字相册书的数据 (JSON 序列化布局数据)。

#### `CreateRecommendationEntity`

存储推荐记录。

### 3.2 Value Objects

**`lib/models/vo/`**

| 文件 | 内容 |
|------|------|
| `photo.dart` | `Photo` UI 模型 (包装 PhotoEntity, 添加 AssetEntity 等运行时数据) |
| `story_section.dart` | `StorySection` — 故事段落: `type` (text/textWithPhoto), `text`, `photoIndex` |
| `story_generation_models.dart` | `StoryGenerationRequest`, `StoryGenerationResult`, `StoryGenerationProgress` — 生成请求/结果/进度模型 |
| `semantic_search_models.dart` | `SemanticSearchQuery`, `SemanticSearchResult`, `SemanticMatch` — 语义搜索模型 |
| `album_book_models.dart` | 数字相册书模型: `layoutType`, `elements`, `templates` |

### 3.3 领域模型

| 文件 | 内容 |
|------|------|
| `ai_theme.dart` | `AITheme` — `{ id, emoji, title, subtitle }` |
| `event.dart` | `Event` UI 模型 (日期范围、位置、标签、封面等) |
| `story.dart` | `Story` UI 模型 |
| `theme_cluster_models.dart` | `ThemeDefinition`, `ThemeCluster`, `ThemeSubcluster`, `ScoredThemePhoto`, `ThemeTimelineGroup`, 聚类算法枚举 |
| `face_cluster_models.dart` | 人脸聚类数据模型 |
| `mobileclip_benchmark.dart` | Benchmark 报告模型 |

---

## 4. 存储层 — Storage

**目录:** `lib/storage/`

### 4.1 ObjectBox 向量数据库

**服务:** `lib/storage/objectbox/objectbox_service.dart`

- 单例模式, 管理 ObjectBox `Store` 生命周期
- 数据文件存储在应用文档目录的 `objectbox/` 子目录
- 提供 `tryBox<T>()` 泛型方法获取 Box

### 4.2 照片 Embedding 索引实体

**文件:** `lib/storage/objectbox/entities/photo_embedding_index_entity.dart`

ObjectBox `@Entity`, 使用 `@HnswIndex(dimensions:512, cosine)` 注解:
- `id` (@Id), `lookupKey` (`$photoId::$modelVersion`, @Unique), `photoId` (@Index), `modelVersion` (@Index), `updatedAtMillis`, `isStale`, `vector` (`List<double>?`, @Property type: floatVector)

### 4.3 人脸 Embedding 索引实体

**文件:** `lib/storage/objectbox/entities/face_embedding_index_entity.dart`

类似照片索引, 增加了 `faceId`, `qualityScore` 字段。

### 4.4 向量索引常量

**文件:** `lib/storage/vector_index/vector_index_constants.dart`

- `kPhotoEmbeddingVectorDimensions = 512`
- `kFaceEmbeddingVectorDimensions = 512`
- `kPhotoEmbeddingModelFamily = 'mobileclip_image'`
- `buildPhotoEmbeddingModelVersion()` → `'mobileclip_image_mobileclip2_litert_fp32_split_v1'`

### 4.5 PhotoEmbeddingIndexRepository

**文件:** `lib/storage/vector_index/photo_embedding_index_repository.dart` (192 行)

核心操作:
- `readEmbeddingForPhoto()` / `readEmbeddingsForPhotos()` — 单/批量读取, 支持旧版 `photo.imageEmbedding` 回退
- `readIndexedEmbeddingsByPhotoIds()` — 按 `lookupKey` (photoId + modelVersion) 批量查询, 过滤 stale
- `upsertEmbedding()` — 插入/替换, 自动归一化向量
- `deleteByPhotoIds()` / `deleteAll()` — 删除
- `queryNearest(vector, topK, modelVersion)` — HNSW 近似最近邻搜索 (cosine 距离), 支持 modelVersion 过滤

### 4.6 FaceEmbeddingIndexRepository

**文件:** `lib/storage/vector_index/face_embedding_index_repository.dart` (199 行)

- `replaceForPhoto()` — 在事务中原子替换一张照片的所有人脸嵌入 (先删后插)
- `upsertFromFace()` — 从 FaceEntity 更新单个人脸
- `readEmbeddingForFace()` / `readEmbeddingsForFaces()` — 读取, 支持回退到 `face.embedding`

### 4.7 业务数据库 (Isar)

Isar 用于存储业务实体 (PhotoEntity, FaceEntity, EventEntity, StoryEntity, DigitalAlbumBookEntity, CreateRecommendationEntity)。Isar 的操作直接在各个 Service 中通过 Isar 实例进行, 没有统一 Repository 层。

---

## 5. 认证模块 (Auth)

### 5.1 服务文件

| 文件 | 功能 |
|------|------|
| `cognito_auth_service.dart` | 认证核心: signIn, signUp, signOut, confirmSignUp, resetPassword, confirmResetPassword, getCurrentUser, fetchAuthAttributes |
| `amplify_cognito_config.dart` | Amplify 配置初始化 |
| `auth_token_service.dart` | Token 管理 (暂未使用?) |

### 5.2 认证流程

```
WelcomePage ──→ SignInPage ──→ WidgetTree
                SignUpPage ──→ ConfirmCode ──→ SignIn
                ForgotPasswordPage ──→ SendCode ──→ ConfirmReset
```

- `SignInPage`: 用户名/密码表单, 调用 `CognitoAuthService.signIn()`, 成功后导航到 `WidgetTree`
- `SignUpPage`: 注册表单 (用户名/姓名/邮箱/密码), 发送验证码, 确认后自动跳转登录
- `ForgotPasswordPage`: 两步流程 (先发送验证码, 再输入验证码+新密码)
- `WelcomePage`: 欢迎页面, 有登录/注册按钮

### 5.3 Amplify 配置

- 使用 Cognito User Pools
- 配置从 `config/profiles/dev.json` 读取
- 替代方案: `lib/config/profiles/dev.example.json` (模板)

---

## 6. 照片扫描与管理 (Photo Service)

### 6.1 服务架构

`PhotoService` 是一个巨大的服务, 拆分为多个文件:

| 文件 | 功能 |
|------|------|
| `photo_service.dart` | 主服务: `deletePhoto()`, `getPhoto()`, 全局 Isar 实例, `pendingAnalyze` stream |
| `photo_service_scan.dart` | `scanPhotos()` — 扫描系统相册, 创建/更新 PhotoEntity |
| `photo_service_scan_coordinator.dart` | 扫描协调器: 批量处理, 分阶段构建 asset |
| `photo_service_asset_build.dart` | 单个 photo asset 构建 |
| `photo_service_asset_builder.dart` | Asset 构建辅助 |
| `photo_service_access.dart` | 读取接口 |
| `photo_service_ai_reset.dart` | AI 分析重置逻辑 |
| `photo_service_models.dart` | 数据模型 |

### 6.2 扫描流程 (`photo_service_scan.dart`)

1. 请求 photo_manager 权限
2. 从系统相册加载 asset (Paginated)
3. 对每个 asset: 检查是否已存在 (按 assetId), 不存在则创建 `PhotoEntity`
4. 写入 Isar, 标记为 `isAiAnalyzed = false`
5. 触发 AI 分析

扫描范围: 可通过底部弹出菜单选择 100/300/500/全部。

### 6.3 缓存清理

在 AlbumPage 中:
- `_clearLocalCacheOnly()` — 清空 Isar 和 ObjectBox 数据库 (确认对话框)
- `_startRefresh()` — 触发全量/部分扫描, 显示 SnackBar 结果

---

## 7. AI 分析管线 (AI Pipeline)

### 7.1 服务架构

AI 管线是项目的核心, 由约 15 个文件构成:

| 文件 | 功能 |
|------|------|
| `ai_service.dart` | 主入口: `processNextBatch()` |
| `ai_service_pipeline.dart` | 管线编排: 定义分析阶段顺序 |
| `ai_service_pipeline_runner.dart` | 管线执行器: 批量处理照片 |
| `ai_service_photo_processor.dart` | 单张照片处理编排 |
| `ai_service_photo_processing.dart` | 单张照片处理的具体步骤 |
| `ai_service_progress.dart` | 进度追踪与报告 |
| `ai_service_profiler.dart` | 性能分析 (各阶段耗时) |
| `ai_service_models.dart` | 数据模型: 分析阶段枚举、批次状态 |
| `ai_service_lifecycle.dart` | 生命周期管理: 暂停/恢复/取消 |
| `ai_service_input.dart` | 输入数据准备 |
| `ai_service_auxiliary.dart` | 辅助功能 |

### 7.2 分析流程 (每张照片)

```
PhotoEntity (new)
    ↓
1. MobileCLIP 图像编码器 → 512维 embedding → 存入 ObjectBox
    ↓
2. MobileCLIP 标签推理 → AI 视觉标签 → 写入 PhotoEntity.aiTags
    ↓
3. OCR (可选, 默认禁用) → OCR 文字/标签
    ↓
4. 人脸检测 (ML Kit) → 人脸框 + 特征 → FaceEntity
    ↓
5. 人脸 Embedding 提取 → 512维 → 存入 ObjectBox
    ↓
6. AI 描述生成 (Caption) → PhotoEntity.aiCaption
    ↓
7. 喜悦分数计算 → PhotoEntity.joyScore
    ↓
8. 标记 isAiAnalyzed = true
```

### 7.3 MobileCLIP 推理

**服务文件:**
- `mobileclip_litert_service.dart` — 图像/文本编码器 (`embedImageBytes()` / `embedTextTokens()` → 512维向量)
- `mobileclip_text_service.dart` — 文本编码器 (`encodeText()` → 512维向量)
- `mobileclip_tag_service.dart` — 标签分类 (`classifyTags()` — 零样本分类)
- `mobileclip_embedding_service.dart` — 全量 Embedding 流程
- `media_embedding_service.dart` — 图片、视频和 GIF 的 MobileCLIP2 S2 embedding

**模型资产:**
- LiteRT: `assets/mobileclip2/s2/mobileclip2_s2_image.tflite`, `mobileclip2_s2_text.tflite`

**Clip Tokenizer:** `assets/clip_tokenizer/` — BPE tokenizer 文件

### 7.4 人脸处理管线

| 服务 | 功能 |
|------|------|
| `face_pipeline_service.dart` | 管线编排 |
| `face_embedding_service.dart` | Embedding 提取 |
| `onnx_face_embedding_service.dart` | ONNX 人脸 Embedding 模型推理 |
| `onnx_session_provider_service.dart` | ONNX 会话管理 |

### 7.5 进度管理

- **`AIProgressNotificationService`** (单例, Riverpod StreamProvider): 发布 AI 分析进度事件
- **`AlbumPage`** 监听该流, 在顶部显示进度横幅 (青色卡片, 进度条, 预计剩余时间, 暂停/停止按钮)
- 分析可暂停/恢复/取消 (通过 `ai_service_lifecycle.dart`)

### 7.6 照片描述生成

**服务:** `photo_caption_service.dart` — 使用 LLM 根据标签+OCR+人脸信息生成自然语言描述。

### 7.7 OCR

**服务:** `ocr_service.dart` — 包装 Google ML Kit Text Recognition。
**策略:** `lib/utils/ocr_policy.dart` — 默认禁用 (`ENABLE_ML_KIT_OCR`), 通过编译开关启用。

---

## 8. 事件聚类 (Event Clustering)

### 8.1 算法

**文件:** `lib/utils/event_cluster_helper.dart` (312 行)

核心: 时空聚类算法, 将照片按时间空间分割为"事件"。

### 8.2 配置参数 (`ClusterConfig`)

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `initialTimeThresholdHours` | 3h | 初始切分时间阈值 |
| `baseDistanceThresholdKm` | 8km | 基础距离阈值 |
| `sameCityTimeThresholdHours` | 6h | 同城时间阈值 |
| `sameCityDistanceThresholdKm` | 20km | 同城距离阈值 |
| `fallbackSameCityDistanceKm` | 45km | 同城距离回退值 |
| `sameDayMergeGapHours` | 8h | 同日合并时间间隙 |
| `crossDayMergeGapHours` | 18h | 跨日合并时间间隙 |
| `minPhotosPerClusterForMerge` | 3 | 合并最小照片数 |
| `enableSameDayTravelMerge` | true | 启用同日旅行合并 |
| `enableCrossDayTravelMerge` | true | 启用跨日旅行合并 |

### 8.3 算法流程

1. **初始切分 `_initialSplit`**: 按时间排序照片, 依次检查每一对相邻照片:
   - 跨城 → 切分
   - 时间超过阈值 → 切分
   - GPS 距离超过阈值 → 切分
2. **合并 `_mergeSameDayTravelClusters`**: 合并相邻集群, 满足:
   - 时间间隙在阈值内
   - 同城
   - 非跨城
3. **地理距离计算**: Haversine 公式 (`_calculateDistance`)

### 8.4 城市识别

`_cityKey()` — 构建层级化位置键:
- `place:prov/city/district/locationName`
- `adcode:code`
- `city:prov/city`
- `district:prov/city/district`

`_isCrossCity()` / `_isSameCity()` — 通过 cityKey 或距离阈值判断。

---

## 9. 语义搜索 (Semantic Search)

### 9.1 服务架构

| 文件 | 功能 |
|------|------|
| `semantic_photo_search_service.dart` | 搜索主入口 |
| `semantic_matching_service.dart` | 匹配与评分 |
| `semantic_query_parser_service.dart` | 查询解析编排 |
| `semantic_query_parser_constants.dart` | 查询解析常量 |
| `semantic_query_parser_models.dart` | 查询解析数据模型 |
| `semantic_query_parser_llm.dart` | LLM 查询解析 (DeepSeek) |
| `semantic_query_parser_local_fallback.dart` | 本地回退解析 (规则+关键词) |
| `semantic_query_parser_short_route.dart` | 短路由: 仅使用时间+标签过滤 |

### 9.2 搜索流程 (完整版)

```
用户输入自然语言查询 (如 "去年夏天的海滩")
    ↓
1. LLM 查询解析 (DeepSeek)
   解析为结构化 JSON:
   {
     timeRange: { start, end },
     location: "海滩",
     coarseTags: ["natural_landscape", "beach_water"],
     positiveSemantics: ["beach", "summer", "sea"],
     recallSemantics: ["outdoor", "vacation"],
     preferredFineTags: ["大海", "沙滩", "日落"]
   }
    ↓
2. 时间过滤: 按 timeRange 筛选照片
3. 位置过滤: 按 location 筛选 (GPS/地址)
4. Embedding 匹配: 使用 MobileCLIP 文本编码器
   将语义短语编码为 512维向量, 与照片向量计算 cosine 相似度
    ↓
5. Taxonomy 标签提升: 匹配粗/细标签的额外加分
6. 排序: 综合得分 (embeddding 相似度 + 标签匹配分)
7. 返回 Top-K 结果
```

### 9.3 搜索流程 (短路由)

当 LLM 不可用时, 使用 `semantic_query_parser_short_route.dart`:
- 仅通过时间范围 + 粗标签 (如果有) + 视觉标签匹配
- 基于关键词的简单过滤

### 9.4 本地回退解析

`semantic_query_parser_local_fallback.dart`:
- 正则提取年份 (如 "2023年", "去年")
- 关键词匹配位置 (如 "海滩", "北京")
- 标签匹配 (从查询中提取已知粗/细标签)

### 9.5 搜索页面

**AlbumSearchPage** (`lib/view/pages/album_search_page.dart`, 985 行):
- 搜索文本框, 支持自然语言查询
- 排序方式: 综合得分 / 时间
- 细标签过滤芯片
- 结果: 网格视图或按天分组
- 故事生成 FAB: 选择照片后添加到故事队列
- 锁定模式 (推荐): 显示预定义查询结果

### 9.6 CreatePage 的语义搜索

**CreatePage** (`lib/view/pages/create_page.dart`, 1029 行) 使用多阶段搜索:
1. NER 提取 (年份/位置)
2. 时空过滤
3. MobileCLIP 文本向量编码 + cosine 相似度
4. Taxonomy 标签加分
5. 视觉标签回退

---

## 10. 主题聚类 (Theme Clusters)

### 10.1 服务

**文件:** `lib/service/theme_cluster_service.dart`, `theme_cluster_compute_helpers.dart`

主题聚类将照片按语义主题分组 (人物、美食、书籍、汽车、风景、宠物)。

### 10.2 主题定义

预定义的 6 大主题 (在 `ThemeDefinition` 中):
- `people` — 人物 (通过人脸检测)
- `food` — 美食 (通过 AI 标签)
- `books` — 书籍/文档 (通过 AI 标签)
- `cars` — 汽车 (通过 AI 标签)
- `scenery` — 风景 (通过 AI 标签)
- `pets` — 宠物 (通过 AI 标签)

每个主题包含:
- 主题 ID, 中文名称, 图标, 颜色
- 匹配标签列表 (粗/细标签)
- 子聚类配置

### 10.3 子聚类算法

核心算法在 `lib/utils/theme_subclustering.dart` (920 行):

#### 通用子聚类 (`GenericThemeSubclusterer`)
1. 使用 DBSCAN 对主题内照片的 512维 embedding 进行聚类
2. 不同主题使用不同的 epsilon 值:
   - scenery=0.16, food=0.14, books=0.14, pets=0.14, cars=0.15, default=0.15
3. 剩余照片 (noise) 处理:
   - 纯 embedding 模式: 合并为一个 cluster
   - 否则: 委托 `HeuristicThemeSubclusterer`

#### 人物子聚类 (`PeopleThemeSubclusterer`)
1. 按人脸数分为 solo (单人) 和 group (多人)
2. DBSCAN 聚类单人照片 (epsilon=0.12)
3. 层级合并相邻身份簇 (centroid cosine distance < 0.16)
4. 附着剩余单人照到最近身份簇 (距离 < 0.18)
5. 每人形成子簇, 合并多人照为额外子簇

#### 启发式子聚类 (`HeuristicThemeSubclusterer`)
规则引擎回退方案:
- books: slides(幻灯片) vs documents(文档)
- food: drinks(饮品) vs meals(餐食)
- people: solo vs group

使用 OCR 关键词、AI 标签等 token 匹配。

### 10.4 聚类模式

用户可在 UI 切换:
- **纯 Embedding 模式**: 仅使用 512维向量
- **混合模式**: embedding + 标签启发式

### 10.5 DBSCAN 算法

**文件:** `lib/utils/dbscan_algorithm.dart` (206 行)

- 基于 cosine 距离的 DBSCAN 实现
- 参数: `epsilon` (邻域半径), `minPoints` (最小点数)
- 返回: `clusters` + `leftovers` (噪声点)

### 10.6 时间线分组

`buildTimelineGroups()` — 按年月分组, 反向排序。

### 10.7 子簇凝聚度

`_computeSubclusterCohesion()` — 计算簇内平均 pairwise cosine 距离。

---

## 11. 人脸聚类 (Face Clustering)

### 11.1 服务

| 服务 | 功能 |
|------|------|
| `face_cluster_service.dart` | 人脸聚类核心逻辑 |
| `face_embedding_service.dart` | 人脸 embedding 提取与管理 |

### 11.2 聚类流程

1. 检测人脸 → 提取 512维 embedding
2. 存储到 ObjectBox FaceEmbeddingIndexEntity
3. 对 embeddings 进行聚类 (基于 cosine 相似度)
4. 分配 `clusterId` 给每个 FaceEntity
5. 支持重新聚类 (`runRecluster()`)

### 11.3 调试页面

**FaceClusterDebugPage** (`lib/view/pages/face_cluster_debug_page.dart`, 486 行):
- 显示聚类概览 (总数/已聚类/未聚类/未匹配/拒绝)
- 每个簇: 标题、成员数、平均质量、模型版本
- 每个成员: 人脸裁剪预览、faceId、photoId、质量分
- 支持重新聚类和过滤大簇

---

## 12. 故事生成 (Story Generation)

### 12.1 服务架构

| 文件 | 功能 |
|------|------|
| `story_generation_orchestrator.dart` | 主编排器 |
| `story_generation_orchestrator_generation.dart` | LLM 调用生成故事 |
| `story_generation_orchestrator_story_builder.dart` | 故事构建 |
| `story_generation_orchestrator_local_runtime.dart` | 本地运行时 |
| `story_generation_orchestrator_models.dart` | 数据模型 |
| `story_queue_service.dart` | 故事队列管理 |
| `story_service.dart` | 故事 CRUD |
| `story_video_preparation_service.dart` | 视频准备 |

### 12.2 故事生成流程

```
用户选择照片 → ConfigPage 配置
    ↓
1. 构建 EventEntity (如果未指定)
2. 构建照片描述 (StoryPromptHelper.buildPhotoDescriptions)
3. 构建 LLM prompt (StoryPromptHelper.buildStoryPrompt)
4. 调用 LLM 生成故事文本 (LLM + 图像占位符)
5. AI 音乐生成 (可选)
6. 创建 StoryEntity (Markdown 格式)
7. 视频渲染准备
```

### 12.3 StoryPromptHelper

**文件:** `lib/utils/story_prompt_helper.dart` (144 行)

- `buildPhotoDescriptions(photos)`: 为每张照片生成描述 (时间戳、位置、标签)
- `buildStoryPrompt(...)`: 构建完整 LLM prompt, 指定:
  - 字数 (150-250 短版 / 300-500 长版)
  - 图片占位符 `![img](index)`
  - 段落结构
  - 位置使用约束

### 12.4 故事生成模式

在 ConfigPage 可配置:
- 故事模式: 普通、短故事、详细故事等
- 故事模板: 按分类展开选择
- 字幕: AI 自动生成 / 手动输入
- 视频比例: 9:16 (竖屏) / 16:9 (横屏)
- 平台: 小红书 / 朋友圈 / B站 / 短视频

### 12.5 故事队列

用户可从各个页面 (AlbumPage、EventDetailPage、SearchPage) 选择照片添加到队列, 然后在队列页面:
- 拖拽排序 `ReorderableListView`
- 编辑单张照片的描述文字
- 移除照片
- 清空队列
- 点击"生成故事 N" 进入 ConfigPage

### 12.6 故事生成进度

**StoryGenerationProgressPage** (`lib/view/pages/story_generation_progress_page.dart`, 523 行):
- 动画步骤卡片: 每个步骤有图标 (待处理/进行中/完成/失败)、标题、详情文字、要点列表、预览图片
- 进行中的步骤有旋转动画
- 错误状态: 重新生成 / 返回修改

### 12.7 故事结果

**StoryResultPage** (`lib/view/pages/story_result_page.dart`, 671 行):
- 顶部 Hero 图片 + 渐变 + 标题
- SliverList 展示故事段落: 可编辑文本 + 照片 + 上下文卡片 (AI 描述/OCR)
- FAB: "播放回忆" (跳转视频页)
- BottomAppBar: 关闭 / 保存 / 数字相册 / 分享

---

## 13. 视频生成与特效 (Video Generation & Effects)

### 13.1 双重渲染架构

Memoria 有两种视频渲染模式:

1. **预览模式 (StoryVideoPage)**: 实时播放, 有 VFX 控制面板, 可调节效果参数
2. **导出模式 (OffscreenRenderWorker)**: 离屏渲染, 使用 `RepaintBoundary.toImage()` + `FlutterQuickVideoEncoder` 编码

### 13.2 视频播放与预览

**StoryVideoPage** (`lib/view/pages/story_video_page.dart`, 1718 行):
- 黑底 Scaffold
- 图像 + 字幕 + 特效叠加
- 节拍同步效果 (Beat-driven)
- VFX 控制面板 (底部弹出):
  - 抖动强度/频率滑块
  - Glitch 滑块
  - Flash 开关
  - 字幕模糊滑块
  - 字幕样式下拉
  - Y 位置/字号滑块
  - 开关: 暗角、噪点、相机框、发光环、云边框

### 13.3 离屏渲染导出

**OffscreenRenderWorker** (`lib/view/pages/offscreen_render_worker.dart`, 888 行):
- 不可见 Widget
- 使用 `TickerProviderStateMixin` 驱动帧
- 每帧使用 `RenderRepaintBoundary.toImage()` 捕获 RGBA 像素
- 通过 `FlutterQuickVideoEncoder` 硬件编码
- 使用 FFmpeg 混音 (`_fastMuxAudio()`)
- 支持 Ken Burns 缩放、抖动、Glitch、Flash、暗角、噪点、相机框、发光环

### 13.4 视频特效

| 特效 | 文件 | 说明 |
|------|------|------|
| 暗角 (Vignette) | `static_filters.dart` | RadialGradient 边缘变暗 |
| 噪点 (Grain) | `static_filters.dart` | noise.png 随机偏移, opacity 0.08 |
| 相机框 | `static_filters.dart` | 水平/垂直相机边框 PNG |
| 发光环 | `static_filters.dart` | CustomPaint 呼吸动画 + 脉冲突出 |
| 字幕 (7种) | `subtitle_effect.dart` | standard/hero/cards/layered/outline/typewriter/strip |
| 云边框 | `cloud_border_effect.dart` | CustomPainter 随机云团沿边浮动 |
| Glitch | `glitch_effect.dart` | 色差偏移 + 随机条带裁剪 |

### 13.5 字幕效果类型

1. **standard** — 默认: 淡入 + 上滑 + 闪光
2. **hero** — 中央大字: 模糊淡入 + 闪光 + VFX 缩放
3. **cards** — 每个字符在粉色卡片中: 交错缩放 + 淡入
4. **layered** — 多层堆叠: 旧层淡出/模糊/缩小
5. **outline** — 大号空心字: 交错 Y 偏移 + 节拍脉动
6. **typewriter** — 打字机 + 绿色闪烁光标
7. **strip** — 旋转 -30° 竖条带: 浮动 + 闪光

### 13.6 节拍同步

- 音频 Beat 数据从资产 JSON 加载或由 `MusicService.analyzeAudio()` 生成
- 支持的资产: `Hachimi.mp3`, `sandal_leap.mp3` 及 `premade/` 目录下的 4 首音乐
- 每个 Beat 包含: 时间戳、强度
- 使用音频播放器 `onPositionChanged` 回调驱动节拍同步状态更新

### 13.7 智能裁剪

- `_calculateFaceAlignment()` — 面积加权人脸质心计算, 实现智能裁切
- Ken Burns 缩放效果: 图像从 100% 缓慢放大到 ~105%

### 13.8 导出管理器

**ExportManager** (`lib/view/pages/export_manager.dart`):
- 单例, 管理后台视频导出
- 创建 OverlayEntry: 不可见渲染 Worker + 浮动进度指示胶囊
- 完成: 移除 Overlay, 显示成功对话框 ("稍后再说" / "去发布")
- 跳转到 PublishPage

---

## 14. 数字相册 (Digital Album)

### 14.1 页面类型

Memoria 有两种数字相册:

1. **DigitalAlbumPage** — 简单分页查看器 (PageView 页面翻转)
2. **DigitalAlbumBookPage** — 高级书册编辑器 (跨页对开 + 拖拽编辑)

### 14.2 DigitalAlbumPage

**文件:** `lib/view/pages/digital_album_page.dart` (1001 行)

页面类型:
- `cover` — 封面: Logo、标题、副标题、英雄图
- `chapter` — 章节: 标题、正文、装饰文字
- `caption` — 说明: 标题、照片、可编辑描述
- `story` — 故事: 标题、照片、可编辑故事文本
- `ending` — 结尾: 标题、正文、页脚

UI: AppBar + PageView + 底栏 (上/下页、页码、进度条)
支持键盘快捷键 (左右箭头)

### 14.3 DigitalAlbumBookPage

**文件:** `lib/view/pages/digital_album_book_page.dart` (1631+ 行)

核心功能:
- **跨页(Spread)对开**: 水平锁屏, 左右两页显示
- **翻页动画**: 手势拖拽翻页 (`DragStart/Update/End/Cancel`)
- **元素操作**: 拖拽移动、缩放、分层 (置前/置后)
- **内联编辑**: 点击文本进入 TextField 编辑
- **模板切换**: 多选布局模板, 应用后重建书册
- **AI 文案**: 调用 LLM 重写所有文案
- **撤销历史**: 最多 40 步撤销快照
- **添加元素**: 添加文字、图片, 替换图片, 删除元素

### 14.4 服务

| 服务 | 功能 |
|------|------|
| `digital_album_book_service.dart` | 书册 CRUD |
| `digital_album_layout_service.dart` | 布局计算 |
| `digital_album_ai_service.dart` | AI 文案生成 |
| `digital_album_validator_service.dart` | 布局验证 |

---

## 15. 推荐引擎 (Recommendation Engine)

### 15.1 服务

| 服务 | 功能 |
|------|------|
| `create_recommendation_service.dart` | 推荐生成与管理 |
| `recommendation_query_template_service.dart` | 查询模板服务 |

### 15.2 推荐查询库

**文件:** `lib/data/recommendation_query_json_library.dart` (60 行)

~40 个预定义推荐查询, 按类别分组:

| 类别 | 示例 |
|------|------|
| 时间 | 今年、去年、本月、上月、往年今日 |
| 位置/记忆 | 故地重游、居家日常、校园生活、城市漫步、旅行 |
| 自然/季节 | 花草、日落、山水、春夏秋冬 |
| 社交/事件 | 聚餐、节日、生日、美食日记、朋友聚会 |
| 活动 | 户外活动、难忘美食 |
| 抽象 | 旧时光、审美精选、爱好、宠物日常 |

### 15.3 发现卡片 (HomePage)

**HomePage** (`lib/view/pages/home_page.dart`, 919 行) 的推荐引擎:

```
_homePageDiscoverRules():
- 时间规则: 年度总结(12/20-1/10), 月度总结(25号后), 往年今日(1-5年前)
- 内容规则: 萌宠/出游/美食/愉快回忆(基于 AI 标签)
- 位置规则: 按城市/省份分组(>=10张照片)
```

### 15.4 创作中心

**CreateHubPage** (`lib/view/pages/create_hub_page.dart`, 959 行):
- "想你所想" 语义搜索入口 → CreatePage
- "创作推荐" 水平滚动卡片 (推荐预览: 封面 + 标签 + 标题 + 缩略图)
- "故事相册" 水平滚动卡片 (已保存的故事)
- 背景刷新: 带 force/cooldown 管理

---

## 16. 垃圾照片清理 (Junk Photo Cleanup)

### 16.1 服务

| 服务 | 功能 |
|------|------|
| `junk_photo_filter_service.dart` | 垃圾照片过滤 (低质量、截图、模糊等) |
| `junk_photo_cleanup_service.dart` | 清理操作: 标记、删除 |

### 16.2 流程

1. AI 分析后标记低质量照片为 `__junk_candidate__`
2. AlbumPage 显示 `JunkPhotoCleanupBanner` (橙色横幅)
3. 点击"查看并处理" → `JunkPhotoCleanupDialog`
4. 对话框中可按原因分类过滤 (ChoiceChip)
5. 全选/取消选择 + 网格预览 + 点击全屏查看
6. 确认删除: 从本地数据库删除记录

### 16.3 UI 组件

- `JunkPhotoCleanupBanner` (lib/view/widgets/junk_photo_cleanup_banner.dart): 橙色横幅, 显示数量 + 原因摘要
- `JunkPhotoCleanupDialog` (lib/view/widgets/junk_photo_cleanup_dialog.dart): 全屏对话框, 网格预览, 分类过滤, 删除确认

---

## 17. 旅行记忆检测 (Travel Memory Detection)

### 17.1 服务

**文件:** `lib/service/travel_memory_detector.dart`

从照片数据中识别旅行事件:
- 按时间排序照片
- 检测地理位置大幅变化 (跨城市)
- 识别旅行的时间范围
- 生成旅行摘要 (目的地、日期、照片数)

### 17.2 调试入口

在 ProfilePage 的开发者设置中触发, 显示摘要对话框。

---

## 18. 音乐生成 (Music Generation)

### 18.1 服务

| 服务 | 功能 |
|------|------|
| `music_gen_service.dart` | AI 音乐生成 (MusicGen 外部服务) |
| `music_service.dart` | 音乐分析: `analyzeAudio()` 生成节拍数据 |
| `llm_service_story_music.dart` | LLM 音乐推荐: `generateMusicPrompt()` |

### 18.2 音乐来源

ConfigPage 中的音乐选择:
- **AI 智能配乐**: 通过 LLM 分析照片主题, 生成音乐描述 prompt, 调用 MusicGen 生成
- **手动导入**: 文件选择器选择本地音频文件

### 18.3 预置音乐

`assets/audio/premade/` 下 4 首:
- Faded Save File.mp3
- Horizons in Motion.mp3
- Soft Save Point.mp3
- Sunrise Checkpoint.mp3

`_servePremadeMusic()` — 关键词匹配算法, 根据 prompt 分析自动匹配预置音乐。

### 18.4 节拍分析

`MusicService.analyzeAudio()` — 分析音频文件生成时间节拍数据 (JSON)。

---

## 19. 创作中心 (Create Hub)

### 19.1 CreateHubPage

**文件:** `lib/view/pages/create_hub_page.dart` (959 行)

WidgetTree 底部导航的中心按钮打开此页面 (index 2 被拦截)。

UI 结构:
- 毛玻璃背景 (BackdropFilter blur) + 粉紫渐变圆装饰
- "Memoria 创作入口" 标题
- "想你所想" — 语义搜索入口卡片 → CreatePage
- "创作推荐" — 水平滚动推荐列表 (带隐藏/查看操作)
- "故事相册" — 水平滚动已保存故事列表 (按 最近更新/最近保存/照片最多 排序)

后台维护:
- 带 session 管理的自动刷新
- force-refresh 机制
- 冷却时间避免频繁刷新

### 19.2 CreatePage

**文件:** `lib/view/pages/create_page.dart` (1029 行)

语义搜索 + 照片选择 → 故事生成:
1. 搜索栏 (多行 TextField + 候选标签芯片)
2. 多阶段语义搜索
3. 照片网格 (3 列, 选择圈)
4. "继续" → ConfigPage

---

## 20. LLM 集成服务

### 20.1 服务架构

| 文件 | 功能 |
|------|------|
| `llm_service.dart` | 主入口: 配置管理 (API key, endpoint) |
| `llm_service_completion.dart` | LLM 补全调用 |
| `llm_service_titles.dart` | 标题/主题生成: `generateCreativeTitles()`, `generateTags()` |
| `llm_service_story_music.dart` | 音乐相关: `generateMusicPrompt()`, `generateSocialMediaCopy()` |

### 20.2 调用场景

- **故事生成**: 根据照片描述生成叙事文本
- **标题生成**: 为事件生成创意标题 (带 emoji)
- **视频文案**: 生成社交媒体发布文案 (小红书/朋友圈等风格)
- **音乐推荐**: 基于照片分析推荐音乐风格描述
- **查询解析**: 自然语言查询 → 结构化搜索条件 (DeepSeek)
- **照片描述**: 生成 AI 描述 (Caption)
- **相册文案**: 数字相册 AI 文案重写

### 20.3 外部 VLM 集成

**InternVL 实验室** (`internvl_lab_page.dart`):
- 调用本地 llama-server 运行 InternVL 模型
- 结构化分析: 选择照片 → 构建 prompt → 调用模型 → 保存 JSON 输出
- 输出存档: `internvl_output_archive_service.dart`

**本地 VLM 测试** (`local_vlm_test_page.dart`, 1202 行):
- 支持 Qwen 0.8B 模型
- 两种模式: 逐张描述 / 多图故事
- 重试逻辑 + CLI 回退
- JSON 输出归一化

---

## 21. 视频转场特效资源

**目录:** `assets/transitions/`

10 种转场效果, 每种含 `.mov` 和 `.webp`:
- blue_circle, flowers, glass, green, light, mosaic, orange_and_red, red, white_circle

**注意:** 目前的代码中, 这些转场资源未在代码中引用, 是预备资源。

---

## 22. 工具与调试页 (Developer Tools)

### 22.1 调试页面列表

| 页面 | 入口 | 说明 |
|------|------|------|
| MobileCLIP Benchmark | Profile → 开发者设置 | 对比 ONNX CPU vs NNAPI 性能 |
| MobileCLIP Vector Probe | Profile → 开发者设置 / Dart-Define | 检查 LiteRT 向量 |
| Face Cluster Debug | Profile → 开发者设置 | 查看人脸聚类结果 |
| Theme Clusters | 底部导航 | 主题聚类浏览 |
| InternVL Lab | 仅代码入口 | VLM 结构化分析实验 |
| Local VLM Test | 仅代码入口 | 本地 Qwen 0.8B 测试 |

### 22.2 MobileCLIP Benchmark

**MobileClipBenchmarkPage** (`lib/view/pages/mobileclip_benchmark_page.dart`, 409 行):
- 样本数: 12/24/48
- 报告: 总览、加速比、适配器详情 (mean/p50/p90)、向量一致性 (cosine/L2/Top-1/Top-5)

### 22.3 MobileCLIP Vector Probe

**MobileClipVectorProbePage** (`lib/view/pages/mobileclip_vector_probe_page.dart`, 524 行):
- 3 张固定测试图片
- LiteRT 向量检查
- 零样本标签分类测试
- Isar vs ObjectBox 读取性能对比

### 22.4 Onsen 模式

**OffscreenRenderWorker** 可独立使用, 用于测试视频导出。

---

## 23. UI 页面清单

### 23.1 页面完整列表

| 页面文件 | 类名 | 路由来源 | 描述 |
|----------|------|----------|------|
| `welcome_page.dart` | `WelcomePage` | main.dart (未登录) | 欢迎/品牌展示 |
| `sign_in_page.dart` | `SignInPage` | WelcomePage | 登录表单 |
| `sign_up_page.dart` | `SignUpPage` | WelcomePage | 注册表单 |
| `forgot_password_page.dart` | `ForgotPasswordPage` | SignInPage | 密码重置 |
| `widget_tree.dart` | `WidgetTree` | main.dart (已登录) | 主界面 (5 标签) |
| `home_page.dart` | `HomePage` | WidgetTree index 0 | 首页/仪表盘 |
| `album_page.dart` | `AlbumPage` | WidgetTree index 1 | 相册浏览 |
| `album_search_page.dart` | `AlbumSearchPage` | AlbumPage | 语义搜索 |
| `event_detail_page.dart` | `EventDetailPage` | AlbumPage / HomePage | 事件详情 |
| `create_hub_page.dart` | `CreateHubPage` | WidgetTree 中心 FAB | 创作中心 |
| `create_page.dart` | `CreatePage` | CreateHubPage | 搜索创建故事 |
| `config_page.dart` | `ConfigPage` | QueuePage / CreatePage | 故事配置 |
| `story_generation_progress_page.dart` | `StoryGenerationProgressPage` | ConfigPage | 生成进度 |
| `story_result_page.dart` | `StoryResultPage` | ProgressPage / 已保存故事 | 故事结果 |
| `story_video_page.dart` | `StoryVideoPage` | StoryResultPage | 视频预览/导出 |
| `story_queue_page.dart` | `StoryQueuePage` | AlbumPage / EventDetail | 故事队列管理 |
| `stories_page.dart` | `StoriesPage` | WidgetTree? | 故事列表 |
| `digital_album_page.dart` | `DigitalAlbumPage` | StoryResultPage | 数字相册查看 |
| `digital_album_book_page.dart` | `DigitalAlbumBookPage` | StoryResultPage | 书册编辑器 |
| `theme_clusters_page.dart` | `ThemeClustersPage` | WidgetTree index 3 | 主题聚类 |
| `profile_page.dart` | `ProfilePage` | WidgetTree index 4 | 个人/设置 |
| `publish_page.dart` | `PublishPage` | ExportManager | 发布分享 |
| `face_cluster_debug_page.dart` | `FaceClusterDebugPage` | Profile → 开发者 | 人脸聚类调试 |
| `mobileclip_benchmark_page.dart` | `MobileClipBenchmarkPage` | Profile → 开发者 | ML Benchmark |
| `mobileclip_vector_probe_page.dart` | `MobileClipVectorProbePage` | Profile/Dart-Define | 向量探测 |
| `internvl_lab_page.dart` | `InternvlLabPage` | 仅代码 | VLM 实验 |
| `local_vlm_test_page.dart` | `LocalVlmTestPage` | 仅代码 | 本地 VLM 测试 |
| `vlm_photo_picker_page.dart` | `VlmPhotoPickerPage` | InternVL/LocalVLM 页面 | 选择照片(用于 VLM) |
| `export_manager.dart` | `ExportManager` | StoryVideoPage | 后台导出管理 |
| `offscreen_render_worker.dart` | `OffscreenRenderWorker` | ExportManager | 离屏渲染器 |

### 23.2 底部导航 (WidgetTree)

```
[首页] [相册] [   +   ] [主题] [我的]
   0      1   中心FAB    3      4
```

- `BottomAppBar` with `CircularNotchedRectangle`
- 中心 FAB 带粉紫渐变, 打开 CreateHubPage

### 23.3 公共组件 (Widgets)

| 文件 | 组件 | 用途 |
|------|------|------|
| `path_image.dart` | `PathImage` | 本地/网络图片渲染 (智能缓存) |
| `deferred_path_image.dart` | `DeferredPathImage` | 延迟加载图片 (交错 30-340ms) |
| `event_card.dart` | `EventCard` | 事件卡片 (封面、标题、日期、标签) |
| `story_list_item.dart` | `StoryListItem` | 故事列表项 |
| `fullscreen_photo_viewer.dart` | `showFullscreenPhotoViewer()` | 全屏图片查看器 (InteractiveViewer) |
| `junk_photo_cleanup_banner.dart` | `JunkPhotoCleanupBanner` | 垃圾照片清理横幅 |
| `junk_photo_cleanup_dialog.dart` | `JunkPhotoCleanupDialog` | 垃圾照片处理对话框 |

---

## 24. 配置系统

### 24.1 配置文件

- `config/profiles/dev.json` — 开发配置 (API Key, Endpoint 等)
- `config/profiles/dev.example.json` — 配置模板
- 通过 `--dart-define=PROFILE=dev` 选择

### 24.2 Dart-Define 开关

| 开关 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `MOBILECLIP_VECTOR_PROBE` | bool | false | 启动时跳转到向量探测页 |
| `ENABLE_STARTUP_MOBILECLIP_WARMUP` | bool | false | 启动时预热 MobileCLIP |
| `ENABLE_ML_KIT_OCR` | bool | false | 启用 ML Kit OCR |

### 24.3 ProfilePage 用户设置

- AI 模型类型: MobileCLIP2 LiteRT
- AI 分析自动恢复: SwitchListTile

---

## 25. 关键数据流图

### 25.1 照片全生命周期

```
系统相册 → PhotoService.scanPhotos()
    → PhotoEntity (Isar)
    → AI Pipeline:
        → MobileCLIP vision → 512维 vector → ObjectBox
        → MobileCLIP tag → aiTags
        → ML Kit OCR → ocrText, ocrTags (可选)
        → ML Kit Face → FaceEntity (Isar)
        → Face Embedding → 512维 vector → ObjectBox
        → Photo caption → aiCaption
        → Joy score → joyScore
    → Event Clustering:
        → EventEntity (Isar)
    → Theme Clustering:
        → ThemeCluster, ThemeSubcluster
    → Face Clustering:
        → clusterId on FaceEntity
```

### 25.2 故事生成数据流

```
用户选择照片
    ↓
Photo IDs → PhotoService → PhotoEntity list
    ↓
StoryPromptHelper.buildPhotoDescriptions()
    ↓
LLM Service.generateStory() → StoryEntity (Markdown)
    ↓
解析为 StorySection list
    ↓
StoryResultPage (文本 + 图片展示)
    ↓
数字相册 (DigitalAlbumPage / DigitalAlbumBookPage)
    视频 (StoryVideoPage → OffscreenRenderWorker → ExportManager)
```

### 25.3 语义搜索数据流

```
自然语言查询
    ↓
SemanticQueryParserService
    ├── LLM route: DeepSeek 解析 → 结构化 JSON
    └── Local fallback: 规则+关键词 → 简化结构
    ↓
时间过滤 + 位置过滤 + Embedding 匹配
    ↓
SemanticMatchingService.score()
    ↓
排序 → 返回 SematicSearchResult list
```

---

## 26. 环境要求与构建

### 26.1 环境要求

- Flutter 3.x (>=3.10.3)
- Dart >=3.10.3
- Android SDK / Xcode (iOS/macOS)
- Git LFS (大模型文件)

### 26.2 构建命令

```bash
# 获取依赖
flutter pub get

# 代码生成 (Isar)
dart run build_runner build

# 运行 (开发)
flutter run --dart-define=PROFILE=dev

# 运行 (带 OCR)
flutter run --dart-define=PROFILE=dev --dart-define=ENABLE_ML_KIT_OCR=true

# 运行 (预热 MobileCLIP)
flutter run --dart-define=PROFILE=dev --dart-define=ENABLE_STARTUP_MOBILECLIP_WARMUP=true

# 向量探测调试
flutter run --dart-define=PROFILE=dev --dart-define=MOBILECLIP_VECTOR_PROBE=true

# Web 版本
flutter run -d chrome --dart-define=PROFILE=dev

# 测试
flutter test
```

### 26.3 启动脚本

- `launch.ps1` — Windows PowerShell 启动脚本
- `launch.sh` — Linux/macOS 启动脚本

---

## 附录 A: 文件索引 (lib/)

| 路径 | 约略行数 | 说明 |
|------|----------|------|
| `main.dart` | 149 | 应用入口 |
| `data/tag_dictionary.dart` | 42 | v1 标签词典 |
| `data/tag_taxonomy_v2.dart` | 1430 | v2 标签分类系统 (~100 fine + 24 coarse) |
| `data/recommendation_query_json_library.dart` | 60 | ~40 个推荐查询模板 |
| `models/entity/*.dart` | ~50-200 each | 6 个 Isar 实体 |
| `models/vo/*.dart` | ~50-200 each | 4 个值对象 |
| `models/*.dart` | ~30-100 each | 4 个领域模型 |
| `utils/dbscan_algorithm.dart` | 206 | DBSCAN 聚类 |
| `utils/event_cluster_helper.dart` | 312 | 事件聚类 |
| `utils/theme_subclustering.dart` | 920 | 主题子聚类 |
| `utils/tag_sanitizer.dart` | 116 | 标签清洗 |
| `utils/ocr_policy.dart` | 71 | OCR 策略 |
| `utils/photo_filter_helper.dart` | 115 | 照片过滤 |
| `utils/location_helper.dart` | 34 | 地理位置辅助 |
| `utils/face_crop_util.dart` | 129 | 人脸裁剪 |
| `utils/smart_title_generator.dart` | 153 | 智能标题 |
| `utils/story_prompt_helper.dart` | 144 | 故事 Prompt 构建 |
| `utils/ai_score_helper.dart` | 24 | AI 评分 |
| `effects/static_filters.dart` | 228 | 暗角/噪点/相机框/发光环 |
| `effects/subtitle_effect.dart` | 477 | 7 种字幕效果 |
| `effects/cloud_border_effect.dart` | 153 | 云边框 |
| `effects/glitch_effect.dart` | 113 | Glitch 特效 |
| `storage/objectbox/*.dart` | ~50 each | ObjectBox 存储 |
| `storage/vector_index/*.dart` | ~200 each | 向量索引仓库 |
| `service/*.dart` | 80+ files | 所有业务服务 |
| `view/widget_tree.dart` | 322 | 底部导航主框架 |
| `view/pages/*.dart` | 32 files | 所有页面 |
| `view/widgets/*.dart` | 7 files | 公共组件 |

---

## 附录 B: 外部依赖

| 包名 | 用途 |
|------|------|
| `photo_manager` | 系统相册访问 |
| `isar` + `isar_flutter_libs` | 业务数据库 |
| `objectbox` + `objectbox_flutter_libs` | 向量数据库 (HNSW) |
| `onnxruntime` | ONNX 模型推理 |
| `google_mlkit_face_detection` | 人脸检测 |
| `google_mlkit_text_recognition` | OCR (可选) |
| `flutter_quick_video_encoder` | 硬件加速视频编码 |
| `ffmpeg_kit_flutter_new` | FFmpeg 音视频合成 |
| `amplify_flutter` + `amplify_auth_cognito` | AWS Cognito 认证 |
| `dio` | HTTP 客户端 (LLM 调用等) |
| `flutter_riverpod` + `riverpod_annotation` | 状态管理 |
| `flutter_image_compress` | 图片压缩 |
| `permission_handler` | 权限管理 |
| `audioplayers` | 音频播放 (节拍同步) |
| `path_provider` | 文件路径 |
| `share_plus` | 分享 |
| `image` (dart) | 图像处理 |
| `file_picker` | 文件选择 |

---

> 本文档由 AI 自动分析项目源码生成, 涵盖 `lib/` 下 148 个 Dart 文件。  
> 生成日期: 2026-05-13
