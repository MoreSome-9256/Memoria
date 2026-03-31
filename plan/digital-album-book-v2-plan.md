# 数字相册书功能升级实现方案

## 1. 目标与结论

本轮需求整体可行，但不适合在现有 [digital_album_page.dart](/D:/softinno/Memoria/lib/view/pages/digital_album_page.dart) 上继续堆叠零散交互。要稳定实现“横屏书本形态 + 真实翻页 + 元素自由编辑 + DeepSeek 自动排版”，建议将数字相册升级为三层架构：

1. 书本渲染层：负责横屏双页展示、翻页手势、翻页动画、页码管理。
2. 版式编辑层：负责图片/文字元素的拖拽、缩放、换图、字体样式调整与持久化。
3. AI 排版层：负责将图片、caption、故事段落和版面规格送给 DeepSeek，返回结构化 JSON 布局，再由 App 校验并落地执行。

当前项目已有以下基础可复用：
- [story_result_page.dart](/D:/softinno/Memoria/lib/view/pages/story_result_page.dart) 已有数字相册入口。
- [digital_album_page.dart](/D:/softinno/Memoria/lib/view/pages/digital_album_page.dart) 已有相册页生成、保存与编辑的第一版逻辑。
- [story_generation_orchestrator.dart](/D:/softinno/Memoria/lib/service/story_generation_orchestrator.dart) 和 [llm_service.dart](/D:/softinno/Memoria/lib/service/llm_service.dart) 已具备 DeepSeek/结构化 JSON 调用经验。
- [vlm_photo_picker_page.dart](/D:/softinno/Memoria/lib/view/pages/vlm_photo_picker_page.dart) 与 `photo_manager` 已具备换图所需的相册选择能力。

结论：功能可做，但建议以“数据模型重构 + 新页面渲染 + AI 协议定义 + 分阶段交付”的方式推进。

## 2. 需求拆解

### 2.1 双页相册书

目标不是单页卡片列表，而是横屏打开的一本相册书：
- 每个 spread 由 `leftPage + rightPage` 组成。
- 支持点击、拖拽或按钮触发翻页。
- 翻页动画要有纸张翻动、阴影、书脊和前后页过渡感。

### 2.2 图片自由编辑

每张图片应支持：
- 长按进入编辑态。
- 拖拽位置。
- 通过角点/边点缩放。
- 在页面边界内约束移动。
- 点击“更换图片”后，从 App 相册中重新选择。

### 2.3 文本自由编辑

每段文字应支持：
- 修改内容。
- 修改位置、大小、颜色。
- 选择预定义字体。
- 切换对齐方式、字重和是否带阴影/描边。

### 2.4 DeepSeek 排版与文案优化

点击数字相册后，不应停留在“一张图一段话”的线性排版，而应：
- 将相册尺寸、页数、图片素材、原始 caption、故事段落等输入 DeepSeek。
- 由 DeepSeek 返回结构化的版式建议与文案优化结果。
- App 对返回结果做校验、边界裁剪、碰撞修正和失败回退。

## 3. 为什么不能直接在当前页上硬改

当前 [digital_album_page.dart](/D:/softinno/Memoria/lib/view/pages/digital_album_page.dart) 的数据模型仍然是“相册页草稿列表”，本质更接近：
- 单页顺序浏览。
- 模板固定渲染。
- 仅支持修改段落文本。

而目标方案需要额外表达：
- spread 概念，而不是单页概念。
- 页面中的多个可编辑元素，而不是固定模板字段。
- AI 生成的坐标、尺寸、样式和装饰元素。
- 用户后续手动编辑后的状态持久化。

因此应新增独立的“相册书文档模型”，而不是继续用 `StorySection -> _AlbumPageDraft` 硬撑。

## 4. 新的数据模型建议

建议新增以下模型：

### 4.1 `DigitalAlbumBookEntity`

职责：持久化整本数字相册书。

建议字段：
- `id`
- `storyId`
- `title`
- `subtitle`
- `theme`
- `pageWidth`
- `pageHeight`
- `spreadCount`
- `contentJson`
- `createdAt`
- `updatedAt`
- `layoutSource`：`manual` / `ai_assisted`

### 4.2 `AlbumSpreadModel`

职责：描述一个跨页 spread。

建议字段：
- `spreadIndex`
- `leftPage`
- `rightPage`
- `backgroundStyle`
- `turnHint`

### 4.3 `AlbumPageModel`

职责：描述单页内容。

建议字段：
- `pageIndex`
- `side`：`left` / `right`
- `backgroundColor`
- `backgroundTexture`
- `elements`

### 4.4 `AlbumElementModel`

职责：描述页面上的一个可编辑元素。

建议字段：
- `id`
- `type`：`image` / `text` / `sticker` / `shape` / `subtitle`
- `x`
- `y`
- `w`
- `h`
- `rotation`
- `zIndex`
- `locked`
- `payload`
- `style`

说明：
- `x/y/w/h` 使用页内归一化坐标，范围为 `0.0 ~ 1.0`。
- 坐标相对于“单页”而不是 spread，这样横竖尺寸变化时更稳定。

## 5. 推荐的交付阶段

### 阶段 A：书本双页基础版

目标：
- 横屏展示。
- spread 双页布局。
- 左右翻页。
- 暂时用按钮 + 手势翻页。
- 动画先采用现成可控方案。

交付后用户即可看到“像书”的相册，而不是单页卡片。

### 阶段 B：元素编辑版

目标：
- 图片可拖拽、缩放、换图。
- 文字可拖拽、改内容、改字体/颜色/字号。
- 新增编辑模式工具条。
- 保存回 `DigitalAlbumBookEntity.contentJson`。

### 阶段 C：DeepSeek 自动排版版

目标：
- 将图片与故事素材发给 DeepSeek。
- 返回结构化排版 JSON。
- App 执行版式并允许用户二次编辑。
- 对 DeepSeek 结果做安全校验与回退。

### 阶段 D：更真实的翻页动画

目标：
- 增加书脊高光、页角弯曲、背页阴影、翻页厚度错觉。
- 从“可用动画”升级为“相册书质感动画”。

## 6. 书本渲染与翻页动画方案

### 6.1 首选实现策略

建议先采用“可控实现”而不是一开始就完全自研物理翻页：

方案 1：
- 先用成熟翻页组件承载翻页。
- 每一页内容仍由我们自己渲染。
- 这样能快速得到真实感较强的翻页体验。

方案 2：
- 若现成组件不够稳定，再自研 `BookSpreadView + PageCurlPainter + GestureController`。
- 自研时仅复用动画思想，不依赖业务层重写。

### 6.2 调研结论

调研到的可参考方案：
- [book_flip](https://pub.dev/packages/book_flip)：提供 3D 书本翻页效果，适合作为第一阶段验证方案。
- [flip_curl_animation_widget](https://pub.dev/packages/flip_curl_animation_widget)：支持 page flip/curl、程序化翻页、手势区分与缩放管理，适合用于更接近杂志/相册翻页的交互验证。

从工程风险看：
- 第一阶段建议优先验证 `flip_curl_animation_widget` 或类似方案。
- 如果手势冲突、层级控制、性能或自定义度不够，再切换为自研页角翻卷动画。

### 6.3 翻页动画的落地要求

无论采用包还是自研，都需要满足：
- 横屏锁定。
- 一次翻动一个 spread。
- 当前页、背页、下一页都能参与动画。
- 中央书脊区域固定。
- 动画中加入阴影渐变与页边高光。
- 支持按钮翻页与拖拽翻页两种方式。

## 7. 自由编辑能力实现方案

### 7.1 图片编辑

图片元素建议使用：
- `Stack + Positioned`
- 编辑态 overlay
- `GestureDetector` 处理拖拽
- 角点 handle 处理缩放

交互规则：
- 长按选中元素。
- 拖拽主体移动。
- 四角 handle 改变尺寸。
- 保持最小宽高。
- 默认限制在页边界内。
- 支持“锁定比例”和“自由拉伸”两种模式。

### 7.2 图片更换

复用现有相册选择链路：
- [vlm_photo_picker_page.dart](/D:/softinno/Memoria/lib/view/pages/vlm_photo_picker_page.dart)
- `photo_manager`

推荐流程：
- 选中图片元素。
- 点击工具条“更换图片”。
- 打开轻量版相册选择器。
- 替换元素的 `photoId/path/thumbnail`.
- 保留原有元素位置与尺寸。

### 7.3 文本编辑

文本元素建议支持：
- 双击或点击编辑。
- 侧边面板/底部面板调整：
  - 文本内容
  - 字体
  - 字号
  - 颜色
  - 行高
  - 对齐
  - 粗细
  - 阴影

### 7.4 字体策略

不要允许任意系统字体输入，建议预置 4-6 种字体：
- 正文宋体风格
- 无衬线简洁风格
- 手写感字体
- 标题书法/海报风格

实现方式：
- 将字体文件加入 `assets/fonts/`
- 定义固定 `fontFamily` 列表
- DeepSeek 输出只允许引用预定义字体 ID

## 8. 自动排版算法建议

### 8.1 总原则

不要让 DeepSeek 直接“自由生成任意像素坐标”后立刻生效。正确做法是：
- App 提供页面规格、模板能力和安全约束。
- DeepSeek 负责内容组织与布局建议。
- App 负责最终校验、修正、裁剪和回退。

### 8.2 推荐算法路线

建议采用“模板 + 约束 + AI 微调”的混合方式：

1. 模板层
- 先准备一批高质量 spread 模板。
- 如：左图右文、双图对开、上图下文、单大图配角标、章节页、封面页。

2. 约束层
- 规定安全区、最小边距、最小字号、最大图片占比、元素不可重叠规则。
- 由本地算法保证页面可读性。

3. AI 层
- DeepSeek 在模板范围内选择模板、填充内容、给出元素坐标和文案优化建议。

### 8.3 为什么不用完全自由搜索

完全自由布局虽然看起来“更智能”，但问题是：
- 结果不稳定。
- 校验复杂。
- 容易超出页面边界。
- 与用户手动编辑状态难以合并。

因此首版建议以模板驱动为主，矩形打包和约束求解为辅。

### 8.4 可借鉴的布局算法

可参考的思路包括：
- “Justified layout”：
  按行填充、统一视觉密度，适合同一时间线的多图编排。
- “Rectangle packing”：
  用于若干图片框在固定页面内的无重叠放置。
- “Constraint-based layout”：
  用于处理边距、对齐、标题位置和元素不越界等规则。

参考资料：
- [Justified collage style autolayout 示例](https://apps.apple.com/us/app/photoscollage-autolayout/id628960643)
- [二维矩形打包研究综述示例](https://pmc.ncbi.nlm.nih.gov/articles/PMC10754432/)
- [Constraint-based Document Layout for the Web](https://research.monash.edu/en/publications/constraint-based-document-layout-for-the-web)

结论：
- 首版算法不建议直接上复杂全局优化。
- 应先以模板和约束求解实现稳定结果，再逐步增加 AI 自由度。

## 9. DeepSeek 排版接口设计

### 9.1 输入内容

建议发送给 DeepSeek 的输入由四部分构成：

1. 相册规格
- 横屏模式
- 单页宽高
- spread 数量目标
- 页面安全区
- 允许的模板列表

2. 内容素材
- 照片列表
- 每张照片的 caption、tags、location、time
- 故事标题、副标题、sections、highlights

3. 设计约束
- 每页最大元素数
- 最大文本字数
- 预定义字体 ID
- 可用颜色 token

4. 输出协议
- 强制只输出 JSON
- 坐标使用归一化页坐标
- 不得输出未知模板/未知字体/未知颜色

### 9.2 返回 JSON 协议

建议新增契约版本：
- `schema_version = "memoria.album.layout.v1"`

推荐返回格式：

```json
{
  "schema_version": "memoria.album.layout.v1",
  "album": {
    "title": "春光记事",
    "subtitle": "在花影与湖水之间",
    "theme": "memory_book",
    "book": {
      "orientation": "landscape",
      "page_width": 1200,
      "page_height": 900,
      "spread_count": 3
    }
  },
  "spreads": [
    {
      "spread_index": 0,
      "template_id": "cover_spread",
      "left_page": {
        "background": {
          "color_token": "paper_warm"
        },
        "elements": [
          {
            "id": "title_1",
            "type": "text",
            "role": "title",
            "x": 0.10,
            "y": 0.14,
            "w": 0.58,
            "h": 0.16,
            "rotation": 0,
            "z_index": 10,
            "text": "春光记事",
            "style": {
              "font_id": "serif_elegant",
              "font_size": 42,
              "color_token": "ink_black",
              "align": "left",
              "weight": "700"
            }
          }
        ]
      },
      "right_page": {
        "background": {
          "color_token": "paper_warm"
        },
        "elements": [
          {
            "id": "image_1",
            "type": "image",
            "role": "hero_photo",
            "photo_id": "asset_123",
            "x": 0.12,
            "y": 0.10,
            "w": 0.76,
            "h": 0.56,
            "rotation": 0,
            "z_index": 1,
            "crop": {
              "mode": "cover",
              "focus_x": 0.5,
              "focus_y": 0.4
            }
          },
          {
            "id": "subtitle_1",
            "type": "text",
            "role": "caption",
            "x": 0.14,
            "y": 0.72,
            "w": 0.70,
            "h": 0.14,
            "rotation": 0,
            "z_index": 5,
            "text": "樱花枝影垂向湖面，春意被风轻轻托住。",
            "style": {
              "font_id": "sans_clean",
              "font_size": 20,
              "color_token": "ink_soft",
              "align": "left",
              "weight": "400"
            }
          }
        ]
      }
    }
  ],
  "global_notes": [
    "封面使用大留白，正文采用图文交替节奏。"
  ]
}
```

### 9.3 解析规则

App 端解析时必须执行：
- `schema_version` 校验
- `template_id` 白名单校验
- `font_id` / `color_token` 白名单校验
- 坐标范围裁剪到 `0.0 ~ 1.0`
- `w/h` 最小值与最大值校验
- 文本长度裁剪
- 图片元素 `photo_id` 存在性校验

### 9.4 回退规则

只要命中以下任一情况，就不能直接使用 AI 布局：
- JSON 解析失败
- spread 数量异常
- 页元素为空
- 坐标大量越界
- 使用未知模板/未知字体

回退策略：
- App 使用本地模板引擎重新排版
- 保留 DeepSeek 优化后的文案，或仅保留标题/副标题

## 10. 本地模板引擎建议

即使接入 DeepSeek，也必须保留本地模板引擎作为兜底。

建议首版提供这些模板：
- `cover_spread`
- `left_image_right_story`
- `left_story_right_image`
- `double_photo_clean`
- `single_photo_caption`
- `chapter_break`
- `ending_spread`

模板引擎职责：
- 根据图片方向、文本长短和章节角色选择模板。
- 根据安全区自动计算默认坐标。
- 当 AI 布局失败时独立生成可展示结果。

## 11. 页面编辑态与展示态分离

建议把相册书页面分成两种模式：

### 展示态
- 只允许翻页、缩放预览、沉浸式阅读。

### 编辑态
- 选中元素后显示边框与控制点。
- 顶部或底部显示工具条。
- 暂停翻页手势，优先响应元素拖拽和缩放。

这样可以避免“翻页手势”和“编辑手势”互相打架。

## 12. 推荐新增文件

建议新增或重构如下文件：
- `lib/models/entity/digital_album_book_entity.dart`
- `lib/models/vo/album_spread_model.dart`
- `lib/models/vo/album_page_model.dart`
- `lib/models/vo/album_element_model.dart`
- `lib/service/digital_album_layout_service.dart`
- `lib/service/digital_album_ai_service.dart`
- `lib/service/digital_album_validator_service.dart`
- `lib/view/pages/digital_album_book_page.dart`
- `lib/view/widgets/album_book_view.dart`
- `lib/view/widgets/album_spread_view.dart`
- `lib/view/widgets/album_element_overlay.dart`
- `lib/view/widgets/album_text_editor_sheet.dart`
- `lib/view/widgets/album_image_editor_toolbar.dart`

现有 [digital_album_page.dart](/D:/softinno/Memoria/lib/view/pages/digital_album_page.dart) 建议定位为旧版或过渡版，避免继续叠加复杂能力。

## 13. 实施顺序建议

### 第 1 周
- 新建数据模型与持久化结构。
- 实现双页 spread 渲染。
- 横屏锁定。
- 左右按钮翻页。

### 第 2 周
- 接入翻页动画组件。
- 完成展示态/编辑态切换。
- 实现文本编辑。

### 第 3 周
- 实现图片拖拽、缩放、换图。
- 完成保存与恢复。

### 第 4 周
- 设计并接入 DeepSeek JSON 协议。
- 完成 AI 布局校验与回退。
- 增加样式 token 与模板系统。

### 第 5 周
- 优化翻页质感。
- 优化编辑器交互。
- 增加字幕、贴纸、章节页等细节。

## 14. 风险与建议

关键建议：
- 不要让 DeepSeek 直接决定最终渲染结果，App 必须保留校验权。
- 不要一开始就追求完全自由排版，先做“模板化 + 可编辑 + AI 辅助”。
- 不要把编辑态和翻页态混在一起，要明确切换。
- 不要继续把复杂信息塞进现有 `StorySection`，应建立独立相册书数据模型。

最终建议：
- 先做“相册书基础渲染 + 编辑态 + JSON 协议”，再做高质量翻页动画。
- 翻页动画是效果增强项，AI 协议和数据模型才是后续可持续扩展的核心。
