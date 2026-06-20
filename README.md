# Smart Story Album

智能故事相册（Flutter + Isar + ObjectBox + ML Kit + MobileCLIP + LLM）。

## 项目简介

Memoria 是一个以本地智能相册为核心的 Flutter 项目。它会扫描系统相册中的照片，完成时间/地点聚类、视觉标签、OCR、人脸分析、事件故事生成，并提供语义检索、主题聚类等能力。

当前项目已经不是单纯的相册 CRUD，而是一个“业务数据层 + 多模态特征层 + 本地索引层”混合系统：

- 业务主数据继续由 `Isar` 承载。
- 向量索引层由 `ObjectBox` 承载。
- 图像、人脸等 embedding 会作为独立索引对象存储，而不是简单塞回业务实体字段。

## 核心能力

- 扫描系统相册照片，按时间与空间聚类为事件。
- 使用 ML Kit + MobileCLIP 做本地视觉标签、人脸分析与文本场景识别。
- 可选接入兼容 OpenAI 的多模态模型，为每张照片生成一句中文 caption。
- 对截图、文档、课件等文本型图片执行 OCR，并把 OCR 结果接入标题、故事和检索。
- 使用高德逆地理解析更细粒度地点，优先展示 `locationName -> district -> city -> province`。
- 支持后台 AI 打标、暂停、继续、结束本轮，以及按最近 100 / 300 / 500 / 全量刷新。
- 提供主题聚类、人脸聚类、语义检索、相似向量调试等调试入口。
- 提供 Isar/ObjectBox 向量读取耗时对比，便于验证引入索引层的收益。

## 当前存储架构

### 1. 业务主数据层：Isar

Isar 继续作为主业务数据库，负责保存：

- `PhotoEntity`
- `FaceEntity`
- `EventEntity`
- `StoryEntity`
- 任务状态、刷新状态、重跑标记等业务流程相关数据

这些数据是“真相层”，也是应用 UI、刷新流程、事件生成流程的主要依赖。

### 2. 向量索引层：ObjectBox

ObjectBox 当前作为并行索引层，负责保存：

- `PhotoEmbeddingIndexEntity`
- `FaceEmbeddingIndexEntity`

每条索引记录都包含：

- owner id
- `modelVersion`
- 向量数据
- 更新时间
- `isStale` 标记

目前 photo embedding 和 face embedding 都已经接入这层索引存储。

### 3. 为什么不是“全量从 Isar 换到 ObjectBox”

当前选择的是“存储分层”，不是“机械换库”：

- `Isar` 负责业务实体和事务语义。
- `ObjectBox` 负责向量索引和近邻查询能力。

这样做的好处是：

- 不会把向量库误当成业务真相源。
- 可以渐进迁移，而不是一次性推倒重来。
- 后续可以逐步把 ANN 候选召回接到主题聚类、相似图、人脸候选召回上。

## 向量索引设计

### Photo 向量

Photo 向量不再只被视作 `PhotoEntity.imageEmbedding` 的附属字段，而是会被同步写入：

- `lib/storage/objectbox/entities/photo_embedding_index_entity.dart`

当前读路径已经要求精确 `modelVersion` 命中，避免不同 MobileCLIP backend 或未来模型升级时误复用旧向量。

### Face 向量

Face 向量会被同步写入：

- `lib/storage/objectbox/entities/face_embedding_index_entity.dart`

读取时按：

- `face.id`
- `face.embeddingModelVersion`

做精确命中，避免不同人脸模型版本混用。

人脸身份向量必须来自专用 face embedding 模型。当前默认实现是 `OnnxFaceEmbeddingService`，可通过 `FACE_EMBEDDING_ONNX_FILE` 或 `FACE_EMBEDDING_ONNX_ASSET` 提供模型。旧的 `mobileclip2_face_baseline_v1` 只保留为历史缓存识别标记，聚类会直接跳过这类向量。

### Repository 层

当前向量访问已经通过 repository 收口：

- `lib/storage/vector_index/photo_embedding_index_repository.dart`
- `lib/storage/vector_index/face_embedding_index_repository.dart`

原则是：

- 业务 service 不直接操纵 ObjectBox schema。
- 向量 repository 负责精确版本读取、删除、批量读取、近邻查询。
- 业务实体是否把向量回填到内存对象，由 service 明确控制，不由 repository 偷偷写回。
- repository 不再回退读取 `PhotoEntity.imageEmbedding` 或 `FaceEntity.embedding` 的旧向量；旧字段只作为业务兼容/写入中转，不再作为检索和聚类的读路径兜底。

## 最近重要更新

- 2026-06-08 检索与聚类准确度收敛：
  - 自然语言检索、聊天检索、创作页筛图和创作推荐统一走 `SemanticPhotoSearchService`。
  - 语义结果只按 MobileCLIP2 S2 的正/负语义 embedding 相似度排序；时间、地点、标签不再伪装成语义相似度加分。
  - 时间约束走确定性过滤：兼容旧秒级 timestamp，日期边界按毫秒比较，本地日内时间支持跨午夜窗口。
  - 地点约束走层级相关度：`locationName / formattedAddress / district / city / province / adcode` 分层评分；城市、省份、区县是范围，POI 是更小范围。POI 查询不会因为上级景区、附近社区或过宽 alias 直接命中，例如“南京市”和“情侣园”会被当作不同粒度处理。
  - 人脸聚类不再使用 MobileCLIP 图像语义向量作为身份 fallback；没有专用 ONNX face embedding 时不产身份向量。聚类改为保守的 cosine 阈值、同照片互斥、centroid / cover / 最小 cross-pair 多重守门，减少不同人被链式合并。
  - photo / face 向量 repository 删除 legacy entity-vector fallback，读取必须命中当前 `modelVersion` 的 ObjectBox 索引。
- 新增 ObjectBox 并行向量索引层，用于承载 photo/face embedding。
- photo embedding 读路径已改为按当前 `modelVersion` 精确读取。
- face embedding 读路径已改为按 `face.id + embeddingModelVersion` 精确读取。
- 新增向量索引 benchmark，可对比 Isar legacy 向量读取和 ObjectBox 精确索引读取耗时。
- 新增 OCR 流程：自动识别文字密集图片，过滤应用 UI / 时间日期 / 截图噪声，并把 OCR 摘要展示到事件详情。
- 优化事件标题与故事生成：对文本型照片使用 OCR / 文本标签，降低“截图内容污染标题”和角色关系幻觉。
- 优化位置展示：事件和照片优先展示 `locationName -> district -> city -> province`。
- 新增安全重建缓存：清空缓存前先做权限、相册和候选照片预检查，并在重建前停止后台 AI 分析，避免并发写库与误清空。
- 刷新入口支持仅处理最近一部分照片，减少首次全量重扫等待时间。

## 模块结构

- `lib/main.dart`：应用入口。
- `lib/view/`：页面与 UI 组件。
- `lib/service/`：照片扫描、聚类、地址解析、AI 分析、OCR、故事生成、benchmark。
- `lib/models/`：Isar 实体与 UI 模型。
- `lib/storage/objectbox/`：ObjectBox store 和向量索引实体。
- `lib/storage/vector_index/`：向量 repository、版本常量、索引访问封装。
- `lib/utils/`：聚类、Prompt、过滤等纯工具逻辑。
- `ai_tools/`：标签词库构建、模型导出、标签校验与 TFLite 对比脚本。
- `assets/`：运行时资源，包括标签向量、模型文件和静态图片。

## 环境要求

- Flutter SDK：`3.x`
- Dart SDK：`>= 3.10.3`
- 运行平台：macOS / iOS / Android
- 本地权限：首次运行需要授予“相册访问权限”

可选外部服务：

- 云端代理：`API_PROXY_BASE_URL`
- LLM：`LLM_AUTH_MODE=cognito_proxy`、`LLM_MODEL`
- 可选视觉模型：`LLM_VISION_MODEL`

## 如何启动

### 1. 安装依赖

```bash
flutter pub get
```

### 2. 生成代码

首次拉起项目，或者修改 Isar/ObjectBox schema 后，都需要重新生成：

```bash
dart run build_runner build --delete-conflicting-outputs
```

这一步会同时生成：

- Isar 的 `*.g.dart`
- ObjectBox 的 `lib/objectbox.g.dart`
- ObjectBox 的 `lib/objectbox-model.json`

注意：

- `lib/objectbox-model.json` 必须提交到版本控制。
- 不要随意手改 `lib/objectbox-model.json`。
- 如果你改了 ObjectBox 实体字段名或类型，先理解 schema 迁移含义再操作。

### 3. 使用 profile 运行

先准备本地 profile：

仓库已经包含不含 provider key 的代理 profile：

```text
config/profiles/proxy.json
```

启动方式：

```bash
# macOS / Linux
./launch.sh proxy

# Windows PowerShell
./launch.ps1 proxy
```

或直接使用 Flutter：

```bash
flutter run --dart-define-from-file=config/profiles/proxy.json
```

当前支持：

- `proxy -> config/profiles/proxy.json`
- `prod -> config/profiles/prod.json`

## 运行参数

运行参数统一放在 profile 文件中，由 `--dart-define-from-file` 一次性注入。

如果要切换 probe 模式：

```bash
flutter run \
  --dart-define-from-file=config/profiles/proxy.json \
  --dart-define=MOBILECLIP_VECTOR_PROBE=true
```

## App 内使用说明

- 首次进入后点击右上角刷新按钮，可选择“先跑最近 100 / 300 / 500 张”或“全部运行”。
- 刷新完成后，聚类先完成，AI 打标转入后台执行。
- 顶部会显示后台 AI 进度条，可暂停、继续或结束本轮。
- 事件详情页支持长按照片查看 AI 关键词和 OCR 关键词。
- 需要彻底重建本地缓存时，优先走应用内“安全重建”流程。

## 向量探针与存储 Benchmark

### MobileCLIP Vector Probe

项目内置了 `MobileCLIPVectorProbePage`，用于：

- 输出完整向量 probe JSON
- 查看 zero-shot tagging 结果
- 对比 Isar/ObjectBox 向量读取耗时

### Isar/ObjectBox Read Benchmark

当前 probe 页面会额外跑一个存储 benchmark：

- 样本范围：同时具备 `Isar legacy embedding` 和 `ObjectBox 当前 modelVersion 索引` 的照片
- 对比内容：
  - Isar：`getAll(ids)` 后读取 `PhotoEntity.imageEmbedding`
  - ObjectBox：按 `lookupKey(photoId + modelVersion)` 精确批量读取
- 输出指标：
  - mean / p90
  - 每轮耗时
  - speedup ratio
  - checksum 差异告警

实现位置：

- `lib/service/vector_index_benchmark_service.dart`

这不是“最终 ANN 压测”，但足够验证把 embedding 从业务主表读，迁到精确索引读路径后，是否已经开始获得收益。

## ObjectBox 接入说明

### 当前已经接入的内容

- ObjectBox Store 初始化：`lib/storage/objectbox/objectbox_service.dart`
- photo 向量索引实体：`PhotoEmbeddingIndexEntity`
- face 向量索引实体：`FaceEmbeddingIndexEntity`
- photo repository：精确版本读取、批量读取、近邻查询、删除
- face repository：精确版本读取、按 photoId 替换、删除

### 当前已经切到 ObjectBox 的主路径

- `MobileClipEmbeddingService`：优先命中当前 `modelVersion` 的 photo 索引
- `AIService`：photo embedding 生产完成后同步写入 ObjectBox
- `FacePipelineService`：face embedding 生产完成后同步写入 ObjectBox
- `FaceClusterService`：聚类前优先读 ObjectBox face 索引
- `SemanticPhotoSearchService`：语义检索读当前版本 photo 索引
- `CreatePage`：创建页语义筛图读取当前版本 photo 索引

### 当前还没做的事

- 主题聚类还没有把 ANN 候选召回真正接入上层，只是已经能复用精确版本索引。
- 相似图 / 人脸候选召回还没有全面走 `queryNearest(...)`。
- 业务主数据仍然在 Isar，不是“全量换到 ObjectBox”。

## MobileCLIP 资源生成

仓库中部分模型和向量产物体积较大，默认按“可重新生成”思路维护。对 Memoria 来说：

- `checkpoints/mobileclip_s2.pt` 是更可信的源模型
- 运行时只打包 MobileCLIP2 S2 LiteRT 图像/文本模型；视频和 GIF 使用同一模型对抽样帧聚合

首次准备端侧视觉模型时，将基模放到：

- `checkpoints/mobileclip_s2.pt`

然后准备本地 Python 环境以及：

- `torch`
- `mobileclip`
- `jieba`
- `requests`

再执行：

```bash
python ai_tools/build_vocab.py
python ai_tools/expand_brain.py
python ai_tools/export_model.py --output-folder saved_model
```

## 团队协作约定

当前项目采用“代码走 Git，大文件走群文件”的协作方式。

- 超过几十 MB 的模型、SDK、zip 包不要提交到 Git。
- 队友 clone 仓库后，需要额外同步大文件包。

群文件至少应包含：

- MobileCLIP2 S2 LiteRT 图像/文本模型
- SmolVLM2 描述模型

队友拿到群文件后，按下面方式放置：

- 将 MobileCLIP2 S2 LiteRT 模型同步到 `assets/mobileclip2/s2/`
- 将 SmolVLM2 模型同步到应用文档目录下的模型目录，或通过应用内模型下载页获取

## 常见问题

### 1. `flutter run` 提示缺少模型资源

请优先检查：

- `checkpoints/mobileclip_s2.pt`
- `assets/mobileclip2/s2/mobileclip2_s2_image.tflite`
- `assets/mobileclip2/s2/mobileclip2_s2_text.tflite`
- `assets/expanded_tags_vectors.json`

### 2. ObjectBox 代码生成后为什么要提交 `objectbox-model.json`

因为该文件保存了实体和属性的 UID。它不是普通临时文件，而是 schema 演进的一部分。

### 3. 为什么 README 里同时写 Isar 和 ObjectBox

因为当前项目采用的是“业务主数据在 Isar，向量索引在 ObjectBox”的分层架构，而不是一次性替换主库。

### 4. 为什么 benchmark 找不到样本

只有同时满足下面条件的照片才会参与当前 benchmark：

- `PhotoEntity.imageEmbedding` 仍然存在 legacy 向量
- ObjectBox 中存在当前 `modelVersion` 对应的 photo 索引

如果没有满足条件的样本，probe 页面会给出 warning。

## 常用命令

```bash
# 安装依赖
flutter pub get

# 生成 Isar + ObjectBox 代码
dart run build_runner build --delete-conflicting-outputs

# 代码格式化
dart format .

# 静态检查
flutter analyze

# 全量测试
flutter test

# 指定测试
flutter test test/service/face_cluster_service_test.dart
flutter test test/service/theme_cluster_service_test.dart
```

## 后续规划

- 把 `queryNearest(...)` 正式接到主题候选召回、相似图、人脸候选召回。
- 逐步减少对 `PhotoEntity.imageEmbedding` 的 legacy 依赖。
- 继续评估是否需要把更多 embedding 类型迁入 ObjectBox：
  - OCR text embedding
  - event summary embedding
  - theme centroid embedding

当前阶段最重要的原则仍然是：

- `Isar` 保存业务真相
- `ObjectBox` 保存向量索引
- 先把索引语义做对，再逐步吃 ANN 的收益

## 检索与聚类准确度报告

本轮调整的核心原则是：语义用向量相似度，元数据用元数据算法，二者不要混在一个“相似度”里。

### 检索逻辑

- 语义：`positive_semantics` 和 `recall_semantics` 由 MobileCLIP2 S2 text encoder 编码，照片只读取当前 `modelVersion` 的 ObjectBox photo embedding。最终语义分数只由正向语义、召回语义和 negative 语义惩罚决定。
- 时间：`time_ranges` 是硬过滤；`local_time_windows` 是本地日内时间窗口，支持 22:00-05:00 这类跨午夜表达。旧数据里的 10 位秒级 timestamp 会先归一到毫秒。
- 地点：`locations` 是硬过滤，但不是简单字符串 contains。算法按字段层级给分：POI/name/address 最高，district/city/province 是更大的空间范围。POI 查询要求 POI 或地址中出现具体名称；像“玄武湖景区”“锁金村”这种上级/邻近上下文只给低分，不能替代“情侣园”的精确命中。
- 标签：`tag_strictness == strict` 时可作为硬过滤；`prefer/optional` 只用于解释和候选分析，不再改变 embedding 排序。

### 人脸聚类逻辑

- 专用人脸模型优先：FaceNet 和 ArcFace 这类方法都把人脸识别建立在专用 face embedding 空间上，而不是通用图像语义向量；因此 MobileCLIP face baseline 不再用于身份聚类。
- 聚类策略：使用归一化向量的 cosine 阈值，不引入 HDBSCAN。每次 seed、attach、merge 都同时检查 centroid、cover face 和最小 cross-pair 相似度。
- 互斥约束：同一张照片里的两张脸默认不应进入同一个身份簇，避免多人合照中不同人被合并。
- 质量约束：低质量、小面积、截图/宠物/表情包/文档等来源的人脸不会作为聚类候选。

### 为什么不用 HDBSCAN

当前 photo / face embedding 都是高维归一化向量，主要判别信号是角度/cosine，而不是低维空间中的密度团块。HDBSCAN 官方 FAQ 说明高维数据下效果会明显下降；DBSCAN 类算法也更适合密度相近的簇，并且实现可能有较高内存成本。因此这里采用阈值图式的保守聚类，而不是密度聚类。

参考资料：

- FaceNet: A Unified Embedding for Face Recognition and Clustering: https://arxiv.org/abs/1503.03832
- ArcFace: Additive Angular Margin Loss for Deep Face Recognition: https://arxiv.org/abs/1801.07698
- FAISS MetricType and cosine/inner-product notes: https://github.com/facebookresearch/faiss/wiki/MetricType-and-distances
- HDBSCAN FAQ on high-dimensional data: https://hdbscan.readthedocs.io/en/latest/faq.html
- scikit-learn DBSCAN notes: https://scikit-learn.org/1.5/modules/generated/sklearn.cluster.DBSCAN.html
