package com.ethanteng.helloporch

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.ethanteng.helloporch.core.CallContact
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.CallTrigger
import com.ethanteng.helloporch.core.FamilyCallRecord
import com.ethanteng.helloporch.core.FamilyCallSession
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyPerson
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.KeypadAction
import com.ethanteng.helloporch.core.NativeCall
import com.ethanteng.helloporch.core.PorchExperience
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The call this device is ringing for or on, and calls it starts: what iOS's PorchContainerViewController and clock
 * screen do for calls. [PorchRoot] shows [incoming] or [active] over everything else. Main thread only.
 */
class CallCenter(private val app: PorchApplication) {
    var incoming by mutableStateOf<IncomingCall?>(null); private set
    var active by mutableStateOf<PorchCall?>(null); private set
    /** The bedside is starting a call: the key was pressed and the server hasn't answered yet. */
    var opening by mutableStateOf(false); private set
    /** Why a call couldn't start, for the screen that started it. */
    var error by mutableStateOf<String?>(null)
    /** A short note on the bedside's clock, such as "No one is assigned to 3", for 5 seconds. */
    var notice by mutableStateOf<String?>(null)

    /** The bedside's ringing call, so a later snapshot of the same call doesn't ring again. */
    private var incomingID: String? = null
    /** Calls a family phone already rang for, newest last. */
    private val rang = ArrayDeque<String>()
    private val trigger = CallTrigger()
    private var cancelOpening = false
    private var noticeGeneration = 0

    /** Whether a call screen is showing, so nothing else may ring or open. */
    val busy: Boolean get() = incoming != null || active != null || opening

    /** Each snapshot, from the coordinator: rings for a call to this device, as iOS's familyChanged does. */
    fun noteLinks(links: FamilyLinks) {
        if (app.device.experience == PorchExperience.FAMILY) {
            for (link in links.links) {
                val state = link.state ?: continue
                val call = state.call ?: continue
                if (call.state != "pending" || call.to != state.me.id || call.kind != "call" || call.id in rang) continue
                if (busy || !app.onScreen || !app.screenReady) continue
                rang.addLast(call.id)
                while (rang.size > 32) rang.removeFirst()
                ring(call, link.credential, name = call.callerName, photo = null, contact = null)
            }
            return
        }
        val credential = links.credential ?: return
        val state = links.state ?: return
        val call = state.call
        if (call == null || call.state != "pending" || call.to != state.me.id) {
            if (call == null || call.state == "ended") incomingID = null
            return
        }
        if (incomingID == call.id || busy || !app.onScreen || !app.screenReady) return
        incomingID = call.id
        val slots = slots()
        val contact = slots.incomingContact(call, state)
        // Someone without a keypad number still shows the photo Porch has for them.
        val photo = contact?.photoData ?: if (call.source != "phone") state.people.firstOrNull { it.id == call.from }?.photoID?.let { app.photos.familyMembers.data(it) } else null
        ring(call, credential, name = contact?.name ?: call.callerName, photo = photo, contact = contact)
    }

    private fun ring(call: FamilyCallRecord, credential: FamilyCredential, name: String, photo: ByteArray?, contact: CallContact?) {
        val ringing = IncomingCall(app, call, credential, name, photo, contact,
            onAnswered = { session -> show(session, name, photo) },
            onClosed = { if (incoming === it) incoming = null })
        incoming = ringing
        ringing.start()
    }

    /** A family phone calls the bedside person. */
    fun call(person: FamilyPerson, mode: NativeCall.Mode, family: FamilyCredential) {
        if (busy) return
        opening = true
        error = null
        app.scope.launch {
            try {
                val session = app.coordinator.startCall(person, mode, dropIn = false, family = family)
                if (!app.onScreen) { session.end(); return@launch }
                show(session, person.name, person.photoID?.let { app.photos.familyMembers.data(it) })
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = (e as? FamilyServiceException)?.takeIf { it.code == "offline" }?.let { "${person.name} isn't available on Porch right now." }
                    ?: e.message ?: "Couldn't start the call."
            } finally {
                opening = false
            }
        }
    }

    /** The bedside presses a key, or taps a person: calls whoever is on that key, as iOS's call(slot:) does. */
    fun bedsideKey(digit: Int) {
        if (busy || !app.screenReady) return
        val slots = slots()
        val action = slots.action(digit)
        if (action == KeypadAction.MESSAGES) return
        if (action == KeypadAction.CALL_CONTROL || action == KeypadAction.TOGGLE_VIDEO) {
            note(text(if (action == KeypadAction.CALL_CONTROL) "Use this key to answer or end a call."
                else "Use this key to turn your camera off or on during a video call."))
            return
        }
        val contact = slots.contact(digit) ?: run {
            note(text("No one is assigned to %@.\nPlease choose another number.", CallSlots.symbol(digit)))
            return
        }
        call(contact)
    }

    private fun call(contact: CallContact) =
        startBedsideCall(contact.familyMemberID, contact.name, contact.nativeCall.mode, contact.photoData, contact)

    /** The bedside calls a family member who isn't on a key, from its people screen. Until caregiver mode (phase 4)
     * can put people on keys, this is how a new household's bedside calls anyone. */
    fun callFromBedside(person: FamilyPerson) =
        startBedsideCall(person.id, person.name, NativeCall.Mode.VIDEO, person.photoID?.let { app.photos.familyMembers.data(it) }, null)

    private fun startBedsideCall(memberID: String?, name: String, mode: NativeCall.Mode, photo: ByteArray?, contact: CallContact?) {
        if (app.device.credential(PorchExperience.BEDSIDE) == null || opening) {
            error = text("Check People and Drop-in in caregiver mode, then try again.")
            return
        }
        if (!trigger.allowLaunch(SystemClock.elapsedRealtime() / 1_000.0)) return
        cancelOpening = false
        app.cell2jack.record("callStartRequested", "digitSource" to "shared touch/keyboard/USB handler")
        opening = true
        app.scope.launch {
            try {
                // Phone fallback comes later in phase 3. Until then a Porch call rings for the full wait, phone number or not.
                val session = app.coordinator.startCall(memberID, name, mode, dropIn = false, waitSeconds = 45)
                if (cancelOpening || !app.onScreen) {
                    session.end()
                    app.cell2jack.record("pendingCallCancelled")
                    return@launch
                }
                app.cell2jack.record("callSessionCreated")
                show(session.copy(peerContact = contact), name, photo)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (cancelOpening) return@launch
                app.cell2jack.record("callStartFailed", "error" to e.message)
                error = text("Couldn't call %@", name) + "\n\n" + BedsideText.error(app, e.message ?: "Couldn't start the call.")
            } finally {
                opening = false
            }
        }
    }

    /** The call-control key or the receiver while a bedside call is still starting: it doesn't open. */
    fun cancelPendingCall(): String {
        if (!opening) return "no call"
        cancelOpening = true
        opening = false
        return "pending call cancelled"
    }

    /** Porch left the screen. Calls end, as on iOS, until Android's calling system keeps them going (later in phase 3). */
    fun leftScreen() {
        incoming?.leftScreen()
        active?.endCall()
        cancelPendingCall()
    }

    private fun show(session: FamilyCallSession, name: String, photo: ByteArray?) {
        val call = PorchCall(app, session, name, photo, onClosed = { if (active === it) active = null })
        active = call
        call.start()
    }

    private fun note(text: String) {
        notice = text
        val generation = ++noticeGeneration
        app.scope.launch {
            delay(5_000)
            if (noticeGeneration == generation) notice = null
        }
    }

    private fun slots(): CallSlots = try { CallSlots.load(app.settings, app.photos) } catch (_: Exception) { CallSlots() }
    private fun text(english: String, vararg arguments: Any?) = BedsideText.string(app, english, *arguments)
}
