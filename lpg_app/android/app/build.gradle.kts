
plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") // Google Services plugin for Firebase
    // END: FlutterFire Configuration
    id("kotlin-android") // Kotlin Android plugin
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin") // Flutter Gradle plugin
}

android {
    // Namespace for your Android application
    namespace = "com.example.lpg_app" // IMPORTANT: Replace with your actual namespace if different
    
    // Compile SDK version, usually picked from flutter.compileSdkVersion
    compileSdk = flutter.compileSdkVersion
    
    // NDK version. Ensure this matches your installed NDK or remove if not explicitly needed
    ndkVersion = "27.0.12077973" 

    // REQUIRED for flutter_local_notifications and Java 8 language features (Core Library Desugaring)
    compileOptions {
        // Sets the source compatibility to Java 8

        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = org.gradle.api.JavaVersion.VERSION_1_8 
        // Sets the target compatibility to Java 8
        targetCompatibility = org.gradle.api.JavaVersion.VERSION_1_8
    }

    // Kotlin options for JVM target
    kotlinOptions {
        // Sets the JVM target version for Kotlin compilation to 1.8 (Java 8)
        jvmTarget = "1.8" 
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // It's highly recommended to use a unique ID, e.g., "com.yourcompany.lpgmonitor"
        applicationId = "com.example.lpg_app" // IMPORTANT: Replace with your actual application ID if different
        multiDexEnabled = true
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        
        // Minimum SDK version. flutter_local_notifications requires API level 21 or higher.
        // Ensure this is 21 or above.
        minSdk = 23 // Recommend minSdk 21 or higher for modern Android development and desugaring
        
        // Target SDK version, usually picked from flutter.targetSdkVersion
        targetSdk = 33
        
        // Version codes and names from Flutter
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Build type configurations
    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Android core library desugaring dependency
    // This is crucial for enabling Java 8 features used by flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") // Ensure version is up-to-date if needed
}
