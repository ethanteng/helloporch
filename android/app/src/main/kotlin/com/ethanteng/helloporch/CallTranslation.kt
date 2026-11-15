package com.ethanteng.helloporch

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.ethanteng.helloporch.core.BedsideLanguage
import com.ethanteng.helloporch.core.CallTranslationLine
import com.ethanteng.helloporch.core.CallTranslationMessage
import com.ethanteng.helloporch.core.FamilyCallRecord
import com.ethanteng.helloporch.core.FamilyCallSession
import com.ethanteng.helloporch.core.PorchExperience
import io.livekit.android.events.RoomEvent
import io.livekit.android.room.Room
import io.livekit.android.room.participant.Participant
import io.livekit.android.room.track.RemoteAudioTrack
import io.livekit.android.room.track.RemoteTrackPublication
import io.livekit.android.room.track.Track
import io.livekit.android.room.track.TrackPublication
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

/**
 * Live translation on a Porch call with the bedside, as iOS's CallTranslation does (`lib/family/translation.ts`, and the
 * translator in `translator/`). The family member on the call turns it on when they can't get something across, and off
 * again; every call starts with it off. They can change the language the bedside hears for this call, and see what the
 * translator heard and said, so they can tell when something was misheard. The bedside shows "Translation on" and,
 * large, what the translator says to it. Other voices are lowered while the translator speaks.
 *
 * [PorchCall] owns it and forwards its room's data, subscriptions and people. Main thread only.
 */
class CallTranslation(private val app: PorchApplication, private val session: FamilyCallSession, private val scope: CoroutineScope,
    private val room: () -> Room,
    /** What the family calls the bedside's person, such as "Mom". */
    val peerName: String) {
    val bedside = session.credential.role == PorchExperience.BEDSIDE
    private val myID = session.credential.deviceID
    private val callID = session.call.id

    /** The translator is in the call, as it last said or as the room shows. */
    var translatorOn by mutableStateOf(false); private set
    /** Bedside: what the translator just said to it, for a while. */
    var caption by mutableStateOf<String?>(null); private set
    /** Family: the last few things said, newest last. */
    var lines by mutableStateOf<List<CallTranslationLine>>(emptyList()); private set
    /** A change is being asked for. */
    var sending by mutableStateOf(false); private set
    /** "Starting translation…", or why a change didn't go through. */
    var notice by mutableStateOf<String?>(null); private set
    /** The language chosen on this phone for this call, before the server confirms it. */
    var chosen by mutableStateOf<BedsideLanguage?>(null); private set
    /** On or off as last asked, until the call record catches up. */
    private var requested by mutableStateOf<Boolean?>(null)
    private var record by mutableStateOf<FamilyCallRecord?>(null)
    private var captionJob: Job? = null
    /** The translator said it stopped. A speaker event must not bring the banner back while it is still leaving. */
    private var turnedOff = false

    val isOn get() = requested ?: record?.translation?.on ?: translatorOn
    /** Family: Translate shows once the bedside's app can show translation, or while it's on. */
    val offered get() = !bedside && (record?.translationAvailable == true || isOn)
    /** The language the bedside hears: chosen here, or confirmed by the server. Null until then: the bedside's own. */
    val language get() = chosen ?: record?.translation?.language?.let(BedsideLanguage::fromCode)
    val showsCaption get() = bedside && translatorOn
    /** Whether a line was said by this phone's person, for the transcript's "You". */
    fun isMine(line: CallTranslationLine) = line.speaker == myID

    /** Whenever the household's call or the room's people change. */
    fun refresh() {
        record = app.coordinator.state(session.credential)?.call?.takeIf { it.id == callID }
        if (requested != null && record?.translation?.on == requested) requested = null
        // The screen can open after the translator joined, such as a call answered from the lock screen. Its first
        // message isn't sent again, so the room says it's here. An explicit stop stands until that agent has left,
        // or the next one subscribes: otherwise the next speaker event paints "Translation on" again.
        if (!translatorPresent()) {
            if (translatorOn || turnedOff) ended()
            translatorOn = false
            turnedOff = false
        } else if (!turnedOff) translatorOn = true
    }

    /** Data on the call. Only the translator's messages are used, so no one on the call can put words on the bedside. */
    fun received(event: RoomEvent.DataReceived) {
        if (event.topic != CallTranslationMessage.topic || event.participant?.kind != Participant.Kind.AGENT) return
        when (val message = CallTranslationMessage.decode(event.data) ?: return) {
            is CallTranslationMessage.State -> {
                translatorOn = message.on
                turnedOff = !message.on
                if (!message.on) ended()
            }
            is CallTranslationMessage.Line ->
                if (bedside) message.line.said?.let(::showCaption) else lines = (lines + message.line).takeLast(20)
            is CallTranslationMessage.Speaking -> lowerVoices(message.on)
        }
    }

    /** The translator's voice arriving means it's on. */
    fun subscribed(participant: Participant, publication: TrackPublication) {
        if (participant.kind == Participant.Kind.AGENT && publication.kind == Track.Kind.AUDIO) {
            turnedOff = false
            translatorOn = true
        }
    }

    /** Someone left. When it's the translator, captions go and voices return to normal. */
    fun peopleChanged() {
        if (!translatorPresent() && (translatorOn || turnedOff)) {
            translatorOn = false
            turnedOff = false
            ended()
        }
    }

    fun toggle(on: Boolean) = send(on, chosen)

    fun choose(option: BedsideLanguage) {
        chosen = option
        if (isOn) send(true, option)
    }

    private fun send(on: Boolean, language: BedsideLanguage?) {
        if (sending) return
        requested = on; sending = true
        notice = if (on) "Starting translation…" else "Turning translation off…"
        scope.launch {
            try {
                val values = mutableMapOf<String, JsonElement>("callID" to JsonPrimitive(callID), "on" to JsonPrimitive(on))
                language?.let { values["language"] = JsonPrimitive(it.code) }
                app.coordinator.update(session.service.send("setCallTranslation", values))
                notice = null
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                requested = null
                notice = error.message ?: "Translation couldn't change. Try again."
            }
            sending = false
            refresh()
        }
    }

    private fun showCaption(text: String) {
        caption = text
        captionJob?.cancel()
        // It stays a while after the translator stops adding to it.
        captionJob = scope.launch { delay(30_000); caption = null }
    }

    private fun ended() {
        lowerVoices(false)
        captionJob?.cancel(); caption = null
    }

    private fun translatorPresent() = room().remoteParticipants.values.any { it.kind == Participant.Kind.AGENT }

    private fun lowerVoices(lower: Boolean) {
        for (participant in room().remoteParticipants.values) {
            if (participant.kind == Participant.Kind.AGENT) continue
            for ((_, track) in participant.audioTrackPublications) (track as? RemoteAudioTrack)?.setVolume(if (lower) 0.3 else 1.0)
        }
    }

    companion object {
        /** Each side hears only the translation meant for it. LiveKit's server can't unsubscribe someone who joined with
         * auto-subscribe, so the call drops the other side's track itself, whether or not this class exists for it (a
         * family member rung into a call has no translation controls). */
        fun keepOwn(participant: Participant, publication: TrackPublication, bedside: Boolean) {
            val name = publication.name
            if (participant.kind == Participant.Kind.AGENT && name.startsWith("porch-translation") && name != CallTranslationMessage.trackName(bedside)) {
                (publication as? RemoteTrackPublication)?.setSubscribed(false)
            }
        }
    }
}
