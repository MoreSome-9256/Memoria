# 故事生成三模式实现方案

## 1. 目标

在用户完成选图并进入故事配置页后，新增一个位于“生成视频”按钮上方的“生成故事”按钮，并新增故事生成方式选择项，支持以下三种模式：

1. `DeepSeek 标签故事`
   - 直接使用所选图片现有的标签、OCR 线索、时间与地点信息，调用 DeepSeek 生成故事。
   - 这是默认模式。

2. `本地 VLM Caption + DeepSeek 故事`
   - 先使用手机本地 VLM 为所选图片逐图生成 caption。
   - 再把标签、caption、时间、地点、OCR 线索一起传给 DeepSeek 生成更细腻的故事。

3. `本地 VLM 直接读图故事`
   - 直接使用手机本地 VLM 对多张图片进行整体理解，生成完整故事。
   - 不依赖云端 DeepSeek。

目标输出：

- 点击“生成故事”后，直接跳转到故事展示页。
- 故事展示页中，图片和故事文字交织排布。
- 文本内容综合：
  - 时间信息
  - 地址信息
  - 图片含义
  - 多图之间的时间推进与空间转换
- 生成的故事应当图文并茂、有文采、可读性强、具有叙事感。

---

## 2. 现状分析

### 2.1 当前已经具备的能力

#### 配置页已有基础壳子

文件：

- [config_page.dart](D:/softinno/Memoria/lib/view/pages/config_page.dart)

当前已经具备：

- 主题、副标题选择
- 画面比例选择
- 发布平台选择
- 配乐方案选择
- 自动字幕开关
- “生成视频”主流程

也就是说，故事生成的新入口应尽量复用这个页面，而不是重新造一个页面。

#### 故事展示页已有图文交织基础

文件：

- [story_result_page.dart](D:/softinno/Memoria/lib/view/pages/story_result_page.dart)

当前已经具备：

- `StoryResultPage.fromStoryEntity(...)`
- 基于 `StoryEntity.parseToSections(...)` 将故事内容拆为若干 section
- section 中图片与文字交织展示
- section 文本可编辑

因此，新的故事生成逻辑应该尽量产出可被 `StoryEntity` 和 `StoryResultPage` 直接消费的数据结构，而不是另起一套展示系统。

#### DeepSeek 故事生成链路已存在

文件：

- [story_service.dart](D:/softinno/Memoria/lib/service/story_service.dart)
- [llm_service.dart](D:/softinno/Memoria/lib/service/llm_service.dart)

当前已有：

- 基于标签、OCR、时间、地点生成故事
- 将故事落为 `StoryEntity`

但现在问题是：

- `ConfigPage` 内的故事生成流程和视频流程混在一起
- 中间有测试/占位代码
- 还没有“按模式生成故事”的干净抽象

#### 本地 VLM 调用方式已跑通

参考文件：

- [local_vlm_test_page.dart](D:/softinno/Memoria/lib/view/pages/local_vlm_test_page.dart)
- [on_device_internvl_service.dart](D:/softinno/Memoria/lib/service/on_device_internvl_service.dart)
- [internvl_experiment_service.dart](D:/softinno/Memoria/lib/service/internvl_experiment_service.dart)

当前已经明确的调用方式：

1. 先将所选图片转换成 `OnDeviceInternvlImagePayload`
   - 包含：
     - `path`
     - `capturedAtIso`
     - `locationName`
     - `latitude`
     - `longitude`

2. 通过本地常驻服务调用：
   - `OnDeviceInternvlService().ensureServerStarted(...)`
   - `InternvlExperimentService().analyzeImagesStructured(...)`

3. prompt 按任务分两种：
   - `captions`
   - `story`

4. 输出 JSON 会被 normalize 成结构化结果

这一点非常重要：

后续不要重新发明一套本地 VLM 接口，应该直接参考 `local_vlm_test_page.dart` 的 prompt、server 启动、fallback、JSON normalize 逻辑。

---

## 3. 目标产品形态

## 3.1 配置页新增内容

在 [config_page.dart](D:/softinno/Memoria/lib/view/pages/config_page.dart) 中新增：

1. “故事生成方式”模块
   - 放在“生成视频”按钮附近，建议位于发布平台与配乐方案下方、生成按钮区上方
   - 采用 3 个单选卡片或 segmented chips

建议文案：

- `DeepSeek 标签故事`
- `本地 VLM Caption + DeepSeek`
- `本地 VLM 直接读图`

默认选中：

- `DeepSeek 标签故事`

2. 新增“生成故事”按钮
   - 放在“生成视频”按钮上方
   - 视觉风格与“生成视频”按钮同系列，但语义明确区分

点击后：

- 不进入视频生产链路
- 只生成故事并跳转到故事展示页

## 3.2 结果页目标

故事展示页应保持现有 `StoryResultPage` 的结构，但故事内容来源改为新的三模式输出。

目标效果：

1. 顶部仍有故事主标题、副标题、Hero 图
2. 下方每个 section 由：
   - 一张图
   - 一段与这张图相关联的故事文字
3. 文本中可以自然体现：
   - 时间推进
   - 地点切换
   - 场景氛围
   - 人物情绪
4. 如果有时间和地址信息，应自然融入叙述，而不是像元数据列表一样机械拼接

---

## 4. 三种故事生成模式设计

## 4.1 模式一：DeepSeek 标签故事

### 适用场景

- 默认模式
- 速度优先
- 图片数量较多时更稳
- 不依赖本地 VLM 推理耗时

### 输入

对每张图片收集：

- `aiTags`
- `aiCaption`（如果已有）
- `ocrTags`
- `ocrText`
- `timestamp`
- `locationName / district / city / province`

在传给 DeepSeek 之前，必须先按时间排序：

1. 优先按图片时间戳升序排列
2. 无时间戳时回退到导入顺序
3. 在 prompt 中保留排序后的 `index`

这样做的目的不是机械排序，而是让模型天然获得：

- 事件先后关系
- 地点迁移顺序
- 情绪和场景的推进节奏

也就是说，传给 DeepSeek 的不是“杂乱标签集合”，而是一条有时间顺序的多图素材流。

### 生成方式

复用 [story_service.dart](D:/softinno/Memoria/lib/service/story_service.dart) 现有思路：

1. 整理多图线索
2. 构建故事 prompt
3. 调用 DeepSeek
4. 返回完整故事正文
5. 再按图片顺序切成若干 section

### 优点

- 实现最稳
- 性能最好
- 适合作为默认值

### 缺点

- 对单张图的细节感知受限于已有标签和 caption 质量

---

## 4.2 模式二：本地 VLM Caption + DeepSeek 故事

### 适用场景

- 希望故事文本更贴近具体画面
- 允许多等待几秒
- 图片数不太多时效果最好

### 输入

先通过本地 VLM 为每张图生成 caption，再合并以下信息：

- `caption`
- `aiTags`
- `ocrTags`
- `ocrText`
- `timestamp`
- `location`

同样要求在进入本地 caption 阶段前先按时间排序，并在 caption 结果中保留与排序后图片一致的索引。

### 本地 VLM 调用方式

必须参考 [local_vlm_test_page.dart](D:/softinno/Memoria/lib/view/pages/local_vlm_test_page.dart) 的 caption 任务：

关键点：

1. 使用 `OnDeviceInternvlService().ensureServerStarted(...)`
2. 使用 `InternvlExperimentService().analyzeImagesStructured(...)`
3. prompt 沿用 caption 模式的结构化约束
4. 输出 JSON 结构固定为：

```json
{
  "captions": [
    {"index": 1, "caption": "..."},
    {"index": 2, "caption": "..."}
  ]
}
```

### 生成方式

1. 逐图生成 caption
2. 将 caption 与现有标签融合
3. 构建更细粒度的 DeepSeek 故事 prompt
4. 生成完整故事
5. 再按图片切 section

### 优点

- 文本更贴合图片内容
- 比纯标签模式更细腻

### 缺点

- 比模式一慢
- 依赖本地模型状态

---

## 4.3 模式三：本地 VLM 直接读图故事

### 适用场景

- 希望完全本地生成
- 不依赖云端
- 追求“看图讲故事”的原生连贯感

### 调用方式

参考 [local_vlm_test_page.dart](D:/softinno/Memoria/lib/view/pages/local_vlm_test_page.dart) 中 `LocalVlmTaskMode.story` 的多图故事任务。

现有 prompt 特征：

1. 告诉模型这是“多图故事生成”
2. 提供图片元数据
3. 要求只输出 JSON
4. 输出格式固定为：

```json
{
  "story": "..."
}
```

### 建议增强

为了接入正式故事展示页，建议在正式接入时把本地 story 输出从单字符串升级为：

```json
{
  "title": "...",
  "subtitle": "...",
  "story": "...",
  "sections": [
    {"index": 1, "text": "..."},
    {"index": 2, "text": "..."}
  ]
}
```

如果第一版不想改太多，也可以先这样做：

1. 本地 VLM 只输出整段故事
2. 再由本地代码按图片顺序切分为 section

### 优点

- 完全本地
- 多图整体感较强

### 缺点

- 最慢
- 输出稳定性最不确定
- 更依赖 prompt 质量和 JSON 规整能力

---

## 5. 推荐实现结构

## 5.1 新增枚举

建议新增：

```dart
enum StoryGenerationMode {
  deepseekTags,
  localCaptionThenDeepseek,
  localDirectStory,
}
```

用途：

- 配置页状态管理
- 生成入口分流
- 埋点和调试输出

## 5.2 新增统一故事编排服务

建议新增服务，例如：

- `story_generation_orchestrator.dart`

职责：

1. 接收：
   - 所选图片
   - 主题、副标题
   - 生成模式
2. 内部决定走哪条链路
3. 统一输出：
   - `StoryEntity`
   - `List<String> captions`（若有）
   - section 文本

这样可以避免把三套逻辑都塞进 `ConfigPage`。

## 5.3 页面职责

建议职责拆分：

- `ConfigPage`
  - 只负责 UI 配置与触发

- `StoryGenerationOrchestrator`
  - 负责三模式路由

- `StoryService`
  - 保留 DeepSeek 故事生成与存储能力

- `LocalVlmStoryService` 或编排器内私有逻辑
  - 负责封装本地 VLM caption/story 调用

---

## 6. 故事内容组织建议

无论哪种生成模式，最终都建议统一成“分段故事”。

每个 section 建议绑定：

1. 对应图片
2. 一段 40-120 字左右的文字

文字来源建议：

- 模式一：
  - DeepSeek 直接输出分段结果，或先输出整篇后本地切段
- 模式二：
  - DeepSeek 根据 caption + 标签输出分段结果
- 模式三：
  - 本地 VLM 直接输出多图故事，再切段

### section 切分建议

第一版不强制要求模型直接输出 `sections`，可以走“整段 -> 本地切段”策略：

1. 按图片数量确定段数
2. 将整段故事按自然句边界拆分
3. 尽量保证：
   - 每张图有对应文字
   - 文本长度相对均衡

如果模型能稳定输出 `sections`，则优先使用模型结果。

## 6.2 传给 DeepSeek 的输入组织

无论是模式一还是模式二，传给 DeepSeek 的输入都不应只是一坨标签文本，而应该是一个按时间整理后的“图片故事素材包”。

推荐步骤：

1. 先对用户所选图片按时间升序排序
2. 为每张图构建统一的素材对象
3. 再把素材对象列表整体传给 DeepSeek

每张图片建议包含以下字段：

- `index`
- `capturedAt` 或格式化后的时间文本
- `locationName`
- `district`
- `city`
- `province`
- `aiTags`
- `ocrTags`
- `ocrTextSummary`
- `existingCaption`
- `localVlmCaption`（仅模式二）

建议的 DeepSeek 输入组织方式：

```json
{
  "theme_hint": "用户选择的主题或切入点",
  "subtitle_hint": "用户填写的副标题或切入点",
  "photos": [
    {
      "index": 1,
      "captured_at": "2025-02-10 18:20",
      "location": {
        "location_name": "外滩",
        "district": "黄浦区",
        "city": "上海",
        "province": "上海"
      },
      "tags": ["城市夜景", "人物", "旅行"],
      "ocr_tags": ["招牌", "地铁站"],
      "ocr_summary": "画面中出现城市招牌与路牌文字",
      "existing_caption": "夜晚站在江边拍下的城市灯光",
      "local_vlm_caption": "a photo of two people standing by a river with a bright city skyline at night"
    }
  ]
}
```

这里有几个关键约束：

1. 时间和地点不是只用于展示，而是应该参与叙事组织
2. 同一张图的标签、OCR、caption 必须按图聚合，不能只做全局拼接
3. DeepSeek 看到的是“逐图线索”，这样更容易写出有顺序、有转场、有细节的故事

推荐在传给 DeepSeek 前先做一层轻量摘要：

- OCR 过长时只保留摘要
- 标签按重要度裁剪到前若干项
- caption 去重

这样可以减少 prompt 体积，提高生成速度和稳定性。

---

## 7. 性能策略

这是这次实现里很关键的一部分。

## 7.1 默认模式必须最快

默认模式是 `DeepSeek 标签故事`，原因：

1. 复用已有标签和 caption
2. 不需要额外本地 VLM 推理
3. 等待时间最短

这样能保证用户第一次使用就有可接受体验。

## 7.2 模式二和模式三要控制图片数

本地 VLM 成本明显更高，因此建议：

1. 用户选择图片很多时，不要直接把全部图传给本地 VLM
2. 先做压缩采样

建议策略：

- `<= 12` 张：全部送入
- `13 - 24` 张：按时间均匀采样 + 保留首尾 + 保留代表图
- `> 24` 张：默认只取 12 到 16 张代表图给本地 VLM

注意：

- 故事展示仍可展示全部照片
- 但故事文本生成只基于代表图，再向全量图片映射 section

## 7.3 本地 VLM Caption 结果缓存

建议：

1. 对单张图片的本地 caption 做缓存
2. 以 `assetId + modelVersion + promptVersion` 为 key

这样同一张图第二次生成故事时，不用重复做本地 caption。

## 7.4 本地 VLM 服务预热

参考 [local_vlm_test_page.dart](D:/softinno/Memoria/lib/view/pages/local_vlm_test_page.dart)：

正式功能里建议：

1. 在用户进入配置页时不立即启动本地 VLM
2. 只有当用户选中模式二或模式三，才开始检查和预热
3. 如有必要，可在点按钮后显示：
   - “正在启动本地故事模型”
   - “正在逐图生成 caption”
   - “正在串联多图生成故事”

## 7.5 并发建议

模式二中：

- caption 生成可以使用批量 structured 调用
- 不建议为每张图单独开网络/模型请求
- 要尽量沿用 `local_vlm_test_page.dart` 当前“一次提交多图”的设计

## 7.6 生成中的流式进度页

用户点击“生成故事”后，不应进入空白 loading 界面，而应进入一个可感知过程的进度页。

这个页面的目标不是单纯显示“正在生成”，而是像一个可视化制作过程，让用户看到系统正在一步步理解素材并组织故事。

推荐页面形态：

- 纵向时间线或卡片流
- 每一步有状态图标：等待中 / 进行中 / 已完成 / 失败
- 每一步下方可展示简短结果摘要
- 在关键步骤展示少量代表图预览

推荐进度步骤：

1. `整理所选图片`
   - 显示：已选择多少张图片
   - 动作：按时间排序、识别缺失时间的素材

2. `解析时间与地点`
   - 显示：识别到的时间范围、地点分布
   - 动作：整理每张图的时间文本、地点文本

3. `提取已有线索`
   - 显示：标签、OCR、已有 caption 的摘要
   - 动作：汇总 AI 标签、OCR、历史 caption

4. `解析图片语义`
   - 模式一：整理标签与元数据后直接进入下一步
   - 模式二：显示本地 caption 进度，例如“已完成 4/12 张”
   - 模式三：显示本地多图理解中，并给出当前批次的预览

5. `提炼精彩片段`
   - 显示：若干故事线索，例如“傍晚抵达外滩”“夜景最强”“聚餐是情绪高潮”
   - 动作：从多图线索中抽取关键节点

6. `组织故事结构`
   - 显示：开头 / 转场 / 高潮 / 收束 等结构摘要
   - 动作：生成故事大纲或 section 草案

7. `为你撰写故事`
   - 显示：流式追加的故事句子或段落
   - 动作：真正生成标题、副标题、正文和 section 文本

8. `保存并整理展示`
   - 显示：故事已保存，正在排版
   - 动作：落库为 `StoryEntity`，准备跳转结果页

实现建议：

1. 新增统一的进度模型，例如：
   - `StoryGenerationProgressStep`
   - 包含：`id`、`title`、`status`、`detail`、`previewPhotos`、`bullets`
2. `StoryGenerationOrchestrator` 在每个阶段发出流式更新
3. 进度页订阅这个更新流并实时刷新 UI

推荐的状态传播方式：

- `Stream<StoryGenerationProgressState>`
- 或 `ValueNotifier<StoryGenerationProgressState>`
- 若项目已有统一状态方案，也可接入现有模式

性能要求：

1. 点击按钮后应立即进入进度页，先展示第一步，不要等到全部数据准备好才刷新
2. caption 批量生成时要持续更新完成数量
3. DeepSeek 写故事时若支持分段输出，可逐步展示；若暂不支持，也应先展示“故事大纲/精彩片段”作为中间态

失败兜底：

- 任何一步失败，都要停在当前进度页
- 显示失败步骤和失败原因
- 提供“重试当前步骤”或“返回重新选择模式”的入口

完成后：

- 进度页自动跳转或 replace 到 [story_result_page.dart](D:/softinno/Memoria/lib/view/pages/story_result_page.dart)
- 避免让用户回到空白中间页

---

## 8. 详细实现步骤

## Phase 1：UI 接入

目标：

1. 在 [config_page.dart](D:/softinno/Memoria/lib/view/pages/config_page.dart) 新增故事生成方式选择
2. 在“生成视频”按钮上方新增“生成故事”按钮
3. 默认模式为 `DeepSeek 标签故事`

这一阶段只改 UI 和状态，不改底层能力。

## Phase 2：模式一接入

目标：

1. 把“生成故事”按钮接到 `StoryService`
2. 只走标签 + OCR + 时间地点 + DeepSeek
3. 生成后跳转 [story_result_page.dart](D:/softinno/Memoria/lib/view/pages/story_result_page.dart)

这一阶段先保证最稳的链路可用。

## Phase 3：模式二接入

目标：

1. 参考 [local_vlm_test_page.dart](D:/softinno/Memoria/lib/view/pages/local_vlm_test_page.dart) 封装本地 caption 批量生成
2. 把 caption 合并进 DeepSeek 故事 prompt
3. 输出更细腻的故事结果

## Phase 4：模式三接入

目标：

1. 封装本地 VLM 多图故事生成
2. 将结果映射为 `StoryEntity + sections`
3. 跳转故事页

## Phase 5：体验收尾

目标：

1. 加入进度文案
2. 加入失败兜底
3. 加入图片数过多时的自动采样提示
4. 加入本地 caption 缓存

---

## 9. 关键风险与应对

## 9.1 风险：本地 VLM 输出 JSON 不稳定

应对：

1. 沿用 `local_vlm_test_page.dart` 的 normalize 逻辑
2. 对输出做结构化兜底
3. story 模式第一版允许先输出整段，再本地切 section

## 9.2 风险：用户一次选很多张图，模式二/三太慢

应对：

1. 加采样
2. 加缓存
3. 默认模式仍为云端标签故事

## 9.3 风险：故事页 section 与图片不对齐

应对：

1. 第一版明确按时间顺序绑定
2. 每张图至少保留一个 section
3. 缺文本时允许回退到 caption

---

## 10. 建议结论

这次实现最稳妥的落地顺序是：

1. 先做 UI 和模式一
2. 再接模式二
3. 最后接模式三

原因：

1. 模式一最接近现有能力，最容易快速做对
2. 模式二在效果和稳定性之间最平衡，预计会成为最有价值的增强模式
3. 模式三最酷，但也是最容易慢、最容易不稳定的模式，应放最后收尾

如果后续开始编码，建议先从：

- [config_page.dart](D:/softinno/Memoria/lib/view/pages/config_page.dart)
- 新增 `story_generation_orchestrator.dart`
- [story_service.dart](D:/softinno/Memoria/lib/service/story_service.dart)
- 本地 VLM 封装服务

这四块开始。
