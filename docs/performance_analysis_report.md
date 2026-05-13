# Memoria 性能分析与优化方案

> 基于代码审计生成的完整性能诊断报告
> 生成日期: 2026-05-13

---

## 目录

- [1. 核心问题: 数据库查询没有索引](#1-核心问题-数据库查询没有索引)
- [2. N+1 查询模式 (事件页面)](#2-n1-查询模式-事件页面)
- [3. 图片加载管线问题](#3-图片加载管线问题)
- [4. 同步文件 IO 阻塞主线程](#4-同步文件-io-阻塞主线程)
- [5. DBSCAN 聚类在主线程运行](#5-dbscan-聚类在主线程运行)
- [6. Sequential for+await 反模式](#6-sequential-forawait-反模式)
- [7. getAll 全表扫描](#7-getall-全表扫描)
- [8. 事件流每次触发全量重查](#8-事件流每次触发全量重查)
- [9. HomePage 单次加载 9-11+ 个查询](#9-homepage-单次加载-9-11-个查询)
- [10. 总结与优先级路线图](#10-总结与优先级路线图)

---

## 1. 核心问题: 数据库查询没有索引

### 问题描述

ObjectBox 实体上频繁查询的字段缺少 `@Index()` 注解, 导致每次查询都是**全表扫描 + 内存排序**。

### 受影响字段

| 实体 | 字段 | 使用场景 | 未索引后果 |
|------|------|---------|-----------|
| `PhotoEntity` | `timestamp` | 按时间排序/范围查询(8+处) | 每次排序都扫描全部照片 |
| `PhotoEntity` | `isAiAnalyzed` | 过滤未分析照片(9处) | 每次过滤扫描全部照片 |
| `EventEntity` | `startTime` | 事件排序/过滤(主排序字段) | 全表扫描 |
| `EventEntity` | `endTime` | 旅行检测 > 条件 | 全表扫描 |
| `EventEntity` | `photoCount` | 过滤小事件( > 条件) | 全表扫描 |
| `StoryEntity` | `eventId` | 按事件查故事 | 全表扫描 |

### 当前状态

```
PhotoEntity.timestamp    → ❌ 无 @Index()
PhotoEntity.isAiAnalyzed → ❌ 无 @Index()
EventEntity              → ❌ 全部字段无 @Index()
StoryEntity.eventId      → ❌ 无 @Index()
```

### 修复方案

在实体上添加索引注解:

```dart
// PhotoEntity
@Index()
late int timestamp;

@Index()
bool isAiAnalyzed = false;

// EventEntity
@Index()
late int startTime;

@Index()
late int endTime;

@Index()
int photoCount = 0;

// StoryEntity
@Index()
int? eventId;
```

### 预期收益

- `HomePage` 的 `ORDER BY timestamp DESC` 从 O(n) 全表扫描变为 O(log n) B-tree 索引查找
- `EventService.watchEvents()` 的排序从内存排序变为数据库排序
- `isAiAnalyzed` 的 9 处过滤从扫描全部行变为精准命中

---

## 2. N+1 查询模式 (事件页面)

### 问题描述

`album_page.dart` 的 `_groupEvents()` 方法对每个事件分别查询照片:

```dart
for (var i = 0; i < eventEntities.length; i++) {
  final event = await eventEntities[i].toPreviewModel(
    loadPhotoEntities: loadPhotos,  // 每个事件一次 getMany()
  );
  allEvents.add(event);
}
```

**影响:** 50 个事件 = 51 次数据库查询, 不仅次数多, 而且循环用 await 串行执行。

### 修复方案

批量加载:

```dart
// 1. 收集所有事件的封面 photoIds
final allCoverIds = eventEntities
    .expand((e) => e.photoIds.take(3))
    .toSet()
    .toList();

// 2. 一次查询全部封面照片
final coverPhotos = photoBox.getMany(allCoverIds);
final coverByEventId = <int, List<PhotoEntity>>{};
for (final id in allCoverIds) {
  coverByEventId.putIfAbsent(id, () => []).add(coverPhotos.firstWhere((p) => p.id == id));
}

// 3. 用内存映射构建 Event, 无任何 await
final events = eventEntities.map((e) => _buildEventFromMemory(
  entity: e,
  covers: e.photoIds.take(3).map((id) => coverByEventId[id]).whereType<PhotoEntity>().toList(),
));
```

### 预期收益

- 数据库查询从 N+1 次降为 1 次
- 串行 await 变为同步内存操作

---

## 3. 图片加载管线问题

### 问题 3a: 网格缩略图使用全分辨率原图

所有图片网格 (相册页、搜索页、事件详情页、主题聚类页) 都用 `Image.file()` 直接从磁盘加载**全分辨率原图** (12MP+, 3-12MB), 即使是 120x150px 的网格小图。

### 问题 3b: ImageCache 未配置

`main.dart` 未配置 Flutter ImageCache, 使用默认 50MB 上限。对于照片管理应用, 5-15 张全分辨率解码图就能撑爆缓存。

### 问题 3c: 搜索页直接使用 `PathImage` 而非 `DeferredPathImage`

`album_search_page.dart:945` 直接使用 `PathImage`, 没有延迟加载, 搜索结果可能瞬间触发数十张全分辨率解码。

### 问题 3d: 延迟加载调度器代码重复 4 份

`_DeferredImageLoadScheduler` 分别存在于:
- `lib/view/widgets/deferred_path_image.dart`
- `lib/view/pages/album_page.dart` (内联)
- `lib/view/pages/theme_clusters_page.dart` (不同类名, 相同逻辑)
- `lib/view/pages/album_page_deferred_image.dart` (已删除的 part 文件? 需要确认)

各自有独立的静态并发队列, 导致应用同时有 8+ 个图片解码任务竞争 I/O。

### 修复方案

```dart
// 1. main.dart - 配置 ImageCache
WidgetsFlutterBinding.ensureInitialized();
PaintingBinding.instance.imageCache.maximumSizeBytes = 200 * 1024 * 1024; // 200MB

// 2. 新建统一的延迟加载调度器 (共享单例)
// lib/view/widgets/deferred_image_scheduler.dart
class DeferredImageScheduler {
  static const int _maxConcurrent = 4;
  static final Queue<_Ticket> _queue = Queue();
  static int _active = 0;
  
  static void enqueue(_Ticket ticket, VoidCallback starter) { ... }
  static void complete(_Ticket ticket) { ... }
}

// 3. 网格图片改用操作系统缩略图
// 使用 photo_manager 的 AssetEntity.thumbnailDataWithSize()
// 已经在 vlm_photo_picker_page.dart:328 和 ai_service_input.dart:137 有示例
Image.memory(thumbnailBytes, fit: BoxFit.cover);

// 4. 配置 cacheExtent
SliverGrid(
  delegate: ...,
  cacheExtent: 500, // 从默认 250px 增加到 500px
)
```

### 预期收益

- 网格图片解码开销从 3-12MB/张降到 50-200KB/张 (60倍减少)
- ImageCache 从爆满载变为有效覆盖
- 搜索页面不再瞬间卡死

---

## 4. 同步文件 IO 阻塞主线程

### 问题描述

多处使用 `file.existsSync()`、`file.deleteSync()` 等同步 IO 在主线程:

| 位置 | 代码 | 影响 |
|------|------|------|
| `path_image.dart:87` | `file.existsSync()` 在 build 中 | 每次 build 可能阻塞数十 ms |
| `story_video_page.dart:835,861,898,1595` | 4 处 `existsSync()` 在 build 中 | 每次视频页 build 都同步检查文件存在 |
| `face_pipeline_service.dart:384-393` | 循环中 `existsSync()` + `deleteSync()` | 同步 IO 叠加 |
| `offscreen_render_worker.dart:689` | `deleteSync()` | 离屏渲染路径 |

### 修复方案

```dart
// 之前
if (!file.existsSync()) return fallback;

// 之后
if (!await file.exists()) return fallback;
```

对于 `path_image.dart` 这种需要立即返回结果的, 使用异步预检查 + 缓存:

```dart
class PathImageState extends State<PathImage> {
  // 文件存在性预检查, 在 initState 中异步执行
  void initState() {
    _checkFileExistence();
  }
  
  Future<void> _checkFileExistence() async {
    final exists = await File(widget.path).exists();
    if (mounted && exists != _fileExists) {
      setState(() => _fileExists = exists);
    }
  }
}
```

---

## 5. DBSCAN 聚类在主线程运行

### 问题描述

`lib/utils/dbscan_algorithm.dart` 的 `clusterScoredPhotos()` 是**复杂度 O(n²) 的 CPU 密集操作** (计算所有点对的 cosine 距离), 但**没有包装在 `Isolate.run` 中**。

`lib/utils/theme_subclustering.dart` (920 行) 调用 DBSCAN 也在主线程。

### 修复方案

```dart
// dbscan_algorithm.dart - 包装为 isolate-safe
static Future<DbscanClusterResult> clusterScoredPhotosAsync({
  required List<ScoredThemePhoto> scoredPhotos,
  int minPhotosPerSubcluster = 3,
  double epsilon = 0.15,
}) async {
  // 只传递可序列化的数据
  final payload = _ClusterPayload(
    embeddings: scoredPhotos.map((p) => p.embedding).toList(),
    minPhotosPerSubcluster: minPhotosPerSubcluster,
    epsilon: epsilon,
  );
  return Isolate.run(() => _clusterInIsolate(payload));
}

// theme_subclustering.dart - 使用异步版本
final result = await DbscanAlgorithm.clusterScoredPhotosAsync(...);
```

---

## 6. Sequential for+await 反模式

### 问题描述

`story_service.dart:464-471` 对照片列表逐一执行异步文件操作:

```dart
for (final photo in photos) {
  final asset = await AssetEntity.fromId(photo.assetId);
  final file = await asset?.file;
  // ...
}
```

`create_recommendation_service.dart:65-104` 对每个推荐预设串行执行搜索 (每个预设包含 embedding + DB 查询):

```dart
for (final preset in duePresets) {
  final result = await _searchPreset(preset, ...);
}
```

### 修复方案

```dart
// story_service.dart - 批量并行
final results = await Future.wait(
  photos.map((photo) async {
    final asset = await AssetEntity.fromId(photo.assetId);
    final file = await asset?.file;
    return (photo, file?.path);
  }),
);

// create_recommendation_service.dart - 限制并发数
final semaphore = Semaphore(3); // 最多 3 个并行
await Future.wait(
  duePresets.map((preset) => semaphore.run(() => _searchPreset(preset))),
);
```

---

## 7. getAll 全表扫描

### 问题描述

多处调用 `box.getAll()` 加载**全部记录**到内存:

| 位置 | 数据量风险 |
|------|-----------|
| `photo_service_access.dart:7` | 所有照片 (可能 10k+) |
| `create_recommendation_service.dart:45-48` | 所有照片 + 所有推荐记录 |
| `story_service.dart:409` | 所有故事 |
| `face_cluster_service.dart:338` | 所有人脸 |

### 修复方案

```dart
// 之前
final allPhotos = _photoBox.getAll();

// 之后 - 按需加载
final recentPhotos = _photoBox.query()
    .order(PhotoEntity_.timestamp, flags: Order.descending)
    .build()
    ..limit = 200;
```

---

## 8. 事件流每次触发全量重查

### 问题描述

`event_service.dart:569-578` 的 `watchEvents()`:

```dart
Stream<List<EventEntity>> watchEvents() {
  return eventBox.query().watch(triggerImmediately: true).map((query) {
    final events = query.find()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));  // 全表扫描 + 内存排序
    return events.where((event) => event.photoCount >= minPhotosForTimelineDisplay).toList();
  });
}
```

只要数据库有**任何变更** (包括单张照片 AI 分析的进度更新、照片扫描等), 这个流就触发一次: 全表扫描所有事件 + 全量内存排序 + 过滤。这是高频率操作下的主要卡顿源。

### 修复方案

```dart
// 方案 A: 使用 debounce 合并高频触发 + 增加索引
EventEntity_.startTime 加 @Index() // 让 DB 排序
EventEntity_.photoCount 加 @Index() // 让 DB 过滤

Stream<List<EventEntity>> watchEvents() {
  return eventBox.query()
      .order(EventEntity_.startTime, flags: Order.descending)
      .watch(triggerImmediately: true)
      .debounce(const Duration(milliseconds: 300)) // 合并 300ms 内的变更
      .asyncMap((query) async {
    // 在 Isolate 中排序
    return Isolate.run(() {
      return query.find()
          .where((e) => e.photoCount >= minPhotosForTimelineDisplay)
          .toList();
    });
  });
}
```

---

## 9. HomePage 单次加载 9-11+ 个查询

### 问题描述

`home_page.dart` 的 `initState()` 同时触发:
- `_loadRecentPhotos()` — 1 个全表扫描 (timestamp DESC, limit 100)
- `_generateDiscoverCards()` — 展开为:
  - `_buildTimeRuleCard()` — 最多 7 个时间范围查询 (年度 + 月度 + 5 年"往年今日")
  - `_buildContentRuleCards()` — 1 个 limit 500 的全表扫描
  - `_buildLocationRuleCards()` — 1 个 limit 1000 的全表扫描
- 以上每个又调用 `reconcileAccessiblePhotos()` — 对每个照片做异步文件存在性检查

总共: **9-11+ 次全表扫描 + 数百次文件 IO**。每次用户点击"首页"标签都触发。

### 修复方案

```dart
// 1. 缓存发现卡片结果
class _HomePageState {
  List<Map<String, dynamic>>? _cachedCards;
  DateTime? _lastCardRefresh;

  static const Duration _cardCacheTtl = Duration(minutes: 15);
  
  void initState() {
    _loadRecentPhotos();
    _generateDiscoverCards(); // 异步, 不阻塞 build
  }
  
  Future<void> _generateDiscoverCards() async {
    // 缓存未过期就跳过
    if (_cachedCards != null && 
        DateTime.now().difference(_lastCardRefresh!) < _cardCacheTtl) {
      return;
    }
    // 合并往年今日的 5 个查询为 1 个
    final years = List.generate(5, (i) => now.year - i);
    final oneOfQuery = photoBox.query(
      PhotoEntity_.timestamp.oneOf(
        years.map((y) => _dateRangeForYear(y)).expand((r) => r),
      ),
    ).build();
  }
}
```

---

## 10. 总结与优先级路线图

### 优先级分级

```
P0 = 严重卡顿, 用户直接感知
P1 = 中度卡顿, 高频操作
P2 = 低频但重度, 特定场景卡死
P3 = 渐进式优化
```

### P0 — 立刻修复 (产生卡顿的最主要原因)

| # | 问题 | 文件 | 修复复杂度 |
|---|------|------|-----------|
| 1 | **`PhotoEntity.timestamp` 缺索引** | `photo_entity.dart:14` | 加一行 `@Index()` |
| 2 | **`PhotoEntity.isAiAnalyzed` 缺索引** | `photo_entity.dart:42` | 加一行 `@Index()` |
| 3 | **`EventEntity` 完全无索引** | `event_entity.dart` | 加 4 行 `@Index()` |
| 4 | **`StoryEntity.eventId` 缺索引** | `story_entity.dart` | 加一行 `@Index()` |
| 5 | **缩略图使用全分辨率原图** | 所有图片网格 | 改用 `AssetEntity.thumbnailDataWithSize()` |
| 6 | **`ImageCache` 未配置** | `main.dart` | 加 2 行配置 |

### P1 — 尽快修复 (高频场景)

| # | 问题 | 文件 | 修复方式 |
|---|------|------|---------|
| 7 | 事件页 N+1 查询 | `album_page.dart:1229-1241` | 批量加载 |
| 8 | `watchEvents()` 全量重查 | `event_service.dart:569-578` | debounce + 索引 |
| 9 | HomePage 9-11 个查询 | `home_page.dart:35-41` | 缓存 + 合并查询 |
| 10 | `story_video_page` build 中 `existsSync()` | `story_video_page.dart` | 改为异步 |
| 11 | `path_image.dart` 中 `existsSync()` | `path_image.dart:87` | 异步预检查 |
| 12 | `album_page.dart` 标签流每改动就重查 | `album_page.dart:401-408` | debounce + 增量更新 |

### P2 — 安排修复 (特定场景卡死)

| # | 问题 | 文件 | 修复方式 |
|---|------|------|---------|
| 13 | DBSCAN 在主线程 O(n²) | `dbscan_algorithm.dart` | `Isolate.run()` |
| 14 | 主题子聚类 920 行在主线程 | `theme_subclustering.dart` | 异步化 |
| 15 | 延迟加载调度器重复 4 份 | 多个文件 | 统一单例 |
| 16 | `getAll()` 全表扫描 | 多个文件 | 按需分页 |
| 17 | `for+await` 串行反模式 | `story_service.dart:464` | `Future.wait` + 批次 |

### P3 — 渐进优化

| # | 问题 | 文件 | 修复方式 |
|---|------|------|---------|
| 18 | `cacheExtent` 未配置 | 所有 `SliverGrid` | 加 `cacheExtent: 500` |
| 19 | 搜索页用 `PathImage` 非 `DeferredPathImage` | `album_search_page.dart:945` | 替换 |
| 20 | `jsonDecode` 大 JSON 在主线程 | `digital_album_book_service.dart:21` | `Isolate.run()` |
| 21 | 内存压力未清理 ImageCache | `widget_tree.dart` | `didHaveMemoryPressure` |
| 22 | 无 `precacheImage()` | 全局 | 滚动预测加载 |

### 预期综合收益

| 场景 | 当前表现 | 优化后预期 |
|------|---------|-----------|
| 打开首页 | 9-11 次全表扫描, 300ms+ | 2-3 次索引查询, <50ms |
| 打开相册标签视图 | 全表扫描 1200 张 + 内存聚类 | 索引查询 + 增量更新, <30ms |
| 网格滚动 | 每张图 3-12MB 全分辨率解码 | 缩略图 50-200KB/张, 延迟加载 |
| 事件页面加载 | N+1 次 getMany, 串行 await | 1 次批量加载, 同步构建 |
| DBSCAN 主题聚类 | O(n²) 在主线程, 应用卡死 1-5s | Isolate 后台运行, UI 不卡 |
| 视频预览页 build | 4 次 `existsSync()` 阻塞 | 异步检查, 0 阻塞 |
| 任意 DB 变更 | `watchEvents` 全表扫描 + 排序 | 索引排序 + 300ms debounce |

---

## 11. 2026-05-14 实施记录

本轮已落地的优化与修复:

- 为 `PhotoEntity.timestamp`、`PhotoEntity.isAiAnalyzed`、`EventEntity.startTime`、`EventEntity.endTime`、`EventEntity.photoCount`、`StoryEntity.eventId` 添加 ObjectBox 索引，并同步更新 `objectbox-model.json` / `objectbox.g.dart`，让高频排序、过滤和关联查询走索引。
- 在 `main.dart` 提高 Flutter `ImageCache` 上限，降低照片网格和封面反复解码导致的抖动。
- 将 `EventService.watchEvents()` 改为数据库层按 `photoCount` 过滤、按 `startTime` 倒序排序，避免每次事件流触发后全量 `find()` + Dart 内存排序/过滤。
- 将相册事件分组里的封面照片加载从每个事件一次 `getMany()` 改为先收集全部封面 id 后批量读取，再用内存 map 构建预览模型，去掉事件页 N+1 查询。
- 移除 `PathImage.build()` 中的同步 `existsSync()`，让图片加载失败走 `Image.file(errorBuilder)`，避免 build 阶段同步文件 IO。
- 将 `EventEntity._resolvePhotoPath()` 的文件存在检查改为异步 `File.exists()`。
- 修复刷新范围 UI: 底部弹窗现在包含 `100/300/500/全量安全重建`，且选择值会真实传入刷新流程。之前选择后实际始终走默认刷新。
- 保留“收集 N 张新照片”的增量刷新语义: 从最新照片开始分页扫描，收集到目标数量的新照片后停止。
- 修复增量扫描的 session 缓存问题: 可以复用 album 引用，但每次刷新都会更新 `assetCountAsync`；全量重建会强制刷新 album/count，避免旧 count 导致漏扫。
- 恢复照片权限校验: 权限被拒绝或 limited 授权列表为空时抛出 `PhotoScanException.permissionDenied`，UI 会引导用户去系统设置。
- 恢复媒体资产索引/向量索引的后台刷新: 增量发现新照片或全量重建后，会异步触发 `MediaAssetSyncService.reconcile()` 与 `MediaEmbeddingIndexService.encodePending()`。
- 撤销 Android 跳过 `originFile` 回退的激进优化，避免部分设备/云端资源 `asset.file` 为空时误判为不可读。

关于内容摘要去重:

- 不建议把 SHA-256 全量计算放进扫描主路径，因为它需要读取每张原图完整字节，容易抵消增量扫描带来的 I/O 优势。
- 推荐后续单独实现懒计算方案: 给 `PhotoEntity` 增加可索引的 `contentHash` 字段，扫描仍用 `assetId` 快速入库；在 AI 入队前或后台空闲时才计算 SHA-256，并在命中相同 hash 的已分析照片时复用标签、caption、embedding 等结果，从而跳过重复处理。
