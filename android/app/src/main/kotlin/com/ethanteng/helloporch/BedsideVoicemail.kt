package com.ethanteng.helloporch

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.CamcorderProfile
import android.media.MediaRecorder
import android.os.Build
import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
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
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.compose.LifecycleEventEffect
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.CallTone
import com.ethanteng.helloporch.core.KeypadAction
import com.ethanteng.helloporch.core.MessageRecordingCheck
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The microphone, or the front camera and microphone, for one message from the bedside, as iOS's BedsideMessageRecorder
 * records it. Recording stops on its own at two minutes, and a recording without any sound isn't kept. Audio is AAC in
 * an `.m4a`; video is CameraX's SD quality (about 640×480) in an `.mp4`, with AAC sound. Main thread only.
 */
class BedsideMessageRecorder(private val context: Context, video: Boolean) {
    /** Becomes false when the camera can't be used, and the message is audio instead. */
    var video = video
        private set
    /** The finished recording, or null when nothing worth sending was recorded. Not called after [cancel]. */
    var onFinish: ((MessageRecording?) -> Unit)? = null
    /** The camera runs while this is resumed: its own, so the camera stops when the message does, not with a screen. */
    private val camera = CameraLifecycle()
    private val preview = Preview.Builder().build()
    private var provider: ProcessCameraProvider? = null
    private var capture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var audio: MediaRecorder? = null
    private var file: File? = null
    private var startedAt = 0L
    private var loudChecks = 0
    /** The loudest a video's sound has been since the last check, from 0 to 1. */
    private var videoAmplitude = 0.0
    private var discarding = false
    private var finished = false

    val isRecording: Boolean get() = startedAt != 0L
    val elapsed: Double get() = if (startedAt == 0L) 0.0 else (SystemClock.elapsedRealtime() - startedAt) / 1_000.0

    class RecorderException : Exception("Couldn't record a message.")

    /** Where the camera shows while recording video, or null while nothing shows it. */
    fun showPreview(surface: Preview.SurfaceProvider?) = preview.setSurfaceProvider(surface)

    /** Sets up the input. Video becomes audio when the camera can't be used. Throws without the microphone. */
    suspend fun prepare() {
        if (!granted(Manifest.permission.RECORD_AUDIO)) throw RecorderException()
        if (video && granted(Manifest.permission.CAMERA) && frontCameraRecordsAAC(context)) {
            var bound: ProcessCameraProvider? = null
            try {
                val provider = ProcessCameraProvider.awaitInstance(context)
                if (discarding) return
                bound = provider
                // About the size of a family phone's video message, so two minutes stays well under the limit.
                val recorder = Recorder.Builder()
                    .setQualitySelector(QualitySelector.from(Quality.SD, FallbackStrategy.higherQualityOrLowerThan(Quality.SD))).build()
                val capture = VideoCapture.withOutput(recorder)
                camera.resume()
                provider.unbindAll()
                provider.bindToLifecycle(camera, CameraSelector.DEFAULT_FRONT_CAMERA, preview, capture)
                this.provider = provider
                this.capture = capture
                return
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                bound?.unbindAll()
                camera.end()
            }
        }
        video = false
        val file = File(context.cacheDir, "bedside-message-${UUID.randomUUID()}.m4a")
        val recorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        try {
            recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioSamplingRate(44_100)
            recorder.setAudioChannels(1)
            recorder.setAudioEncodingBitRate(64_000)
            recorder.setMaxDuration((MessageRecordingCheck.MAX_SECONDS * 1_000).toInt())
            recorder.setOutputFile(file.path)
            // Two minutes stops it, and what was recorded is kept.
            recorder.setOnInfoListener { _, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) { runCatching { audio?.stop() }; finish(true) }
            }
            recorder.setOnErrorListener { _, _, _ -> finish(false) }
            recorder.prepare()
        } catch (e: Exception) {
            recorder.release()
            file.delete()
            throw RecorderException()
        }
        audio = recorder
        this.file = file
        if (discarding) release()
    }

    /** Starts recording, or false when it can't. */
    fun start(): Boolean {
        if (isRecording || discarding || finished) return false
        if (video) {
            val capture = capture ?: return false
            // Checked again here: recording video with sound needs the microphone.
            if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) return false
            val file = File(context.cacheDir, "bedside-message-${UUID.randomUUID()}.mp4")
            this.file = file
            val output = FileOutputOptions.Builder(file).setDurationLimitMillis((MessageRecordingCheck.MAX_SECONDS * 1_000).toLong()).build()
            recording = try {
                capture.output.prepareRecording(context, output).withAudioEnabled().start(ContextCompat.getMainExecutor(context)) { event ->
                    when (event) {
                        is VideoRecordEvent.Status -> videoAmplitude = maxOf(videoAmplitude, event.recordingStats.audioStats.audioAmplitude)
                        // Reaching two minutes, or the camera going away, still leaves a complete file.
                        is VideoRecordEvent.Finalize -> finish(event.error in completeFiles)
                        else -> {}
                    }
                }
            } catch (_: Exception) {
                return false
            }
        } else {
            try { audio?.start() ?: return false } catch (_: Exception) { return false }
        }
        startedAt = SystemClock.elapsedRealtime()
        return true
    }

    /** Called a few times a second while recording: whether something louder than a quiet room was heard. */
    fun sample() {
        if (!isRecording) return
        val amplitude = if (video) videoAmplitude.also { videoAmplitude = 0.0 }
            else (runCatching { audio?.maxAmplitude ?: 0 }.getOrDefault(0)) / 32_767.0
        if (MessageRecordingCheck.loud(amplitude)) loudChecks += 1
    }

    /** Finishes the recording; [onFinish] receives it. */
    fun stop() {
        if (!isRecording) return
        if (video) recording?.stop()
        else finish(runCatching { audio?.stop() }.isSuccess)
    }

    /** Throws the recording away, whether or not it started. */
    fun cancel() {
        discarding = true
        onFinish = null
        if (isRecording) stop() else { release(); finish(false) }
    }

    private fun finish(successfully: Boolean) {
        if (finished) return
        finished = true
        val duration = minOf(MessageRecordingCheck.MAX_SECONDS, elapsed)
        startedAt = 0L
        recording = null
        release()
        val callback = onFinish
        onFinish = null
        val file = file
        if (!successfully || discarding || file == null || !MessageRecordingCheck.keep(duration, loudChecks)) {
            file?.delete()
            callback?.invoke(null)
            return
        }
        callback?.invoke(MessageRecording(file, if (video) "video" else "audio", if (video) "video/mp4" else "audio/mp4", duration))
    }

    /** Lets go of the microphone and the camera. */
    private fun release() {
        audio?.let { runCatching { it.release() } }
        audio = null
        provider?.unbindAll()
        provider = null
        capture = null
        camera.end()
    }

    private fun granted(permission: String) = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /**
     * Whether video from the front camera records its sound as AAC, which every family phone plays. CameraX records the
     * sound the tablet's recording profiles name, and some name AMR (the emulator's do), which iPhones can't play: a
     * tablet like that records the message as audio. A camera without profiles leaves it to CameraX, which uses AAC.
     */
    private fun frontCameraRecordsAAC(context: Context): Boolean = try {
        val manager = context.getSystemService(CameraManager::class.java)
        val front = manager.cameraIdList.firstOrNull { manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT }
        val qualities = listOf(CamcorderProfile.QUALITY_480P, CamcorderProfile.QUALITY_720P, CamcorderProfile.QUALITY_HIGH)
        val codecs = when {
            front == null -> emptyList()
            Build.VERSION.SDK_INT >= 31 -> qualities.flatMap { quality -> CamcorderProfile.getAll(front, quality)?.audioProfiles?.map { it.codec }.orEmpty() }
            else -> front.toIntOrNull()?.let { id ->
                @Suppress("DEPRECATION")
                qualities.filter { CamcorderProfile.hasProfile(id, it) }.map { CamcorderProfile.get(id, it).audioCodec }
            }.orEmpty()
        }
        codecs.all { it == MediaRecorder.AudioEncoder.AAC }
    } catch (_: Exception) {
        true
    }

    private class CameraLifecycle : LifecycleOwner {
        private val registry = LifecycleRegistry(this)
        override val lifecycle: Lifecycle get() = registry
        fun resume() { registry.currentState = Lifecycle.State.RESUMED }
        fun end() { if (registry.currentState.isAtLeast(Lifecycle.State.CREATED)) registry.currentState = Lifecycle.State.DESTROYED }
    }

    private companion object {
        val completeFiles = setOf(VideoRecordEvent.Finalize.ERROR_NONE, VideoRecordEvent.Finalize.ERROR_DURATION_LIMIT_REACHED,
            VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED, VideoRecordEvent.Finalize.ERROR_SOURCE_INACTIVE)
    }
}

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

    val recorder = BedsideMessageRecorder(app, video)
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
                // The call mustn't wait on a recorder that never reports back.
                scope.launch {
                    delay(2_000)
                    val next = closing ?: return@launch
                    closing = null
                    phase = Phase.DONE
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
