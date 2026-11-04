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

    fun begin(pin: String) {
        this.pin = pin
        expiresAt = clock().plusSeconds(idleSeconds)
    }

    fun end() {
        pin = null
        expiresAt = Instant.MIN
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
