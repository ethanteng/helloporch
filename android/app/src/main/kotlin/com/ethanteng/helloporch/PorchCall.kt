package com.ethanteng.helloporch

import android.Manifest
import android.content.pm.PackageManager
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.ethanteng.helloporch.core.BedsideLanguage
import com.ethanteng.helloporch.core.CallPreferences
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.CallTone
import com.ethanteng.helloporch.core.FamilyCallSession
import com.ethanteng.helloporch.core.FamilyLinks
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
 * A call between Porch devices, with LiveKit's media: the Android counterpart of iOS's NativeCallViewController for
 * paired calls. The bedside and family phones both use it, calling out or answering.
 *
 * It lives in [CallCenter], not in the screen, so turning the device keeps the call. [CallScreen] shows it. Phone
 * fallback, drop-ins, people added to the call, and hanging up after silence come later in phase 3 (android/PLAN.md).
 * Main thread only.
 */
class PorchCall(
    private val app: PorchApplication,
    session: FamilyCallSession,
    /** Who's on the other end, as this device shows them. */
    val name: String,
    val photo: ByteArray?,
    /** Called once the call has ended and its screen should close. */
    private val onClosed: (PorchCall) -> Unit,
) {
    data class Tile(val identity: String, val name: String, val track: VideoTrack?)

    private var session: FamilyCallSession? = session
    val callID = session.call.id
    val video = session.call.mode == NativeCall.Mode.VIDEO
    val role = session.credential.role
    private val peerID = session.peerID
    private val scope = MainScope()
    val room: Room = LiveKit.create(app)

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

    private var accepted = session.call.state == "accepted"
    private var hasConnectedPeer = false
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

    fun start() {
        scope.launch { room.events.events.collect(::handle) }
        // LiveKit updates these a moment after each change, so the buttons follow them rather than reading them once.
        scope.launch { room.localParticipant::isMicrophoneEnabled.flow.collect { microphoneOn = it } }
        scope.launch { room.localParticipant::isCameraEnabled.flow.collect { cameraOn = it } }
        // A family phone in several families follows the one this call is in.
        scope.launch { app.coordinator.links.collect(::familyChanged) }
        updateKeypadHint()
        if (!accepted) ringback.start()
        connectionJob = scope.launch { connect() }
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
            val join = session.service.send("joinCall", mapOf("callID" to JsonPrimitive(callID)))
            val token = join.token
            val url = join.serverUrl
            if (token == null || url == null) throw CallException("The call invitation is no longer valid.")
            if (!LiveKitAddress.isAllowed(url)) throw CallException("The calling server returned an invalid LiveKit address.")
            if (!granted(Manifest.permission.RECORD_AUDIO) && !ask(listOf(Manifest.permission.RECORD_AUDIO)))
                throw CallException("Allow Porch to use the microphone in Settings → Apps → Porch → Permissions to make calls.")
            if (video && !granted(Manifest.permission.CAMERA) && !ask(listOf(Manifest.permission.CAMERA))) throw CallException(
                "Allow Porch to use the camera in Settings → Apps → Porch → Permissions, or choose Voice in this person's setup.")
            room.connect(url, token)
            enableMicrophone()
            if (video && CallPreferences.startVideoWithCamera(role, app.settings)) room.localParticipant.setCameraEnabled(true)
            mediaReady = true
            controlsEnabled = true
            refresh()
            waitJob?.cancel()
            waitJob = scope.launch {
                // Until phone fallback (later in phase 3), every unanswered call rings for its full wait.
                delay((if (accepted) 30 else session.waitSeconds) * 1_000L)
                if (!hasConnectedPeer) finish(returning("No one joined."))
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            // WebRTC reports a microphone that won't record with an AssertionError, not an exception.
            if (ending) return
            failed = true
            ringback.stop()
            room.disconnect()
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
        if (peers.isNotEmpty()) {
            hasConnectedPeer = true
            waitJob?.cancel()
            ringback.stop()
        } else if (mediaReady && !hasConnectedPeer && !accepted) ringback.start()
        status = when {
            peers.isNotEmpty() -> text(if (!mediaReady) "Connecting audio…" else if (video) "Video call connected" else "Voice call connected")
            accepted -> text("Connecting with %@…", name)
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
    }

    private fun videoOf(participant: Participant): VideoTrack? =
        participant.videoTrackPublications.firstOrNull { (publication, track) -> !publication.muted && track is VideoTrack }?.second as? VideoTrack

    private fun playConnectionCue() {
        if (cuePlayed) return
        cuePlayed = true
        cue.play(CallTone.CONNECTED)
    }

    private fun handle(event: RoomEvent) {
        // A replaced room's late events don't belong to this call.
        if (event.room !== room) return
        when (event) {
            is RoomEvent.ParticipantDisconnected -> participantLeft()
            is RoomEvent.Reconnecting -> if (!ending && !failed) status = text("Reconnecting…")
            is RoomEvent.Disconnected -> if (!ending && mediaReady) finish(returning("The call disconnected."))
            is RoomEvent.ActiveSpeakersChanged -> {}
            else -> refresh()
        }
    }

    private fun participantLeft() {
        if (ending) return
        // The bedside is never left on with only a phone a family caregiver added, such as a bank.
        val bedside = role == PorchExperience.BEDSIDE
        if (hasConnectedPeer && room.remoteParticipants.values.none { !bedside || it.kind != Participant.Kind.SIP }) finish(returning("Call ended."))
        else refresh()
    }

    private fun familyChanged(links: FamilyLinks) {
        val session = session ?: return
        if (ending) return
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

    /** Ends the call: the media first, then the call on the server, then the screen, after `message` shows a moment. */
    fun finish(message: String?) {
        if (ending) return
        ending = true
        ringback.stop()
        cue.stop()
        connectionJob?.cancel()
        waitJob?.cancel()
        controlJob?.cancel()
        permissionsAnswered(false)
        controlsEnabled = false
        endEnabled = false
        status = message ?: text("Ending call…")
        scope.launch {
            connectionJob?.join()
            controlJob?.join()
            room.disconnect()
            session?.end()
            session = null
            tiles = emptyList()
            localTrack = null
            if (message != null) delay(1_500)
            onClosed(this@PorchCall)
            // The screen lets go of its video first.
            delay(500)
            room.release()
            scope.cancel()
        }
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
}
