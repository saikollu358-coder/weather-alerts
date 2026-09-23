import java.io.FileInputStream
import java.util.Properties

// Firebase Android config enters via the platform config file
// `android/app/google-services.json` (see FIREBASE_SETUP in AGENTS.md / README).
// The google-services Gradle plugin is applied only when that file is present,
// so the project keeps building in local-only mode without any Firebase config.
val hasGoogleServices = file("google-services.json").exists()

// Google Maps API key (NEVER committed). Provided at build time via the
// `WEATHER_ALERTS_GOOGLE_MAPS_API_KEY` environment variable or the Gradle
// property of the same name (e.g. in android/gradle.properties). An empty key
// keeps the app buildable and the map shows a setup hint at runtime.
val googleMapsApiKey: String = System.getenv("WEATHER_ALERTS_GOOGLE_MAPS_API_KEY")
    ?: (findProperty("WEATHER_ALERTS_GOOGLE_MAPS_API_KEY") as? String ?: "")

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The google-services plugin cannot be applied conditionally inside the
// plugins {} block (Kotlin DSL). It is declared `apply false` in
// settings.gradle.kts and applied here only when the config file exists.
if (hasGoogleServices) {
    apply(plugin = "com.google.gms.google-services")
}

// Release signing keys (NEVER committed). Create android/key.properties from
// key.properties.example before publishing to a store. When missing, release
// builds fall back to debug signing so CI stays functional.
val keystoreProperties = Properties().apply {
    val propsFile = rootProject.file("key.properties")
    if (propsFile.exists()) load(FileInputStream(propsFile))
}
val hasReleaseKeys = keystoreProperties.containsKey("storeFile")

android {
    namespace = "com.weatheralerts.weather_alerts"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires core library desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.weatheralerts.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["googleMapsApiKey"] = googleMapsApiKey
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeys) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeys) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // No android/key.properties: fall back to debug signing so the
                // release build works, but the APK is NOT store-publishable.
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // flutter_local_notifications requires core library desugaring.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
