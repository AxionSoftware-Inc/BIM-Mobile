import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use { signingProperties.load(it) }
}

fun signingValue(environmentName: String, propertyName: String): String? =
    System.getenv(environmentName)?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { it != null }

if (System.getenv("REQUIRE_RELEASE_SIGNING") == "true" && !hasReleaseSigning) {
    throw GradleException(
        "Production signing is required. Provide key.properties or " +
            "ANDROID_KEYSTORE_PATH/ANDROID_KEYSTORE_PASSWORD/ANDROID_KEY_ALIAS/ANDROID_KEY_PASSWORD."
    )
}

android {
    namespace = "com.example.viewer_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.viewer_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DTBE_BUILD_TESTS=OFF",
                    "-DTBE_BUILD_CLI=OFF",
                    "-DTBE_BUILD_EXAMPLES=OFF",
                    "-DTBE_ENABLE_OCCT=OFF",
                )
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../../../CMakeLists.txt")
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfigs.create("release") {
                    storeFile = file(releaseStoreFile!!)
                    storePassword = releaseStorePassword
                    keyAlias = releaseKeyAlias
                    keyPassword = releaseKeyPassword
                }
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Local verification remains possible. The release script sets
                // REQUIRE_RELEASE_SIGNING=true and will refuse this fallback.
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }

    // Dart FFI receives the absolute nativeLibraryDir path from MainActivity.
    // Keep C++ libraries extracted there instead of relying on zip-backed
    // loading behaviour, which varies across Android vendors.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.google.android.filament:filament-android:1.71.6")
    implementation("com.google.android.filament:filament-utils-android:1.71.6")
    implementation("com.google.android.filament:filamat-android:1.71.6")
}

flutter {
    source = "../.."
}
