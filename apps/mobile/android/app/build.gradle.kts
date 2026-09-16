import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseTaskRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("release", ignoreCase = true)
}
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()

if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { input ->
        keystoreProperties.load(input)
    }
} else if (releaseTaskRequested) {
    error("Missing android/key.properties for release signing.")
}

fun requiredKeystoreProperty(name: String): String =
    keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: error("Missing key.properties value: $name")

val minappVariant = providers.gradleProperty("minappVariant").orNull
if (minappVariant != null && minappVariant != "girls") {
    error("Unsupported minappVariant: $minappVariant")
}
val isGirlsVariant = minappVariant == "girls"

android {
    namespace = "jp.cloxs.min"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "jp.cloxs.min"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["appIcon"] =
            if (isGirlsVariant) "@drawable/girls_brand_icon" else "@mipmap/ic_launcher"
        manifestPlaceholders["launchTheme"] =
            if (isGirlsVariant) "@style/GirlsLaunchTheme" else "@style/LaunchTheme"
        manifestPlaceholders["appLabel"] = if (isGirlsVariant) "みんアプGirls" else "min"
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = requiredKeystoreProperty("keyAlias")
                keyPassword = requiredKeystoreProperty("keyPassword")
                storeFile = file(requiredKeystoreProperty("storeFile"))
                storePassword = requiredKeystoreProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else if (releaseTaskRequested) {
                error("Missing android/key.properties for release signing.")
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
