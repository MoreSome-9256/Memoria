# Memoria 当前实现导读

> 核查日期：2026-06-10  
> 范围：当前工作区中的正式用户功能，不包含“开发者设置”内部实验页。  
> 目标：不阅读源码也能理解程序现在如何运行、数据从哪里来、各功能如何连接，以及当前有哪些风险。

仓库已有的 `docs/architecture_overview.md` 覆盖面很广，但部分描述已经落后于实际实现。遇到冲突时，应优先相信本目录中的当前实现文档和源码。

## 文档索引

1. [运行时、媒体访问与扫描分析管线](runtime-scan-and-media.md)
2. [检索、聚类与回忆发现策略](retrieval-clustering-and-discovery.md)
3. [用户界面与创作流程](user-interfaces-and-creation.md)
4. [已知问题、设计缺陷与修复优先级](known-issues-and-priorities.md)

## 全局数据边界

- `PhotoEntity.assetId`：系统相册资源的持久身份。读取缩略图、原图、动态图片和视频时应优先使用。
- `PhotoEntity.path`：可能为空、过期或只是临时路径，不能作为照片是否可显示、是否可处理的唯一判断。
- `PhotoEntity.id`：ObjectBox 内部记录 ID，只在本地数据库中有效。
- ObjectBox 业务实体：照片、事件、故事、创作推荐等。
- ObjectBox HNSW 向量索引：照片 MobileCLIP embedding。
- 系统相册：原始图片、视频和动态图片的最终来源。
- 临时缓存：缩略图、标签 prompt 原型、视频准备文件等，不应成为业务事实来源。

## 当前主导航

`WidgetTree` 提供五个入口：

1. 首页 `HomePage`
2. 相册 `AlbumPage`
3. 中央创作按钮 `CreateHubPage`
4. 主题 `ThemeClustersPage`
5. 我的 `ProfilePage`

全局还叠加 AI 分析进度横幅和回忆助手悬浮入口 `MemoryAssistantOverlay`。

