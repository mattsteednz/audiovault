import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
    println("BUILD LOG: key.properties loaded successfully.")
} else {
    println("BUILD LOG: key.properties NOT FOUND at ${keyPropertiesFile.absolutePath}")
}

android {
    namespace = "com.mattsteed.audiovault"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    lint {
        // This stops Lint from killing the build for minor plugin warnings
        checkReleaseBuilds = false
        abortOnError = false
    }

    defaultConfig {
        applicationId = "com.mattsteed.audiovault"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // We create the release config regardless, but only populate it if we have the data
        create("release") {
            val ksPath = "C:/Users/Matt/.android/keys/audiovault-release.jks"
            val ksFile = file(ksPath)
            
            if (ksFile.exists() && keyProperties.containsKey("storePassword")) {
                storeFile = ksFile
                storePassword = keyProperties["storePassword"] as String
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                println("BUILD LOG: Signing configuration applied for Release.")
            } else {
                println("BUILD LOG: Signing configuration SKIPPED. File exists: ${ksFile.exists()}")
            }
        }
    }

    buildTypes {
        release {
            // Use the = syntax to be absolutely direct
            signingConfig = signingConfigs.getByName("release")
            
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }

        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}