// Shared by the phone app (:app) and the Wear OS app (:wear): the /api/quick client,
// the snapshot models, the device-key store and the widget/watch strings.
// No third-party JSON or HTTP library: org.json and HttpURLConnection only.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.carecoins.quickcore"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    testImplementation("junit:junit:4.13.2")
    // Android's org.json is a stub in local unit tests; use the real one there.
    testImplementation("org.json:json:20240303")
}
