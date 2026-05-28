# Native Libraries Setup

This document describes how to set up native libraries for llama.cpp on Android and iOS.

## Android

The AAR file `llama-cpp-dart.aar` contains `libllama.so` for ARM64 devices.

### Already Configured

The dependency is already added in `android/app/build.gradle.kts`:

```kotlin
implementation(files("libs/llama-cpp-dart.aar"))
```

The library is loaded with a relative path:

```dart
LlamaEngine.spawn(
  libraryPath: 'libllama.so',  // Relative path, loaded from APK
  ...
)
```

## iOS / macOS

The xcframework is located at `ios/Frameworks/llama.xcframework`.

### ⚠️ Manual Xcode Configuration Required

**You must manually add the xcframework in Xcode:**

1. Open the iOS workspace:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. In Xcode:
   - Select the **Runner** project
   - Select the **Runner** target
   - Open the **General** tab
   - Find **Frameworks, Libraries, and Embedded Content**
   - Click **+**
   - Select **Add Other...**
   - Choose `ios/Frameworks/llama.xcframework`
   - Set **Embed** to **Embed & Sign**

### Why spawnFromProcess?

iOS/macOS uses `LlamaEngine.spawnFromProcess()` instead of `LlamaEngine.spawn()`:

```dart
// iOS/macOS: xcframework is linked into the app binary
LlamaEngine.spawnFromProcess(
  modelParams: ModelParams(path: modelPath, gpuLayers: 99),
  contextParams: const ContextParams(nCtx: 4096),
  ...
)

// Android: loads libllama.so from APK
LlamaEngine.spawn(
  libraryPath: 'libllama.so',
  ...
)
```

**Reason:** The xcframework is embedded into the app process by Xcode, so it's loaded from process symbols rather than from a file path.

## Related Files

- Android AAR: `android/app/libs/llama-cpp-dart.aar`
- iOS xcframework: `ios/Frameworks/llama.xcframework`
- Service code: `lib/service/local_vlm_description_service.dart`
