import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from android/key.properties, which is never committed
// (android/.gitignore already excludes key.properties, *.jks and *.keystore).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

if (!hasReleaseKeystore) {
    logger.warn(
        "meridian: android/key.properties is missing — the release build will be unsigned. " +
        "Debug builds are unaffected."
    )
}

android {
    namespace = "com.meridian.meridian_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.meridian.meridian_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Never fall back to the debug keystore. Its key is byte-identical on
            // every machine that has ever run the Android SDK, so an APK signed
            // with it can be replaced in place by anyone who builds the same
            // applicationId — the replacement inherits this app's UID, data
            // directory and Keystore alias, and so the bearer token with it.
            //
            // Without android/key.properties the release build stays unsigned and
            // will refuse to install, which is the safe failure. Create the key
            // once, then write the four values into that (gitignored) file:
            //
            //   keytool -genkey -v -keystore ~/meridian-release.jks \
            //     -keyalg RSA -keysize 2048 -validity 10000 -alias meridian
            //
            signingConfig = if (hasReleaseKeystore) signingConfigs.getByName("release") else null
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
