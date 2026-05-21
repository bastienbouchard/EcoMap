import java.util.Base64

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
    File(keystorePath).writeBytes(keystoreBytes)
    File(rootDir, "app/key.properties").writeText(
        "storeFile=$keystorePath\n" +
        "storePassword=${System.getenv("CM_KEYSTORE_PASSWORD") ?: ""}\n" +
        "keyAlias=${System.getenv("CM_KEY_ALIAS") ?: ""}\n" +
        "keyPassword=${System.getenv("CM_KEY_PASSWORD") ?: ""}\n"
    )
}

val keyProps = java.util.Properties()
val keyPropsFile = rootProject.file("app/key.properties")
if (keyPropsFile.exists()) keyProps.load(keyPropsFile.inputStream())

android {
    namespace = "com.bastienbouchard.ecomap"
    compileSdk = 35
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
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = keyProps["storeFile"]?.let { file(it as String) }
            storePassword = keyProps["storePassword"] as String? ?: ""
            keyAlias = keyProps["keyAlias"] as String? ?: ""
            keyPassword = keyProps["keyPassword"] as String? ?: ""
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

flutter {
    source = "../.."
}
