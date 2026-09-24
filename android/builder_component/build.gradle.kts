import java.security.MessageDigest

plugins {
    id("com.android.application")
}

val toolchainArchive = System.getenv("VIBEKITS_ANDROID_BUILDER_TOOLCHAIN_ARCHIVE")
val expectedToolchainSha256 = "367d0f2327bf28b57509351fd06afb38656e7e9b2562a9ad46e72720c91f1452"
val stageToolchain = tasks.register<Copy>("stageBuilderToolchain") {
    if (!toolchainArchive.isNullOrBlank()) from(toolchainArchive)
    into(layout.buildDirectory.dir("generated/builder-assets"))
    rename { "pad-builder-toolchain-arm64.zip" }
    doFirst {
        check(!toolchainArchive.isNullOrBlank() && file(toolchainArchive).isFile) {
            "Set VIBEKITS_ANDROID_BUILDER_TOOLCHAIN_ARCHIVE to the verified PAD arm64 toolchain archive"
        }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(file(toolchainArchive).readBytes()).joinToString("") { "%02x".format(it) }
        check(digest == expectedToolchainSha256) { "PAD builder toolchain SHA-256 mismatch" }
    }
}

android {
    namespace = "com.vibekits.vibekits.component.builder"
    compileSdk = 35
    buildFeatures { aidl = true }
    sourceSets.getByName("main").assets.srcDir(
        layout.buildDirectory.dir("generated/builder-assets")
    )
    defaultConfig {
        applicationId = "com.vibekits.vibekits.component.builder"
        minSdk = 24
        // PAD63 is API 31. Executing the unpacked arm64 aapt tool and its
        // private libraries was verified in a non-debuggable SDK 35 app.
        targetSdk = 35
        versionCode = 2
        versionName = "1.0.1"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
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
        release { signingConfig = signingConfigs.findByName("kemiRelease") }
    }
}

tasks.matching { it.name == "mergeReleaseAssets" }.configureEach {
    dependsOn(stageToolchain)
}
tasks.matching { it.name.contains("lint", ignoreCase = true) }.configureEach {
    dependsOn(stageToolchain)
}
