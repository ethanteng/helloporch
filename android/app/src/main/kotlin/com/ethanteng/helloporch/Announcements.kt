package com.ethanteng.helloporch

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.ethanteng.helloporch.core.BedsideLanguage
import com.ethanteng.helloporch.core.BedsidePreferences
import com.ethanteng.helloporch.core.CallTone
import java.io.File
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What the bedside says, played only on this device and never in a call. */
private val speechAttributes: AudioAttributes =
    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()

/**
 * Android's text-to-speech, started once for the bedside. The engine writes each sentence to a file and Porch plays it,
 * so the sound comes from the app on screen: Android 16 mutes playback from apps in the background, which the speech
 * engine's own app is. The engine takes a moment to start, so a sentence asked for before then waits. Main thread only.
 */
class BedsideSpeech(context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val folder = File(context.cacheDir, "PorchSpeech/spoken")
    /** null while the engine starts, then whether it did. */
    private var ready: Boolean? = null
    /** Completes with [ready] once the engine has started, so a voice check can wait instead of guessing. */
    private val started = CompletableDeferred<Boolean>()
    /** Sentences asked for while the engine starts, by ID and in order, so [stop] can take one back. */
    private val queued = linkedMapOf<String, () -> Unit>()
    /** Sentences being written, by ID, with what to do once they are. */
    private val writing = mutableMapOf<String, (Boolean) -> Unit>()
    private val players = mutableMapOf<String, MediaPlayer>()
    private val engine: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        main.post {
            ready = status == TextToSpeech.SUCCESS
            val starting = queued.values.toList()
            queued.clear()
            starting.forEach { it() }
            // After this callback returns. A waiter that then speaks must not re-enter the engine from inside it.
            if (!started.isCompleted) main.post { if (!started.isCompleted) started.complete(ready == true) }
        }
    }

    init {
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String) {}
            override fun onDone(utteranceId: String) = written(utteranceId, true)
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String) = written(utteranceId, false)
            override fun onError(utteranceId: String, errorCode: Int) = written(utteranceId, false)
            override fun onStop(utteranceId: String, interrupted: Boolean) = written(utteranceId, false)
        })
    }

    /**
     * Says `text` in `language`, in the caregiver's chosen voice when this engine has it, and calls `done` with whether
     * it was said. False straight away when the engine has no voice for the language. Returns an ID for [stop].
     */
    fun speak(text: String, language: BedsideLanguage, voiceName: String?, done: (Boolean) -> Unit): String = say(text, done) {
        val voice = voiceName?.let { name -> engine.voices?.firstOrNull { it.name == name && language.supportsSpeechVoice(it.locale.toLanguageTag()) } }
        if (voice != null) engine.setVoice(voice) == TextToSpeech.SUCCESS else engine.setLanguage(language.locale) >= TextToSpeech.LANG_AVAILABLE
    }

    /**
     * Whether this tablet's engine has a voice for `locale`, once the engine has started. Suspends until it has.
     * False when it failed to start, or it has no voice for `locale`. Main thread only.
     */
    suspend fun hasVoice(locale: Locale): Boolean {
        if (!started.await()) return false
        return engine.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE
    }

    /** Says `text` in `locale`'s built-in voice, such as a text's words that Porch couldn't translate. */
    fun speak(text: String, locale: Locale, done: (Boolean) -> Unit): String =
        say(text, done) { engine.setLanguage(locale) >= TextToSpeech.LANG_AVAILABLE }

    /** `voice` picks the voice once the engine has started, and says whether it has one. */
    private fun say(text: String, done: (Boolean) -> Unit, voice: () -> Boolean): String {
        val id = UUID.randomUUID().toString()
        val start = start@{
            if (ready != true) { done(false); return@start }
            if (!voice()) { done(false); return@start }
            folder.mkdirs()
            val file = File(folder, "$id.wav")
            writing[id] = { ok -> if (ok) play(id, file, done) else { file.delete(); done(false) } }
            if (engine.synthesizeToFile(text, null, file, id) != TextToSpeech.SUCCESS) written(id, false)
        }
        if (ready == null) queued[id] = start else start()
        return id
    }

    /** The engine's voices for `language`, by name, for caregiver settings. Empty until the engine has started. */
    fun voices(language: BedsideLanguage): List<android.speech.tts.Voice> =
        if (ready != true) emptyList()
        else engine.voices.orEmpty().filter { language.supportsSpeechVoice(it.locale.toLanguageTag()) }.sortedBy { it.name }

    /** Stops `id`, waiting for the engine, being written or being said. Its `done` isn't called. */
    fun stop(id: String) {
        queued.remove(id)
        if (writing.remove(id) != null) engine.stop()
        players.remove(id)?.let { runCatching { it.stop() }; it.release() }
        File(folder, "$id.wav").delete()
    }

    private fun written(id: String, success: Boolean) {
        main.post { writing.remove(id)?.invoke(success) }
    }

    private fun play(id: String, file: File, done: (Boolean) -> Unit) {
        val player = MediaPlayer()
        val finish = { said: Boolean ->
            if (players.remove(id) != null) { player.release(); file.delete(); done(said) }
        }
        try {
            player.setAudioAttributes(speechAttributes)
            player.setDataSource(file.path)
            player.setOnCompletionListener { finish(true) }
            player.setOnErrorListener { _, _, _ -> finish(false); true }
            player.prepare()
            players[id] = player
            player.start()
        } catch (_: Exception) {
            player.release()
            file.delete()
            done(false)
        }
    }
}

/**
 * Says something on the bedside: who it's calling as a call starts, and a drop-in before it connects. The announcement
 * chime, then the sentence in the household's natural voice if this tablet already has the clip, or else
 * text-to-speech in the bedside's language. It never waits for a clip to download. A watchdog of 15 seconds from when
 * the sentence starts keeps a stuck speech engine from holding a call or quietly starting a video drop-in.
 * The Android counterpart of iOS's PorchIncomingAudio. Main thread only; one sentence at a time.
 */
class Announcer(private val app: PorchApplication) {
    private val chime = TonePlayer(AudioAttributes.USAGE_MEDIA)
    private val scope = MainScope()
    private var clip: MediaPlayer? = null
    private var speaking: String? = null
    private var startJob: Job? = null
    private var watchdog: Job? = null
    private var completion: ((Boolean) -> Unit)? = null
    /** How long a sentence may take once it starts: 15 seconds, or longer for a text's words. */
    private var limit = 15_000L

    /**
     * The chime, then `message`. `done` gets whether it was said, and isn't called after [stop]. The voices are the
     * saved ones unless caregiver settings pass the ones being chosen, to preview them; a preview waits up to
     * `naturalWait` milliseconds for a natural clip that isn't here yet, as iOS does. Without `chime` it goes on from
     * something already said, such as a text's words after who it's from: `textID` lets the server read them although
     * they're longer than an announcement, and `voiceLocale` reads words Porch couldn't translate in that language's
     * built-in voice.
     */
    fun speak(message: String, language: BedsideLanguage = BedsideText.language(app),
        voiceName: String? = BedsidePreferences.load(app.settings).announcementVoiceIdentifier(language),
        naturalVoice: String? = NaturalVoice.selected(app, language), naturalWait: Long = 0, chime: Boolean = true,
        textID: String? = null, voiceLocale: Locale? = null, done: (Boolean) -> Unit) {
        stop()
        completion = done
        // A text's words take longer to say than an announcement.
        limit = if (chime) 15_000 else 15_000 + message.length * 350L
        if (chime && !this.chime.play(CallTone.ANNOUNCEMENT)) { finish(false); return }
        val natural = naturalVoice.takeIf { voiceLocale == null }
        startJob = scope.launch {
            if (chime) delay((CallTone.ANNOUNCEMENT.duration * 1_000).toLong())
            // A call or a drop-in never waits for a clip; a preview of a voice just chosen fetches it.
            val ready = natural?.let { NaturalVoice.clip(app, message, language, it, naturalWait, textID) }
            if (ready != null && playClip(ready) { said -> if (said) finish(true) else { ready.delete(); speakBuiltIn(message, language, voiceName, voiceLocale) } }) {
                armWatchdog()
                return@launch
            }
            // A clip that couldn't start is broken.
            ready?.delete()
            speakBuiltIn(message, language, voiceName, voiceLocale)
        }
        // Until speech starts, so a stuck engine can't hold the call either.
        armWatchdog()
    }

    /** "Ethan is dropping in with video. Connecting in five seconds." */
    fun announceDropIn(name: String, video: Boolean, done: (Boolean) -> Unit) = speak(dropInMessage(app, name, video), done = done)

    fun stop() {
        completion = null
        startJob?.cancel(); startJob = null
        watchdog?.cancel(); watchdog = null
        speaking?.let { app.speech.stop(it) }; speaking = null
        clip?.let { runCatching { it.stop() }; it.release() }; clip = null
        chime.stop()
    }

    private fun speakBuiltIn(message: String, language: BedsideLanguage, voiceName: String?, voiceLocale: Locale? = null) {
        armWatchdog()
        val done = { said: Boolean -> speaking = null; finish(said) }
        speaking = if (voiceLocale != null) app.speech.speak(message, voiceLocale, done) else app.speech.speak(message, language, voiceName, done)
    }

    private fun playClip(file: File, done: (Boolean) -> Unit): Boolean = try {
        val player = MediaPlayer()
        player.setAudioAttributes(speechAttributes)
        player.setDataSource(file.path)
        player.setOnCompletionListener { if (clip === it) { clip = null; it.release(); done(true) } }
        player.setOnErrorListener { mp, _, _ -> if (clip === mp) { clip = null; mp.release(); done(false) }; true }
        player.prepare()
        player.start()
        clip = player
        true
    } catch (_: Exception) {
        false
    }

    private fun armWatchdog() {
        watchdog?.cancel()
        watchdog = scope.launch { delay(limit); finish(false) }
    }

    private fun finish(said: Boolean) {
        val done = completion
        stop()
        done?.invoke(said)
    }

    companion object {
        fun dropInMessage(app: PorchApplication, name: String, video: Boolean) = BedsideText.string(app,
            if (video) "%@ is dropping in with video. Connecting in five seconds." else "%@ is dropping in with audio. Connecting in five seconds.", name)

        fun callingMessage(app: PorchApplication, name: String) = BedsideText.string(app, "Calling %@.", name)
    }
}

/**
 * Says who the bedside is calling the moment a key is pressed, while the call is still being set up. The call's
 * ringback and its audio wait for the sentence, as on iOS, where joining the call cut the sentence off. Main thread only.
 */
class OutgoingAnnouncement(app: PorchApplication, name: String) {
    private val announcer = Announcer(app)
    private val waiting = mutableListOf<() -> Unit>()
    private val record: (String) -> Unit = { outcome -> app.cell2jack.record("callAnnouncementEnded", "outcome" to outcome) }
    var finished = false
        private set

    init {
        announcer.speak(Announcer.callingMessage(app, name), done = { said -> end(if (said) "said" else "not said") })
    }

    /** Runs `next` once the sentence is over: said, couldn't be said, or stopped. */
    fun then(next: () -> Unit) { if (finished) next() else waiting += next }

    suspend fun finished() {
        if (finished) return
        val done = kotlinx.coroutines.CompletableDeferred<Unit>()
        then { done.complete(Unit) }
        done.await()
    }

    fun stop() {
        announcer.stop()
        end("stopped")
    }

    private fun end(outcome: String) {
        if (finished) return
        finished = true
        record(outcome)
        val next = waiting.toList()
        waiting.clear()
        next.forEach { it() }
    }
}
