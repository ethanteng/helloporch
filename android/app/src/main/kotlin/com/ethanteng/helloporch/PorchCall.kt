package com.ethanteng.helloporch

import android.Manifest
import android.content.pm.PackageManager
import android.os.SystemClock
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.ethanteng.helloporch.core.BedsideLanguage
import com.ethanteng.helloporch.core.CallContact
import com.ethanteng.helloporch.core.CallInactivityTimer
import com.ethanteng.helloporch.core.CallPreferences
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.CallTone
import com.ethanteng.helloporch.core.FamilyCallSession
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.KeypadAction
import com.ethanteng.helloporch.core.LiveKitAddress
import com.ethanteng.helloporch.core.NativeCall
import com.ethanteng.helloporch.core.PorchExperience
import io.livekit.android.LiveKit
import io.livekit.android.events.RoomEvent
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import io.livekit.android.room.track.VideoTrack
import io.livekit.android.util.flow
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

/**
 * A call, with LiveKit's media: the Android counterpart of iOS's NativeCallViewController. The bedside and family phones
 * both use it, calling out or answering. The bedside also uses it for phone calls: when someone on its keypad doesn't
 * answer Porch, it calls their regular phone instead (phone fallback), and it answers calls to the household's Porch
 * number from regular phones.
 *
 * It lives in [CallCenter], not in the screen, so turning the device keeps the call. [CallScreen] shows it. Main thread
 * only.
 */
class PorchCall(
    private val app: PorchApplication,
    /** The Porch call, or null for a bedside calling a phone straight away. */
    session: FamilyCallSession?,
    /** Who's on the other end, as this device shows them. */
    val name: String,
    val photo: ByteArray?,
    /** Who the bedside is calling, which may still be being said as the call opens. Its ringing and audio wait for it. */
    private val announcement: OutgoingAnnouncement? = null,
    /** The keypad contact the bedside is calling. If it has a phone number, Porch calls that when Porch isn't answered. */
    private val contact: CallContact? = null,
    /** Their phone straight away: their Porch app couldn't ring. */
    private val phoneOnly: Boolean = false,
    /** Called once the call has ended and its screen should close. */
    private val onClosed: (PorchCall) -> Unit,
) {
    data class Tile(val identity: String, val name: String, val track: VideoTrack?)

    private var session: FamilyCallSession? = session
    private val callID = session?.call?.id
    /** A video call. A call that moves to someone's phone becomes a voice call. */
    var video by mutableStateOf(session?.call?.mode == NativeCall.Mode.VIDEO && !phoneOnly); private set
    val role = session?.credential?.role ?: PorchExperience.BEDSIDE
    private val peerID = session?.peerID
    /** Someone calling the household's Porch number from a regular phone, which the bedside answered. */
    private val inboundPhone = session?.call?.source == "phone"
    /** The number the bedside tries when Porch isn't answered. */
    private val phoneNumber = contact?.phoneNumber?.takeIf { role == PorchExperience.BEDSIDE && !inboundPhone }
    private val scope = MainScope()
    /** Replaced by a room of its own when the call moves to their phone, so a late Porch answer can't join it. */
    var room: Room by mutableStateOf(LiveKit.create(app)); private set
    private var roomJobs: List<Job> = emptyList()

    var status by mutableStateOf(text("Connecting…")); private set
    var placeholder by mutableStateOf(text(if (video) "Waiting for video" else "Voice call\nCamera is off")); private set
    /** Whether the person's photo and [placeholder] show, in place of their video. */
    var showingPlaceholder by mutableStateOf(true); private set
    var microphoneOn by mutableStateOf(false); private set
    var cameraOn by mutableStateOf(false); private set
    /** Mute and camera, one change at a time. */
    var controlsEnabled by mutableStateOf(false); private set
    var endEnabled by mutableStateOf(true); private set
    var endTitle by mutableStateOf(text("End call")); private set
    /** The other people with their video: the person this call is with first. */
    var tiles by mutableStateOf<List<Tile>>(emptyList()); private set
    /** This device's camera, for the self view. */
    var localTrack by mutableStateOf<VideoTrack?>(null); private set
    var keypadHint by mutableStateOf<String?>(null); private set
    /** Permissions the call needs and doesn't have yet. The screen asks for them and answers [permissionsAnswered]. */
    var permissionRequest by mutableStateOf<List<String>?>(null); private set

    private var accepted = session?.call?.state == "accepted"
    private var hasConnectedPeer = false
    /** On the call to their phone, from fallback or straight away. */
    private var onPhone = phoneOnly
    private var switchingToPhone = false
    /** Hangs their phone up. Kept until the server confirms it has. */
    private var phoneControlToken: String? = null
    /** Porch turned the camera off when it left the screen, and turns it back on when it's back. */
    private var cameraWhenBack = false
    private var fallbackJob: Job? = null
    private var mediaReady = false
    private var ending = false
    private var failed = false
    private val ringback = Ringback()
    private val cue = TonePlayer()
    private var cuePlayed = false
    private var connectionJob: Job? = null
    private var waitJob: Job? = null
    private var controlJob: Job? = null
    private var permissionAnswer: CompletableDeferred<Boolean>? = null
    /** Hanging up after a stretch of silence, when a caregiver turned it on (off by default; 15 seconds to 30 minutes). */
    private val inactivity = CallInactivityTimer(
        if (CallPreferences.disconnectAfterSilence(app.settings)) CallPreferences.silenceSeconds(app.settings).toDouble() else null,
        clock = SystemClock::elapsedRealtime)

    fun start() {
        watch(room)
        // A family phone in several families follows the one this call is in.
        scope.launch { app.coordinator.links.collect(::familyChanged) }
        updateKeypadHint()
        if (inactivity.timeout != null) scope.launch {
            while (!ending && !failed) { delay(1_000); checkInactivity() }
        }
        announcement?.let(ringback::hold)
        if (!accepted) ringback.start()
        connectionJob = scope.launch { if (phoneOnly) switchToPhone() else connect() }
    }

    /** Follows a room's events, and its microphone and camera, which LiveKit updates a moment after each change, so the
     * buttons follow them rather than reading them once. */
    private fun watch(room: Room) {
        roomJobs.forEach { it.cancel() }
        roomJobs = listOf(
            scope.launch { room.events.events.collect(::handle) },
            scope.launch { room.localParticipant::isMicrophoneEnabled.flow.collect { microphoneOn = it } },
            scope.launch { room.localParticipant::isCameraEnabled.flow.collect { cameraOn = it } },
        )
    }

    /** Porch left the screen and the call goes on: the camera turns off until it's back, as on iOS. */
    fun leftForeground() {
        if (!video || !cameraOn || ending) return
        cameraWhenBack = true
        scope.launch { runCatching { room.localParticipant.setCameraEnabled(false) } }
    }

    /** Porch is back on screen: the camera it turned off comes back on. One turned off during the call stays off. */
    fun returnedToForeground() {
        if (!cameraWhenBack || ending) return
        cameraWhenBack = false
        scope.launch { runCatching { room.localParticipant.setCameraEnabled(true) } }
    }

    fun toggleMicrophone() = changeMedia(camera = false)
    fun toggleCamera() = changeMedia(camera = true)

    /** The End call button, the call-control key, or the receiver put back. */
    fun endCall() {
        if (role == PorchExperience.BEDSIDE) app.cell2jack.record("callEndRequested")
        finish(null)
    }

    /** A keypad key while the call is showing: the call-control key hangs up, and the video key turns the camera off
     * or on. Other keys do nothing during a call. */
    fun keypadDigit(digit: Int) {
        when (slots().action(digit)) {
            KeypadAction.CALL_CONTROL -> endCall()
            KeypadAction.TOGGLE_VIDEO -> if (video && controlsEnabled) toggleCamera()
            else -> {}
        }
    }

    fun permissionsAnswered(granted: Boolean) {
        permissionRequest = null
        permissionAnswer?.complete(granted)
        permissionAnswer = null
    }

    private suspend fun connect() {
        val session = session ?: return
        try {
            val join = session.service.send("joinCall", mapOf("callID" to JsonPrimitive(session.call.id)))
            val token = join.token
            val url = join.serverUrl
            if (token == null || url == null) throw CallException("The call invitation is no longer valid.")
            if (!LiveKitAddress.isAllowed(url)) throw CallException("The calling server returned an invalid LiveKit address.")
            if (!granted(Manifest.permission.RECORD_AUDIO) && !ask(listOf(Manifest.permission.RECORD_AUDIO)))
                throw CallException("Allow Porch to use the microphone in Settings → Apps → Porch → Permissions to make calls.")
            if (video && !granted(Manifest.permission.CAMERA) && !ask(listOf(Manifest.permission.CAMERA))) throw CallException(
                "Allow Porch to use the camera in Settings → Apps → Porch → Permissions, or choose Voice in this person's setup.")
            // Joining switches the audio to a call, which cut the bedside's sentence off on iOS. Android keeps the order.
            announcement?.finished()
            room.connect(url, token)
            enableMicrophone()
            // Allowed just now, on a first call: the call's service needs the microphone named to keep recording locked.
            app.calls.updateService()
            if (video && CallPreferences.startVideoWithCamera(role, app.settings)) room.localParticipant.setCameraEnabled(true)
            mediaReady = true
            controlsEnabled = true
            refresh()
            waitJob?.cancel()
            waitJob = scope.launch {
                // Someone with a phone number gets the fallback wait, then a call to their phone.
                val seconds = when {
                    accepted -> 30
                    phoneNumber == null -> session.waitSeconds
                    else -> CallPreferences.fallbackSeconds(app.settings)
                }
                delay(seconds * 1_000L)
                if (hasConnectedPeer) return@launch
                if (phoneNumber != null && !accepted) fallbackJob = scope.launch { switchToPhone() }
                else finish(returning("No one joined."))
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // WebRTC reports a microphone that won't record with an AssertionError, not an exception.
            if (ending) return
            // Porch couldn't ring them here, so their phone can.
            if (phoneNumber != null && !hasConnectedPeer && !accepted) {
                fallbackJob = scope.launch { switchToPhone() }
                return
            }
            failed = true
            ringback.stop()
            announcement?.stop()
            room.disconnect()
            // The other end stops ringing now, while the explanation stays on this screen.
            this.session?.let { app.scope.launch { it.end() } }
            this.session = null
            tiles = emptyList()
            localTrack = null
            status = text("Couldn't start the call.")
            placeholder = BedsideText.error(app, e.message ?: "Couldn't start the call.")
            showingPlaceholder = true
            controlsEnabled = false
            endTitle = text(if (role == PorchExperience.BEDSIDE) "Back to clock" else "Close")
        }
    }

    /**
     * Turns the microphone on, trying once more after a moment if it won't record. Some tablets' audio service restarts
     * as a call's sound starts and stops (the MUISOO KB10's crashes, in android/PLAN.md), and recording fails until it's
     * back, which WebRTC reports with an AssertionError.
     */
    private suspend fun enableMicrophone() {
        try {
            if (room.localParticipant.setMicrophoneEnabled(true)) return
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            Log.w("Porch", "The microphone didn't start; trying again", e)
        }
        delay(1_500)
        if (!room.localParticipant.setMicrophoneEnabled(true)) throw CallException("Couldn't turn the microphone on. Please try again.")
    }

    private fun refresh() {
        if (ending || failed) return
        updateKeypadHint()
        val peers = room.remoteParticipants.values.toList()
        // A regular phone's leg says how its call is going: connected once it's "active" (or "automation", such as a
        // menu that answers), and gone at "hangup".
        if (inboundPhone || onPhone) {
            val leg = if (inboundPhone) peers.firstOrNull() else peers.firstOrNull { it.identity?.value == PHONE_IDENTITY }
            val sip = leg?.attributes?.get("sip.callStatus")
            when {
                sip == "hangup" -> { finishPhoneCall(); return }
                sip == "active" || (onPhone && sip == "automation") -> {
                    hasConnectedPeer = true
                    waitJob?.cancel()
                    ringback.stop()
                    playConnectionCue()
                    status = text("Phone call connected")
                }
                inboundPhone -> status = text("Connecting audio…")
                else -> {
                    if (mediaReady && !hasConnectedPeer) ringback.start()
                    status = if (hasConnectedPeer) text("Reconnecting phone call…") else text("Calling %@'s phone…", name)
                }
            }
            checkInactivity()
            return
        }
        if (peers.isNotEmpty()) {
            hasConnectedPeer = true
            waitJob?.cancel()
            ringback.stop()
        } else if (mediaReady && !hasConnectedPeer && !accepted && !switchingToPhone) ringback.start()
        status = when {
            peers.isNotEmpty() -> text(if (!mediaReady) "Connecting audio…" else if (video) "Video call connected" else "Voice call connected")
            accepted -> text("Connecting with %@…", name)
            phoneNumber != null -> text("Trying %@ on Porch…\nTheir phone will ring if Porch isn't answered.", name)
            else -> text("Calling %@ on Porch…", name)
        }
        if (video) {
            // An added phone has no video, so it gets no tile.
            tiles = peers.filter { it.kind != Participant.Kind.SIP }
                .sortedBy { if (it.identity?.value == peerID) 0 else 1 }
                .map { peer -> Tile(peer.identity?.value.orEmpty(), peer.name.orEmpty(), videoOf(peer)) }
            localTrack = videoOf(room.localParticipant)
            showingPlaceholder = !(tiles.size > 1 || tiles.firstOrNull()?.track != null)
        }
        if (hasConnectedPeer && mediaReady) playConnectionCue()
        checkInactivity()
    }

    /** Ends the call after the chosen stretch with no one speaking. Silence counts only while connected with someone,
     * and a phone on the call, such as a bank on hold, counts as speaking, as on iOS. */
    private fun checkInactivity(speaking: Boolean = false) {
        if (inactivity.timeout == null || ending || failed) return
        val peers = room.remoteParticipants.values
        val leg = if (inboundPhone) peers.firstOrNull() else peers.firstOrNull { it.identity?.value == PHONE_IDENTITY }
        val sip = leg?.attributes?.get("sip.callStatus")
        // A call with a regular phone counts as connected once that phone has answered.
        val connected = mediaReady && !switchingToPhone && room.state == Room.State.CONNECTED && peers.isNotEmpty() &&
            (!(onPhone || inboundPhone) || sip == "active" || sip == "automation")
        // A phone a family caregiver added to a Porch call, such as a bank's hold music, keeps it from ending as quiet.
        val phoneGuest = !onPhone && !inboundPhone && peers.any { it.kind == Participant.Kind.SIP }
        val speech = speaking || phoneGuest || room.localParticipant.isSpeaking || peers.any { it.isSpeaking }
        if (inactivity.update(connected, speech)) finish(returning("Call ended."))
    }

    private fun videoOf(participant: Participant): VideoTrack? =
        participant.videoTrackPublications.firstOrNull { (publication, track) -> !publication.muted && track is VideoTrack }?.second as? VideoTrack

    private fun playConnectionCue() {
        if (cuePlayed) return
        cuePlayed = true
        announcement?.stop()
        cue.play(CallTone.CONNECTED)
    }

    private fun handle(event: RoomEvent) {
        // A replaced room's late events don't belong to this call.
        if (event.room !== room) return
        when (event) {
            is RoomEvent.ParticipantDisconnected -> participantLeft(event.participant)
            is RoomEvent.Reconnecting -> if (!ending && !failed) { inactivity.reset(); status = text("Reconnecting…") }
            is RoomEvent.Disconnected -> if (!ending && !switchingToPhone && mediaReady) finish(returning("The call disconnected."))
            // Even a word between the timer's ticks starts the silence over.
            is RoomEvent.ActiveSpeakersChanged -> checkInactivity(speaking = event.speakers.isNotEmpty())
            else -> refresh()
        }
    }

    private fun participantLeft(participant: Participant) {
        if (ending) return
        if (onPhone && participant.identity?.value == PHONE_IDENTITY) { finishPhoneCall(); return }
        if (switchingToPhone || onPhone) return
        // The bedside is never left on with only a phone a family caregiver added, such as a bank.
        val bedside = role == PorchExperience.BEDSIDE && !inboundPhone
        if (hasConnectedPeer && room.remoteParticipants.values.none { !bedside || it.kind != Participant.Kind.SIP }) finish(returning("Call ended."))
        else refresh()
    }

    private fun finishPhoneCall() =
        finish(text(if (hasConnectedPeer) "Call ended. Returning to the clock…" else "The phone call ended before it was answered."))

    /**
     * Porch wasn't answered, so the bedside calls their phone, in iOS's order (`switchToPhone`): the Porch call ends as
     * moved to their phone, unless they answered it just now; the Porch room is left for a room of the phone's own, so a
     * late Porch answer can't join; then the phone is dialed once Porch is in that room.
     */
    private suspend fun switchToPhone() {
        val number = phoneNumber ?: return
        if (ending || failed || hasConnectedPeer || accepted) return
        if (!granted(Manifest.permission.RECORD_AUDIO) && !ask(listOf(Manifest.permission.RECORD_AUDIO))) {
            fail(text("Microphone access is required."), text("Allow Porch's microphone in Settings to make a phone call."))
            return
        }
        controlJob?.join()
        if (ending || hasConnectedPeer) return
        // Prefer a Porch answer that arrived just as the wait ran out.
        if (room.remoteParticipants.isNotEmpty()) { refresh(); return }
        session?.let { porch ->
            switchingToPhone = true
            try {
                val response = porch.service.send("fallback", mapOf("callID" to JsonPrimitive(porch.call.id)))
                session = null
                app.coordinator.update(response)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                switchingToPhone = false
                if ((e as? FamilyServiceException)?.code == "answered") {
                    accepted = true
                    waitJob?.cancel()
                    ringback.stop()
                    if (!mediaReady) finish(text("They answered Porch, but this device couldn't connect. Please try again."))
                    else waitJob = scope.launch {
                        delay(30_000)
                        if (!hasConnectedPeer) finish(text("Couldn't finish connecting the Porch call."))
                    }
                } else fail(text("Couldn't switch to their phone."), BedsideText.error(app, e.message ?: "Couldn't switch to their phone."))
                return
            }
        }
        if (ending) return
        val microphone = !mediaReady || microphoneOn
        switchingToPhone = true
        ringback.stop()
        mediaReady = false
        controlsEnabled = false
        video = false
        status = text("Porch wasn't answered. Trying %@'s phone…", name)
        // Leaving releases the camera and microphone before joining the phone's room.
        val porchRoom = room
        room = LiveKit.create(app)
        watch(room)
        porchRoom.disconnect()
        scope.launch { delay(500); porchRoom.release() }
        if (!ending) ringback.start()
        tiles = emptyList()
        localTrack = null
        showingPlaceholder = true
        placeholder = text("Phone call\nCamera is off")
        onPhone = true
        updateKeypadHint()
        try {
            // A caregiver approved this number when they saved it. Without a PIN, the server's own list decides.
            val approval = if (app.caregiverPIN.isNotEmpty()) PhoneApprovals.authorize(app, number) else null
            val prepared = PhoneCalling.prepare(app, number, name, approval)
            phoneControlToken = prepared.controlToken
            announcement?.finished()
            room.connect(prepared.serverUrl, prepared.token)
            if (microphone) enableMicrophone() else room.localParticipant.setMicrophoneEnabled(false)
            app.calls.updateService()
            ringback.start()
            PhoneCalling.start(app, prepared.controlToken)
            switchingToPhone = false
            mediaReady = true
            controlsEnabled = true
            refresh()
            waitJob?.cancel()
            waitJob = scope.launch {
                delay(60_000)
                if (!hasConnectedPeer) finish(text("Their phone didn't answer. Returning to the clock…"))
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            if (ending) return
            switchingToPhone = false
            // Back to clock also hangs up a phone leg made before this failed.
            fail(text("Couldn't connect their phone."), BedsideText.error(app, e.message ?: "Couldn't connect their phone."))
            room.disconnect()
        }
    }

    /** Stops on an explanation, which stays until Back to clock. */
    private fun fail(title: String, detail: String) {
        failed = true
        ringback.stop()
        announcement?.stop()
        status = title
        placeholder = detail
        showingPlaceholder = true
        tiles = emptyList()
        localTrack = null
        controlsEnabled = false
        endTitle = text("Back to clock")
    }

    private fun familyChanged(links: FamilyLinks) {
        val session = session ?: return
        // Moving to their phone ends the Porch call, which isn't this call ending.
        if (ending || switchingToPhone) return
        val state = links.state(session.credential) ?: return
        val call = state.call
        if (call == null || call.id != callID || call.state == "ended") {
            val english = BedsideText.language(app) == BedsideLanguage.ENGLISH
            finish(if (english) call?.reason ?: text("Call ended. Returning to Porch…") else text("Call ended. Returning to Porch…"))
            return
        }
        if (role == PorchExperience.BEDSIDE) refresh()
        if (call.state == "accepted" && !accepted) {
            accepted = true
            waitJob?.cancel()
            ringback.stop()
            refresh()
            waitJob = scope.launch {
                delay(30_000)
                if (!hasConnectedPeer) finish(text("Couldn't connect the call. Please try again."))
            }
        }
    }

    private fun changeMedia(camera: Boolean) {
        if (controlJob != null || !mediaReady || ending || (camera && !video)) return
        controlsEnabled = false
        controlJob = scope.launch {
            try {
                val local = room.localParticipant
                val on = !(if (camera) cameraOn else microphoneOn)
                val changed = if (camera) local.setCameraEnabled(on) else local.setMicrophoneEnabled(on)
                if (ending) return@launch
                if (!changed) throw IllegalStateException("not changed")
                // A chime plays when the camera turns on, as on iOS.
                if (camera && on) cue.play(CallTone.CONNECTED)
                refresh()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                if (!ending) status = text(if (camera) "Couldn't change camera. Try again." else "Couldn't change microphone. Try again.")
            } finally {
                controlJob = null
                if (!ending) controlsEnabled = true
            }
        }
    }

    /**
     * Ends the call: the media first, then the call on the server, then the screen, after `message` shows a moment. A
     * regular phone stays connected until the server confirms it's hung up, so that's tried twice, and then offered as
     * Retry ending phone call.
     */
    fun finish(message: String?) {
        if (ending) return
        ending = true
        ringback.stop()
        announcement?.stop()
        cue.stop()
        connectionJob?.cancel()
        fallbackJob?.cancel()
        waitJob?.cancel()
        controlJob?.cancel()
        permissionsAnswered(false)
        controlsEnabled = false
        endEnabled = false
        status = message ?: text("Ending call…")
        scope.launch {
            connectionJob?.join()
            fallbackJob?.join()
            controlJob?.join()
            room.disconnect()
            val porch = session
            if (porch != null && inboundPhone) {
                if (!twice { porch.endConfirmed() }) { couldNotHangUp(); return@launch }
            } else porch?.end()
            session = null
            tiles = emptyList()
            localTrack = null
            phoneControlToken?.let { ticket ->
                // Its own request, which the call ending doesn't cancel.
                if (!twice { PhoneCalling.end(app, ticket) }) { couldNotHangUp(); return@launch }
                phoneControlToken = null
            }
            if (message != null) delay(1_500)
            onClosed(this@PorchCall)
            // The screen lets go of its video first.
            delay(500)
            room.release()
            scope.cancel()
        }
    }

    /** Whether `action` went through, trying once more if it didn't. */
    private suspend fun twice(action: suspend () -> Unit): Boolean {
        repeat(2) {
            try { action(); return true } catch (e: CancellationException) { throw e } catch (_: Exception) {}
        }
        return false
    }

    private fun couldNotHangUp() {
        failed = true
        ending = false
        endEnabled = true
        endTitle = text("Retry ending phone call")
        status = text("Porch disconnected. Couldn't confirm the phone call ended. Check the internet connection and try again.")
    }

    private suspend fun ask(permissions: List<String>): Boolean {
        val answer = CompletableDeferred<Boolean>()
        permissionAnswer = answer
        permissionRequest = permissions
        return answer.await()
    }

    private fun granted(permission: String) = ContextCompat.checkSelfPermission(app, permission) == PackageManager.PERMISSION_GRANTED

    private fun updateKeypadHint() {
        if (role != PorchExperience.BEDSIDE) return
        val slots = slots()
        keypadHint = listOfNotNull(
            slots.digit(KeypadAction.CALL_CONTROL)?.let { text("Key %@: hang up", CallSlots.symbol(it)) },
            if (video) slots.digit(KeypadAction.TOGGLE_VIDEO)?.let { text("Key %@: video off / on", CallSlots.symbol(it)) } else null,
        ).joinToString(" · ").ifEmpty { null }
    }

    private fun slots(): CallSlots = try { CallSlots.load(app.settings, app.photos) } catch (_: Exception) { CallSlots() }

    /** "Call ended. Returning to the clock…" on the bedside, and "…to Porch" on a family phone. */
    private fun returning(sentence: String) =
        text(if (role == PorchExperience.BEDSIDE) "$sentence Returning to the clock…" else "$sentence Returning to Porch…")

    private fun text(english: String, vararg arguments: Any?) = BedsideText.string(app, english, *arguments)

    private class CallException(message: String) : Exception(message)

    private companion object {
        /** The regular phone in a bedside's call to it (lib/calls/phone.ts). */
        const val PHONE_IDENTITY = "phone"
    }
}
