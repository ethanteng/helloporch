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
import com.ethanteng.helloporch.core.FamilySnapshot
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
    /** The call this device is ringing for or on. */
    val calls by lazy { CallCenter(this) }
    /** Ringing when Porch isn't open, from Firebase. */
    val push by lazy { PorchPush(this) }
    /** A call ringing through a notification while Porch isn't on screen. */
    val systemCalls by lazy { SystemCalls(this) }
    /** The family's messages waiting on the bedside, kept downloaded so they play at once. */
    val messages by lazy { BedsideMessages(this) }
    /** Text-to-speech for the bedside's announcements, started when the bedside first comes to the front so it's
     * ready by the first key press. */
    val speech by lazy { BedsideSpeech(this) }
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

    /** Shows the other mode and checks in as it. Push moves to the new mode's households (PorchPush.register). */
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
        push.register()
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
        speech
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
        // Cell2JackAttachedActivity's process can start before the tablet is unlocked, when nothing here can be read.
        if (Application.getProcessName().endsWith(Cell2JackAttachedActivity.processSuffix)) return
        CallNotifications.createChannels(this)
        // Porch checks in while it's open and tells each family when it closes. Push rings it for calls while it's
        // closed. A call in progress on a family phone keeps it checking in, so the call goes on with the phone locked.
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) { onScreen = true; coordinator.start(); calls.cameOnScreen(); push.register() }
            override fun onStop(owner: LifecycleOwner) {
                onScreen = false
                calls.leftScreen()
                if (!calls.continuing) coordinator.pause()
            }
        })
        push.start()
    }

    /** The bedside's work after each snapshot, as `FamilyCoordinator.changed()` does on iOS: family members' photos
     * download, keypad contacts follow their family members, the server hears the keypad's numbers, and the natural
     * voice's sentences are fetched ahead. */
    private fun afterSnapshot(links: FamilyLinks) {
        // A call to this device rings, on the bedside and on family phones.
        calls.noteLinks(links)
        systemCalls.noteLinks(links)
        // A family joined or left, or a bedside set up: the households that ring this device change with it.
        push.register()
        // Photos caregiver mode downloaded on a family phone don't stay.
        if (links.state?.me?.role == PorchExperience.FAMILY) FamilyPhotos.pruneOnFamilyPhone(this)
        val state = links.state?.takeIf { it.me.role == PorchExperience.BEDSIDE } ?: return
        try {
            val slots = CallSlots.load(settings, photos)
            device.credential(PorchExperience.BEDSIDE)?.let { FamilyPhotos.sync(this, state, it, slots) }
            followFamily(state, slots)
            keypadReport.report(slots, coordinator)
            // Messages download as they arrive, and the server hears when they did.
            messages.sync(state)
            // A call or a drop-in never waits for the natural voice, so its sentences are fetched ahead.
            NaturalVoice.prefetch(this, state, slots)
        } catch (error: Exception) {
            // iOS shows this as the check-in's error, such as a saved keypad that can't be read until a caregiver saves
            // it again in caregiver mode.
            Log.w("Porch", "Couldn't update the keypad: ${error.message}")
        }
    }

    /** Keys show their family members' current names and photos, and keep following an invitation once it's accepted. */
    private fun followFamily(state: FamilySnapshot, slots: CallSlots) {
        val previous = slots.copy()
        slots.reconcile(state, photos.familyMembers)
        if (slots != previous) slots.save(settings, photos)
    }

    /** A family member's photo downloaded: keys showing them pick it up now, not at the next check-in. */
    fun photoSaved() {
        val state = coordinator.links.value.state?.takeIf { it.me.role == PorchExperience.BEDSIDE } ?: return
        try { followFamily(state, CallSlots.load(settings, photos)) } catch (error: Exception) { Log.w("Porch", "Couldn't update the keypad: ${error.message}") }
    }

    /** What a tablet set up as a new Porch leaves behind of the household it was: its keypad, photos, call, display and
     * message settings, its waiting messages, and the camera's part in attendance, as `PorchDevice.forgetBedsideHousehold`
     * does on iOS. The voicemail outbox comes with phase 5's third part. Family pairings stay. */
    fun forgetBedsideHousehold() {
        messages.forget()
        CallSlots.forget(settings, photos)
        photos.familyMembers.prune(keeping = emptySet(), olderThan = Instant.MAX)
        CallPreferences.forget(settings)
        BedsidePreferences().save(settings)
        MessageAutoplay().save(settings)
        BedsideAttendance.setCameraEnabled(false, settings)
    }

    private companion object { const val caregiverPINAccount = "porch.contact-setup-code" }
}
