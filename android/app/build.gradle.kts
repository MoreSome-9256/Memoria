plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import org.gradle.api.tasks.Sync

android {
    namespace = "com.example.photo_album"
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    androidResources {
        noCompress += listOf("tflite", "pt", "bin", "onnx", "mp3", "gguf", "so")
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.photo_album"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        // minSdk = flutter.minSdkVersion  // Required for photo_manager
        // targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode.toInt()
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17")
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

val localLlmAssetDir = layout.buildDirectory.dir("generated/localLlmAssets")

val prepareLocalLlmAssets = tasks.register<Sync>("prepareLocalLlmAssets") {
    into(localLlmAssetDir)

    from("../../third_party/llama.cpp/install-android-baseline/bin") {
        include("llama-server", "llama-mtmd-cli")
        into("local_llm/install-android-baseline/bin")
    }

    from("../../third_party/llama.cpp/install-android-baseline/lib") {
        include("libggml-base.so", "libggml-cpu.so", "libggml.so", "libllama.so", "libmtmd.so")
        into("local_llm/install-android-baseline/lib")
    }

    from("../../checkpoints/qwen") {
        include("Qwen3.5-0.8B-Q4_K_M.gguf", "mmproj-F16.gguf")
        into("local_llm/checkpoints/qwen")
    }
}

android.sourceSets.getByName("main").assets.srcDir(localLlmAssetDir)

tasks.matching { task ->
    task.name == "mergeDebugAssets" || task.name == "mergeReleaseAssets"
}.configureEach {
    dependsOn(prepareLocalLlmAssets)
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.mlkit:text-recognition-chinese:16.0.0")
}
