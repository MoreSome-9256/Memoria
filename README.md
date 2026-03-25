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

### 3. 使用 Profile 运行（推荐）

不再建议每次手写一长串 `--dart-define`。项目已改为 Profile 文件驱动：

1) 先创建本地 profile（不要提交密钥）

```bash
mkdir -p config/profiles
cp config/profiles/dev.example.json config/profiles/dev.json
```

2) 编辑 `config/profiles/dev.json`，填入你自己的参数（LLM / AMap / Cognito）

3) 直接按 profile 启动

```bash
# macOS / Linux
./launch.sh dev

# Windows PowerShell
./launch.ps1 dev
```

也支持直接使用 Flutter 原生命令：

```bash
flutter run --dart-define-from-file=config/profiles/dev.json
```

当前支持 profile 切换：

- `dev` -> `config/profiles/dev.json`
- `prod` -> `config/profiles/prod.json`

你可以继续新增 `staging.json` 等环境，脚本会按同名 profile 自动读取。

如果要切换 MobileCLIP2 模型来源，也可以追加这些可选参数：

```bash
# 视觉模型：优先从本地文件读取（可选）
--dart-define=MOBILECLIP2_ONNX_FILE=/absolute/path/to/vision_model.onnx

# 视觉模型：改成其它已注册 asset（可选）
--dart-define=MOBILECLIP2_ONNX_ASSET=assets/mobileclip2/s2/vision_model.onnx

# 文本模型：从本地文件读取（可选）
--dart-define=MOBILECLIP2_TEXT_ONNX_FILE=/absolute/path/to/text_model.onnx

# 输入尺寸覆盖（可选）
--dart-define=MOBILECLIP_ONNX_INPUT_SIZE=256
```

## 运行配置（可选）

运行参数统一放在 profile 文件中，由 `--dart-define-from-file` 一次性注入。

## 本地 Qwen3.5-0.8B（APK 内置）

当前项目本地多模态推理已切到 Qwen3.5-0.8B + llamadart，配置为单文件 GGUF（不需要单独 mmproj 配置）。

### 1) 下载量化模型（推荐来源）

- 基座官方：`Qwen/Qwen3.5-0.8B`
- 量化发布者：`bartowski`
- 推荐仓库：`bartowski/Qwen_Qwen3.5-0.8B-GGUF`

推荐默认量化：`Q4_K_M`

```bash
huggingface-cli download bartowski/Qwen_Qwen3.5-0.8B-GGUF Qwen_Qwen3.5-0.8B-Q4_K_M.gguf --local-dir assets/local_vlm --local-dir-use-symlinks False
```

### 2) 放置路径

将模型文件放到：

- `assets/local_vlm/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf`

### 3) 打包 APK（随包内置）

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

### 4) 运行时覆盖（可选）

- 覆盖资产文件名：`LOCAL_QWEN35_08B_GGUF_ASSET=assets/local_vlm/<file>.gguf`
- 使用绝对路径文件：`LOCAL_QWEN35_08B_GGUF_PATH=/absolute/path/to/model.gguf`

### 5) 量化选择建议

- `Q4_K_M`：默认首选，手机端最稳。
- `Q3_K_M`：内存更省，质量会下降，适合低端机兜底。
- `Q5_K_M`：质量更好，内存与耗时更高，适合中高端机。

## App 内使用说明

- 首次进入后点击右上角刷新按钮，可选择“先跑最近 100 / 300 / 500 张”或“全部运行”。
- 刷新完成后，聚类会先完成，AI 打标转入后台执行，不会继续阻塞主界面。
- 顶部会显示后台 AI 进度条，可暂停、继续或结束本轮。
- 事件详情页支持长按照片查看 AI 关键词和 OCR 关键词。
- 需要彻底重建本地照片缓存时，走应用内“安全重建”流程，不建议手动清库后立刻重扫。

## MobileCLIP 资源生成

仓库中部分模型和向量产物体积较大，默认按“可重新生成”思路维护。对 Memoria 来说，`checkpoints/mobileclip_s2.pt` 应视为更可信的源模型；`ONNX` 和未来的 `ncnn` 都是从这个 checkpoint 派生出来的运行时产物。

首次准备端侧视觉模型时，先把基模放到：

- `checkpoints/mobileclip_s2.pt`

然后准备本地 Python 环境以及 `torch`、`mobileclip`、`jieba`、`requests`、`onnx`、`onnxsim`、`onnx2tf` 等依赖，再按顺序执行：

```bash
# 1. 构建或扩展中文视觉标签词库
python ai_tools/build_vocab.py
python ai_tools/expand_brain.py

# 2. 导出 MobileCLIP TFLite 模型
python ai_tools/export_model.py --output-folder saved_model
```

当前仓库不再推荐本地重新导出 MobileCLIP 的 NCNN 模型。直接使用作者提供的现成导出包即可：

- https://drive.google.com/file/d/1WFQEwWxUCFhDASbXv7fAlXUHn1BnVGGI/view

下载后把其中的 `mobileclip_s2_export` 目录放到：

- `third_party/mobileclip_s2_export/`

目录里应包含这 6 个文件：

- `image_encoder.ncnn.param`
- `image_encoder.ncnn.bin`
- `text_encoder.ncnn.param`
- `text_encoder.ncnn.bin`
- `projection_layer.ncnn.param`
- `projection_layer.ncnn.bin`

Flutter 运行时使用的是同步后的 assets 副本：

- `assets/ncnn/mobileclip_s2/image_encoder.ncnn.param`
- `assets/ncnn/mobileclip_s2/image_encoder.ncnn.bin`
- `assets/ncnn/mobileclip_s2/text_encoder.ncnn.param`
- `assets/ncnn/mobileclip_s2/text_encoder.ncnn.bin`
- `assets/ncnn/mobileclip_s2/projection_layer.ncnn.param`
- `assets/ncnn/mobileclip_s2/projection_layer.ncnn.bin`

原生推理代码参考作者仓库里的 `ncnn_mobileclip_infer`；Memoria 当前直接消费作者导出的这套模型文件，不再把本地 `pnnx` 导出链当作默认获取方式。

### 团队协作约定

当前项目采用“代码走 Git，大文件走群文件”的协作方式。

- 超过几十 MB 的模型、SDK、zip 包不要提交到 Git。
- 队友 clone 仓库后，需要再从群文件同步这几个大文件包。
- 群文件里当前至少应包含：
  - `mobileclip_s2_export.zip`
  - `ncnn-20260113-android-vulkan.zip`
  - 如需重新走导出链再额外提供 `pnnx-*.zip`

队友拿到群文件后，按下面方式放置：

- 解压 `mobileclip_s2_export.zip` 到 `third_party/mobileclip_s2_export/`
- 将其中 6 个 `.param/.bin` 文件同步到 `assets/ncnn/mobileclip_s2/`
- 解压 `ncnn-20260113-android-vulkan.zip` 到 `third_party/ncnn-20260113-android-vulkan/`

这样做的结果是：

- Git 仓库保持干净，不会因为几百 MB 大文件膨胀
- 队友补齐群文件后，Android 侧仍然可以正常编译

如果缺少上面任意一组大文件，仓库本身可以拉下来，但无法完整构建 NCNN Android 版本。

### 当前 NCNN 运行方式

当前 Memoria 里的 NCNN 路径已经接入 Android 原生推理，但实际运行仍然是 CPU 路径，不是 Vulkan 计算路径。

- 现在链接的是 Vulkan 版 NCNN SDK
- 但代码里没有显式开启 `use_vulkan_compute`
- 也没有调用 `set_vulkan_device(...)`

所以当前状态应理解为：

- `NCNN SDK`: Vulkan-capable
- `Memoria 当前实际推理`: CPU

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

`pubspec.yaml` 已注册上述 6 个 assets，Dart 侧启动时会先把它们落盘到 Android 沙盒，再通过 FFI 传绝对路径给 native bridge。

Android 侧建议直接放官方预编译 NCNN Android 包到：

- `third_party/ncnn-android-vulkan/`
- `third_party/ncnn-20260113-android-vulkan/`

当前 `android/app/src/main/cpp/CMakeLists.txt` 会自动在这两种目录名里搜索头文件和 `ncnn` 库；找到后就会把 bridge 切换到“已链接 ncnn runtime”的构建模式。

### Linux 最小部署示例

如果你要在 Linux 或 Ubuntu 上先做离线验证，推荐直接下载官方预编译 ncnn 包，不要手工链接一堆依赖。最小工程可以像这样写：

```cmake
cmake_minimum_required(VERSION 3.16)
project(memoria_ncnn_smoke_test)

set(ncnn_DIR "/absolute/path/to/ncnn/lib/cmake/ncnn")
find_package(ncnn REQUIRED)

add_executable(ncnn_smoke_test test.cpp)
target_link_libraries(ncnn_smoke_test PRIVATE ncnn)
target_compile_features(ncnn_smoke_test PRIVATE cxx_std_17)
```

```cpp
#include <ncnn/net.h>

int main() {
  ncnn::Net net;
  if (net.load_param("image_encoder.ncnn.param") != 0) {
    return 1;
  }
  if (net.load_model("image_encoder.ncnn.bin") != 0) {
    return 2;
  }
  return 0;
}
```

然后用标准 CMake 流程构建：

```bash
cmake -S . -B build
cmake --build build -j
```

这和当前 Android 侧 [android/app/src/main/cpp/CMakeLists.txt](android/app/src/main/cpp/CMakeLists.txt) 的思路一致：都应该让 CMake 帮你接管 ncnn 依赖，不要手动硬拼 OpenMP、glslang 一类库。

### 和当前 Bridge 的对应关系

当前 native bridge 已经准备好消费 pnnx 产物，但还有一个必须执行的人工确认步骤：

- 导出后先打开 `image_encoder.ncnn.param`
- 确认真实输入 blob 名
- 确认真正输出 blob 名
- 再决定是否继续使用 `android/app/src/main/cpp/memoria_ncnn_bridge.cpp` 里当前默认的 `in0` / `out0`

当前这次实际导出已经确认：

- 输入 blob 名是 `in0`
- 输出 blob 名是 `out0`

如果 blob 名不一致，优先改 bridge 常量，而不是在 Dart 侧做兼容层。

其中 Flutter 当前线上运行时默认使用 `mobileclip_vision_ir9.onnx`；NCNN 接入完成后，Benchmark 和 native bridge 应优先消费上面的 `.param/.bin` 产物。

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


