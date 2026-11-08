package com.ethanteng.helloporch

import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.annotation.OptIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.compose.ContentFrame
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyMessage
import com.ethanteng.helloporch.core.KeypadAction
import com.ethanteng.helloporch.core.ReceivedText
import java.util.Locale
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Plays waiting messages one after another until none are left or someone stops it, then shows and reads waiting texts
 * the same way, as iOS's MessagePlayerViewController does: the chime and who it's from, then the message or the text's
 * words, and only one played or read to the end leaves the queue. Stop, the messages key or the call key stop it, and
 * leave the rest waiting. A call that comes in takes over. Main thread only.
 */
class MessagePlayback(private val app: PorchApplication, messages: List<FamilyMessage>, texts: List<ReceivedText>,
    private val slots: CallSlots, private val onFinish: (MessagePlayback) -> Unit) {
    private val queue = ArrayDeque(messages)
    private val textQueue = ArrayDeque(texts)
    /** The text showing: being announced, read, or held on screen a moment after. */
    var currentText by mutableStateOf<ReceivedText?>(null)
        private set
    /** A text read to the end stays on screen this long, for anyone still reading it, before the next one. */
    private var hold: Job? = null
    /** The language of the words showing, found while who they're from is said. */
    private var foreign: Deferred<String?>? = null
    private val announcer = Announcer(app)
    private var player: ExoPlayer? = null
    /** The message showing: being announced, or playing. */
    var current by mutableStateOf<FamilyMessage?>(null)
        private set
    /** Whether a video is playing, which covers the screen with who it's from in a banner. */
    var video by mutableStateOf<ExoPlayer?>(null)
        private set
    var ended = false
        private set
    /** A call took over. That is not Stop, so what's still waiting can start by itself afterwards. */
    var interrupted = false
        private set

    fun start() = playNext()

    /** Who it's from and when, as the screen shows them. */
    fun title(message: FamilyMessage) = BedsideText.string(app, if (message.kind == "voicemail") "Voicemail from %@" else "Message from %@",
        BedsideMessages.sender(app, message, slots).first)
    fun detail(message: FamilyMessage) = BedsideText.string(app, "Sent %@", BedsideMessages.sentText(app, message.sentAt))
    fun photo(message: FamilyMessage): ByteArray? {
        // Someone without a keypad number still shows the photo Porch has for them.
        val contact = BedsideMessages.sender(app, message, slots).second.contact
        return contact?.photoData ?: if (message.fromPhone) null else FamilyPhotos.data(app, message.from)
    }

    /** Who a text is from and when, and what the screen says about its words. */
    fun textTitle(text: ReceivedText) = BedsideText.string(app, "Text from %@", BedsideMessages.textSender(app, text.from, slots).first)
    fun textDetail(text: ReceivedText) = BedsideText.string(app, "Sent %@", BedsideMessages.sentText(app, text.sentAt))
    fun textPhoto(text: ReceivedText): ByteArray? = BedsideMessages.textSender(app, text.from, slots).second?.photoData
    /** That it was translated, and from what, then what came with it. */
    fun textNotes(text: ReceivedText): List<String> =
        listOfNotNull(if (text.translated) BedsideMessages.translatedNote(app, text.sourceLanguage) else null) + BedsideMessages.attachmentNotes(app, text)

    private fun playNext() {
        if (ended) return
        hold?.cancel(); hold = null
        currentText = null
        // Texts follow the messages.
        val message = queue.removeFirstOrNull() ?: run {
            val text = textQueue.removeFirstOrNull() ?: return close()
            return show(text)
        }
        val file = app.messages.file(message)
        if (!file.exists()) return playNext()
        current = message
        video = null
        // A natural clip gets a few seconds to arrive, since nothing is counting down.
        announcer.speak(BedsideMessages.announcement(app, message, slots), naturalWait = 3_000) { play(message) }
    }

    @OptIn(UnstableApi::class)
    private fun play(message: FamilyMessage) {
        if (ended || current?.id != message.id) return
        val player = ExoPlayer.Builder(app).build()
        player.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(
            if (message.mode == "video") C.AUDIO_CONTENT_TYPE_MOVIE else C.AUDIO_CONTENT_TYPE_SPEECH).build(), false)
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) completed(message)
            }

            // A file that can't play is skipped, and stays queued for a caregiver to look at.
            override fun onPlayerError(error: PlaybackException) {
                if (ended || current?.id != message.id) return
                release()
                current = null
                playNext()
            }
        })
        player.setMediaItem(MediaItem.fromUri(app.messages.file(message).toURI().toString()))
        player.prepare()
        player.play()
        this.player = player
        if (message.mode == "video") video = player
    }

    private fun completed(message: FamilyMessage) {
        if (ended || current?.id != message.id) return
        release()
        current = null
        app.messages.markPlayed(message)
        playNext()
    }

    /** A text: who it's from and when, then its words in the bedside's language, read aloud. */
    private fun show(text: ReceivedText) {
        current = null
        video = null
        currentText = text
        // The detector reads the words off the main thread while who they're from is said.
        foreign = app.scope.async(Dispatchers.Default) { BedsideMessages.otherLanguage(app, text) }
        announcer.speak(BedsideMessages.textAnnouncement(app, text.from, text.sentAt, slots)) { read(text) }
    }

    private fun read(text: ReceivedText) {
        if (ended || currentText?.id != text.id) return
        if (text.text.isEmpty()) return readAttachments(text)
        app.scope.launch {
            val other = runCatching { foreign?.await() }.getOrNull()
            if (ended || currentText?.id != text.id) return@launch
            // Its own language's built-in voice when this tablet has one. Without one, the bedside's voice reads it, with an
            // accent, rather than not at all. A reading that's cut off or fails otherwise isn't tried again in another voice.
            val locale = other?.let(Locale::forLanguageTag)?.takeIf(app.speech::hasVoice)
            // A long text's natural reading gets longer to arrive than an announcement.
            announcer.speak(text.text, chime = false, textID = text.id, voiceLocale = locale, naturalWait = 8_000) { said ->
                if (said) readAttachments(text) else unread(text)
            }
        }
    }

    /** Its words couldn't be read aloud. It stays on screen a moment, then waits for another time, as a message that can't
     * play does: only a text read to the end leaves the queue, and reading it deletes its words on the server. */
    private fun unread(text: ReceivedText) = finishText(text, read = false)

    private fun readAttachments(text: ReceivedText) {
        if (ended || currentText?.id != text.id) return
        val note = BedsideMessages.attachmentSentence(app, text) ?: return finishText(text)
        // The words were already said. A picture by itself is only this sentence, so if it couldn't be said the text
        // waits, as one whose words couldn't be read does: reporting it read deletes it on the server.
        announcer.speak(note, chime = false) { said -> if (said || text.text.isNotEmpty()) finishText(text) else unread(text) }
    }

    /** Read to the end, so it won't show again. It stays on screen a moment before the next one. */
    private fun finishText(text: ReceivedText, read: Boolean = true) {
        if (ended || currentText?.id != text.id) return
        if (read) app.messages.markRead(text)
        hold = app.scope.launch {
            delay(TEXT_HOLD)
            if (!ended && currentText?.id == text.id) playNext()
        }
    }

    /** Stopping early leaves the message showing queued for another time. */
    fun stop() = close()

    /** Closes at once for a call. */
    fun interrupt() {
        if (ended) return
        interrupted = true
        close()
    }

    private fun close() {
        if (ended) return
        ended = true
        announcer.stop()
        hold?.cancel(); hold = null
        foreign?.cancel(); foreign = null
        release()
        current = null
        currentText = null
        onFinish(this)
    }

    private fun release() {
        video = null
        player?.release()
        player = null
    }

    private companion object {
        const val TEXT_HOLD = 8_000L
    }
}

/** A text: who it's from and when, its words as large as fits, what's true of them, and the words as sent under a
 * translation. A short one sits in the middle of the room above Stop; a long one scrolls. */
@Composable
private fun TextShowing(playback: MessagePlayback, text: ReceivedText) {
    val length = text.text.length
    // Labels take the width, so a long text wraps rather than being cut off.
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Photo(playback.textPhoto(text), Modifier.size(140.dp))
        Text(playback.textTitle(text), Modifier.fillMaxWidth(), color = PorchColors.nightText, fontSize = 40.sp, fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center)
        Text(playback.textDetail(text), Modifier.fillMaxWidth().padding(bottom = 20.dp), color = PorchColors.nightSecondary, fontSize = 26.sp,
            textAlign = TextAlign.Center)
        if (text.text.isNotEmpty()) Text(text.text, Modifier.fillMaxWidth().padding(bottom = 12.dp), color = PorchColors.nightText,
            fontSize = when { length <= 80 -> 52.sp; length <= 200 -> 44.sp; length <= 500 -> 36.sp; else -> 30.sp },
            fontWeight = FontWeight.Medium, textAlign = if (length <= 200) TextAlign.Center else TextAlign.Start)
        val notes = playback.textNotes(text)
        if (notes.isNotEmpty()) Text(notes.joinToString("\n"), Modifier.fillMaxWidth(), color = PorchColors.nightSecondary, fontSize = 22.sp,
            textAlign = TextAlign.Center)
        if (text.translated && text.body.isNotEmpty()) Text(text.body, Modifier.fillMaxWidth(), color = PorchColors.nightSecondary, fontSize = 26.sp,
            textAlign = TextAlign.Center)
    }
}

/** The screen while messages play: who each is from and when, or the video with them in a banner, and Stop. */
@OptIn(UnstableApi::class)
@Composable
fun MessagePlayerScreen(app: PorchApplication, playback: MessagePlayback) = LargeType {
    KeepScreenOn()
    BackHandler { playback.stop() }
    // Leaving the screen stops it, as iOS stops when the iPad goes to the background. Turning the tablet, or plugging
    // the keypad in, recreates this activity and is still the same screen.
    val activity = LocalActivity.current
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { if (activity?.isChangingConfigurations != true) playback.stop() }
    // The messages key stops it, and so does the call key people already know.
    CallKeys(app, onDigit = { digit ->
        val action = runCatching { CallSlots.load(app.settings, app.photos).action(digit) }.getOrNull()
        if (action == KeypadAction.MESSAGES || action == KeypadAction.CALL_CONTROL) playback.stop()
    }, onHangUp = { "hang-up ignored while messages play" })
    val message = playback.current
    val video = playback.video
    val text = playback.currentText
    Box(Modifier.fillMaxSize().background(PorchColors.night)) {
        if (video != null) ContentFrame(video, Modifier.fillMaxSize())
        Column(Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 32.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            if (message != null && video != null) {
                // Who and when, kept on screen over the video.
                Text("${playback.title(message)} · ${playback.detail(message)}", Modifier
                    .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(24.dp)).padding(horizontal = 28.dp, vertical = 14.dp),
                    color = Color.White, fontSize = 30.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 2)
            }
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                // Each text starts at its top, however far the one before was scrolled.
                if (text != null) key(text.id) { TextShowing(playback, text) }
                if (message != null && video == null) Column(Modifier.offset(y = (-30).dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    Photo(playback.photo(message), Modifier.size(240.dp))
                    Text(playback.title(message), color = PorchColors.nightText, fontSize = 48.sp, fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center)
                    Text(playback.detail(message), color = PorchColors.nightSecondary, fontSize = 28.sp, textAlign = TextAlign.Center)
                }
            }
            Button(onClick = playback::stop, modifier = Modifier.heightIn(min = 96.dp), contentPadding = PaddingValues(horizontal = 48.dp, vertical = 24.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0.68f, 0.19f, 0.19f), contentColor = Color.White)) {
                Text(BedsideText.string(app, "Stop"), fontSize = 36.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}
