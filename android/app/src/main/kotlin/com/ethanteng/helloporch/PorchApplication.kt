package com.ethanteng.helloporch

import android.app.Application

/** Where the app's long-lived pieces are made, once per process. */
class PorchApplication : Application() {
    val settings by lazy { SharedPreferencesSettings(this) }
    val secrets by lazy { KeystoreSecretStore(this) }
    val transport by lazy { OkHttpFamilyTransport() }
}
