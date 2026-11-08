package com.ethanteng.helloporch

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.AudioAttributes
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ethanteng.helloporch.core.CallTone
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyMessageThread
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.MessageRecordingCheck
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Records an audio or video message, up to two minutes, for the bedside and sends it, as iOS's
 * MessageComposerViewController does. Audio starts with a beep, like a voicemail greeting. Video uses the front camera
 * here in Porch, not the camera app, which can record in formats an iPad can't play. It lives in a ViewModel, so turning
 * the phone keeps what's being recorded. Sending goes on if the screen closes. Main thread only.
 */
class MessageComposer(application: Application) : AndroidViewModel(application) {
    enum class Phase { IDLE, CAMERA, RECORDING_AUDIO, RECORDING_VIDEO, RECORDED, SENDING }

    private val app = application as PorchApplication
    var phase by mutableStateOf(Phase.IDLE); private set
    var recording by mutableStateOf<MessageRecording?>(null); private set
    var poster by mutableStateOf<Bitmap?>(null); private set
    /** "0:12 / 2:00" while recording. */
    var timerText by mutableStateOf(""); private set
    /** Why the last step didn't work, until it's dismissed. */
    var error by mutableStateOf<String?>(null)
    /** Sent: the screen says so, then closes. */
    var sent by mutableStateOf(false); private set
    /** What to do once Android allows the microphone (and camera). Kept here, so turning the phone while it asks
     * doesn't lose it, such as Leave a message starting to record. */
    var afterPermission: (() -> Unit)? = null
    /** The front camera has finished opening, so Start recording can begin. */
    var cameraReady by mutableStateOf(false); private set
    var recorder: MessageRecorder? = null; private set
    private val upload = MessageUpload()
    private val beep = TonePlayer(AudioAttributes.USAGE_MEDIA)
    private var timer: Job? = null
    /** The beep and the pause before audio starts recording. */
    private var starting: Job? = null
    private var family: FamilyCredential? = null
    private var kind = "message"
    /** The composer screen is showing. This ViewModel lives with the activity, so a send that finishes after the screen
     * closes must not raise "Message sent": that note's OK would close the next visit. */
    private var screenOpen = false

    /** Whom it's for, once, as the screen opens. */
    fun open(family: FamilyCredential, kind: String) {
        if (this.family != null) return
        this.family = family
        this.kind = kind
    }

    /** A beep, then the microphone. A recording under a second isn't kept. */
    fun startAudio() {
        if (phase != Phase.IDLE) return
        val recorder = MessageRecorder(app, video = false, keep = { seconds, _ -> seconds >= 1 })
        this.recorder = recorder
        phase = Phase.RECORDING_AUDIO
        timerText = ""
        starting = viewModelScope.launch {
            try {
                recorder.prepare()
                recorder.onFinish = ::recorded
                beep.play(CallTone.BEEP)
                delay(700)
                if (phase != Phase.RECORDING_AUDIO || this@MessageComposer.recorder !== recorder) return@launch
                if (!recorder.start()) throw MessageRecorder.RecorderException()
                tick(recorder)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                recorder.cancel()
                this@MessageComposer.recorder = null
                phase = Phase.IDLE
                error = "Couldn't start recording. Try again."
            }
        }
    }

    /** The front camera, showing, until Start recording. */
    fun openCamera() {
        if (phase != Phase.IDLE) return
        val recorder = MessageRecorder(app, video = true, keep = { seconds, _ -> seconds >= 1 })
        this.recorder = recorder
        cameraReady = false
        phase = Phase.CAMERA
        viewModelScope.launch {
            try {
                recorder.prepare()
                // The camera couldn't be used, so this would record audio.
                if (!recorder.video) throw MessageRecorder.RecorderException()
                if (phase == Phase.CAMERA && this@MessageComposer.recorder === recorder) cameraReady = true
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                recorder.cancel()
                if (this@MessageComposer.recorder === recorder) {
                    this@MessageComposer.recorder = null
                    cameraReady = false
                    phase = Phase.IDLE
                    error = "Couldn't open the camera. Try again, or record audio."
                }
            }
        }
    }

    fun startVideo() {
        val recorder = recorder ?: return
        if (phase != Phase.CAMERA || !cameraReady) return
        recorder.onFinish = ::recorded
        if (!recorder.start()) { error = "Couldn't start recording. Try again."; return }
        phase = Phase.RECORDING_VIDEO
        tick(recorder)
    }

    /** Stops recording; what was recorded comes back to play, send or record again. */
    fun stop() {
        timer?.cancel()
        val recorder = recorder ?: return
        // Stopped during the beep, before recording began: nothing was recorded, and it mustn't start after all.
        if (!recorder.isRecording) { discard(); return }
        recorder.stop()
    }

    /** The screen said it was sent; a composer opened later starts fresh. */
    fun acknowledgeSent() { sent = false }

    /** The screen came up, or left for somewhere other than a turn of the phone. Leaving throws away what wasn't sent.
     * A send already going finishes, without raising its note on the next visit. */
    fun screenVisibility(open: Boolean) {
        screenOpen = open
        if (!open) discard()
    }

    /** Back to the start, throwing away anything recorded or the camera that was open. */
    fun discard() {
        if (phase == Phase.SENDING) return
        timer?.cancel()
        starting?.cancel()
        beep.stop()
        recorder?.cancel()
        recorder = null
        cameraReady = false
        recording?.file?.delete()
        recording = null
        poster = null
        phase = Phase.IDLE
    }

    fun send() {
        val recording = recording ?: return
        val family = family ?: return
        if (phase != Phase.RECORDED) return
        phase = Phase.SENDING
        // The app's scope, so it finishes even if the screen closes.
        app.scope.launch {
            try {
                val message = upload.send(app, recording, kind, family)
                poster?.let { MessagePosters.save(app, it, message.id) }
                recording.file.delete()
                this@MessageComposer.recording = null
                poster = null
                phase = Phase.IDLE
                if (screenOpen) sent = true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                phase = Phase.RECORDED
                // An upload that took too long, or a message unsent from the thread meanwhile, comes back as expired with
                // "Record the message again", but this recording can still go: Send starts a new message with it.
                val expired = (e as? FamilyServiceException)?.let { it.status == 409 && "expired" in it.message } == true
                error = if (expired) "Sending took too long, so it didn't go. Tap Send to try again."
                    else e.message ?: "Couldn't send the message. Try again."
            }
        }
    }

    private fun tick(recorder: MessageRecorder) {
        timer?.cancel()
        timer = viewModelScope.launch {
            while (true) {
                val seconds = minOf(MessageRecordingCheck.MAX_SECONDS, recorder.elapsed).toInt()
                timerText = "${FamilyMessageThread.length(seconds)} / 2:00"
                delay(500)
            }
        }
    }

    private fun recorded(made: MessageRecording?) {
        timer?.cancel()
        recorder = null
        if (made == null) { phase = Phase.IDLE; return }
        recording = made
        phase = Phase.RECORDED
        if (made.mode == "video") viewModelScope.launch {
            val frame = MessagePosters.frame(made.file.path)
            if (recording?.file == made.file) poster = frame
        }
    }

    /** Closing the screen throws away what wasn't sent; sending goes on. */
    override fun onCleared() {
        screenOpen = false
        timer?.cancel()
        beep.stop()
        recorder?.cancel()
        if (phase != Phase.SENDING) recording?.file?.delete()
    }
}

/**
 * The message being recorded for `recipient`: Record a video or Record audio, then the recording, then Play it back,
 * Send and Record again, as iOS's composer lays it out. A "voicemail" offered after a call that wasn't answered can start
 * recording audio at once.
 */
@Composable
fun MessageComposerScreen(app: PorchApplication, family: FamilyCredential, recipient: String, kind: String, startAudio: Boolean, onDone: () -> Unit) {
    val composer: MessageComposer = viewModel(key = "composer:${family.deviceID}:$kind")
    LaunchedEffect(composer) { composer.open(family, kind) }
    val context = LocalContext.current
    val activity = LocalActivity.current
    // Leaving the screen, but not turning the phone, throws away what wasn't sent.
    DisposableEffect(composer) {
        composer.screenVisibility(true)
        onDispose { if (activity?.isChangingConfigurations != true) composer.screenVisibility(false) }
    }
    // Porch leaving the screen stops a recording, which keeps what was recorded, and closes a camera preview that
    // hasn't started. Turning the phone isn't leaving.
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) {
        if (activity?.isChangingConfigurations == true) return@LifecycleEventEffect
        when (composer.phase) {
            MessageComposer.Phase.CAMERA -> composer.discard()
            MessageComposer.Phase.RECORDING_AUDIO, MessageComposer.Phase.RECORDING_VIDEO -> composer.stop()
            else -> {}
        }
    }
    val close = { composer.discard(); onDone() }
    BackHandler {
        when (composer.phase) {
            MessageComposer.Phase.CAMERA, MessageComposer.Phase.RECORDING_AUDIO, MessageComposer.Phase.RECORDING_VIDEO -> composer.discard()
            else -> close()
        }
    }
    val permissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        val next = composer.afterPermission
        composer.afterPermission = null
        // Backing out of the dialog answers with no results. `all` on that empty map is true.
        if (results.isNotEmpty() && results.values.all { it }) next?.invoke()
        else composer.error = "Allow Porch to use the microphone, and the camera for video, in Settings to record a message."
    }
    fun withPermissions(video: Boolean, action: () -> Unit) {
        val needed = listOfNotNull(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA.takeIf { video })
            .filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
        if (needed.isEmpty()) action() else { composer.afterPermission = action; permissions.launch(needed.toTypedArray()) }
    }
    var started by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(startAudio) {
        if (startAudio && !started && composer.phase == MessageComposer.Phase.IDLE && composer.recording == null) {
            started = true
            withPermissions(video = false) { composer.startAudio() }
        }
    }
    val videoSupported = remember { MessageRecorder.videoSupported(context) }
    var playing by remember { mutableStateOf<MessageMedia?>(null) }

    when (composer.phase) {
        MessageComposer.Phase.CAMERA, MessageComposer.Phase.RECORDING_VIDEO -> CameraRecording(composer, recipient)
        else -> FormScreen(if (kind == "voicemail") "Leave a message" else "Send a message",
            navigation = { TextButton(onClick = close) { Text("Back") } }) {
            when (composer.phase) {
                MessageComposer.Phase.IDLE -> FormSection("Message for $recipient", "Up to two minutes. It waits on their Porch until they play it.") {
                    val video: @Composable () -> Unit = {
                        FormButton("Record a video", onClick = { withPermissions(video = true) { composer.openCamera() } }, enabled = videoSupported,
                            filled = kind != "voicemail")
                    }
                    val audio: @Composable () -> Unit = {
                        FormButton("Record audio", onClick = { withPermissions(video = false) { composer.startAudio() } }, filled = kind == "voicemail")
                    }
                    if (kind == "voicemail") { audio(); video() } else { video(); audio() }
                    if (!videoSupported) Text("This phone's camera can't record a video message every family phone plays, so record audio instead.",
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                MessageComposer.Phase.RECORDING_AUDIO -> FormSection("Recording for $recipient…", "Speak after the beep. You have two minutes.") {
                    Text(composer.timerText, Modifier.fillMaxWidth(), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center)
                    FormButton("Stop recording", onClick = composer::stop)
                }
                else -> {
                    val recording = composer.recording
                    val sending = composer.phase == MessageComposer.Phase.SENDING
                    val length = FamilyMessageThread.length(recording?.durationSeconds?.toInt() ?: 0)
                    val play = { recording?.let { playing = MessageMedia(it.file.path, if (it.mode == "video") "Video message" else "Audio message", it.mode == "video") } }
                    FormSection(if (recording?.mode == "video") "Video message · $length" else "Audio message · $length",
                        if (sending) "Keep Porch open until it finishes sending." else null) {
                        if (recording?.mode == "video") RecordingPoster(composer.poster, playable = !sending, onPlay = { play() })
                        FormButton("Play it back", onClick = { play() }, enabled = !sending, filled = false)
                        FormButton(if (sending) "Sending…" else "Send to $recipient", onClick = composer::send, enabled = !sending)
                        FormButton("Record again", onClick = composer::discard, enabled = !sending, filled = false)
                    }
                }
            }
        }
    }
    playing?.let { MessagePlayerDialog(it) { playing = null } }
    if (composer.sent) {
        val finish = { composer.acknowledgeSent(); onDone() }
        AlertDialog(onDismissRequest = finish, title = { Text("Message sent") },
            text = { Text("It's waiting on $recipient's Porch. See when it's played in Messages with $recipient.") },
            confirmButton = { TextButton(onClick = finish) { Text("OK") } })
    }
    PorchErrorDialog(composer.error) { composer.error = null }
}

/** The front camera, full screen, with Start recording, then the timer and Stop. */
@Composable
private fun CameraRecording(composer: MessageComposer, recipient: String) {
    val recording = composer.phase == MessageComposer.Phase.RECORDING_VIDEO
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(factory = { context ->
            PreviewView(context).apply {
                scaleType = PreviewView.ScaleType.FILL_CENTER
                composer.recorder?.showPreview(surfaceProvider)
            }
        }, modifier = Modifier.fillMaxSize().semantics { contentDescription = "Your camera preview" },
            onRelease = { composer.recorder?.showPreview(null) })
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(20.dp)).padding(horizontal = 20.dp, vertical = 12.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                Text(if (recording) "Recording for $recipient…" else "Video message for $recipient", color = Color.White,
                    style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
                if (recording) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(14.dp).background(Color(0.9f, 0.2f, 0.2f), CircleShape))
                    Text(composer.timerText, color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
                } else Text("Up to two minutes.", color = Color.White.copy(alpha = 0.85f), style = MaterialTheme.typography.bodyMedium)
            }
            Box(Modifier.weight(1f))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = composer::discard, Modifier.weight(1f).heightIn(min = 56.dp),
                    colors = ButtonDefaults.outlinedButtonColors(containerColor = Color.Black.copy(alpha = 0.5f), contentColor = Color.White)) {
                    Text("Cancel", style = MaterialTheme.typography.titleMedium)
                }
                Button(onClick = if (recording) composer::stop else composer::startVideo, Modifier.weight(1f).heightIn(min = 56.dp),
                    enabled = composer.recorder != null && (recording || composer.cameraReady),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0.68f, 0.19f, 0.19f), contentColor = Color.White)) {
                    Text(when {
                        recording -> "Stop recording"
                        composer.cameraReady -> "Start recording"
                        else -> "Starting camera…"
                    }, style = MaterialTheme.typography.titleMedium)
                }
            }
        }
    }
}

/** A recorded video's preview frame, tapped to play it back. */
@Composable
private fun RecordingPoster(image: Bitmap?, playable: Boolean, onPlay: () -> Unit) {
    Box(Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceVariant)
        .then(if (playable) Modifier.clickable(onClick = onPlay) else Modifier), contentAlignment = Alignment.Center) {
        if (image != null) Image(image.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        if (playable) Box(Modifier.size(56.dp).background(Color.Black.copy(alpha = 0.45f), CircleShape), contentAlignment = Alignment.Center) {
            Text("▶", color = Color.White, fontSize = 26.sp)
        }
    }
}
