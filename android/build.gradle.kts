allprojects {
    repositories {
        // 🌟 新增这一行：专门用来下载 Flutter 引擎 (flutter_embedding) 的国内镜像！
        maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }
        // 🌟 1. 加上阿里云的公共和 Google 镜像源（Kotlin 语法）
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        
        // 🌟 2. 为了以防万一，把 FFmpeg 以前常驻的老巢 JCenter 镜像也加上
        maven { url = uri("https://maven.aliyun.com/repository/jcenter") }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

//  补丁挪到了这里！在 evaluationDependsOn 之前执行
subprojects {
    afterEvaluate {
        if (project.hasProperty("android")) {
            project.extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                if (namespace == null) {
                    namespace = project.group.toString()
                }
                // ➕ 新增下面这一行：强行把所有老插件的编译版本拉高到 34！
                compileSdkVersion(34)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
