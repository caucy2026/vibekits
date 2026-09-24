import java.security.MessageDigest

plugins {
    id("com.android.application")
}

val mihomoBinary = System.getenv("VIBEKITS_ANDROID_MIHOMO_BIN")
val stageMihomo = tasks.register<Copy>("stageMihomo") {
    val source = mihomoBinary?.takeIf { it.isNotBlank() }
    if (source != null) from(source)
    into(layout.buildDirectory.dir("generated/mihomo-jni/arm64-v8a"))
    rename { "libmihomo.so" }
    doFirst {
        check(source != null && file(source).isFile) {
            "Set VIBEKITS_ANDROID_MIHOMO_BIN to the verified Android arm64 Mihomo executable"
        }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(file(source).readBytes()).joinToString("") { "%02x".format(it) }
        check(digest == "dbd8af275219a097d66362d543b32f65ba0d4de9d96a49bf5e9abdcdad3af6f1") {
            "Mihomo v1.19.31 Android arm64 digest mismatch"
        }
    }
}

android {
    namespace = "com.caucy.vibekits.component.network_proxy"
    compileSdk = 35
    buildFeatures { aidl = true }
    sourceSets.getByName("main").jniLibs.srcDir(
        layout.buildDirectory.dir("generated/mihomo-jni")
    )
    packaging.jniLibs {
        useLegacyPackaging = true
        keepDebugSymbols += "**/libmihomo.so"
    }
    defaultConfig {
        applicationId = "com.caucy.vibekits.component.network_proxy"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        ndk { abiFilters += "arm64-v8a" }
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

tasks.matching { it.name == "mergeReleaseJniLibFolders" }.configureEach {
    dependsOn(stageMihomo)
}
