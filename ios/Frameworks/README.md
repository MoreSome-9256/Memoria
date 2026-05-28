# iOS Frameworks

This directory contains native frameworks for iOS/macOS.

## llama.xcframework

The llama.cpp bindings for Dart/Flutter, compiled as an XCFramework supporting:
- ios-arm64 (iOS devices)
- ios-arm64-simulator (iOS Simulator on Apple Silicon)
- macos-arm64 (macOS on Apple Silicon)

### ⚠️ Required: Add to Xcode Project

**The xcframework must be manually added in Xcode for the app to build.**

#### Steps:

1. Open the Xcode workspace:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. In Xcode:
   - Select the **Runner** project (top of left sidebar)
   - Select the **Runner** target
   - Click the **General** tab
   - Scroll to **Frameworks, Libraries, and Embedded Content**
   - Click the **+** button
   - Select **Add Other...**
   - Navigate to and select `ios/Frameworks/llama.xcframework`
   - Ensure **Embed** is set to **Embed & Sign**

3. Build and run:
   ```bash
   flutter run
   ```

### Why Embed & Sign?

- **Embed**: The framework is bundled into the app, making it available at runtime
- **Sign**: Required for App Store distribution

### Verification

After adding, you should see `llama.xcframework` listed under:
- Project Settings → General → Frameworks, Libraries, and Embedded Content
- Project Settings → Build Phases → Embed Frameworks

### Usage in Dart

The framework is loaded via process symbols (not file path):

```dart
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

final engine = await LlamaEngine.spawnFromProcess(
  modelParams: ModelParams(path: modelPath, gpuLayers: 99),
  contextParams: const ContextParams(nCtx: 4096),
  multimodalParams: MultimodalParams(mmprojPath: mmprojPath),
);
```

**Note:** `spawnFromProcess()` is used instead of `spawn()` because the xcframework is linked into the app binary by Xcode.
