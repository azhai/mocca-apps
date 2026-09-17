import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式发布签名：从 android/key.properties 读取（该文件与 *.jks 均已被
// android/.gitignore 忽略，不会进版本库）。文件缺失时回退到 debug 签名，
// 这样新克隆的仓库无需提供密钥也能构建（仅用于本地调试，不可用于发布）。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

// 是否启用了 ABI 拆分构建。Flutter 传的是 -Psplit-per-abi=true
// （见 flutter_tools/lib/src/android/gradle.dart）。启用拆分时不能设置 abiFilters，
// 否则 Gradle 报 "Conflicting configuration: 'xxx' in ndk abiFilters cannot be
// present when splits abi filters are set"。
val abiSplitEnabled = providers.gradleProperty("split-per-abi").orNull == "true"

android {
    namespace = "com.mocca.vod"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mocca.vod"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // 只打包 arm64-v8a。近几年的手机（2017 年起）均为 64 位 ARM，
            // 32 位 armv7 与 x86_64 已无实际需要：单包从 ~56MB 降到 ~21MB。
            //
            // 必须写在这里（buildTypes.release）而不是 defaultConfig：
            // Flutter 插件会对「每个 buildType」执行 ndk.abiFilters.clear() 后填入
            // 默认三平台，而 buildType 层与 defaultConfig 层在 AGP 中是合并关系，
            // 写在 defaultConfig 的过滤会被永远盖过去（这正是之前限制失效的原因）。
            if (!abiSplitEnabled) {
                ndk {
                    abiFilters.clear()
                    abiFilters.add("arm64-v8a")
                }
            }
        }
    }
}

flutter {
    source = "../.."
}
