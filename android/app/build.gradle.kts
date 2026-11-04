plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.ethanteng.helloporch"
    // Current AndroidX libraries need API 37 to build against. The app still targets 36 (decision 6 in PLAN.md).
    compileSdk = 37

    defaultConfig {
        // The same ID as the iOS bundle.
        applicationId = "com.ethanteng.helloporch"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
        // The calling server, as on iOS (PorchServerURL). Invitations for any other server carry it in their link.
        buildConfigField("String", "PORCH_SERVER_URL", "\"https://porch-calling-prototype.vercel.app\"")
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
}
