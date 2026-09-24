plugins {
    id("com.android.application")
}

android {
    namespace = "com.vibekits.vibekits.component.adb"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.vibekits.vibekits.component.adb"
        minSdk = 24
        targetSdk = 35
        versionCode = 5
        versionName = "1.4"
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
