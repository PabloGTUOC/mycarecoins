import java.io.FileInputStream
import java.util.Properties

// Release signing credentials live in android/key.properties, which is
// gitignored and must never be committed.
//
// Without it, a release build falls back to debug keys so `flutter run --release`
// and `flutter build apk` keep working locally. That fallback is fine for those —
// and useless for an app bundle, whose only purpose is a Play upload that Play
// would reject. So `bundleRelease` fails outright instead (see below).
//
// A warning is not enough on its own: `flutter build` swallows Gradle's warning
// output, so `logger.warn` here is invisible in the exact command that produces
// an upload artifact. Only a hard failure reaches the person running it.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists()

if (!hasReleaseKeystore) {
    gradle.taskGraph.whenReady {
        // Exact name only. AGP also creates bundleReleaseResources,
        // bundleReleaseClassesToCompileJar and friends, which are part of an
        // ordinary assembleRelease — matching those by substring would block
        // `flutter run --release` and `flutter build apk` too.
        if (allTasks.any { it.name == "bundleRelease" }) {
            throw GradleException(
                "\n\nCannot build a release app bundle: fluterFront/android/key.properties is missing.\n" +
                "An .aab exists only to be uploaded to Google Play, and Play rejects debug-signed uploads.\n\n" +
                "  1. keytool -genkey -v -keystore ~/carecoins-upload.jks \\\n" +
                "             -alias upload -keyalg RSA -keysize 2048 -validity 10000\n" +
                "  2. cp android/key.properties.example android/key.properties, then fill it in\n" +
                "     (absolute storeFile path — `~` is not expanded)\n" +
                "  3. cd android && ./gradlew :app:signingReport   # Variant: release -> Config: release\n\n" +
                "See docs/store-release-checklist.md. For local testing use `flutter run --release`\n" +
                "or `flutter build apk`, which still fall back to debug signing.\n"
            )
        }
    }
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.plugin.compose")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.carecoins.carecoins_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // rootProject.file() passes an absolute path through unchanged and
                // resolves a relative one against android/. It does not expand `~`.
                storeFile = keystoreProperties.getProperty("storeFile")
                    ?.let { rootProject.file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    defaultConfig {
        applicationId = "com.carecoins.carecoins_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Visible under `./gradlew`; `flutter build` hides warnings, which is
                // why bundleRelease fails hard above rather than relying on this.
                logger.warn(
                    "\n*** android/key.properties not found — signing this RELEASE build with " +
                    "DEBUG keys. Fine for `flutter run --release`; Google Play would reject an " +
                    "upload. See docs/store-release-checklist.md. ***\n"
                )
                signingConfigs.getByName("debug")
            }
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

// Home-screen widget, ongoing notification and the Wear OS hand-off
// (docs/android-widget-wear-plan.md). The API client and models live in :quickcore.
dependencies {
    implementation(project(":quickcore"))
    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.glance:glance-material3:1.1.1")
    implementation("androidx.work:work-runtime-ktx:2.10.1")
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
}
