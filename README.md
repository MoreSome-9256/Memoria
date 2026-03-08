# Smart Story Album

智能故事相册（Flutter + Isar + ML Kit + LLM）。

## 项目简介

- 扫描系统相册照片，按时间与空间聚类为事件。
- 使用 ML Kit 做本地标签与人脸分析。
- 对可展示事件生成标题与故事（仅上传结构化文本，不上传图片二进制）。
- 使用 Isar 做本地数据存储与回查。

## 模块结构

- `lib/main.dart`：应用入口。
- `lib/view/`：页面与 UI 组件。
- `lib/service/`：照片扫描、聚类、地址解析、AI 分析、故事生成。
- `lib/models/`：Isar 实体与 UI 模型。
- `lib/utils/`：聚类、Prompt、过滤等纯工具逻辑。
- `lib/data/`：本地 mock 数据。
- `imgs/`：样例图片与脚本。
- `doc/`：任务拆解与验收文档。

## 环境要求

- Flutter SDK：`3.x`（需包含 Dart，建议与项目当前 `pubspec.yaml` 的 SDK 约束兼容）。
- Dart SDK：`>=3.10.3`（由 Flutter 自带）。
- 运行平台：macOS / iOS / Android（需有可用模拟器或真机）。
- 本地权限：首次运行需要授予“相册访问权限”。
- 可选外部服务：
  - 高德逆地理：需要 `AMAP_WEB_KEY`（用于地址解析）。
  - LLM 服务：需要 `LLM_BASE_URL`、`LLM_API_PATH`、`LLM_MODEL`、`LLM_API_KEY`（用于标题/故事生成）。

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
  --dart-define=LLM_MODEL=deepseek-ai/DeepSeek-V3.2 \
  --dart-define=LLM_API_KEY=YOUR_API_KEY
```

## MobileCLIP 资源生成

仓库默认不提交以下可再生产物：

- `assets/expanded_tags_taxonomy.json`
- `assets/expanded_tags_vectors.json`
- `ai_tools/expanded_tags_vectors.json`
- `ai_tools/expanded_tags_taxonomy.json`
- `mobileclip_vision.onnx`
- `mobileclip_vision_ir9.onnx`

原因：这些文件体积大，且都可以通过脚本重新生成；其中 `assets/expanded_tags_vectors.json` 已经不再被运行时使用，Flutter 运行时实际只依赖 `assets/expanded_tags_taxonomy.json` 和 `mobileclip_vision_ir9.onnx`。

在首次运行应用前，请先自行下载 MobileCLIP-S2 基模，并放到以下固定路径：

- `checkpoints/mobileclip_s2.pt`

在首次运行应用前，请先准备本地 Python 环境以及 `torch`、`mobileclip`、`jieba`、`requests`、`onnx` 等脚本依赖，然后按顺序执行：

```bash
# 1. 从常用词表中过滤并向量化中文视觉标签
python ai_tools/expand_brain.py

# 2. 基于向量词库构建带类别信息的 taxonomy
python ai_tools/build_taxonomy.py

# 3. 导出 MobileCLIP ONNX 模型
python ai_tools/export_mobileclip_onnx.py
```

`expand_brain.py` 和 `build_taxonomy.py` 依赖 `DEEPSEEK_API_KEY` 环境变量：

```powershell
$env:DEEPSEEK_API_KEY = "YOUR_KEY"
```

生成完成后，将 taxonomy 复制到 Flutter 资源目录：

```powershell
Copy-Item ai_tools/expanded_tags_taxonomy.json assets/expanded_tags_taxonomy.json
```

导出脚本会在项目根目录生成以下 ONNX 文件：

- `mobileclip_vision.onnx`
- `mobileclip_vision_ir9.onnx`

其中 `mobileclip_vision_ir9.onnx` 是 Flutter 运行时实际加载的模型；`mobileclip_vision.onnx` 主要用于导出中间产物和桌面侧校验。

如果缺少 `checkpoints/mobileclip_s2.pt`、`assets/expanded_tags_taxonomy.json` 或 `mobileclip_vision_ir9.onnx`，`flutter run` 会因为缺失资源而失败。

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


