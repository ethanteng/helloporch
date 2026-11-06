package com.ethanteng.helloporch

import android.media.AudioAttributes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.ethanteng.helloporch.core.CallContact
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.CallTone
import com.ethanteng.helloporch.core.CallTrigger
import com.ethanteng.helloporch.core.FamilyCallRecord
import com.ethanteng.helloporch.core.FamilyCallSession
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.IncomingCallKey
import com.ethanteng.helloporch.core.KeypadAction
import com.ethanteng.helloporch.core.NativeCall
import com.ethanteng.helloporch.core.PorchExperience
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

/**
 * A call ringing on this device while Porch is open, with Answer and Decline: the Android counterpart of iOS's
 * IncomingFamilyCallViewController. On iOS a family phone rings through CallKit instead; Android's calling system and
 * push come at the end of phase 3, and until then a family phone rings here while Porch is open.
 *
 * A drop-in announces itself and connects after a countdown later in phase 3. Until then it waits for Answer, as iOS
 * does when the announcement can't play. [IncomingCallScreen] shows it. Main thread only.
 */
class IncomingCall(
    private val app: PorchApplication,
    val call: FamilyCallRecord,
    private val credential: FamilyCredential,
    val name: String,
    val photo: ByteArray?,
    private val contact: CallContact?,
    private val onAnswered: (FamilyCallSession) -> Unit,
    private val onClosed: (IncomingCall) -> Unit,
) {
    val video = call.mode == NativeCall.Mode.VIDEO
    val dropIn = call.kind == "dropIn"
    var answering by mutableStateOf(false); private set
    var status by mutableStateOf(text(when {
        dropIn -> if (video) "Video drop-in" else "Audio drop-in"
        else -> if (video) "Incoming video call" else "Incoming audio call"
    })); private set
    val answerTitle = text(if (video) "Answer video call" else "Answer audio call")
    val declineTitle = text(if (dropIn) "Don't connect" else "Decline")
    /** On the bedside, how the call-control key answers and declines. */
    val keypadHint: String? = if (credential.role != PorchExperience.BEDSIDE) null
        else slots().digit(KeypadAction.CALL_CONTROL)?.let { CallSlots.symbol(it) }?.let { text("Tap %@ to answer. Hold %@ to decline.", it, it) }

    private val ring = TonePlayer(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
    private val scope = MainScope()
    private val trigger = CallTrigger()
    private val key = IncomingCallKey()
    private var holdJob: Job? = null
    private var closed = false

    fun start() {
        if (!ring.play(CallTone.INCOMING)) status = text("The sound couldn't play. Tap Answer to connect.")
        scope.launch { app.coordinator.links.collect(::check) }
    }

    fun answer() {
        if (answering || closed) return
        answering = true
        ring.stop()
        holdJob?.cancel()
        val session = session()
        scope.launch {
            try {
                val result = session.service.send("acceptCall", mapOf("callID" to JsonPrimitive(call.id), "available" to JsonPrimitive(true)))
                if (!app.onScreen) { app.scope.launch { session.end() }; close(); return@launch }
                app.coordinator.update(result)
                close()
                onAnswered(session.copy(call = result.state?.call ?: call))
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                app.scope.launch { session.end() }
                close()
            }
        }
    }

    fun decline() {
        if (closed) return
        answering = true
        val session = session()
        app.scope.launch { session.end() }
        close()
    }

    /** Porch left the screen while this rang. A call Porch isn't showing can't be answered, so it's declined. */
    fun leftScreen() { if (!answering) decline() }

    /** A keypad key, pressed: the call-control key answers when it's let go, and declines when it's held a second. */
    fun keyDown(digit: Int, keyCode: Int): Boolean {
        if (slots().action(digit) != KeypadAction.CALL_CONTROL) return false
        if (!trigger.keyDown(keyCode) || answering) return true
        decide(key.begin(keyCode, dropIn = false))
        if (!answering) {
            holdJob?.cancel()
            holdJob = scope.launch { delay(1_000); decide(key.held(keyCode)) }
        }
        return true
    }

    fun keyUp(digit: Int, keyCode: Int): Boolean {
        if (slots().action(digit) != KeypadAction.CALL_CONTROL) return false
        trigger.keyUp(keyCode)
        key.release(keyCode)?.let { holdJob?.cancel(); decide(it) }
        return true
    }

    /** A key on the Cell2Jack phone. A serial report is a tap, never a long press, so the call-control key answers. */
    fun cell2jackDigit(digit: Int): String {
        if (answering || slots().action(digit) != KeypadAction.CALL_CONTROL) return "incoming key ignored"
        answer()
        return "answer requested"
    }

    private fun decide(decision: IncomingCallKey.Decision?) {
        if (answering) return
        when (decision) {
            IncomingCallKey.Decision.ANSWER -> answer()
            IncomingCallKey.Decision.DECLINE -> decline()
            null -> {}
        }
    }

    /** The call ended or went away, such as when the caller hung up. */
    private fun check(links: FamilyLinks) {
        if (answering) return
        val current = links.state(credential)?.call
        if (current != null && current.id == call.id && current.state != "ended") return
        close()
    }

    private fun close() {
        if (closed) return
        closed = true
        ring.stop()
        holdJob?.cancel()
        trigger.resetKeys()
        key.cancel()
        onClosed(this)
        scope.cancel()
    }

    private fun session() = FamilyCallSession(credential, call, name, app.service(credential), peerContact = contact)
    private fun slots(): CallSlots = try { CallSlots.load(app.settings, app.photos) } catch (_: Exception) { CallSlots() }
    private fun text(english: String, vararg arguments: Any?) = BedsideText.string(app, english, *arguments)
}
