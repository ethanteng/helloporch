package com.ethanteng.helloporch

import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.ethanteng.helloporch.core.CallGuestRules
import com.ethanteng.helloporch.core.FamilyCallSession
import com.ethanteng.helloporch.core.FamilyPhoneGuest
import com.ethanteng.helloporch.core.FamilyPorchGuest
import com.ethanteng.helloporch.core.FamilyRelative
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.PhoneGuestLeg
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

/**
 * Lets a family member on a call with the bedside add someone, as iOS's CallGuestControls does: another family member
 * on Porch, who rings like an ordinary call and joins with video, or, for caregivers, a regular phone, such as a bank
 * that needs Mom on the line, with a keypad for its menus and its own hang-up. The server rings or dials them into the
 * call's room. A family member stays on if whoever added them leaves; a phone stays on only while this phone does, and
 * only this phone sees its number. Anyone in the family on the call can add one of each at a time. Main thread only.
 */
class CallGuests(private val app: PorchApplication, private val session: FamilyCallSession, private val scope: CoroutineScope,
    private val room: () -> Room) {
    private val callID = session.call.id
    private val myID = session.credential.deviceID
    private val bedsideID = CallGuestRules.bedsideID(session.call, myID)

    /** Add someone, on the call's buttons, and what it says: "Add a phone" when no family can be rung. */
    var showsAdd by mutableStateOf(false); private set
    var addTitle by mutableStateOf("Add someone"); private set
    /** A ring or a dial is being asked for. */
    var adding by mutableStateOf(false); private set
    /** "Ringing David…", or for a few seconds how it went. */
    var status by mutableStateOf<String?>(null); private set
    /** "Calling Bank…", "Bank is on the call", or for a few seconds how it ended. */
    var phoneStatus by mutableStateOf<String?>(null); private set
    /** The phone this one added, while it's on the call: its keypad and its own hang-up show. */
    var phone by mutableStateOf<FamilyPhoneGuest?>(null); private set
    /** Its keypad works once it has answered. */
    var phoneAnswered by mutableStateOf(false); private set
    var hangingUp by mutableStateOf(false); private set
    /** Who Add someone offers, while its list is open, and whether it offers a phone number too. */
    var choices by mutableStateOf<List<FamilyRelative>?>(null); private set
    var choicesIncludePhone by mutableStateOf(false); private set
    /** The form for the phone number to add, while it's open. */
    var phoneForm by mutableStateOf(false); private set
    /** The added phone's keypad, while it's open, and the keys sent to it so far. */
    var keypad by mutableStateOf(false); private set
    var keysPressed by mutableStateOf(""); private set
    /** Why a ring, a dial or a hang-up didn't go through, until it's dismissed. */
    var error by mutableStateOf<String?>(null)

    /** The family member just rung in, until the household's call shows them, and how each invitation last looked. */
    private var invited: FamilyPorchGuest? = null
    private val states = mutableMapOf<String, String>()
    private var notice: String? = null
    private var noticeJob: Job? = null
    private var phoneNotice: String? = null
    private var phoneNoticeJob: Job? = null
    /** The added phone's leg in the room. */
    private var leg: PhoneGuestLeg? = null
    /** Phones this one already saw end, so a check-in from before the hang-up can't bring one back. */
    private val finished = mutableSetOf<String>()
    private var dialing = false
    /** The phone this one is hanging up. The server takes it out of the room before it answers, so its leaving isn't the
     * other end hanging up. */
    private var hangingUpID: String? = null
    private var watchJob: Job? = null
    /** Keys go out one at a time, in the order pressed. */
    private val keys = Channel<Char>(Channel.UNLIMITED)
    private var peers: List<Participant> = emptyList()

    init {
        scope.launch {
            for (key in keys) {
                val code = CallGuestRules.dtmfCode(key) ?: continue
                val sent = runCatching { room().localParticipant.publishDtmf(code, key.toString()).getOrThrow() }
                if (sent.isFailure) error = "Couldn't send that key. Try again."
            }
        }
    }

    /** Whenever the room's people or the household's call change. */
    fun refresh(peers: List<Participant> = this.peers) {
        this.peers = peers
        val state = app.coordinator.state(session.credential)
        val call = state?.call?.takeIf { it.id == callID }
        // A phone this one added, such as after the call screen came back, is followed again.
        call?.phoneGuest?.takeIf { phone == null && it.addedBy == myID && it.id !in finished }?.let(::track)
        phone?.let { added ->
            val leg = leg ?: return@let
            val present = peers.firstOrNull { it.identity?.value == added.identity }
            if (!leg.observe(present != null, present?.attributes?.get("sip.callStatus"), now())) phoneAnswered = leg.answered
            else if (hangingUpID == added.id) { end(added); showPhone("You hung up ${added.label}.") }
            else legEnded(added, leg.answered)
        }
        val guest = latest(call?.porchGuest)
        // The bedside's LiveKit identity is its member ID. Someone is added only once both are in the room.
        val bedsideHere = bedsideID != null && peers.any { it.kind != Participant.Kind.SIP && it.identity?.value == bedsideID }
        val ringable = CallGuestRules.ringable(state?.family.orEmpty(), guest)
        val canDial = canDial()
        showsAdd = CallGuestRules.showsAdd(call, bedsideHere, ringable, canDial)
        addTitle = if (ringable.isNotEmpty()) "Add someone" else "Add a phone"
        status = if (guest?.state == "ringing") "Ringing ${guest.name}…" else notice
        phoneStatus = phone?.let { if (phoneAnswered) "${it.label} is on the call" else "Calling ${it.label}…" } ?: phoneNotice
    }

    /** Family on Porch first, since they join with video, then a phone number. With only one choice, it opens directly. */
    fun add() {
        val state = app.coordinator.state(session.credential)
        val people = CallGuestRules.ringable(state?.family.orEmpty(), invited ?: state?.call?.takeIf { it.id == callID }?.porchGuest)
        val canDial = canDial()
        when {
            people.isEmpty() && canDial -> phoneForm = true
            people.isNotEmpty() -> { choicesIncludePhone = canDial; choices = people }
        }
    }

    fun closeChoices() { choices = null }

    fun choosePhone() { choices = null; phoneForm = true }

    fun closePhoneForm() { phoneForm = false }

    fun ring(person: FamilyRelative) {
        choices = null
        if (adding) return
        adding = true
        scope.launch {
            try {
                val response = session.service.send("addPorchGuest", mapOf("callID" to JsonPrimitive(callID), "memberID" to JsonPrimitive(person.id)))
                app.coordinator.update(response)
                response.porchGuest?.let { invited = it; states[it.id] = it.state }
            } catch (e: CancellationException) {
                throw e
            } catch (e: FamilyServiceException) {
                error = e.message
            } catch (e: Exception) {
                error = "Couldn't reach Porch. Check the connection and try again."
            } finally {
                adding = false
                refresh()
            }
        }
    }

    /**
     * Dials `number` (E.164) into the call as `label`, such as "Bank". Throws why it couldn't, for the form to show. A
     * dial that fails on the server's side may still be ringing, and the server keeps tracking it, so another number
     * waits for the next check-in to show it here first.
     */
    suspend fun dial(label: String, number: String) {
        if (dialing) throw FamilyServiceException("Porch is still checking the last number. Try again in a moment.", 409)
        dialing = true
        adding = true
        var settle = 0L
        try {
            val response = try {
                session.service.send("addPhoneGuest", mapOf("callID" to JsonPrimitive(callID), "phoneNumber" to JsonPrimitive(number),
                    "label" to JsonPrimitive(label)))
            } catch (e: FamilyServiceException) {
                if (e.status >= 500) settle = 6_000
                throw e
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                settle = 6_000
                throw FamilyServiceException("Couldn't reach Porch. Check the connection and try again.", 0)
            }
            app.coordinator.update(response)
            track(response.phoneGuest ?: throw FamilyServiceException("Couldn't add that phone number.", 502))
            phoneForm = false
        } finally {
            val wait = settle
            scope.launch {
                delay(wait)
                dialing = false
                adding = false
                refresh()
            }
        }
    }

    /** Hangs up the phone this one added. It stays on the call while the server says otherwise. */
    fun hangUp() {
        val current = phone ?: return
        if (hangingUp) return
        hangingUp = true
        hangingUpID = current.id
        scope.launch {
            try {
                val response = session.service.send("removePhoneGuest", mapOf("callID" to JsonPrimitive(callID), "guestID" to JsonPrimitive(current.id)))
                app.coordinator.update(response)
                if (phone?.id == current.id) {
                    end(current)
                    showPhone("You hung up ${current.label}.")
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: FamilyServiceException) {
                error = e.message
            } catch (e: Exception) {
                error = "Couldn't reach Porch. Check the connection and try again."
            } finally {
                hangingUp = false
                hangingUpID = null
                refresh()
            }
        }
    }

    fun openKeypad() { if (phone != null && phoneAnswered) { keysPressed = ""; keypad = true } }

    fun closeKeypad() { keypad = false }

    /** A key on the added phone's keypad, for menus such as "press 1 for your account balance". */
    fun press(key: Char) {
        if (CallGuestRules.dtmfCode(key) == null || phone == null) return
        keysPressed = (keysPressed + key).takeLast(24)
        keys.trySend(key)
    }

    /** A caregiver can add one phone at a time. */
    private fun canDial() = app.coordinator.state(session.credential)?.canAddPhoneGuests == true && phone == null && !dialing

    private fun track(added: FamilyPhoneGuest) {
        phone = added
        phoneAnswered = false
        phoneNotice = null
        leg = PhoneGuestLeg(now())
        watchJob?.cancel()
        // A phone that never joins is caught once its time is up, even if nothing in the room changes.
        watchJob = scope.launch {
            delay((PhoneGuestLeg.JOIN_SECONDS * 1_000).toLong())
            refresh()
        }
    }

    private fun legEnded(ended: FamilyPhoneGuest, answered: Boolean) {
        end(ended)
        showPhone(if (answered) "${ended.label} hung up." else "${ended.label} didn't answer.")
        // Frees the call for another number. The server also checks the room, so a failure here is harmless.
        scope.launch {
            runCatching { session.service.send("removePhoneGuest", mapOf("callID" to JsonPrimitive(callID), "guestID" to JsonPrimitive(ended.id))) }
        }
    }

    private fun end(ended: FamilyPhoneGuest) {
        finished += ended.id
        phone = null
        phoneAnswered = false
        leg = null
        keypad = false
        watchJob?.cancel()
    }

    /** The latest invitation, from the server once it has caught up with this phone. A change this phone sees happen is
     * said for a few seconds; one that was already over when the call opened isn't. */
    private fun latest(server: FamilyPorchGuest?): FamilyPorchGuest? {
        invited?.let { local -> if (server?.id == local.id) invited = null }
        val guest = invited ?: server ?: return null
        val previous = states.put(guest.id, guest.state)
        if (previous != null && previous != guest.state) CallGuestRules.notice(guest)?.let(::show)
        return guest
    }

    private fun show(message: String) {
        notice = message
        noticeJob?.cancel()
        noticeJob = scope.launch {
            delay(5_000)
            notice = null
            refresh()
        }
    }

    private fun showPhone(message: String) {
        phoneNotice = message
        phoneNoticeJob?.cancel()
        phoneNoticeJob = scope.launch {
            delay(5_000)
            phoneNotice = null
            refresh()
        }
    }

    private fun now() = SystemClock.elapsedRealtime() / 1_000.0
}
