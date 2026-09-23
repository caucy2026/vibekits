plugins {
    id("com.android.application")
}

android {
    namespace = "com.vibekits.vibekits.component.models"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.vibekits.vibekits.component.models"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    sourceSets.named("main") {
        assets.srcDir("../../test_data/models")
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
            signingConfig = signingConfigs.findByName("kemiRelease")
        }
    }
}
