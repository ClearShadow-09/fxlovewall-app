import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 从 android/key.properties 读签名信息（由 build_apk.ps1 生成）。
// 用与旧 Kotlin 版同一个 debug keystore —— 签名一致才能直接覆盖升级，
// 否则 Android 会因签名不符而拒绝安装。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // 与旧 Kotlin 版同名，保证覆盖升级而不是并存
    namespace = "com.fxlovewall.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.fxlovewall.app"
        // zikzak_inappwebview 要求 API 24+；旧版也正好是 24，保持一致
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ================================================================ 体积
    // 需求 6：APK 从 52.4MB 压到约 35MB。
    //
    // 实测构成：47.9MB / 52.4MB 全是三个 ABI 各一份的原生库
    // （libflutter.so 每个就 11-12MB + libapp.so 5MB + libdartjni.so）。
    // 所以唯一有效的手段就是**少打一个 ABI**。
    //
    // 按用户选择保留 arm64-v8a + armeabi-v7a，去掉 x86_64 ——
    // 后者只在模拟器和极少数 x86 平板上用到，真机清一色是 ARM。
    // （代价：本机模拟器装不了这个包，验证得用 arm 镜像或真机。）
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a")
            // true = 除了按 ABI 拆分的包，再额外产出一个含全部 ABI 的通用包。
            // 我们要的正是那个通用包（单文件分发 + 直接下载安装），所以设 true。
            isUniversalApk = true
        }
    }
    // 只对 .so 生效的传统打包方式：把原生库**压缩**进 APK。
    // 默认（useLegacyPackaging=false）是「不压缩、安装时按页对齐解压」，
    // 装完占空间更小、启动更快，但 APK 文件本身会大 10MB 以上。
    // 对一个要下载安装的 APK 来说，换来更小的下载体积更划算。
    packaging {
        jniLibs {
            useLegacyPackaging = true

            // ⚠️ 关键：把「不带引擎的残缺 ABI」从精简包里剔除。
            //
            // 踩过的坑：用 --target-platform android-arm,android-arm64 构建精简包时，
            // Flutter 只产出 arm64-v8a / armeabi-v7a 的 libflutter.so 和 libapp.so，
            // 但 zikzak_inappwebview 及其传递依赖里带着 x86_64 的
            // libdartjni.so / libdatastore_shared_counter.so，Gradle 照样打进去。
            //
            // 后果：x86_64 设备（MuMu 等模拟器）按 ABI 优先级选中 x86_64 目录，
            // 那两个 .so 加载成功，却找不到 libflutter.so → 启动即 SIGSEGV。
            // 实测 MuMu 上正是这个崩法。
            //
            // 这里保证「包内 ABI 集合 ⊆ 已编译引擎的 ABI 集合」。
            // 通用包用 -PfxUniversal=true 构建（三个 ABI 引擎齐全），不做任何排除。
            val universal = project.hasProperty("fxUniversal")
            if (!universal) {
                excludes += "lib/x86/**"
                excludes += "lib/x86_64/**"
                excludes += "lib/riscv64/**"
            }
        }
    }

    signingConfigs {
        create("fxwall") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // ⚠️ 必须显式关掉压缩。
            // AGP 9 在 release 下默认启用 R8，会把 io.flutter.embedding.android.*
            // 这类类重命名（实测 FlutterActivity 被改成了 `mk`）。Flutter 引擎里有
            // 按类名/枚举名反射的代码，混淆后会直接崩溃或启动异常。
            // Flutter 官方模板本来也不开压缩，这里显式写死以免被 AGP 默认值带走。
            isMinifyEnabled = false
            isShrinkResources = false

            // 万一以后要开压缩，这行保证 keep 规则生效
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("fxwall")
            } else {
                // 没配 keystore 时退回 debug，至少能构建出来
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
