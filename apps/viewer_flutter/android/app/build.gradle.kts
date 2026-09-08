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
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

// TEMPORARY MIGRATION HOOK (native streaming V2)
//
// GitHub's Contents API can replace this ~330 KB host file but cannot apply a
// small guarded hunk, and hosted Actions for this repository currently fail
// before a runner starts. Keep the source transformation deterministic and in
// the repository instead: the first Android Kotlin compile applies the guarded
// patch locally, later compiles are no-ops because the script has a marker.
//
// This task deliberately runs before every Kotlin compilation and the patch is
// idempotent. Once the generated source change is committed normally, remove
// both this hook and .github/scripts/codex_fix_native_streaming.py.
val nativeStreamingPatchScript = projectDir.resolve("../../../../.github/scripts/codex_fix_native_streaming.py")
val nativeStreamingHost = projectDir.resolve(
    "src/main/kotlin/com/example/viewer_flutter/RenderSceneFilamentHostView.kt"
)
val applyNativeStreamingPatch = tasks.register<Exec>("applyNativeStreamingPatch") {
    group = "build setup"
    description = "Apply guarded native BIM streaming/resource-lifecycle migration"
    workingDir(projectDir.resolve("../../../.."))
    val pythonExecutable = System.getenv("PYTHON")?.takeIf { it.isNotBlank() } ?: "python3"
    commandLine(pythonExecutable, nativeStreamingPatchScript.absolutePath)
    inputs.file(nativeStreamingPatchScript)
    // The task edits this source only once; forcing execution keeps Gradle from
    // caching a pre-migration state when switching branches/worktrees.
    outputs.upToDateWhen { false }
    doFirst {
        require(nativeStreamingPatchScript.isFile) {
            "Missing native streaming patch script: ${nativeStreamingPatchScript.absolutePath}"
        }
        require(nativeStreamingHost.isFile) {
            "Missing Filament host source: ${nativeStreamingHost.absolutePath}"
        }
    }
}

tasks.configureEach {
    if (name.startsWith("compile") && name.endsWith("Kotlin")) {
        dependsOn(applyNativeStreamingPatch)
    }
}

dependencies {
    implementation("com.google.android.filament:filament-android:1.71.6")
    implementation("com.google.android.filament:filament-utils-android:1.71.6")
    implementation("com.google.android.filament:filamat-android:1.71.6")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
