package com.ethanteng.helloporch

import android.app.Application
import android.os.SystemClock
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.ethanteng.helloporch.core.AttendanceTracker
import com.ethanteng.helloporch.core.BedsideAttendance
import com.ethanteng.helloporch.core.BedsidePreferences
import com.ethanteng.helloporch.core.CallPreferences
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.ContactPhotoStore
import com.ethanteng.helloporch.core.FamilyCoordinator
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyService
import com.ethanteng.helloporch.core.KeypadNumberReport
import com.ethanteng.helloporch.core.MessageAutoplay
import com.ethanteng.helloporch.core.PollOrder
import com.ethanteng.helloporch.core.PorchDevice
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.SecretStore
import java.io.File
import java.time.Instant
import kotlinx.coroutines.MainScope

/** Where the app's long-lived pieces are made, once per process. */
class PorchApplication : Application() {
    val settings by lazy { SharedPreferencesSettings(this) }
    val secrets by lazy { KeystoreSecretStore(this) }
    val transport by lazy { OkHttpFamilyTransport() }
    /** Only a tablet can be the bedside, as only an iPad can on iOS: a smallest width of 600 dp or more. */
    val device by lazy { PorchDevice(settings, secrets, BuildConfig.PORCH_SERVER_URL, canBeBedside = resources.configuration.smallestScreenWidthDp >= 600) }
    /** Keypad photos, and in `familyMembers` the family's own, where iOS keeps them (Application Support/Porch/ContactPhotos). */
    val photos by lazy { ContactPhotoStore(File(filesDir, "Porch/ContactPhotos")) }
    /** Lasts as long as the process, so the last check-in as Porch closes still goes out. */
    val scope = MainScope()
    /** Whether Porch is on screen. */
    var onScreen = false
        private set
    /** Whether the screen showing could take an incoming call, as `readyForIncoming` says on iOS: the bedside's home, or
     * a family phone's list of families, with nothing open over it. Setup, the welcome screen and joining aren't. */
    var screenReady = false
    val coordinator by lazy {
        FamilyCoordinator(device, scope, { service(it) }, PollOrder(), canReceive = { onScreen && screenReady }, attendance = AttendanceTracker.shared,
            afterChange = ::afterSnapshot)
    }
    val keypadReport by lazy { KeypadNumberReport(scope, { service(it) }, pin = { caregiverPIN }, now = SystemClock::elapsedRealtime) }
    /** Counts mode changes, so the screens pick the new mode up. */
    var modeChanges by mutableIntStateOf(0)
        private set

    fun service(credential: FamilyCredential) = FamilyService(credential, transport)
    fun service(origin: String) = FamilyService(origin, null, transport)

    /** The caregiver PIN, under the iOS Keychain account, readable only while the tablet is unlocked. Empty when there's
     * none or it can't be read now. */
    var caregiverPIN: String
        get() = secrets.read(caregiverPINAccount)?.decodeToString() ?: ""
        set(value) = secrets.write(caregiverPINAccount, value.encodeToByteArray(), SecretStore.Access.WHEN_UNLOCKED)

    /** Shows the other mode and checks in as it. Push, which the old mode unregisters first, comes with calls (phase 3). */
    private val cell2jackKeypad = lazy { Cell2JackKeypad(this, settings) }
    /** The Cell2Jack, the bedside's corded-phone keypad. It runs only while the bedside is in front (MainActivity), and
     * is never made on a family phone. */
    val cell2jack by cell2jackKeypad
    /** The activity is resumed. Process [onScreen] stays true through a system dialog that pauses the activity, such as
     * the USB permission question, and the Cell2Jack should not run then. */
    private var activityResumed = false

    fun switchExperience(experience: PorchExperience) {
        device.experience = experience
        modeChanges++
        if (onScreen) coordinator.start()
        if (experience == PorchExperience.BEDSIDE) {
            // Already in front: onResume ran while this tablet was still a family phone, so it never started the keypad.
            if (activityResumed) cell2jack.start()
        } else stopCell2Jack()
    }

    /** [joinFamily] writes the mode itself and checks in as a family phone. The screens read [modeChanges], so without
     * this they keep the welcome screen or the bedside clock until the next check-in, and Set up can switch the tablet
     * back. It does not check in again: that would tell the new family the phone had gone offline. */
    fun noteModeChanged() { modeChanges++ }

    /** The activity is in front. A bedside starts its Cell2Jack; a family phone never makes one. */
    fun bedsideCameToFront() {
        activityResumed = true
        if (device.experience != PorchExperience.BEDSIDE) return
        if (cell2jackKeypad.isInitialized()) cell2jack.noteReturnedToFront()
        cell2jack.start()
    }

    /** The activity left the front, such as behind another app, the screen turning off, or a system dialog. */
    fun bedsideLeftFront() {
        activityResumed = false
        stopCell2Jack()
    }

    /** Stops the Cell2Jack, if this device made one: when Porch leaves the front, or the tablet stops being the
     * bedside, such as by joining a family. */
    fun stopCell2Jack() { if (cell2jackKeypad.isInitialized()) cell2jack.stop() }

    override fun onCreate() {
        super.onCreate()
        // Porch checks in while it's open and tells each family when it closes. Push wakes it for calls (phase 3).
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) { onScreen = true; coordinator.start() }
            override fun onStop(owner: LifecycleOwner) { onScreen = false; coordinator.pause() }
        })
    }

    /** The bedside's work after each snapshot, as `FamilyCoordinator.changed()` does on iOS: keypad contacts follow their
     * family members, and the server hears the keypad's numbers. Photo sync and speech-clip prefetch come with the
     * clock's contact grid and calls (phase 3). */
    private fun afterSnapshot(links: FamilyLinks) {
        val state = links.state?.takeIf { it.me.role == PorchExperience.BEDSIDE } ?: return
        try {
            val slots = CallSlots.load(settings, photos)
            val previous = slots.copy()
            slots.reconcile(state, photos.familyMembers)
            if (slots != previous) slots.save(settings, photos)
            keypadReport.report(slots, coordinator)
        } catch (error: Exception) {
            // iOS shows this as the check-in's error, such as a saved keypad that can't be read until a caregiver saves
            // it again in caregiver mode (phase 4).
            Log.w("Porch", "Couldn't update the keypad: ${error.message}")
        }
    }

    /** What a tablet set up as a new Porch leaves behind of the household it was: its keypad, photos, call, display and
     * message settings, and the camera's part in attendance, as `PorchDevice.forgetBedsideHousehold` does on iOS. The
     * unsent outbox comes with messages (phase 5). Family pairings stay. */
    fun forgetBedsideHousehold() {
        CallSlots.forget(settings, photos)
        photos.familyMembers.prune(keeping = emptySet(), olderThan = Instant.MAX)
        CallPreferences.forget(settings)
        BedsidePreferences().save(settings)
        MessageAutoplay().save(settings)
        BedsideAttendance.setCameraEnabled(false, settings)
    }

    private companion object { const val caregiverPINAccount = "porch.contact-setup-code" }
}
