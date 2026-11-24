package com.ethanteng.helloporch

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.MediaPlayer
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.annotation.DrawableRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ethanteng.helloporch.core.BedsideLanguage
import com.ethanteng.helloporch.core.FamilyLinks
import com.ethanteng.helloporch.core.FamilyMessageThread
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.FamilySnapshot
import com.ethanteng.helloporch.core.FamilyVoiceRecording
import com.ethanteng.helloporch.core.PorchExperience
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.math.roundToLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody

// Caregivers' own voices (lib/family/voices.ts). On their phone, a caregiver chooses the bedside's announcement voice
// and records their own: about a minute of reading aloud, which ElevenLabs makes a voice from. Only the person whose
// voice it is records it, live, after agreeing to its use; the recording isn't kept.

/** The Voice page, or recording your voice opened from it in its place. */
@Composable
fun VoicePages(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, onBack: (() -> Unit)?) {
    var recording by rememberSaveable { mutableStateOf(false) }
    if (recording) { RecordVoicePages(admin, links, onDone = { recording = false }); return }
    FormScreen(CaregiverPage.VOICE.title(admin.onBedside), navigation = onBack?.let { back -> { TextButton(onClick = back) { Text("Back") } } }) {
        VoicePage(app, admin, links, onRecord = { recording = true })
    }
}

/** A choice being saved, shown as chosen until it is. A null `voiceID` is the built-in voice. */
private class Choosing(val voiceID: String?)

/**
 * The bedside language's announcement voices, as iOS's Voice page lists them: your own voice, or a way to record it,
 * then other caregivers' voices, the listed voices and the bedside's built-in voice. Tapping one uses it at once.
 */
@Composable
private fun VoicePage(app: PorchApplication, admin: CaregiverAdmin, links: FamilyLinks, onRecord: () -> Unit) {
    val state = admin.state(links) ?: return
    val snapshot = admin.snapshot(links)
    val language = state.language
    val choices = state.announcementVoices
    if (choices == null) { Text("Voices aren't available right now.", color = MaterialTheme.colorScheme.onSurfaceVariant); return }
    val me = snapshot?.me?.id ?: admin.myID
    val yours = choices.yours(me)
    var choosing by remember { mutableStateOf<Choosing?>(null) }
    var removing by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val preview = remember { VoicePreview(app) }
    DisposableEffect(Unit) { onDispose { preview.stop() } }
    val selected = choosing.let { if (it != null) it.voiceID else choices.selected }
    val ready = choosing == null && !removing

    // Saved at once, as a phone has no Save. What's shown goes back if it isn't.
    fun choose(voiceID: String?) {
        if (!ready || voiceID == selected) return
        preview.stop()
        choosing = Choosing(voiceID)
        error = null
        admin.launch {
            try {
                request("setSpeechVoice", mapOf("language" to JsonPrimitive(language.code), "voiceID" to (voiceID?.let(::JsonPrimitive) ?: JsonNull)))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "Couldn't save. Try again."
            } finally {
                choosing = null
            }
        }
    }

    CaregiverGroup("${language.displayName} announcements") {
        Column(Modifier.selectableGroup()) {
            if (yours == null) {
                CaregiverRow(onClick = onRecord, label = "Your voice, not recorded. Record") {
                    Surface(Modifier.size(40.dp), shape = CircleShape, color = PorchBrand.honey) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(painterResource(R.drawable.ic_mic), contentDescription = null, Modifier.size(22.dp), tint = PorchBrand.accent)
                        }
                    }
                    Column(Modifier.weight(1f)) {
                        Text("Your voice", style = MaterialTheme.typography.titleMedium)
                        Text("Not recorded", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text("Record", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                }
            } else {
                val person = state.people.firstOrNull { it.id == me }
                val photo = person?.let { memberPhoto(app, admin, it) }
                VoiceRow(yours.name, "Your voice", selected == yours.id, ready, avatar = { Avatar(yours.name, photo, 40.dp) }) { choose(yours.id) }
            }
            for (voice in choices.others(me) + choices.listed) {
                HorizontalDivider()
                VoiceRow(voice.name, voice.detail, selected == voice.id, ready) { choose(voice.id) }
            }
            HorizontalDivider()
            VoiceRow("Built-in voice", "On ${bedsideName(snapshot, state.householdName)}’s ${bedsideDevice(snapshot)}", selected == null, ready) { choose(null) }
        }
    }
    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    // A natural or family voice, read by the server. The bedside's built-in voice is only on the bedside.
    FormButton(if (preview.playing) "Playing…" else "Preview", filled = false, icon = R.drawable.ic_speaker,
        enabled = selected != null && !preview.playing, onClick = {
            val voiceID = selected ?: return@FormButton
            error = null
            preview.play(scope, admin, language, voiceID) { error = it }
        })
    if (yours != null) CaregiverGroup {
        IconRow(R.drawable.ic_record_again, "Record again", PorchBrand.accent, MaterialTheme.colorScheme.onSurface, enabled = ready, onClick = onRecord)
        HorizontalDivider()
        IconRow(R.drawable.ic_trash, "Remove my voice", PorchBrand.danger, PorchBrand.danger, enabled = ready, onClick = { confirmRemove = true })
    }
    if (confirmRemove) AlertDialog(onDismissRequest = { confirmRemove = false },
        title = { Text("Remove your voice?") },
        text = { Text("Porch stops using it and deletes it.") },
        confirmButton = {
            TextButton(onClick = {
                confirmRemove = false
                preview.stop()
                removing = true
                error = null
                admin.launch {
                    try { request("removeVoice") } catch (e: CancellationException) { throw e } catch (e: Exception) {
                        error = e.message ?: "Couldn't remove your voice. Try again."
                    } finally { removing = false }
                }
            }) { Text("Remove", color = PorchBrand.danger) }
        },
        dismissButton = { TextButton(onClick = { confirmRemove = false }) { Text("Cancel") } })
}

/** The bedside's name, as family see it, such as "Rose". */
private fun bedsideName(snapshot: FamilySnapshot?, householdName: String): String =
    snapshot?.people?.firstOrNull { it.role == PorchExperience.BEDSIDE }?.name ?: householdName

/** One voice to choose: a radio button, its name and how it sounds. */
@Composable
private fun VoiceRow(title: String, detail: String, selected: Boolean, enabled: Boolean, avatar: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).selectable(selected, enabled = enabled, role = Role.RadioButton, onClick = onClick)
        .padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        RadioButton(selected, onClick = null)
        avatar?.invoke()
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** A row that does something, with its icon first. */
@Composable
private fun IconRow(@DrawableRes icon: Int, title: String, iconColor: Color, textColor: Color, enabled: Boolean, onClick: () -> Unit) {
    CaregiverRow(onClick = if (enabled) onClick else null) {
        Icon(painterResource(icon), contentDescription = null, Modifier.size(22.dp), tint = iconColor)
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, color = textColor,
            fontWeight = if (textColor == PorchBrand.danger) FontWeight.SemiBold else null)
    }
}

/**
 * A voice's sample sentence read by the server (`previewSpeech`), as the bedside's own preview reads it: a drop-in
 * announcement in the bedside language. The clip is downloaded and played, then deleted. Main thread only.
 */
private class VoicePreview(private val app: PorchApplication) {
    var playing by mutableStateOf(false); private set
    private var job: Job? = null
    private var player: MediaPlayer? = null
    private var file: File? = null

    fun play(scope: CoroutineScope, admin: CaregiverAdmin, language: BedsideLanguage, voiceID: String, onError: (String) -> Unit) {
        stop()
        playing = true
        job = scope.launch {
            try {
                val text = language.format("%@ is dropping in with video. Connecting in five seconds.", language.text("A family member"))
                val clip = admin.request("previewSpeech", mapOf("language" to JsonPrimitive(language.code), "voiceID" to JsonPrimitive(voiceID),
                    "text" to JsonPrimitive(text))).clip
                // From storage over HTTPS, or a local test server's own address.
                val origin = admin.origin
                if (clip == null || !(clip.url.startsWith("https://") || (origin != null && clip.url.startsWith("${origin.removeSuffix("/")}/")))) {
                    throw FamilyServiceException(couldNotPlay, 503)
                }
                val saved = withContext(Dispatchers.IO) { download(clip.url) } ?: throw FamilyServiceException(couldNotPlay, 503)
                file = saved
                start(saved)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                job = null
                stop()
                onError(e.message ?: couldNotPlay)
            }
        }
    }

    fun stop() {
        job?.cancel(); job = null
        player?.let { runCatching { it.stop() }; it.release() }; player = null
        file?.delete(); file = null
        playing = false
    }

    private fun download(url: String): File? = client.newCall(Request.Builder().url(url).build()).execute().use { http ->
        val bytes = http.body.bytes()
        if (http.code != 200 || bytes.isEmpty() || bytes.size > 2_000_000) return null
        File(app.cacheDir, "voice-preview-${UUID.randomUUID()}.mp3").also { it.writeBytes(bytes) }
    }

    private fun start(clip: File) {
        val player = MediaPlayer()
        this.player = player
        player.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
        player.setOnCompletionListener { if (this.player === it) { job = null; stop() } }
        player.setOnErrorListener { mp, _, _ -> if (this.player === mp) { job = null; stop() }; true }
        player.setDataSource(clip.path)
        player.prepare()
        player.start()
    }

    private companion object {
        const val couldNotPlay = "Couldn't play the voice. Try again."
        val client: OkHttpClient by lazy { OkHttpClient.Builder().callTimeout(20, TimeUnit.SECONDS).followRedirects(false).build() }
    }
}

/**
 * Records a caregiver's voice on their phone, then makes it into an announcement voice: `voiceUpload`, the file straight
 * to storage, then `createVoice`. MessageRecorder records it as it records messages, up to three minutes. It lives in a
 * ViewModel, as MessageComposer does, so turning the phone keeps the recording going. Main thread only.
 */
class CaregiverVoiceRecorder(application: Application) : AndroidViewModel(application) {
    enum class Phase { READY, STARTING, RECORDING, RECORDED }

    private val app = application as PorchApplication
    var phase by mutableStateOf(Phase.READY); private set
    /** While recording, how long so far; once recorded, its length. */
    var seconds by mutableDoubleStateOf(0.0); private set
    /** The microphone's level, from 0 to 1, ten times a second: the meter, and the recording's waveform. */
    val levels = mutableStateListOf<Float>()
    var recording by mutableStateOf<MessageRecording?>(null); private set
    /** The voice is being made from the recording. */
    var making by mutableStateOf(false); private set
    /** Why recording or making the voice didn't work, shown on the page. */
    var error by mutableStateOf<String?>(null)
    /** The voice was made. The screen goes back to the Voice page and clears it. */
    var made by mutableStateOf(false)
    private var recorder: MessageRecorder? = null
    private var starting: Job? = null
    private var ticker: Job? = null
    /** The pages were left while the voice was being made: the recording goes once that's done. */
    private var abandoned = false

    fun start() {
        if (phase != Phase.READY || making) return
        error = null
        levels.clear()
        seconds = 0.0
        // Kept whatever its length: Stop waits for 20 seconds, and the server says if it's too short.
        val recorder = MessageRecorder(app, video = false, keep = { _, _ -> true }, maxSeconds = FamilyVoiceRecording.MAX_SECONDS)
        this.recorder = recorder
        phase = Phase.STARTING
        starting = viewModelScope.launch {
            try {
                recorder.prepare()
                if (phase != Phase.STARTING || this@CaregiverVoiceRecorder.recorder !== recorder) return@launch
                recorder.onFinish = ::recorded
                if (!recorder.start()) throw MessageRecorder.RecorderException()
                phase = Phase.RECORDING
                tick(recorder)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                recorder.cancel()
                if (this@CaregiverVoiceRecorder.recorder === recorder) {
                    this@CaregiverVoiceRecorder.recorder = null
                    phase = Phase.READY
                    error = "Couldn't start recording. Try again."
                }
            }
        }
    }

    /** Stops recording, once there's enough. Three minutes stops it by itself. */
    fun stop() {
        val recorder = recorder ?: return
        if (phase != Phase.RECORDING || !FamilyVoiceRecording.canStop(recorder.elapsed)) return
        recorder.stop()
    }

    private fun tick(recorder: MessageRecorder) {
        ticker?.cancel()
        ticker = viewModelScope.launch {
            while (this@CaregiverVoiceRecorder.recorder === recorder && !recorder.isFinished) {
                seconds = minOf(FamilyVoiceRecording.MAX_SECONDS, recorder.elapsed)
                levels.add(FamilyVoiceRecording.level(recorder.sample()))
                delay(100)
            }
        }
    }

    private fun recorded(made: MessageRecording?) {
        ticker?.cancel()
        recorder = null
        if (made == null) {
            phase = Phase.READY
            error = "Couldn't record. Try again."
            return
        }
        recording = made
        seconds = made.durationSeconds
        phase = Phase.RECORDED
    }

    /** Back to the start: recording stops and what was recorded is deleted. While the voice is being made, that waits. */
    fun discard() {
        if (making) { abandoned = true; return }
        starting?.cancel(); starting = null
        ticker?.cancel(); ticker = null
        recorder?.cancel(); recorder = null
        recording?.file?.delete(); recording = null
        levels.clear()
        seconds = 0.0
        error = null
        phase = Phase.READY
    }

    /** Uploads the recording and makes the voice, which the server then chooses for the bedside's language. */
    fun make(admin: CaregiverAdmin) {
        val recording = recording ?: return
        if (making || phase != Phase.RECORDED) return
        making = true
        error = null
        viewModelScope.launch {
            try {
                val size = withContext(Dispatchers.IO) { recording.file.length() }
                val created = admin.request("voiceUpload", mapOf("contentType" to JsonPrimitive(FamilyVoiceRecording.CONTENT_TYPE),
                    "sizeBytes" to JsonPrimitive(size), "durationSeconds" to JsonPrimitive((recording.durationSeconds * 10).roundToLong() / 10.0)))
                val target = created.upload
                val pathname = created.pathname
                if (target == null || pathname == null) throw FamilyServiceException("Recording a voice isn't available right now.", 503)
                val status = withContext(Dispatchers.IO) {
                    val request = Request.Builder().url(target.url)
                        .method(target.method, recording.file.asRequestBody(FamilyVoiceRecording.CONTENT_TYPE.toMediaTypeOrNull()))
                    // Exactly the headers the server signed, Content-Type among them.
                    target.headers.forEach { (name, value) -> request.header(name, value) }
                    uploads.newCall(request.build()).execute().use { it.code }
                }
                if (status !in 200..299) throw FamilyServiceException("The recording didn't upload. Check the connection and try again.", status, "upload")
                admin.request("createVoice", mapOf("pathname" to JsonPrimitive(pathname), "consent" to JsonPrimitive(true)))
                // The server doesn't keep it either. Leaving the pages clears the rest.
                recording.file.delete()
                made = true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: "Couldn't make your voice. Try again."
            } finally {
                making = false
                if (abandoned) { abandoned = false; made = false; discard() }
            }
        }
    }

    override fun onCleared() {
        ticker?.cancel()
        recorder?.cancel()
        recording?.file?.delete()
    }

    private companion object {
        val uploads: OkHttpClient by lazy { OkHttpClient.Builder().callTimeout(120, TimeUnit.SECONDS).build() }
    }
}

/** Recording your voice, then listening back and agreeing to its use. Leaving them, but not turning the phone, deletes
 * the recording. */
@Composable
private fun RecordVoicePages(admin: CaregiverAdmin, links: FamilyLinks, onDone: () -> Unit) {
    val voice: CaregiverVoiceRecorder = viewModel(key = "caregiverVoice")
    val activity = LocalActivity.current
    DisposableEffect(voice) { onDispose { if (activity?.isChangingConfigurations != true) voice.discard() } }
    // Porch leaving the screen ends caregiver mode, so the microphone stops now rather than when it's back.
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) {
        if (activity?.isChangingConfigurations != true && voice.phase != CaregiverVoiceRecorder.Phase.RECORDED) voice.discard()
    }
    // Made: the Voice page shows it chosen. The household is read again in case the phone turned while it was made.
    LaunchedEffect(voice.made) { if (voice.made) { voice.made = false; admin.refresh(); onDone() } }
    val close = { voice.discard(); onDone() }
    BackHandler { if (!voice.making) close() }
    if (voice.phase == CaregiverVoiceRecorder.Phase.RECORDED) CheckVoiceScreen(admin, links, voice, close)
    else RecordVoiceScreen(voice, close)
}

/** The script to read, the microphone's level, how long so far, and Start or Stop. */
@Composable
private fun RecordVoiceScreen(voice: CaregiverVoiceRecorder, close: () -> Unit) {
    val context = LocalContext.current
    var refused by rememberSaveable { mutableStateOf(false) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        refused = !granted
        if (granted) voice.start()
    }
    val recording = voice.phase == CaregiverVoiceRecorder.Phase.RECORDING
    val seconds = voice.seconds
    BoxWithConstraints(Modifier.fillMaxSize()) {
        // The script takes the room the controls leave. A short screen, such as a phone on its side, scrolls instead.
        val tall = maxHeight >= 600.dp
        FormScreen("Your voice", navigation = { TextButton(onClick = close) { Text("Back") } }, scrolls = !tall) {
            Text("Read this aloud, somewhere quiet.", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            ScriptCard(if (recording) FamilyVoiceRecording.paragraph(seconds) else null, if (tall) Modifier.weight(1f) else Modifier.height(280.dp))
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                LevelMeter(if (recording) voice.levels.takeLast(METER_BARS) else emptyList())
                Text(FamilyMessageThread.length(seconds.toInt()), fontSize = 34.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurface)
                LinearProgressIndicator(progress = { FamilyVoiceRecording.progress(seconds) }, Modifier.fillMaxWidth().height(6.dp),
                    color = PorchBrand.accent, trackColor = Color(0xFFE6D9C6), strokeCap = StrokeCap.Round, gapSize = 0.dp, drawStopIndicator = {})
                Text("About a minute", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                val enabled = if (recording) FamilyVoiceRecording.canStop(seconds) else voice.phase == CaregiverVoiceRecorder.Phase.READY
                RecordButton(recording, enabled) {
                    when {
                        recording -> voice.stop()
                        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED -> { refused = false; voice.start() }
                        else -> ask.launch(Manifest.permission.RECORD_AUDIO)
                    }
                }
                Text(if (recording) "Stop" else "Start", Modifier.clearAndSetSemantics {}, style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold)
                val problem = if (refused) "Allow the microphone for Porch in Settings." else voice.error
                problem?.let { Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center) }
            }
        }
    }
}

private const val METER_BARS = 17

/** The script on its card, in the site's serif. While recording, the paragraph to read now is dark and the rest muted,
 * and the card keeps it in view. */
@Composable
private fun ScriptCard(current: Int?, modifier: Modifier) {
    val list = rememberLazyListState()
    LaunchedEffect(current) { if (current != null) list.animateScrollToItem(current) }
    Surface(modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp), tonalElevation = 2.dp) {
        // Padded outside the list, so the paragraph before the one in view doesn't peek in above it.
        LazyColumn(Modifier.fillMaxSize().padding(horizontal = 20.dp, vertical = 18.dp), state = list, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            itemsIndexed(FamilyVoiceRecording.script) { index, paragraph ->
                Text(paragraph, fontFamily = newsreader, fontWeight = FontWeight.Medium, fontSize = 21.sp, lineHeight = 30.sp,
                    color = if (current == null || index == current) PorchBrand.ink else Color(0xFF7A6455))
            }
        }
    }
}

/** The microphone's level just now, as bars. */
@Composable
private fun LevelMeter(levels: List<Float>) {
    Canvas(Modifier.width((METER_BARS * 9 - 4).dp).height(40.dp).clearAndSetSemantics {}) {
        val bar = 5.dp.toPx()
        val gap = 4.dp.toPx()
        val shown = List(METER_BARS - levels.size) { 0f } + levels
        shown.forEachIndexed { index, level ->
            val height = maxOf(bar, level * size.height)
            drawRoundRect(PorchBrand.accent, Offset(index * (bar + gap), (size.height - height) / 2), Size(bar, height), CornerRadius(bar / 2))
        }
    }
}

/** A big round button: a red dot to start, a red square to stop. */
@Composable
private fun RecordButton(recording: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val red = PorchBrand.danger.copy(alpha = if (enabled) 1f else 0.35f)
    Surface(onClick = onClick, enabled = enabled, shape = CircleShape, color = PorchBrand.paper,
        border = BorderStroke(4.dp, PorchBrand.ink.copy(alpha = if (enabled) 1f else 0.35f)),
        modifier = Modifier.size(76.dp).semantics { contentDescription = if (recording) "Stop recording" else "Start recording" }) {
        Box(contentAlignment = Alignment.Center) {
            if (recording) Box(Modifier.size(28.dp).background(red, RoundedCornerShape(7.dp)))
            else Box(Modifier.size(56.dp).background(red, CircleShape))
        }
    }
}

/** Listen back, agree that it's your voice, and make it. */
@Composable
private fun CheckVoiceScreen(admin: CaregiverAdmin, links: FamilyLinks, voice: CaregiverVoiceRecorder, close: () -> Unit) {
    val recording = voice.recording ?: return
    var agreed by rememberSaveable { mutableStateOf(false) }
    val state = admin.state(links)
    val bedside = bedsideName(admin.snapshot(links), state?.householdName ?: "your loved one")
    val player = remember(recording.file) { RecordingPlayer(recording.file) }
    DisposableEffect(player) { onDispose { player.release() } }
    FormScreen("Your voice", navigation = { TextButton(onClick = close, enabled = !voice.making) { Text("Back") } }) {
        Text("Listen back", style = porchTitleStyle(MaterialTheme.typography.headlineMedium))
        CaregiverGroup {
            CaregiverRow {
                Surface(onClick = { player.toggle() }, shape = CircleShape, color = PorchBrand.ink,
                    modifier = Modifier.size(44.dp).semantics { contentDescription = if (player.playing) "Pause your recording" else "Play your recording" }) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(painterResource(if (player.playing) R.drawable.ic_pause else R.drawable.ic_play_arrow), contentDescription = null,
                            Modifier.size(22.dp), tint = Color.White)
                    }
                }
                Waveform(voice.levels, player.progress, Modifier.weight(1f).height(34.dp))
                Text(FamilyMessageThread.length(recording.durationSeconds.toInt()), style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        CaregiverGroup {
            Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).toggleable(agreed, enabled = !voice.making, role = Role.Checkbox) { agreed = it }
                .padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Checkbox(agreed, onCheckedChange = null, enabled = !voice.making)
                Text("This is my voice. Porch may use it to speak to $bedside.", Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
            }
        }
        // While it's made, the button says so and nothing else can change.
        Button(onClick = { if (!voice.making) { player.pause(); voice.make(admin) } }, Modifier.fillMaxWidth().heightIn(min = 50.dp), enabled = agreed,
            shape = LocalFormButtonShape.current ?: ButtonDefaults.shape, colors = porchButtonColors()) {
            if (voice.making) {
                CircularProgressIndicator(Modifier.size(20.dp), color = LocalContentColor.current, strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
            }
            Text(if (voice.making) "Making your voice…" else "Use my voice", style = MaterialTheme.typography.titleMedium)
        }
        voice.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        FormPlainButton("Record again", onClick = { player.pause(); voice.discard() }, enabled = !voice.making)
        Text("ElevenLabs makes the voice. The recording isn't kept.", style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** The recording's levels as bars, dark up to where playback has reached. */
@Composable
private fun Waveform(levels: List<Float>, progress: Float, modifier: Modifier) {
    Canvas(modifier.clearAndSetSemantics {}) {
        val gap = 2.dp.toPx()
        val count = ((size.width + gap) / (3.dp.toPx() + gap)).toInt().coerceIn(8, 48)
        val width = (size.width - gap * (count - 1)) / count
        FamilyVoiceRecording.bars(levels, count).forEachIndexed { index, level ->
            val height = maxOf(3.dp.toPx(), level * size.height)
            val played = (index + 0.5f) / count <= progress
            drawRoundRect(if (played) PorchBrand.ink else Color(0xFFC9B8A6), Offset(index * (width + gap), (size.height - height) / 2),
                Size(width, height), CornerRadius(1.dp.toPx()))
        }
    }
}

/** Plays the recording back, and how far it has played. Main thread only. */
private class RecordingPlayer(private val file: File) {
    var playing by mutableStateOf(false); private set
    var progress by mutableFloatStateOf(0f); private set
    private var player: MediaPlayer? = null
    private val ticks = MainScope()
    private var ticking: Job? = null

    fun toggle() { if (playing) pause() else play() }

    private fun play() {
        val player = this.player ?: try {
            MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                setDataSource(file.path)
                setOnCompletionListener { finished() }
                prepare()
            }
        } catch (_: Exception) { return }
        this.player = player
        player.start()
        playing = true
        ticking?.cancel()
        ticking = ticks.launch {
            while (playing) {
                val duration = runCatching { player.duration }.getOrDefault(0)
                if (duration > 0) progress = runCatching { player.currentPosition }.getOrDefault(0).toFloat() / duration
                delay(50)
            }
        }
    }

    private fun finished() {
        playing = false
        progress = 0f
        ticking?.cancel()
    }

    fun pause() {
        if (!playing) return
        runCatching { player?.pause() }
        playing = false
        ticking?.cancel()
    }

    fun release() {
        ticks.cancel()
        playing = false
        player?.release()
        player = null
    }
}
