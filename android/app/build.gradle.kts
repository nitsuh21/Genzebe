import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (gitignored) holds the upload-key
// credentials. See android/key.properties.example and
// docs/play-store-submission.md for how to create it.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
    listOf("storePassword", "keyPassword", "keyAlias", "storeFile").forEach { key ->
        require(!keystoreProperties.getProperty(key).isNullOrBlank()) {
            "android/key.properties is missing '$key'"
        }
    }
} else {
    logger.warn(
        "WARNING: android/key.properties not found — release builds will be signed " +
            "with the DEBUG key. Such builds cannot be uploaded to Google Play. " +
            "Copy android/key.properties.example to android/key.properties and fill it in."
    )
}

android {
    namespace = "com.nitsuh.genzeb"
    // Flutter 3.44 defaults compileSdk/targetSdk to 36, which satisfies the
    // Play target-API requirement (>= 35). Floors guard against an older SDK.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nitsuh.genzeb"
        minSdk = flutter.minSdkVersion
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        // Driven by `version:` in pubspec.yaml (name+code).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    // Local-only fallback so `flutter run --release` works
                    // without the upload key. Never upload such a build.
                    signingConfigs.getByName("debug")
                }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
