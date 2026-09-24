plugins { id("com.android.application") }

android {
    namespace = "com.vibekits.vibekits.builderprobeclient"
    compileSdk = 35
    buildFeatures { aidl = true }
    defaultConfig {
        applicationId = "com.vibekits.vibekits.builderprobeclient"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
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
