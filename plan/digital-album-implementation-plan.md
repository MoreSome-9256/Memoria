# 数字相册功能实现方案

## 1. 背景与目标

当前项目已经具备一条完整的“故事生成 -> 结果展示 -> 用户编辑 -> 保存故事”的链路：

- 生成入口在 [create_page.dart](/D:/softinno/Memoria/lib/view/pages/create_page.dart) / [story_generation_progress_page.dart](/D:/softinno/Memoria/lib/view/pages/story_generation_progress_page.dart)
- 核心编排在 [story_generation_orchestrator.dart](/D:/softinno/Memoria/lib/service/story_generation_orchestrator.dart)
- 存储实体在 [story_entity.dart](/D:/softinno/Memoria/lib/models/entity/story_entity.dart)
- 展示与编辑页在 [story_result_page.dart](/D:/softinno/Memoria/lib/view/pages/story_result_page.dart)

现有结果页更像“图文故事长页”，而不是“实体相册式数字翻页体验”。本方案目标是在现有故事能力之上，新增一个“数字相册”能力层，让用户可以把生成后的图文故事进一步整理为可翻页、可编辑、自动排版的数字相册。

核心目标：

1. 在故事生成完成后，支持用户一键进入“生成数字相册”流程。
2. 数字相册中的每一页都可以承载图片、caption、短故事或混合内容。
3. caption / 短故事必须支持用户逐页二次编辑。
4. 系统需要自动完成页面编排、大小调控、时间线/故事线组织。
5. 相册浏览体验要接近实体相册，支持翻页和动态翻页效果。

---

## 2. 需求拆解

### 2.1 用户视角需求

用户在故事结果页完成故事生成后，希望继续做一件事：

- 不是仅仅看图文长页
- 而是把这组故事内容“装订”为数字相册

数字相册需要满足：

- 图片有说明文字
- 精彩图片可配更完整的一段故事
- 用户能改文字
- 页面不是机械列表，而是有版式、有节奏
- 翻页时有相册感

### 2.2 系统视角需求

系统需要新增的不是一个简单页面，而是一整条新的数据和渲染链路：

1. 从 `StoryEntity + PhotoEntity` 推导相册素材
2. 生成相册页模型
3. 自动做版式决策
4. 存储相册结构
5. 渲染可翻页 UI
6. 支持编辑后持久化

---

## 3. 当前代码基础分析

## 3.1 已有可复用能力

### 3.1.1 故事结构化产物

[story_generation_orchestrator.dart](/D:/softinno/Memoria/lib/service/story_generation_orchestrator.dart) 已经能输出：

- `title`
- `subtitle`
- `story`
- `sections`
- `highlights`

其中 `sections` 已经天然接近“每张图对应一段内容”的相册素材，这一点可以直接复用。

### 3.1.2 StoryEntity 的 Markdown 组织方式

[story_entity.dart](/D:/softinno/Memoria/lib/models/entity/story_entity.dart) 中已经存在：

- `content`
- `photoIds`
- `parseToSections(...)`
- `sectionsToMarkdown(...)`

这说明当前系统已经有“结构化 section <-> 持久化内容”的转换能力。数字相册可以沿用这个思路，但不建议继续只靠 Markdown 表达复杂版式。

### 3.1.3 故事结果页可编辑能力

[story_result_page.dart](/D:/softinno/Memoria/lib/view/pages/story_result_page.dart) 已经具备：

- section 列表展示
- 文本逐段编辑
- 保存回 `StoryEntity`

这为数字相册的“逐页编辑”提供了直接经验。

## 3.2 当前不足

现有结构不适合直接承载数字相册，主要问题有：

1. `StoryEntity.content` 偏向线性长文，不适合描述复杂页面布局。
2. `StorySection` 只有“图 + 文”最基础关系，没有页、模板、布局、强调级别等概念。
3. 当前结果页是 `CustomScrollView + SliverList`，天然是长页滚动，不是翻页模型。
4. 当前保存逻辑只保存文本内容，不保存页面设计信息。

结论：

数字相册应作为一套新的“相册实体 + 页面模型 + 渲染页”能力新增，而不是直接把 `StoryResultPage` 改造成翻页相册。

---

## 4. 建议的功能边界

本次建议将“数字相册”定义为：

- 由故事生成结果派生出的二次内容产品
- 与 `StoryEntity` 有引用关系，但拥有独立存储结构
- 默认从故事结果页发起创建
- 支持后续再次打开、编辑、浏览、导出

建议不要把它做成：

- 临时 UI 状态
- 只在内存中存在的翻页效果
- 直接覆盖原故事内容

换句话说：

- 故事是故事
- 数字相册是基于故事派生出的新对象

这样更符合后续扩展，例如：

- 一个故事可生成多个不同风格相册
- 同一组照片可有“时间线版”“故事版”“纪念册版”

---

## 5. 数据模型设计建议

## 5.1 新增实体：DigitalAlbumEntity

建议新增 `DigitalAlbumEntity`，用于持久化数字相册整体信息。

建议字段：

- `id`
- `storyId`
- `title`
- `subtitle`
- `coverPhotoId`
- `createdAt`
- `updatedAt`
- `theme`
- `layoutMode`
- `pageCount`
- `contentJson`
- `isGeneratedByAi`

说明：

- `storyId`：关联来源故事
- `contentJson`：核心页面结构，建议用 JSON 字符串存
- `layoutMode`：例如 `timeline` / `narrative` / `mixed`
- `theme`：例如 `paper`, `memory`, `minimal`, `vintage`

## 5.2 页面级模型：DigitalAlbumPage

建议定义页模型，不直接存 Widget，而是存可序列化结构。

建议字段：

- `pageIndex`
- `templateType`
- `primaryPhotoId`
- `secondaryPhotoIds`
- `title`
- `caption`
- `storyText`
- `layoutHints`
- `editableFields`

其中：

- `templateType` 决定页模板
- `layoutHints` 提供自动排版信息
- `editableFields` 标识哪些文本是用户可改的

## 5.3 模板类型建议

建议首版控制在 4-6 种模板以内：

1. `cover`
2. `single_photo_caption`
3. `single_photo_story`
4. `double_photo_timeline`
5. `chapter_break`
6. `ending`

这样可以避免首版模板过多、难以稳定自动编排。

---

## 6. 生成链路设计

## 6.1 入口位置

建议在 [story_result_page.dart](/D:/softinno/Memoria/lib/view/pages/story_result_page.dart) 里新增入口按钮：

- “生成数字相册”

位置建议：

- 放在底部操作区，和“保存”“播放回忆”并列
- 或者在 AppBar / 更多菜单中提供

## 6.2 生成流程

建议的生成流程：

1. 读取 `StoryEntity`
2. 读取关联 `PhotoEntity`
3. 从 `story.sections` / `photo.aiCaption` / 本地 VLM caption / OCR / tags 中组装候选素材
4. 调用“数字相册编排服务”生成页面结构
5. 产出 `DigitalAlbumEntity`
6. 跳转到数字相册预览页

## 6.3 文案生成策略

数字相册中的文案建议分级：

### A. Caption

适用于普通图片页：

- 一句话
- 有文采但不虚浮
- 基于真实画面
- 优先使用本地 VLM 的可见内容描述

### B. 短故事

适用于精彩图片页或章节页：

- 1-3 段短文
- 来自现有故事 sections、highlights 或重新摘要

### C. 章节标题

适用于故事线比较清晰的页面分组：

- 如“午后序章”“湖畔一瞬”“回看时光”

## 6.4 文案来源优先级

建议优先级：

1. 本地 VLM caption
2. 已保存的 `photo.aiCaption`
3. 故事 section 文本
4. `highlights`
5. OCR / tags 作为辅助，不直接裸用

原因：

- 数字相册最终展示内容必须“切实”
- 优先用图片视觉描述，而不是标签堆砌

---

## 7. 自动排版设计

## 7.1 排版目标

数字相册不是单纯“图下加字”，而要做到：

- 信息层级清晰
- 图文节奏自然
- 页面密度有变化
- 既像相册，也像经过设计的纪念册

## 7.2 排版模式

建议首版支持两种模式：

### 7.2.1 时间线模式

适用于：

- 多图按拍摄时间推进明显
- 旅行、活动、日常记录

规则：

- 以时间为主轴
- 每页 1-2 张图
- 文案强调当时情境和推进关系

### 7.2.2 故事线模式

适用于：

- 用户主题明确
- sections 已经形成明显叙事

规则：

- 按 section / highlights 组织页顺序
- 章节页 + 内容页混排

## 7.3 自动布局规则建议

建议使用规则驱动，而不是首版就做复杂布局搜索。

输入维度：

- 图片横竖比例
- 图片主题强度
- 是否人物主图
- caption 长短
- 是否适合作为章节页

规则样例：

- 竖图 + 短 caption -> `single_photo_caption`
- 横图 + 文本较长 -> `single_photo_story`
- 同一时间段两张相关图 -> `double_photo_timeline`
- 高亮图 -> `single_photo_story` 或 `cover`

## 7.4 页面密度控制

建议加入页级约束：

- 单页文字上限
- 单页图片数量上限
- 连续高密度页不能太多
- 封面/结尾页必须留白更多

---

## 8. 翻页交互设计

## 8.1 交互形式建议

建议首版采用“书本式横向翻页”：

- 左右翻页
- 当前页 / 下一页的纸张翻转动效
- 支持点击左右边缘或滑动翻页

## 8.2 Flutter 技术实现建议

首版建议分两层：

### A. 基础可用版

使用：

- `PageView`
- 自定义 `PageTransformer`
- `AnimatedBuilder`

优点：

- 实现稳定
- 性能可控
- 易于先把相册模型和页面布局跑通

### B. 增强实体翻页版

后续如需要更强实体感，可引入：

- 自定义 `CustomPainter`
- 页面裁切 / 阴影 / 翻转矩阵
- 或谨慎引入成熟翻页包

建议：

首版先做“高质量伪翻页”，不要一上来做重度 3D 纸张模拟。

原因：

- 当前项目还有视频导出、故事页、较多图片渲染链路
- 真正的复杂翻页会显著增加卡顿和维护成本

---

## 9. 编辑能力设计

## 9.1 编辑粒度

建议允许编辑：

- 封面标题
- 副标题
- 每页 caption
- 每页故事文案
- 章节页标题

不建议首版开放：

- 自由拖拽图片位置
- 任意改模板
- 富文本复杂样式编辑

原因：

首版重点应是“自动生成 + 轻量修订”，不是做全功能编辑器。

## 9.2 编辑入口

建议在数字相册预览页中：

- 点击文字区域直接编辑
- 或每页右上角出现“编辑”按钮

编辑后：

- 更新页模型
- 同步更新 `DigitalAlbumEntity.contentJson`

---

## 10. 页面与模块拆分建议

## 10.1 新增页面

建议新增：

- `digital_album_preview_page.dart`
- `digital_album_editor_page.dart` 或直接在 preview 中内嵌编辑

## 10.2 新增服务

建议新增：

- `digital_album_service.dart`
  - 相册生成
  - 相册保存/读取
  - 页面模型序列化

- `digital_album_layout_service.dart`
  - 自动模板选择
  - 页面布局规则

## 10.3 新增模型

建议新增：

- `digital_album_entity.dart`
- `digital_album_models.dart`

其中 `digital_album_models.dart` 可放：

- `DigitalAlbumDocument`
- `DigitalAlbumPage`
- `DigitalAlbumPageTemplate`
- `DigitalAlbumLayoutMode`

---

## 11. 与现有故事链路的关系

## 11.1 不替代 StoryEntity

数字相册不应替代 `StoryEntity`，而应依附于它：

- `StoryEntity` 仍然是故事原始结果
- `DigitalAlbumEntity` 是二次编排产物

## 11.2 与 StoryResultPage 的关系

[story_result_page.dart](/D:/softinno/Memoria/lib/view/pages/story_result_page.dart) 建议继续保留为：

- 快速阅读
- 文本编辑
- 保存故事
- 生成视频

数字相册页面则承担：

- 相册式浏览
- 页面编辑
- 翻页交互

这样职责更清晰。

---

## 12. 推荐实施阶段

## Phase 1：数据与静态预览

目标：

- 定义 `DigitalAlbumEntity`
- 定义页模型
- 从 `StoryEntity` 生成静态相册结构
- 用 `PageView` 展示无动画或轻动画相册页

完成标志：

- 用户能从故事页进入数字相册预览
- 每页显示图文
- 支持保存和再次打开

## Phase 2：自动排版与文本编辑

目标：

- 接入模板选择逻辑
- 支持 timeline / narrative 两种模式
- 支持逐页编辑文案
- 保存后持久化

完成标志：

- 相册不再只是“一个固定模板重复”
- 用户可逐页修改 caption / 故事

## Phase 3：翻页动效增强

目标：

- 引入更接近实体相册的翻页动画
- 增加阴影、纸张层次、封面/封底效果

完成标志：

- 浏览体验明显区别于普通 `PageView`

## Phase 4：导出能力

可选后续：

- 导出为视频式翻页回忆
- 导出为图片/PDF 纪念册

---

## 13. 风险与注意事项

## 13.1 最大风险：自动排版过度复杂

建议首版不要追求：

- 自由拖拽
- 任意混排
- 高自由度设计器

否则容易拖垮整体开发节奏。

## 13.2 最大业务风险：文案失真

数字相册中的 caption 和短故事必须建立在“真实图片内容”上。

建议：

- 保留本地 VLM caption 作为核心输入
- 对 tags / OCR 只做辅助
- 对长文案做人工可编辑兜底

## 13.3 最大交互风险：翻页动画卡顿

当前项目图片多、视频能力重，翻页动画如果过于复杂，会影响中低端设备表现。

建议：

- 首版优先保证流畅
- 动画可渐进增强

---

## 14. 最终建议

建议采用“故事页之上新增数字相册层”的路线，而不是直接改造故事结果页。

最优实施顺序：

1. 先新增 `DigitalAlbumEntity + 页面模型`
2. 再做从 `StoryEntity` 派生相册结构
3. 再做自动排版
4. 最后做高质量翻页动画

这样可以保证：

- 架构清晰
- 可持续迭代
- 不破坏当前故事生成与结果页链路

---

## 15. 本方案对应的落地文件建议

建议后续新增或修改的文件如下：

- 新增 [digital_album_entity.dart](/D:/softinno/Memoria/lib/models/entity/digital_album_entity.dart)
- 新增 [digital_album_models.dart](/D:/softinno/Memoria/lib/models/vo/digital_album_models.dart)
- 新增 [digital_album_service.dart](/D:/softinno/Memoria/lib/service/digital_album_service.dart)
- 新增 [digital_album_layout_service.dart](/D:/softinno/Memoria/lib/service/digital_album_layout_service.dart)
- 新增 [digital_album_preview_page.dart](/D:/softinno/Memoria/lib/view/pages/digital_album_preview_page.dart)
- 按需新增 [digital_album_flip_view.dart](/D:/softinno/Memoria/lib/view/widgets/digital_album_flip_view.dart)
- 修改 [story_result_page.dart](/D:/softinno/Memoria/lib/view/pages/story_result_page.dart) 以增加“生成数字相册”入口
- 修改 [photo_service.dart](/D:/softinno/Memoria/lib/service/photo_service.dart) / Isar schema 注册以纳入新实体

---

## 16. 当前结论

你的需求是合理且非常适合当前项目方向的。  
它不是一个简单 UI 小功能，而是“故事生成结果的二次产品化能力”。  
从当前代码基础出发，完全适合拆成一个独立的“数字相册模块”来做。

本次仅输出方案，不进行编码。
