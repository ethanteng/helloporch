import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    // The open-source licenses on the About page, gathered from the dependencies at build time.
    alias(libs.plugins.aboutlibraries.android)
}

// Firebase, which rings a phone when Porch isn't open, from the app's google-services.json in this folder. The repo is
// public, so that file stays out of git (.gitignore), and without it the app builds with push turned off. The Google
// Services plugin isn't used: it would make every build need the file.
val firebase: Map<String, String> = file("google-services.json").takeIf { it.exists() }?.let { config ->
    @Suppress("UNCHECKED_CAST")
    val json = groovy.json.JsonSlurper().parse(config) as Map<String, Any?>
    val project = json["project_info"] as Map<String, Any?>
    @Suppress("UNCHECKED_CAST")
    val app = (json["client"] as List<Map<String, Any?>>).first {
        val info = it["client_info"] as Map<*, *>
        (info["android_client_info"] as Map<*, *>)["package_name"] == "com.ethanteng.helloporch"
    }
    mapOf(
        "FIREBASE_APP_ID" to (app["client_info"] as Map<*, *>)["mobilesdk_app_id"].toString(),
        "FIREBASE_API_KEY" to ((app["api_key"] as List<*>).first() as Map<*, *>)["current_key"].toString(),
        "FIREBASE_PROJECT_ID" to project["project_id"].toString(),
        "FIREBASE_SENDER_ID" to project["project_number"].toString(),
    )
} ?: emptyMap()

// Release builds are signed with Porch's upload key, which Google Play replaces with the app signing key. The key and
// its passwords stay outside the repo, in a properties file named by -Pporch.upload or PORCH_ANDROID_UPLOAD (README).
// Without one, a release build is left unsigned.
val upload: Pair<Properties, File>? = ((findProperty("porch.upload") as String?) ?: System.getenv("PORCH_ANDROID_UPLOAD"))
    ?.let { file(it) }?.takeIf { it.exists() }
    ?.let { found -> Properties().apply { found.inputStream().use { load(it) } } to found.parentFile }

android {
    namespace = "com.ethanteng.helloporch"
    // Current AndroidX libraries need API 37 to build against. The app still targets 36 (decision 6 in PLAN.md).
    compileSdk = 37

    defaultConfig {
        // The same ID as the iOS bundle.
        applicationId = "com.ethanteng.helloporch"
        minSdk = 29
        targetSdk = 36
        // Each upload to Google Play needs a higher versionCode: -Pporch.versionCode (README).
        versionCode = (findProperty("porch.versionCode") as String?)?.toInt() ?: 1
        versionName = (findProperty("porch.versionName") as String?) ?: "0.1"
        // The calling server, as on iOS (PorchServerURL). Invitations for any other server carry it in their link.
        buildConfigField("String", "PORCH_SERVER_URL", "\"https://porch-calling-prototype.vercel.app\"")
        for (name in listOf("FIREBASE_APP_ID", "FIREBASE_API_KEY", "FIREBASE_PROJECT_ID", "FIREBASE_SENDER_ID")) {
            buildConfigField("String", name, "\"${firebase[name].orEmpty()}\"")
        }
    }

    upload?.let { (properties, folder) ->
        signingConfigs {
            create("upload") {
                storeFile = folder.resolve(properties.getProperty("storeFile"))
                storePassword = properties.getProperty("storePassword")
                keyAlias = properties.getProperty("keyAlias")
                keyPassword = properties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // targetSdk stays at 36 until Android 17's behavior changes are tested (decision 6 in PLAN.md).
    lint { disable += "OldTargetApi" }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.okhttp)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.material3)
    implementation(libs.zxing.core)
    implementation(libs.livekit.android)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)
    implementation(libs.aboutlibraries.compose.m3)
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.ui.compose)
    // The bedside records a video message after an unanswered video call (android/PLAN.md, phase 5).
    implementation(libs.androidx.camera.camera2)
    implementation(libs.androidx.camera.lifecycle)
    implementation(libs.androidx.camera.video)
    implementation(libs.androidx.camera.view)
    implementation(libs.mlkit.face.detection)
}
