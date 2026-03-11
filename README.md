# Smart Story Album

智能故事相册（Flutter + Isar + ML Kit + MobileCLIP + LLM）。

## 项目简介

- 扫描系统相册照片，按时间与空间聚类为事件。
- 使用 ML Kit + MobileCLIP 做本地视觉标签、人脸分析与文本场景识别。
- 可选接入兼容 OpenAI 的多模态模型，为每张照片生成一句中文 caption；未配置视觉接口时回退为本地规则 caption。
- 对截图、文档、课件等文本型图片执行 OCR，并把 OCR 结果接入标题、故事和检索。
- 使用高德逆地理解析更细粒度地点，优先展示 POI、园区、校区、楼栋等位置名称。
- 支持后台 AI 打标、暂停、继续、结束本轮，以及按最近 100 / 300 / 500 / 全量刷新。
- 使用 Isar 做本地数据存储与回查。

## 最近更新

- 新增 OCR 流程：自动识别文字密集图片，过滤应用 UI / 时间日期 / 截图噪声，并把 OCR 摘要展示到事件详情。
- 优化事件标题与故事生成：对文本型照片使用 OCR / 文本标签，降低“截图内容污染标题”和角色关系幻觉。
- 优化位置展示：事件和照片优先展示 `locationName -> district -> city -> province`。
- 新增安全重建缓存：清空缓存前先做权限、相册和候选照片预检查，并在重建前停止后台 AI 分析，避免并发写库与误清空。
- 刷新入口支持仅处理最近一部分照片，减少首次全量重扫等待时间。

## 模块结构

- `lib/main.dart`：应用入口。
- `lib/view/`：页面与 UI 组件。
- `lib/service/`：照片扫描、聚类、地址解析、AI 分析、OCR、故事生成。
- `lib/models/`：Isar 实体与 UI 模型。
- `lib/utils/`：聚类、Prompt、过滤等纯工具逻辑。
- `ai_tools/`：标签词库构建、模型导出、标签校验与 TFLite 对比脚本。
- `assets/`：运行时资源，包括标签向量、模型文件和静态图片。

## 环境要求

- Flutter SDK：`3.x`（需包含 Dart，建议与项目当前 `pubspec.yaml` 的 SDK 约束兼容）。
- Dart SDK：`>=3.10.3`（由 Flutter 自带）。
- 运行平台：macOS / iOS / Android（需有可用模拟器或真机）。
- 本地权限：首次运行需要授予“相册访问权限”。
- 可选外部服务：
  - 高德逆地理：需要 `AMAP_WEB_KEY`（用于地址解析）。
  - LLM 服务：需要 `LLM_BASE_URL`、`LLM_API_PATH`、`LLM_MODEL`、`LLM_API_KEY`（用于标题/故事生成）。
  - 可选视觉模型：可额外提供 `LLM_VISION_MODEL`，用于单张照片 caption；未提供时默认沿用 `LLM_MODEL`。

## 如何启动

### 1. 安装依赖

```bash
flutter pub get
```

### 2. 生成 Isar 代码（首次或模型变更后）

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3. 运行应用

```bash
flutter run
```

如果需要完整能力，请同时提供高德和 LLM 配置：

```bash
flutter run \
  --dart-define=AMAP_WEB_KEY=YOUR_AMAP_WEB_KEY \
  --dart-define=LLM_BASE_URL=http://your-gateway/v1 \
  --dart-define=LLM_API_PATH=/chat/completions \
  --dart-define=LLM_MODEL=deepseek-chat \
  --dart-define=LLM_API_KEY=YOUR_API_KEY
```

## 运行配置（可选）

### 高德逆地理

```bash
flutter run --dart-define=AMAP_WEB_KEY=YOUR_AMAP_WEB_KEY
```

### LLM 配置

```bash
flutter run \
  --dart-define=LLM_BASE_URL=http://your-gateway/v1 \
  --dart-define=LLM_API_PATH=/chat/completions \
  --dart-define=LLM_MODEL=deepseek-chat \
  --dart-define=LLM_API_KEY=YOUR_API_KEY
```

## App 内使用说明

- 首次进入后点击右上角刷新按钮，可选择“先跑最近 100 / 300 / 500 张”或“全部运行”。
- 刷新完成后，聚类会先完成，AI 打标转入后台执行，不会继续阻塞主界面。
- 顶部会显示后台 AI 进度条，可暂停、继续或结束本轮。
- 事件详情页支持长按照片查看 AI 关键词和 OCR 关键词。
- 需要彻底重建本地照片缓存时，走应用内“安全重建”流程，不建议手动清库后立刻重扫。

## MobileCLIP 资源生成

仓库中部分模型和向量产物体积较大，默认按“可重新生成”思路维护。首次准备端侧视觉模型时，先把基模放到：

- `checkpoints/mobileclip_s2.pt`

然后准备本地 Python 环境以及 `torch`、`mobileclip`、`jieba`、`requests`、`onnx`、`onnxsim`、`onnx2tf` 等依赖，再按顺序执行：

```bash
# 1. 构建或扩展中文视觉标签词库
python ai_tools/build_vocab.py
python ai_tools/expand_brain.py

# 2. 导出 MobileCLIP TFLite 模型
python ai_tools/export_model.py --output-folder saved_model
```

可选校验脚本：

```bash
# 检查标签质量
python ai_tools/verify_tags.py path/to/image1.jpg path/to/image2.jpg

# 对比某张图在指定 TFLite 模型上的标签结果
python ai_tools/compare_tflite_tags.py path/to/image.jpg --tflite saved_model/mobileclip_vision_float16.tflite --top-k 10
```

`ai_tools/export_model.py` 支持切换端侧友好激活函数：

```bash
python ai_tools/export_model.py --output-folder saved_model_quickgelu --activation quickgelu
python ai_tools/export_model.py --output-folder saved_model_silu --activation silu
```

仓库默认不强制提交以下可再生产物：

- `assets/expanded_tags_vectors.json`
- `ai_tools/expanded_tags_vectors.json`
- `mobileclip_vision.onnx`
- 其他实验性导出目录，如 `saved_model_quickgelu/`、`saved_model_silu/`

如果要重新构建扩展标签词库，相关脚本依赖 `DEEPSEEK_API_KEY` 环境变量：

```powershell
$env:DEEPSEEK_API_KEY = "YOUR_KEY"
```

导出脚本会在项目根目录或指定输出目录生成以下文件：

- `mobileclip_vision.onnx`
- `saved_model/mobileclip_vision_float16.tflite`
- `saved_model/mobileclip_vision_float32.tflite`

其中 Flutter 运行时默认使用 `assets/mobileclip_vision_float16.tflite`。

如果缺少 `checkpoints/mobileclip_s2.pt` 或运行时所需的 `assets/mobileclip_vision_float16.tflite` / `assets/expanded_tags_vectors.json`，`flutter run` 会因为缺失资源而失败。

## 常用命令

```bash
# 代码格式化
dart format .

# 静态检查
flutter analyze

# 全量测试
flutter test

# 指定测试文件
flutter test test/utils/event_cluster_helper_test.dart
```


