import java.util.Base64
import java.util.Properties
import java.io.File as JavaFile

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Génère key.properties depuis les variables d'environnement Codemagic
val keystoreB64 = System.getenv("CM_KEYSTORE_B64")
val keystorePath = "/tmp/ecomap-keystore.p12"
if (keystoreB64 != null) {
    val keystoreBytes = Base64.getDecoder().decode(keystoreB64)
    JavaFile(keystorePath).writeBytes(keystoreBytes)
    JavaFile(rootDir, "app/key.properties").writeText(
        "storeFile=$keystorePath\n" +
        "storePassword=${System.getenv("MY_STORE_PASSWORD") ?: ""}\n" +
        "keyAlias=${System.getenv("MY_KEY_ALIAS") ?: "ecomap"}\n" +
        "keyPassword=${System.getenv("MY_KEY_PASSWORD") ?: ""}\n"
    )
}

val keyProps = Properties()
val keyPropsFile = JavaFile(rootDir, "app/key.properties")
if (keyPropsFile.exists()) keyProps.load(keyPropsFile.inputStream())

android {
    namespace = "com.bastienbouchard.ecomap"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.bastienbouchard.ecomap"
        minSdk = 23
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = (keyProps["storeFile"] as String?)?.let { JavaFile(it) }
            storePassword = keyProps["storePassword"] as String? ?: ""
            keyAlias = keyProps["keyAlias"] as String? ?: ""
            keyPassword = keyProps["keyPassword"] as String? ?: ""
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

