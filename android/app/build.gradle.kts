plugins {
    id("com.android.application")
    // Jetpack Compose compiler, for the Glance home-screen widgets.
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.obsidianscout.obsidianscout_app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.obsidianscout.obsidianscout_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystoreFile = file("release.keystore")
            if (keystoreFile.exists()) {
                storeFile = keystoreFile
                storePassword = "obsidianscout"
                keyAlias = "obsidianscout"
                keyPassword = "obsidianscout"
            } else {
                val debugKeystore = signingConfigs.getByName("debug")
                storeFile = debugKeystore.storeFile
                storePassword = debugKeystore.storePassword
                keyAlias = debugKeystore.keyAlias
                keyPassword = debugKeystore.keyPassword
            }
        }
    }

    buildFeatures {
        compose = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // App bundles go to Google Play, which forbids self-updating, so they drop the install-packages permission.
    // APKs (GitHub releases) keep it for in-app updates.
    val buildingBundle = gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }
    if (buildingBundle) {
        sourceSets.getByName("release").manifest.srcFile("src/playBundle/AndroidManifest.xml")
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

dependencies {
    // Home-screen widgets (Glance) and their background refresh (WorkManager).
    implementation("androidx.glance:glance-appwidget:1.2.0")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
}
