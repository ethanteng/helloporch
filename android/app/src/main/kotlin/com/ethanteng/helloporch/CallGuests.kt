package com.ethanteng.helloporch

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.ethanteng.helloporch.core.CallGuestRules
import com.ethanteng.helloporch.core.FamilyCallSession
import com.ethanteng.helloporch.core.FamilyPorchGuest
import com.ethanteng.helloporch.core.FamilyRelative
import com.ethanteng.helloporch.core.FamilyServiceException
import io.livekit.android.room.participant.Participant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

/**
 * Lets a family member on a call with the bedside ring in another family member, who joins with video, as iOS's
 * CallGuestControls does for family: Add someone lists whose Porch can ring now, `addPorchGuest` rings them, and the
 * line under the call's status says how it goes. Their phone gets an ordinary incoming call for the invitation. Anyone in
 * the family on the call can add one at a time, and they stay on if whoever added them leaves. Main thread only.
 */
class CallGuests(private val app: PorchApplication, private val session: FamilyCallSession, private val scope: CoroutineScope) {
    private val callID = session.call.id
    private val bedsideID = CallGuestRules.bedsideID(session.call, session.credential.deviceID)

    /** Add someone, on the call's buttons. */
    var showsAdd by mutableStateOf(false); private set
    /** A ring is being asked for. */
    var adding by mutableStateOf(false); private set
    /** "Ringing David…", or for a few seconds how it went. */
    var status by mutableStateOf<String?>(null); private set
    /** Who Add someone offers, while its list is open. */
    var choices by mutableStateOf<List<FamilyRelative>?>(null); private set
    /** Why a ring couldn't start, until it's dismissed. */
    var error by mutableStateOf<String?>(null)

    /** The family member just rung in, until the household's call shows them, and how each invitation last looked. */
    private var invited: FamilyPorchGuest? = null
    private val states = mutableMapOf<String, String>()
    private var notice: String? = null
    private var noticeJob: Job? = null
    private var peers: List<Participant> = emptyList()

    /** Whenever the room's people or the household's call change. */
    fun refresh(peers: List<Participant> = this.peers) {
        this.peers = peers
        val state = app.coordinator.state(session.credential)
        val call = state?.call?.takeIf { it.id == callID }
        val guest = latest(call?.porchGuest)
        // The bedside's LiveKit identity is its member ID. Someone rung in only once both are in the room.
        val bedsideHere = bedsideID != null && peers.any { it.kind != Participant.Kind.SIP && it.identity?.value == bedsideID }
        showsAdd = CallGuestRules.showsAdd(call, bedsideHere, CallGuestRules.ringable(state?.family.orEmpty(), guest))
        status = if (guest?.state == "ringing") "Ringing ${guest.name}…" else notice
    }

    /** Opens the list of who can be rung in. */
    fun add() {
        val state = app.coordinator.state(session.credential)
        val people = CallGuestRules.ringable(state?.family.orEmpty(), invited ?: state?.call?.takeIf { it.id == callID }?.porchGuest)
        if (people.isNotEmpty()) choices = people
    }

    fun closeChoices() { choices = null }

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
}
