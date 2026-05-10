import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")

}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()

if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.budisciplink.budisciplink"
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
        applicationId = "com.budisciplink.budisciplink"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                val keyAliasValue = keystoreProperties["keyAlias"]?.toString()
                val keyPasswordValue = keystoreProperties["keyPassword"]?.toString()
                val storeFileValue = keystoreProperties["storeFile"]?.toString()
                val storePasswordValue = keystoreProperties["storePassword"]?.toString()

                if (!keyAliasValue.isNullOrBlank() &&
                    !keyPasswordValue.isNullOrBlank() &&
                    !storeFileValue.isNullOrBlank() &&
                    !storePasswordValue.isNullOrBlank()
                ) {
                    keyAlias = keyAliasValue
                    keyPassword = keyPasswordValue
                    storeFile = rootProject.file(storeFileValue)
                    storePassword = storePasswordValue
                }
            }
        }
    }

    buildTypes {
        release {
            // Use release key when available; fallback to debug key for local testing.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
