package com.ethanteng.helloporch

import android.content.Context
import android.icu.text.DateFormat
import android.icu.util.ULocale
import android.os.SystemClock
import android.util.Log
import android.view.textclassifier.TextClassificationManager
import android.view.textclassifier.TextLanguage
import androidx.annotation.WorkerThread
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.ethanteng.helloporch.core.BedsideLanguage
import com.ethanteng.helloporch.core.BedsideMessageQueue
import com.ethanteng.helloporch.core.CallContact
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyMessage
import com.ethanteng.helloporch.core.FamilySnapshot
import com.ethanteng.helloporch.core.FamilyText
import com.ethanteng.helloporch.core.MessageSender
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.PorchJson
import com.ethanteng.helloporch.core.ReceivedText
import java.io.File
import java.io.IOException
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Keeps the family's waiting messages downloaded on the bedside, so they play at once and without a connection, and tells
 * each sender theirs arrived and was played, as iOS's BedsideMessages does. Phone voicemail from a verified caller saved
 * on the keypad is let through here; other phone voicemail waits for a caregiver. Texts to the Porch number are kept the
 * same way, ready in the bedside's language, and show after the messages. Main thread only.
 */
class BedsideMessages(private val app: PorchApplication) {
    /** Downloaded messages that haven't been played here, oldest first. */
    var ready by mutableStateOf<List<FamilyMessage>>(emptyList())
        private set
    /** Texts prepared in the bedside's language that haven't been read here, oldest first. */
    var readyTexts by mutableStateOf<List<ReceivedText>>(emptyList())
        private set
    /** What's ready to play, messages and texts together. */
    val waitingCount: Int get() = ready.size + readyTexts.size

    /** A text's words still waiting to be read, or null once it was read, removed, or is being fetched again. */
    fun preparedText(id: String): ReceivedText? = readyTexts.firstOrNull { it.id == id }

    private val downloading = mutableSetOf<String>()
    /** When a failed download may be tried again, in elapsed real time. */
    private val retryAfter = mutableMapOf<String, Long>()
    /** Played here, and hidden at once, until the server drops them. Kept across restarts, so a message played without a
     * connection isn't offered again as new after the tablet restarts. */
    private val played: MutableSet<String> by lazy { loadIDs(PLAYED_KEY) }
    /** Played here, but the server hasn't heard yet. After a restart that's all of [played]: telling it again is harmless. */
    private val unreported: MutableSet<String> by lazy { played.toMutableSet() }
    /** The server heard these arrived, though a check-in may not show it yet. */
    private val delivered = mutableSetOf<String>()
    private val delivering = mutableSetOf<String>()
    private val releasing = mutableSetOf<String>()
    private val fetchingTexts = mutableSetOf<String>()
    /** Read here, and hidden at once, until the server drops them. Kept across restarts, as played messages are. */
    private val readTexts: MutableSet<String> by lazy { loadIDs(READ_KEY) }
    private val unreportedTexts: MutableSet<String> by lazy { readTexts.toMutableSet() }
    private val folder get() = File(app.filesDir, "Porch/Messages")
    private val textFolder get() = File(app.filesDir, "Porch/Texts")
    /** A video message can be 100 MB. */
    private val client by lazy { OkHttpClient.Builder().callTimeout(10, TimeUnit.MINUTES).build() }

    /** Messages playing on the screen, while they are. */
    var playback by mutableStateOf<MessagePlayback?>(null)
        private set

    fun file(message: FamilyMessage) = File(folder, "${message.id}.${message.fileExtension}")

    /** Plays what's waiting, from the clock's button or the messages key. False when nothing is ready to play, or a call
     * is ringing, up, or still starting: iOS won't start messages while one is opening. */
    fun play(): Boolean {
        if (playback != null) return true
        if (app.calls.busy) return false
        val messages = ready
        val texts = readyTexts
        if (messages.isEmpty() && texts.isEmpty()) return false
        // A keypad that can't be read still plays. Names fall back to the family member's, or the caller's number.
        val slots = runCatching { CallSlots.load(app.settings, app.photos) }.getOrElse { CallSlots() }
        val created = MessagePlayback(app, messages, texts, slots) { if (playback === it) playback = null }
        playback = created
        created.start()
        return true
    }

    /** A call takes over from the messages playing. */
    fun interrupt() = playback?.interrupt()

    /** After each check-in, and after a download or a message played to the end. */
    fun sync(state: FamilySnapshot? = app.coordinator.links.value.state) {
        if (app.device.experience != PorchExperience.BEDSIDE || state?.me?.role != PorchExperience.BEDSIDE) return
        val credential = app.device.credential(PorchExperience.BEDSIDE) ?: return
        val all = state.messages.orEmpty()
        val ids = all.map { it.id }.toSet()
        if (played.retainAll(ids)) savePlayed()
        unreported.retainAll(ids); delivered.retainAll(ids); releasing.retainAll(ids)
        val slots = if (all.any { it.held == true }) runCatching { CallSlots.load(app.settings, app.photos) }.getOrNull() else null
        for (message in BedsideMessageQueue.releasable(all, slots, releasing)) releaseKnownCaller(message, credential)
        val queue = BedsideMessageQueue.waiting(all, played)
        // Removed, expired and played messages leave the tablet too.
        val keep = queue.map { file(it).name }.toSet()
        val partial = downloading.toSet()
        folder.listFiles()?.filter { it.name !in keep && it.name.substringBefore('.') !in partial }?.forEach { it.delete() }
        val nowReady = queue.filter { file(it).exists() }
        if (nowReady != ready) ready = nowReady
        // The sender sees it arrived. Asked again each check-in until the server shows it, so a dropped connection right
        // after a download doesn't leave it undelivered.
        for (message in nowReady) if (!message.delivered && message.id !in delivered && message.id !in delivering) deliver(message, credential)
        for (id in unreported.toList()) report(id, credential)
        // Texts from numbers the household doesn't know wait for a caregiver, like phone voicemail.
        val allTexts = state.texts.orEmpty()
        val textIDs = allTexts.map { it.id }.toSet()
        if (readTexts.retainAll(textIDs)) saveIDs(READ_KEY, readTexts)
        unreportedTexts.retainAll(textIDs)
        val textQueue = BedsideMessageQueue.waitingTexts(allTexts, readTexts)
        val keepTexts = textQueue.map { textFile(it.id).name }.toSet()
        textFolder.listFiles()?.filter { it.name !in keepTexts }?.forEach { gone ->
            savedText(gone.nameWithoutExtension)?.let(::forgetReading)
            gone.delete()
        }
        // Each is prepared in the bedside's language. One kept from before a language change is fetched again.
        val language = BedsideText.language(app).code
        val nowReadyTexts = textQueue.mapNotNull { savedText(it.id) }.filter { it.language == language }
        if (nowReadyTexts != readyTexts) readyTexts = nowReadyTexts
        for (id in unreportedTexts.toList()) reportRead(id, credential)
        // Don't compete with a call for bandwidth.
        if (state.busy) return
        val now = SystemClock.elapsedRealtime()
        for (message in queue) {
            if (message.id in downloading || file(message).exists() || (retryAfter[message.id] ?: 0) > now) continue
            download(message, credential)
        }
        for (text in textQueue) {
            if (text.id in fetchingTexts || savedText(text.id)?.language == language || (retryAfter[text.id] ?: 0) > now) continue
            fetch(text, credential)
        }
    }

    /** Read to the end: the text leaves the queue for good, and its words are deleted on the server. */
    fun markRead(text: ReceivedText) {
        readTexts += text.id
        saveIDs(READ_KEY, readTexts)
        app.device.credential(PorchExperience.BEDSIDE)?.let { reportRead(text.id, it) }
        sync()
    }

    /** Played to the end: it leaves the queue for good, and the sender sees it was played. */
    fun markPlayed(message: FamilyMessage) {
        played += message.id
        savePlayed()
        app.device.credential(PorchExperience.BEDSIDE)?.let { report(message.id, it) }
        sync()
    }

    /** What a tablet set up as a new Porch leaves behind: the old household's messages. */
    fun forget() {
        playback?.stop()
        ready = emptyList()
        readyTexts = emptyList()
        downloading.clear(); retryAfter.clear(); played.clear(); unreported.clear(); delivered.clear(); releasing.clear()
        readTexts.clear(); unreportedTexts.clear()
        saveIDs(PLAYED_KEY, played); saveIDs(READ_KEY, readTexts)
        folder.deleteRecursively()
        textFolder.deleteRecursively()
    }

    private fun download(message: FamilyMessage, credential: FamilyCredential) {
        downloading += message.id
        app.scope.launch {
            try {
                val media = app.service(credential).send("messageMedia", mapOf("messageID" to JsonPrimitive(message.id))).media
                    ?: throw IOException("Missing message link.")
                val destination = file(message)
                withContext(Dispatchers.IO) {
                    folder.mkdirs()
                    val part = File(folder, destination.name + PART)
                    client.newCall(Request.Builder().url(media.url).build()).execute().use { response ->
                        if (!response.isSuccessful) throw IOException("Couldn't download the message: ${response.code}")
                        part.outputStream().use { output -> response.body.byteStream().copyTo(output) }
                    }
                    // Not played, so not delivered: the tablet became another household's bedside meanwhile.
                    if (!stillPaired(credential)) { part.delete(); return@withContext }
                    if (!part.renameTo(destination)) { part.delete(); throw IOException("Couldn't keep the message.") }
                }
                downloading -= message.id
                // Then the sync tells the server it arrived.
                if (stillPaired(credential)) sync()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w("Porch", "Couldn't download message ${message.id}: ${e.message}")
                downloading -= message.id
                retryAfter[message.id] = SystemClock.elapsedRealtime() + 60_000
            }
        }
    }

    private fun deliver(message: FamilyMessage, credential: FamilyCredential) {
        delivering += message.id
        app.scope.launch {
            try {
                app.service(credential).send("messageDelivered", mapOf("messageID" to JsonPrimitive(message.id)))
                delivered += message.id
            } catch (e: CancellationException) { throw e } catch (_: Exception) {
            } finally { delivering -= message.id }
        }
    }

    private fun savePlayed() = saveIDs(PLAYED_KEY, played)

    private fun loadIDs(key: String) = app.settings.getString(key)?.split('\n')?.filter { it.isNotEmpty() }.orEmpty().toMutableSet()

    private fun saveIDs(key: String, ids: Set<String>) = if (ids.isEmpty()) app.settings.remove(key) else app.settings.putString(key, ids.joinToString("\n"))

    private fun textFile(id: String) = File(textFolder, "$id.json")

    private fun savedText(id: String): ReceivedText? =
        runCatching { PorchJson.decodeFromString(ReceivedText.serializer(), textFile(id).readText()) }.getOrNull()

    /** The server translates a text the first time it's fetched in a language, which can take a while for a long one. */
    private fun fetch(text: FamilyText, credential: FamilyCredential) {
        fetchingTexts += text.id
        app.scope.launch {
            try {
                val received = app.service(credential).send("textMessage", mapOf("textID" to JsonPrimitive(text.id))).text
                    ?.takeIf { it.id == text.id } ?: throw IOException("Missing text.")
                if (!stillPaired(credential)) return@launch
                // Fetched again in a new language: the earlier reading goes, though the words may be the same.
                savedText(text.id)?.let(::forgetReading)
                withContext(Dispatchers.IO) {
                    textFolder.mkdirs()
                    val destination = textFile(text.id)
                    val temporary = File.createTempFile("text", ".json", app.cacheDir)
                    try {
                        temporary.writeText(PorchJson.encodeToString(ReceivedText.serializer(), received))
                        // cacheDir and filesDir can be different drives. Copy when a rename can't cross them.
                        if (!temporary.renameTo(destination)) temporary.copyTo(destination, overwrite = true)
                    } finally {
                        temporary.delete()
                    }
                }
                // Still in fetchingTexts, so this sync won't start another fetch for the same text. Taking the id out
                // before sync, and again in finally, dropped a refetch that sync had just begun.
                sync()
                if (stillPaired(credential) && preparedText(text.id) != null) prefetchReadings()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w("Porch", "Couldn't fetch text ${text.id}: ${e.message}")
                retryAfter[text.id] = SystemClock.elapsedRealtime() + 60_000
            } finally {
                fetchingTexts -= text.id
            }
        }
    }

    private fun reportRead(id: String, credential: FamilyCredential) {
        unreportedTexts -= id
        app.scope.launch {
            try { app.service(credential).send("textRead", mapOf("textID" to JsonPrimitive(id))) }
            catch (e: CancellationException) { throw e } catch (_: Exception) { unreportedTexts += id }
        }
    }

    /** The words are on the tablet, so their natural reading can be fetched before anyone presses Play. */
    private fun prefetchReadings() {
        val state = app.coordinator.links.value.state ?: return
        val slots = runCatching { CallSlots.load(app.settings, app.photos) }.getOrNull() ?: return
        NaturalVoice.prefetch(app, state, slots)
    }

    /** A text's natural readings are its words, so they go with it. */
    private fun forgetReading(text: ReceivedText) {
        if (text.text.isEmpty()) return
        BedsideLanguage.entries.firstOrNull { it.code == text.language }?.let { NaturalVoice.forget(app, text.text, it) }
    }

    private fun stillPaired(credential: FamilyCredential) = app.device.credential(PorchExperience.BEDSIDE)?.credential == credential.credential

    private fun releaseKnownCaller(message: FamilyMessage, credential: FamilyCredential) {
        releasing += message.id
        app.scope.launch {
            // The next check-in carries it as released. After a failure, a later sync tries again.
            try { app.service(credential).send("releaseKnownCaller", mapOf("messageID" to JsonPrimitive(message.id))) }
            catch (e: CancellationException) { throw e } catch (_: Exception) { releasing -= message.id }
        }
    }

    private fun report(id: String, credential: FamilyCredential) {
        unreported -= id
        app.scope.launch {
            try { app.service(credential).send("messagePlayed", mapOf("messageID" to JsonPrimitive(id))) }
            catch (e: CancellationException) { throw e } catch (_: Exception) { unreported += id }
        }
    }

    companion object {
        private const val PART = ".part"
        private const val PLAYED_KEY = "porch.messages.played.v1"
        private const val READ_KEY = "porch.texts.read.v1"

        /** Who it's from, as the bedside shows and says it, in its own language for an unknown caller. */
        fun sender(app: PorchApplication, message: FamilyMessage, slots: CallSlots): Pair<String, MessageSender> {
            val sender = BedsideMessageQueue.sender(message, slots, ::displayNumber)
            return (sender.name ?: BedsideText.string(app, "Unknown caller")) to sender
        }

        /** "Message from Ethan. Sent today at 3:05 PM.", as the bedside says it before playing. */
        fun announcement(app: PorchApplication, message: FamilyMessage, slots: CallSlots) = BedsideText.string(app,
            if (message.kind == "voicemail") "Voicemail from %@. Sent %@." else "Message from %@. Sent %@.", sender(app, message, slots).first,
            sentText(app, message.sentAt))

        /** Who a text is from, as the bedside shows and says it: the keypad contact saved with that number, then the name a
         * caregiver gave it for phone drop-in, or the number itself. Texts show by themselves only from numbers the household
         * knows, so they borrow its names as caller ID would. */
        fun textSender(app: PorchApplication, from: String, slots: CallSlots): Pair<String, CallContact?> {
            slots.contact(from)?.let { return it.name to it }
            app.coordinator.links.value.state?.phoneDropIns?.firstOrNull { it.number == from }?.let { return it.name to null }
            return (if (from.startsWith("+")) displayNumber(from) else from) to null
        }

        /** "Text from David. Sent today at 3:05 PM.", as the bedside says it before reading one. */
        fun textAnnouncement(app: PorchApplication, from: String, sentAt: Long, slots: CallSlots) =
            BedsideText.string(app, "Text from %@. Sent %@.", textSender(app, from, slots).first, sentText(app, sentAt))

        /** What came with a text, as the screen shows it: pictures, then anything else, such as a contact card. */
        fun attachmentNotes(app: PorchApplication, text: ReceivedText): List<String> {
            val pictures = text.pictures ?: 0
            return listOfNotNull(
                when {
                    pictures < 1 -> null
                    pictures == 1 -> BedsideText.string(app, "It came with a picture, which Porch can't show yet.")
                    else -> BedsideText.string(app, "It came with %d pictures, which Porch can't show yet.", pictures)
                },
                if ((text.attachments ?: 0) > 0) BedsideText.string(app, "It came with something Porch can't show yet.") else null)
        }

        /** The same, as the bedside says it after the words. */
        fun attachmentSentence(app: PorchApplication, text: ReceivedText): String? = attachmentNotes(app, text).takeIf { it.isNotEmpty() }?.joinToString(" ")

        /** "Translated from Spanish", in the bedside's language. */
        fun translatedNote(app: PorchApplication, sourceLanguage: String?): String? {
            val tag = sourceLanguage ?: return null
            val name = Locale.forLanguageTag(tag).getDisplayLanguage(BedsideText.language(app).locale).takeIf { it.isNotEmpty() && it != tag } ?: return null
            return BedsideText.string(app, "Translated from %@", name)
        }

        /** Words the server named as written in another language, which Porch couldn't translate. Their reading isn't fetched
         * ahead in the bedside's voice. */
        fun knownForeign(text: ReceivedText): Boolean =
            !text.translated && text.sourceLanguage?.let { !BedsideMessageQueue.sameLanguage(it, text.language) } == true

        /**
         * Words Porch couldn't translate, written in a language other than the bedside's: read in that language's built-in
         * voice rather than with the bedside voice's accent. The server names the language when it can tell; otherwise
         * Android's own detector guesses, except on a Tagalog bedside, which it would call something else, as Apple's does.
         * Off the main thread: the detector can take a moment.
         */
        @WorkerThread
        fun otherLanguage(app: PorchApplication, text: ReceivedText): String? {
            if (text.translated) return null
            val bedside = BedsideText.language(app)
            val tag = text.sourceLanguage ?: if (bedside == BedsideLanguage.TAGALOG) null else detectLanguage(app, text.text)
            // The language only, never the words.
            return tag?.takeIf { !BedsideMessageQueue.sameLanguage(it, bedside.code) }?.also { Log.i("Porch", "A text is read in its own language: $it") }
        }

        private fun detectLanguage(context: Context, words: String): String? = runCatching {
            val classifier = context.getSystemService(TextClassificationManager::class.java)?.textClassifier ?: return null
            val result = classifier.detectLanguage(TextLanguage.Request.Builder(words).build())
            if (result.localeHypothesisCount == 0) return null
            val top = result.getLocale(0)
            top.toLanguageTag().takeIf { result.getConfidenceScore(top) >= 0.6f }
        }.getOrNull()

        /** When it was sent, in the bedside's language: today and yesterday by name, as iOS's relative formatting does. */
        fun sentText(app: PorchApplication, sentAt: Long): String {
            val locale = ULocale.forLocale(BedsideText.language(app).locale)
            return DateFormat.getDateTimeInstance(DateFormat.RELATIVE_MEDIUM, DateFormat.SHORT, locale).format(Date(sentAt * 1_000))
        }
    }
}
