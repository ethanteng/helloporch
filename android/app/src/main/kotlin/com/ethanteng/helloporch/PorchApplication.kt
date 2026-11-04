package com.ethanteng.helloporch

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.ethanteng.helloporch.core.AttendanceTracker
import com.ethanteng.helloporch.core.FamilyCoordinator
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyService
import com.ethanteng.helloporch.core.PollOrder
import com.ethanteng.helloporch.core.PorchDevice
import kotlinx.coroutines.MainScope

/** Where the app's long-lived pieces are made, once per process. */
class PorchApplication : Application() {
    val settings by lazy { SharedPreferencesSettings(this) }
    val secrets by lazy { KeystoreSecretStore(this) }
    val transport by lazy { OkHttpFamilyTransport() }
    /** Only a tablet can be the bedside, as only an iPad can on iOS: a smallest width of 600 dp or more. */
    val device by lazy { PorchDevice(settings, secrets, BuildConfig.PORCH_SERVER_URL, canBeBedside = resources.configuration.smallestScreenWidthDp >= 600) }
    /** Lasts as long as the process, so the last check-in as Porch closes still goes out. */
    val scope = MainScope()
    /** Whether Porch is on screen. Until incoming calls can show (phase 3), that's all being able to take one means. */
    var onScreen = false
        private set
    val coordinator by lazy { FamilyCoordinator(device, scope, { service(it) }, PollOrder(), canReceive = { onScreen }, attendance = AttendanceTracker.shared) }

    fun service(credential: FamilyCredential) = FamilyService(credential, transport)
    fun service(origin: String) = FamilyService(origin, null, transport)

    override fun onCreate() {
        super.onCreate()
        // Porch checks in while it's open and tells each family when it closes. Push wakes it for calls (phase 3).
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) { onScreen = true; coordinator.start() }
            override fun onStop(owner: LifecycleOwner) { onScreen = false; coordinator.pause() }
        })
    }
}
