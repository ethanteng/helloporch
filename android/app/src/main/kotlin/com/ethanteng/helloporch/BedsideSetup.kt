package com.ethanteng.helloporch

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ethanteng.helloporch.core.BedsideInvitation
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.ValidationException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

/** One screen of setup. */
enum class SetupStep { LINK, NAME, PIN, NUMBER, PERMISSIONS, CALLING, CORDED_PHONE, YOUR_PHONE, DONE }

/** The screens after the number, in order. Each is skipped when there's nothing to do on it. */
enum class SetupStage { PERMISSIONS, PHONE, YOUR_PHONE, DONE }

/**
 * Setting up a new bedside tablet, one screen at a time, as BedsideSetup.swift does: the setup link, unless Porch was
 * opened from it; who it's for; the caregiver PIN, which sets the tablet up; its own phone number; the microphone and
 * camera; how they'll call; the caregiver's own phone; then Done.
 *
 * Until the tablet is set up, the first screen can be cancelled and the others go back. Once it's set up, each screen
 * that's left replaces the last, so its number can't be skipped by going back. It lives in a ViewModel, so a request
 * in flight goes on when the activity is recreated, as it is when a USB keypad is plugged in.
 */
class BedsideSetup(application: Application) : AndroidViewModel(application) {
    private val app = application as PorchApplication

    /** Setup is showing, over the bedside's home screen, as iOS presents it over the clock. */
    var open by mutableStateOf(false)
        private set
    var steps by mutableStateOf(listOf(SetupStep.NAME))
        private set
    val step: SetupStep get() = steps.last()
    /** Who this Porch is for, such as "Mom", once it's chosen. */
    var name by mutableStateOf("")
    /** Setting up a new Porch in place of the one this tablet already is, until the PIN step swaps them. Until then the
     * old one stays as it was, and Cancel keeps it. */
    var replacing by mutableStateOf(false)
        private set
    /** What went wrong, shown until it's dismissed. */
    var error by mutableStateOf<String?>(null)
    var enrolling by mutableStateOf(false)
        private set
    /** The number step's state, while it's showing. */
    var number by mutableStateOf<SetupNumber?>(null)
        private set
    /** The add-your-phone step's state, while it's showing. */
    var yourPhone by mutableStateOf<SetupYourPhone?>(null)
        private set
    private var enrollment: Job? = null

    /** The PIN gate before a setup that stopped after its PIN goes on, as caregiver mode's gate is on iOS. */
    var unlocking by mutableStateOf(false)
        private set
    var checkingPIN by mutableStateOf(false)
        private set

    init {
        // Their phone joined with the invitation on the screen.
        viewModelScope.launch { app.coordinator.links.collect { yourPhone?.familyChanged(it.state) } }
    }

    /** The name these screens use, such as Mom. */
    val lovedOne: String get() = name.trim().ifEmpty { app.coordinator.state?.householdName ?: "Your loved one" }

    /** The setup link comes first, unless Porch was opened from it or this tablet has the operator's setup code instead. */
    private val needsLink: Boolean get() = app.device.bedsideActivation == null && app.caregiverPIN.length < 16

    fun start(replacing: Boolean = false) {
        leaveSteps()
        name = ""; error = null; this.replacing = replacing; open = true
        steps = listOf(if (needsLink) SetupStep.LINK else SetupStep.NAME)
    }

    /** A setup that stopped after its PIN, such as when Porch was closed, goes on from its number. */
    fun resume() {
        leaveSteps()
        name = ""; error = null; replacing = false; open = true
        show(SetupStep.NUMBER)
    }

    /** No Porch number yet, and the microphone or camera never asked about: setup stopped after its PIN. */
    val unfinished: Boolean
        get() {
            val state = app.coordinator.state ?: return false
            return state.porchNumber == null && SetupPermissions.neverAsked(app) && app.device.credential(PorchExperience.BEDSIDE) != null
        }

    /** The first screen can be cancelled until the tablet is set up, or while it's being replaced. */
    val canCancel: Boolean get() = steps.size == 1 && (app.device.credential(PorchExperience.BEDSIDE) == null || replacing)
    /** Going back cancels the PIN step's request. Once a replacement has stopped the old Porch ringing, that has to finish
     * first, so the old one can be put back. */
    val canGoBack: Boolean get() = steps.size > 1 && !(replacing && enrolling)
    /** The first screen offers the way out: this tablet can be a family member's instead. A tablet being replaced is
     * already a bedside, and becomes a family device in caregiver mode. */
    val offersFamily: Boolean get() = steps.size == 1 && !replacing

    fun push(step: SetupStep) {
        steps = steps + step
        entered(step)
    }

    fun back() {
        if (!canGoBack) return
        left(step)
        steps = steps.dropLast(1)
    }

    /** Replaces every screen with `step`, so none can be gone back to. */
    fun show(step: SetupStep) {
        leaveSteps()
        steps = listOf(step)
        entered(step)
    }

    fun show(stage: SetupStage) = show(screen(stage))

    /** The first screen from `stage` on that has something to do. */
    fun screen(stage: SetupStage): SetupStep = when {
        stage <= SetupStage.PERMISSIONS && SetupPermissions.needed(app) -> SetupStep.PERMISSIONS
        stage <= SetupStage.PHONE -> SetupStep.CALLING
        stage <= SetupStage.YOUR_PHONE && SetupYourPhone.needed(app.coordinator.state) -> SetupStep.YOUR_PHONE
        else -> SetupStep.DONE
    }

    fun cancel() {
        leaveSteps()
        app.device.saveActivation(null)
        open = false
    }

    /** The way out on the first screen: this tablet is a family member's. */
    fun useAsFamily() {
        cancel()
        app.switchExperience(PorchExperience.FAMILY)
    }

    /** Done. A caregiver puts people on the keypad in caregiver mode. */
    fun finish() {
        leaveSteps()
        open = false
    }

    private fun entered(step: SetupStep) {
        when (step) {
            SetupStep.NUMBER -> number = SetupNumber(app, viewModelScope, { lovedOne }, onError = { error = it }).also { it.load() }
            SetupStep.YOUR_PHONE -> yourPhone = SetupYourPhone(app, viewModelScope, { lovedOne }, onError = { error = it })
            else -> {}
        }
    }

    private fun left(step: SetupStep) {
        when (step) {
            SetupStep.PIN -> { enrollment?.cancel(); enrolling = false }
            SetupStep.NUMBER -> { number?.cancel(); number = null }
            SetupStep.YOUR_PHONE -> { yourPhone?.cancel(); yourPhone = null }
            else -> {}
        }
    }

    private fun leaveSteps() = steps.forEach(::left)

    fun saveLink(text: String) {
        val link = text.trim()
        try {
            BedsideInvitation(link, app.device.defaultOrigin)
        } catch (_: IllegalArgumentException) {
            error = "That isn't a Porch setup link. Copy the whole link from your invitation and paste it here."
            return
        }
        app.device.saveActivation(link)
        push(SetupStep.NAME)
    }

    fun saveName(text: String) {
        val chosen = text.trim()
        if (chosen.isEmpty()) { error = "Enter who this Porch is for, such as Mom."; return }
        name = chosen
        push(SetupStep.PIN)
    }

    /** The caregiver PIN, chosen twice. Continuing sets the tablet up with the server. */
    fun enroll(pin: String, confirmation: String) {
        if (enrolling) return
        if (!pinPattern.matches(pin) || pin != confirmation) { error = "Enter the same six digits in both PIN fields."; return }
        enrolling = true
        enrollment = viewModelScope.launch {
            try {
                val device = app.device
                val invitation = device.bedsideActivation?.let { BedsideInvitation(it, device.defaultOrigin) }
                val origin = invitation?.origin ?: app.settings.getString(serverKey) ?: device.defaultOrigin
                // The same identity on a retry, so a lost response doesn't use the link up.
                val pending = device.pending(PorchExperience.BEDSIDE, origin, invitation?.code ?: "")
                val registration = device.registration(pending) +
                    mapOf("name" to JsonPrimitive(name), "pin" to JsonPrimitive(pin), "platform" to JsonPrimitive("android")) +
                    (invitation?.let { mapOf("activation" to JsonPrimitive(it.code)) } ?: emptyMap())
                // Only the operator's setup code: a tablet being replaced keeps its old household's PIN there.
                val operatorCode = app.caregiverPIN.takeIf { it.length >= 16 }
                // Replacing: the old household stops ringing this tablet first, so its calls can't reach the new one.
                // Push comes with calls (phase 3); until then, a failed attempt has no registration to put back.
                val previous = if (replacing) device.credential(PorchExperience.BEDSIDE) else null
                if (previous != null) device.leaveBedside(previous) { app.service(it) }
                val response = app.service(origin).send("enrollBedside", registration, pin = operatorCode)
                val token = response.credential ?: throw ValidationException("Paste the complete Porch invitation link from your caregiver.")
                // Store the new pairing and its PIN before forgetting the old keypad. A check-in reports whatever keypad is
                // on the tablet, and the PIN write needs the tablet unlocked, so a lock during enrollment can store one and
                // not the other. The old keypad stays until both are stored.
                device.save(FamilyCredential(origin, token, PorchExperience.BEDSIDE))
                try {
                    app.caregiverPIN = pin
                } catch (failure: Exception) {
                    previous?.let(device::save)
                    throw failure
                }
                if (previous != null) { app.forgetBedsideHousehold(); replacing = false }
                app.coordinator.start(); app.coordinator.update(response)
                device.saveActivation(null)
                // Done with this request: moving on mustn't cancel it.
                enrollment = null
                show(SetupStep.NUMBER)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                // A cancelled link answers 410, with the server's own words for it.
                error = failure.message ?: "Couldn't reach Porch. Check the connection and try again."
            } finally {
                enrolling = false
            }
        }
    }

    /** Caregiver mode is open, after the PIN. */
    var caregiver by mutableStateOf(false)
        private set

    fun openGate() { error = null; unlocking = true }
    fun closeGate() { unlocking = false }
    fun closeCaregiver() { caregiver = false }

    /** Checks the PIN with the server, then goes on with setup, or opens caregiver mode, as `CaregiverPINViewController`
     * does on iOS. */
    fun unlock(pin: String) {
        if (checkingPIN) return
        if (!pinPattern.matches(pin)) { error = "Enter six digits."; return }
        val credential = app.device.credential(PorchExperience.BEDSIDE) ?: return
        checkingPIN = true
        viewModelScope.launch {
            try {
                app.service(credential).send("verifyPIN", pin = pin)
                app.caregiverPIN = pin
                unlocking = false
                // A setup that stopped after its PIN goes on; otherwise the PIN opens caregiver mode.
                if (unfinished) resume() else caregiver = true
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                error = failure.message ?: "Couldn't reach Porch. Check the connection and try again."
            } finally {
                checkingPIN = false
            }
        }
    }

    private companion object {
        val pinPattern = Regex("^[0-9]{6}$")
        /** The server a caregiver chose on iOS, before setup links named it. */
        const val serverKey = "porch.native.server"
    }
}
