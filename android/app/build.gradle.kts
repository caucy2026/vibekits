plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vibekits.vibekits"
    testBuildType = "release"
    buildFeatures { aidl = true }
    sourceSets.getByName("main").assets.srcDir(
        layout.buildDirectory.dir("generated/adb-helper-assets")
    )
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    packaging {
        jniLibs {
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/x86_64/**",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vibekits.vibekits"
        testInstrumentationRunner = "com.vibekits.vibekits.PadBuilderBridgeInstrumentation"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // KEMI PAD is arm64. Keep the core Harness relay in the base APK,
        // while excluding unused x86 and 32-bit model runtimes.
        ndk { abiFilters += "arm64-v8a" }

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    val releaseStore = System.getenv("KEMI_ANDROID_KEYSTORE")
    signingConfigs {
        if (!releaseStore.isNullOrBlank()) {
            create("kemiRelease") {
                storeFile = file(releaseStore)
                storePassword = System.getenv("KEMI_ANDROID_STORE_PASSWORD")
                keyAlias = System.getenv("KEMI_ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("KEMI_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Without explicit signing inputs produce an unsigned artifact for
            // the documented external signer; never silently use a debug key.
            signingConfig = signingConfigs.findByName("kemiRelease")
            proguardFiles("pad-builder-bridge-test.pro")
        }
    }
}

val stageAdbHelperRelease = tasks.register<Copy>("stageAdbHelperRelease") {
    dependsOn(":adb_helper:assembleRelease")
    from(project(":adb_helper").layout.buildDirectory.file(
        if (System.getenv("KEMI_ANDROID_KEYSTORE").isNullOrBlank())
            "outputs/apk/release/adb_helper-release-unsigned.apk"
        else
            "outputs/apk/release/adb_helper-release.apk"
    ))
    into(layout.buildDirectory.dir("generated/adb-helper-assets"))
    rename { "vibekits-adb-helper.apk" }
    doLast {
        check(layout.buildDirectory.file("generated/adb-helper-assets/vibekits-adb-helper.apk").get().asFile.isFile) {
            "ADB helper APK was not staged; refusing an Android package without remote ADB bootstrap"
        }
    }
}
tasks.matching { it.name == "mergeReleaseAssets" }.configureEach {
    dependsOn(stageAdbHelperRelease)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Flutter declares these assets for desktop builds. The Android release Copy
// task omits them; Android reads the separately signed model component APK.
tasks.withType<Copy>().matching { it.name == "copyFlutterAssetsRelease" }.configureEach {
    exclude("flutter_assets/test_data/models/**")
}
