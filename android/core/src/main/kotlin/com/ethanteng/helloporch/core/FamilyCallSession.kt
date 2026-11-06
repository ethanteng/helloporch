package com.ethanteng.helloporch.core

import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonPrimitive

data class FamilyCallSession(
    val credential: FamilyCredential,
    val call: FamilyCallRecord,
    val peerName: String,
    val service: FamilyService,
    val peerContact: CallContact? = null,
    /** How long this caller rings before giving up. Family phones use the household's voicemail wait. */
    val waitSeconds: Int = CallPreferences.defaultVoicemailSeconds,
) {
    /** The other device on this call. */
    val peerID: String get() = if (call.from == credential.deviceID) call.to else call.from

    suspend fun end() {
        try {
            service.send("endCall", mapOf("callID" to JsonPrimitive(call.id)))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
        }
    }

    suspend fun endConfirmed() {
        try {
            service.send("endCall", mapOf("callID" to JsonPrimitive(call.id)))
        } catch (error: FamilyServiceException) {
            // A newer call replaced this one; the server has already released it.
            if (error.status != 404) throw error
        }
    }
}

/** Caregiver mode opened from a family phone. The PIN is kept in memory only and is
 * forgotten after ten idle minutes or when the app leaves the foreground. Main thread only. */
class RemoteCaregiverSession(private val clock: () -> Instant = { Instant.now() }) {
    private var pin: String? = null
    private var expiresAt: Instant = Instant.MIN
    private var staying = false
    private var awaitingAnswer = false

    /** The household as caregiver mode last read it, so the pages show it at once after the phone turns. Forgotten
     * with the PIN. */
    var household: FamilyAdminState? = null

    /** Goes up each time Porch leaves the screen, so a PIN check still on its way then can't open caregiver mode
     * behind it. */
    var departures = 0
        private set

    fun begin(pin: String) {
        this.pin = pin
        expiresAt = clock().plusSeconds(idleSeconds)
    }

    fun end() {
        pin = null
        expiresAt = Instant.MIN
        staying = false
        awaitingAnswer = false
        household = null
    }

    /**
     * Porch is about to open something over itself for the caregiver, such as the photo picker or the share sheet.
     * On Android that's another app's screen, so Porch going behind it isn't the caregiver leaving. iOS shows those
     * inside Porch. One that `answers`, such as a picker, always does when the caregiver comes back through it, even
     * with nothing chosen. Porch back in front without that answer means the caregiver left from it, such as with
     * Home and then Porch from the launcher, and Porch never saw them leave: that ends caregiver mode.
     */
    fun stayThroughNextStop(answers: Boolean = false) { staying = true; awaitingAnswer = answers }

    /** The picker Porch opened answered. */
    fun answered() { awaitingAnswer = false }

    /** What Porch was about to open didn't open, so the next time Porch leaves is the caregiver leaving. */
    fun didNotOpen() { staying = false; awaitingAnswer = false }

    /** Porch left the screen. That ends caregiver mode, unless it was for something Porch opened. */
    fun leftForeground() {
        if (staying) { staying = false; return }
        departures += 1
        end()
    }

    /** Porch was opened again from outside, such as from the launcher, which closes a picker it had opened. The
     * caregiver went somewhere else meanwhile, so caregiver mode ends, as when Porch leaves the screen. */
    fun reopened() {
        departures += 1
        end()
    }

    /** Porch is in front again, so the next time it leaves is the caregiver leaving. */
    fun returned() {
        staying = false
        if (awaitingAnswer) end()
    }

    val isActive: Boolean get() = pin != null && expiresAt > clock()

    /** The PIN for the next request; using it counts as activity. */
    val activePIN: String?
        get() {
            val pin = pin
            if (!isActive || pin == null) { end(); return null }
            expiresAt = clock().plusSeconds(idleSeconds)
            return pin
        }

    companion object {
        private const val idleSeconds = 600L
        val shared = RemoteCaregiverSession()
    }
}
