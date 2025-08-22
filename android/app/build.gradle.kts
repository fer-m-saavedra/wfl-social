plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")      // ← usa el id moderno
    // El plugin de Flutter va después de Android y Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wflw.comunidades"      // ← igual al package del Manifest
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.wflw.comunidades"   // ← igual al namespace/manifest
        minSdk = maxOf(21, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 🔑 Java 17 + desugaring
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // habilita desugaring para jdk8+ features usadas por flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // firma de ejemplo; ajustá si tenés keystore de release
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 🔑 libs de desugaring (versión estable)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
