package com.ethanteng.helloporch.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive

/**
 * Keypad contacts live on the bedside. The server needs their numbers to let them ring while unknown callers are
 * blocked, so they're reported whenever they differ from its copy, as `reportKeypad` does on iOS. Main thread only,
 * like the coordinator it reports for.
 */
class KeypadNumberReport(
    private val scope: CoroutineScope,
    private val serviceFor: (FamilyCredential) -> FamilyService,
    /** The caregiver PIN, which can be read only while the tablet is unlocked. Empty or null waits for the next snapshot. */
    private val pin: () -> String?,
    /** Milliseconds, from a clock that only moves forward. */
    private val now: () -> Long,
) {
    /** When a failed report may be tried again, for that device and those numbers. */
    private class Retry(val credential: String, val numbers: List<String>, val after: Long)
    private var retry: Retry? = null
    /** The coordinator session a report is in flight for. A paused or restarted coordinator can report again. */
    private var reporting: Long? = null

    fun report(slots: CallSlots, coordinator: FamilyCoordinator) {
        val session = coordinator.session
        if (reporting == session) return
        val state = coordinator.state?.takeIf { it.me.role == PorchExperience.BEDSIDE } ?: return
        val credential = coordinator.credential ?: return
        val numbers = state.callScreening?.keypadNumbersToReport(slots) ?: return
        retry?.let { if (it.credential == credential.credential && it.numbers == numbers && it.after > now()) return }
        val pin = pin()?.ifEmpty { null } ?: return
        reporting = session
        scope.launch {
            try {
                val response = serviceFor(credential).send("setKeypadNumbers", mapOf("numbers" to JsonArray(numbers.map(::JsonPrimitive))), pin = pin)
                // Leaving bedside mode, or pairing a different household, starts a new session. Its snapshot must not be
                // replaced by this one, and its own report must not be stopped.
                if (coordinator.session != session || coordinator.credential?.credential != credential.credential) return@launch
                retry = null; reporting = null
                coordinator.update(response)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                // A wrong PIN or a lockout waits longer, so retries can't use up the caregivers' PIN attempts. The wait is
                // kept even if Porch paused meanwhile; it only applies to this device's credential.
                val status = (error as? FamilyServiceException)?.status
                retry = Retry(credential.credential, numbers, now() + if (status == 403 || status == 429) 600_000 else 30_000)
                if (coordinator.session == session) reporting = null
            }
        }
    }
}
