package com.ethanteng.helloporch

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.getSystemService
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.PorchExperience
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive

/**
 * Ringing when Porch isn't open: Firebase Cloud Messaging, as PushKit is on iOS (SystemIncomingCalls.registerDevice).
 * Each household this device rings for gets its FCM token (`registerVoIP` with `platform: "android"`), and the server
 * pushes a call to it when Porch isn't checking in. The bedside registers for its household, and a family phone for
 * every family it's in. The other mode's households are told to stop.
 *
 * A device that can't answer such a call registers no token, so the server doesn't count on it: answering needs the
 * microphone, and ringing needs a notification that can show. Firebase's settings come from google-services.json at
 * build time; a build without them never registers. Main thread only.
 */
class PorchPush(private val app: PorchApplication) {
    /** This device's FCM token, once Firebase has given it. */
    private var token: String? = null
    /** Whether every household this device rings for took the token, so it rings while Porch is closed. */
    var ready by mutableStateOf(false); private set
    private var job: Job? = null
    /** What was last registered, so check-ins don't register it again. */
    private var registered: String? = null

    val configured: Boolean get() = listOf(BuildConfig.FIREBASE_APP_ID, BuildConfig.FIREBASE_API_KEY, BuildConfig.FIREBASE_PROJECT_ID,
        BuildConfig.FIREBASE_SENDER_ID).all { it.isNotEmpty() }

    /** Sets Firebase up from the build's settings and asks for the token. */
    fun start() {
        if (!configured) return
        try {
            if (FirebaseApp.getApps(app).isEmpty()) {
                FirebaseApp.initializeApp(app, FirebaseOptions.Builder()
                    .setApplicationId(BuildConfig.FIREBASE_APP_ID)
                    .setApiKey(BuildConfig.FIREBASE_API_KEY)
                    .setProjectId(BuildConfig.FIREBASE_PROJECT_ID)
                    .setGcmSenderId(BuildConfig.FIREBASE_SENDER_ID)
                    .build())
            }
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (task.isSuccessful) tokenChanged(task.result)
                else Log.w("Porch", "No push token", task.exception)
            }
        } catch (e: Exception) {
            // Google Play services may be missing or out of date. Porch still rings while it's open.
            Log.w("Porch", "Push isn't available", e)
        }
    }

    /** A new token, from Firebase. */
    fun tokenChanged(token: String) {
        this.token = token
        register()
    }

    /** Whether this device can ring and be answered while Porch is closed: the microphone, and call notifications. */
    fun canRing(): Boolean {
        val microphone = granted(app, Manifest.permission.RECORD_AUDIO)
        val notifications = (Build.VERSION.SDK_INT < 33 || granted(app, Manifest.permission.POST_NOTIFICATIONS)) &&
            NotificationManagerCompat.from(app).areNotificationsEnabled()
        return microphone && notifications
    }

    /** Whether a call can show full screen over the lock screen. Android 14 asks the user to allow it for some apps. */
    fun canShowFullScreen(): Boolean =
        Build.VERSION.SDK_INT < 34 || app.getSystemService<NotificationManager>()?.canUseFullScreenIntent() == true

    /**
     * Gives each household this device rings for the token, or none when it can't ring, and takes it from the other
     * mode's. Runs again only when what it would send changes, such as a family joined or left, a mode switch, or a
     * permission given in Settings; [force] sends it anyway.
     */
    fun register(force: Boolean = false) {
        val token = token ?: return
        val experience = app.device.experience
        val bedside = listOfNotNull(app.device.credential(PorchExperience.BEDSIDE))
        val families = app.device.families
        val profiles = if (experience == PorchExperience.BEDSIDE) bedside else families
        val others = if (experience == PorchExperience.BEDSIDE) families else bedside
        val enabled = canRing()
        val key = listOf(token, enabled, experience, profiles.map { it.credential }, others.map { it.credential }).toString()
        if (!force && key == registered) return
        registered = key
        val previous = job
        job?.cancel()
        job = app.scope.launch {
            previous?.join()
            for (other in others) {
                try { app.service(other).send("registerVoIP", mapOf("token" to JsonNull)) }
                catch (e: CancellationException) { throw e } catch (_: Exception) {}
            }
            if (profiles.isEmpty()) { ready = false; return@launch }
            val values: Map<String, JsonElement> = if (enabled) mapOf("token" to JsonPrimitive(token), "platform" to JsonPrimitive("android"))
                else mapOf("token" to JsonNull)
            // Ready once every household that still has this device took it. One that removed it can't ring it anyway.
            var accepted: Boolean? = null
            for (profile in profiles) {
                try {
                    val ok = app.service(profile).send("registerVoIP", values).pushReady == true
                    accepted = (accepted ?: true) && ok
                } catch (e: CancellationException) {
                    throw e
                } catch (e: FamilyServiceException) {
                    if (e.status != 401) { accepted = false; registered = null }
                } catch (_: Exception) {
                    accepted = false
                    // Tried again at the next check-in.
                    registered = null
                }
            }
            ready = enabled && accepted == true
        }
    }

    private companion object {
        fun granted(context: Context, permission: String) = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
    }
}
