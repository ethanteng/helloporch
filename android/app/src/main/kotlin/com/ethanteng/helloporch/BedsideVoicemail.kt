package com.ethanteng.helloporch

import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.camera.video.Recording
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.CallTone
import com.ethanteng.helloporch.core.KeypadAction
import com.ethanteng.helloporch.core.MessageRecordingCheck
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * After a Porch call isn't answered, records a message for that person the way a phone's voicemail does, as iOS's
 * BedsideVoicemailViewController does: a spoken prompt, a beep, then up to two minutes of audio or video, matching the
 * call. Finishing (the button, the call-control key, putting the receiver back or the time limit) sends it; saying
 * nothing sends nothing. It goes to the outbox, which sends it once it can. Main thread only.
 */
class BedsideVoicemail(
    private val app: PorchApplication,
    private val memberID: String,
    val name: String,
    val photo: ByteArray?,
    video: Boolean,
    reason: Reason,
    private val onClosed: (BedsideVoicemail) -> Unit,
) {
    enum class Reason { UNANSWERED, UNAVAILABLE }
    private enum class Phase { STARTING, PROMPTING, RECORDING, STOPPING, DONE }

    val recorder = MessageRecorder(app, video)
    private val announcer = Announcer(app)
    private val beep = TonePlayer()
    private val scope = MainScope()
    private var phase = Phase.STARTING
    private var began = false
    private var completed = false
    private var closed = false
    private var timer: Job? = null
    /** What comes next once it closes for something more important, such as an incoming call. */
    private var closing: (() -> Unit)? = null
    private val reasonText = text(if (reason == Reason.UNANSWERED) "%@ didn't answer." else "%@ isn't available right now.", name)
    private val prompt = text(if (reason == Reason.UNANSWERED) "%@ didn't answer. Please leave a message after the beep."
        else "%@ isn't available right now. Please leave a message after the beep.", name)

    val title = text("Leave a message for %@", name)
    var status by mutableStateOf("$reasonText\n${text("Speak after the beep.")}"); private set
    /** "0:12 / 2:00" while recording. */
    var timerText by mutableStateOf<String?>(null); private set
    var sendEnabled by mutableStateOf(false); private set
    var cancelEnabled by mutableStateOf(true); private set
    /** Video shows Mom her camera, with the words at the top and the buttons on dark panels, like a video call. */
    var showingCamera by mutableStateOf(false); private set
    /** "Press # when you're finished.", when a key ends calls. */
    val hint: String? = runCatching { CallSlots.load(app.settings, app.photos).digit(KeypadAction.CALL_CONTROL) }.getOrNull()
        ?.let { text("Press %@ when you're finished.", CallSlots.symbol(it)) }

    /** Starts once its screen shows: the microphone, or the camera, then the prompt and the beep. */
    fun begin() {
        if (began || phase != Phase.STARTING) return
        began = true
        scope.launch {
            try {
                recorder.prepare()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                complete(text("Couldn't record a message."))
                return@launch
            }
            if (phase != Phase.STARTING) { recorder.cancel(); return@launch }
            showingCamera = recorder.video
            phase = Phase.PROMPTING
            announcer.speak(prompt) { beepThenRecord() }
        }
    }

    private fun beepThenRecord() {
        if (phase != Phase.PROMPTING) return
        beep.play(CallTone.BEEP)
        scope.launch {
            delay(((CallTone.BEEP.duration + 0.1) * 1_000).toLong())
            record()
        }
    }

    private fun record() {
        if (phase != Phase.PROMPTING) return
        recorder.onFinish = ::recorded
        if (!recorder.start()) {
            recorder.cancel()
            complete(text("Couldn't record a message."))
            return
        }
        phase = Phase.RECORDING
        sendEnabled = true
        status = text("Recording your message…")
        updateTimer()
        timer = scope.launch {
            while (true) {
                delay(250)
                recorder.sample()
                updateTimer()
            }
        }
    }

    private fun updateTimer() {
        val seconds = minOf(MessageRecordingCheck.MAX_SECONDS, recorder.elapsed).toInt()
        val limit = MessageRecordingCheck.MAX_SECONDS.toInt()
        timerText = "%d:%02d / %d:%02d".format(seconds / 60, seconds % 60, limit / 60, limit % 60)
    }

    /** Sending keeps what was recorded; before the beep, or with Don't send, nothing is kept. */
    fun finish(send: Boolean) {
        when (phase) {
            Phase.STARTING, Phase.PROMPTING -> {
                phase = Phase.DONE
                announcer.stop()
                beep.stop()
                recorder.cancel()
                complete(text("Message not sent."))
            }
            Phase.RECORDING -> {
                phase = Phase.STOPPING
                timer?.cancel()
                sendEnabled = false
                cancelEnabled = false
                if (send) recorder.stop() else { recorder.cancel(); complete(text("Message not sent.")) }
            }
            Phase.STOPPING, Phase.DONE -> {}
        }
    }

    /** The call-control key finishes the message, as hanging up does on a phone. */
    fun keypadDigit(digit: Int) {
        val action = runCatching { CallSlots.load(app.settings, app.photos).action(digit) }.getOrNull()
        if (action == KeypadAction.CALL_CONTROL) finish(send = true)
    }

    /** Putting the receiver back finishes the message: before the beep, nothing is sent. */
    fun hangUp(): String {
        finish(send = true)
        return "message finished"
    }

    /** A recording that's done goes to the outbox, even when the screen already closed for a call. */
    private fun recorded(recording: MessageRecording?) {
        timer?.cancel()
        if (recording == null) { complete(text("No message was recorded.")); return }
        try {
            app.outbox.add(recording, memberID)
            complete(sentConfirmation(app, name), speak = true)
        } catch (_: Exception) {
            recording.file.delete()
            complete(text("Couldn't record a message."))
        }
    }

    /** Shows (and for a sent message, says) how it ended, then returns to the clock. */
    private fun complete(outcome: String, speak: Boolean = false) {
        if (completed || closed) return
        completed = true
        phase = Phase.DONE
        timer?.cancel()
        sendEnabled = false
        cancelEnabled = false
        showingCamera = false
        status = outcome
        timerText = null
        closing?.let { next -> closing = null; close(next); return }
        val later: (Boolean) -> Unit = { scope.launch { delay(1_500); close() } }
        if (speak) announcer.speak(outcome, done = later) else later(true)
    }

    /** Closes at once for an incoming call or leaving Porch, keeping anything already said. */
    fun interrupt(then: () -> Unit) {
        when (phase) {
            Phase.RECORDING, Phase.STOPPING -> {
                closing = then
                if (phase == Phase.RECORDING) finish(send = true)
                // The call mustn't wait on a recorder that never reports back, or find the camera and microphone still
                // held. A recording that finishes after this still goes to the outbox.
                scope.launch {
                    delay(2_000)
                    val next = closing ?: return@launch
                    closing = null
                    phase = Phase.DONE
                    recorder.letGo()
                    close(next)
                }
            }
            Phase.STARTING, Phase.PROMPTING -> {
                phase = Phase.DONE
                announcer.stop()
                beep.stop()
                recorder.cancel()
                close(then)
            }
            Phase.DONE -> close(then)
        }
    }

    private fun close(next: (() -> Unit)? = null) {
        if (closed) { next?.invoke(); return }
        closed = true
        timer?.cancel()
        announcer.stop()
        beep.stop()
        onClosed(this)
        next?.invoke()
        scope.cancel()
    }

    private fun text(english: String, vararg arguments: Any?) = BedsideText.string(app, english, *arguments)

    companion object {
        /** What the bedside says once a message is recorded for this person. */
        fun sentConfirmation(app: PorchApplication, name: String) = BedsideText.string(app, "Your message is on its way to %@.", name)
    }
}

/** The message being recorded: who it's for and why, the timer, and Don't send and Send message, in the night colors. */
@Composable
fun BedsideVoicemailScreen(app: PorchApplication, voicemail: BedsideVoicemail) = LargeType {
    KeepScreenOn()
    // The buttons and keys finish it; Back isn't a way out of a message being recorded, as on iOS.
    BackHandler {}
    CallKeys(app, onDigit = voicemail::keypadDigit, onHangUp = voicemail::hangUp)
    // Like a call, the message ends when Porch leaves the screen; what was said is still sent. Turning the tablet
    // recreates this activity and is still the same screen.
    val activity = LocalActivity.current
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { if (activity?.isChangingConfigurations != true) voicemail.interrupt {} }
    LaunchedEffect(voicemail) { voicemail.begin() }
    val camera = voicemail.showingCamera
    val overlay = if (camera) Modifier.background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(24.dp)) else Modifier
    Box(Modifier.fillMaxSize().background(PorchColors.night)) {
        if (camera) {
            val description = BedsideText.string(app, "Your camera preview")
            AndroidView(factory = { context ->
                PreviewView(context).apply {
                    scaleType = PreviewView.ScaleType.FILL_CENTER
                    voicemail.recorder.showPreview(surfaceProvider)
                }
            }, modifier = Modifier.fillMaxSize().semantics { contentDescription = description },
                onRelease = { voicemail.recorder.showPreview(null) })
        }
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = if (camera) Alignment.TopCenter else Alignment.Center) {
                Column(overlay.widthIn(max = 860.dp).padding(horizontal = 24.dp, vertical = 20.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text(voicemail.title, color = PorchColors.nightText, fontSize = 60.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
                    Text(voicemail.status, color = PorchColors.nightText, fontSize = 38.sp, textAlign = TextAlign.Center)
                    voicemail.timerText?.let { timer ->
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Box(Modifier.size(40.dp).background(Color(0.9f, 0.2f, 0.2f), CircleShape))
                            Text(timer, color = PorchColors.nightText, fontSize = 64.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
                        }
                    }
                    if (!camera) {
                        if (voicemail.photo != null) Photo(voicemail.photo, Modifier.padding(top = 16.dp).size(240.dp))
                        else MicrophoneGlyph(PorchColors.nightText, Modifier.padding(top = 16.dp).size(120.dp))
                    }
                }
            }
            Column(overlay.fillMaxWidth().padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)) {
                voicemail.hint?.let { Text(it, color = PorchColors.nightSecondary, fontSize = 32.sp, textAlign = TextAlign.Center) }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    VoicemailButton(BedsideText.string(app, "Don't send"), PorchColors.nightSurface, voicemail.cancelEnabled, Modifier.weight(1f)) {
                        voicemail.finish(send = false)
                    }
                    VoicemailButton(BedsideText.string(app, "Send message"), Color(0.18f, 0.5f, 0.34f), voicemail.sendEnabled, Modifier.weight(1f)) {
                        voicemail.finish(send = true)
                    }
                }
            }
        }
    }
}

@Composable
private fun VoicemailButton(title: String, color: Color, enabled: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled, modifier = modifier.heightIn(min = 112.dp), shape = RoundedCornerShape(24.dp),
        contentPadding = PaddingValues(20.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color, contentColor = Color.White,
            disabledContainerColor = color.copy(alpha = 0.4f), disabledContentColor = Color.White.copy(alpha = 0.6f))) {
        Text(title, fontSize = 40.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
    }
}

/** A microphone, as iOS's `mic.fill` shows while recording audio for someone without a photo. */
@Composable
private fun MicrophoneGlyph(color: Color, modifier: Modifier) {
    Canvas(modifier) {
        val w = size.width
        val h = size.height
        val stroke = w * 0.07f
        drawRoundRect(color, topLeft = Offset(w * 0.34f, h * 0.06f), size = Size(w * 0.32f, h * 0.52f), cornerRadius = CornerRadius(w * 0.16f))
        drawArc(color, 0f, 180f, useCenter = false, topLeft = Offset(w * 0.2f, h * 0.28f), size = Size(w * 0.6f, h * 0.5f), style = Stroke(stroke))
        drawLine(color, Offset(w * 0.5f, h * 0.78f), Offset(w * 0.5f, h * 0.92f), stroke)
        drawLine(color, Offset(w * 0.34f, h * 0.93f), Offset(w * 0.66f, h * 0.93f), stroke)
    }
}
