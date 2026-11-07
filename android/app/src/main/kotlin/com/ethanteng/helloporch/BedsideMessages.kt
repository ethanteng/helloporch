package com.ethanteng.helloporch

import android.icu.text.DateFormat
import android.icu.util.ULocale
import android.os.SystemClock
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.ethanteng.helloporch.core.BedsideMessageQueue
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyMessage
import com.ethanteng.helloporch.core.FamilySnapshot
import com.ethanteng.helloporch.core.MessageSender
import com.ethanteng.helloporch.core.PorchExperience
import java.io.File
import java.io.IOException
import java.util.Date
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
 * on the keypad is let through here; other phone voicemail waits for a caregiver. Texts to the Porch number come in phase
 * 5's second part. Main thread only.
 */
class BedsideMessages(private val app: PorchApplication) {
    /** Downloaded messages that haven't been played here, oldest first. */
    var ready by mutableStateOf<List<FamilyMessage>>(emptyList())
        private set
    val waitingCount: Int get() = ready.size

    private val downloading = mutableSetOf<String>()
    /** When a failed download may be tried again, in elapsed real time. */
    private val retryAfter = mutableMapOf<String, Long>()
    /** Played here, and hidden at once, before the server confirms. */
    private val played = mutableSetOf<String>()
    /** Played here, but the server hasn't heard yet. */
    private val unreported = mutableSetOf<String>()
    private val releasing = mutableSetOf<String>()
    private val folder get() = File(app.filesDir, "Porch/Messages")
    /** A video message can be 100 MB. */
    private val client by lazy { OkHttpClient.Builder().callTimeout(10, TimeUnit.MINUTES).build() }

    /** Messages playing on the screen, while they are. */
    var playback by mutableStateOf<MessagePlayback?>(null)
        private set

    fun file(message: FamilyMessage) = File(folder, "${message.id}.${message.fileExtension}")

    /** Plays what's waiting, from the clock's button or the messages key. False when nothing is ready to play. */
    fun play(): Boolean {
        if (playback != null) return true
        val messages = ready.takeIf { it.isNotEmpty() } ?: return false
        val slots = runCatching { CallSlots.load(app.settings, app.photos) }.getOrNull() ?: return false
        val created = MessagePlayback(app, messages, slots) { if (playback === it) playback = null }
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
        played.retainAll(ids); unreported.retainAll(ids); releasing.retainAll(ids)
        val slots = if (all.any { it.held == true }) runCatching { CallSlots.load(app.settings, app.photos) }.getOrNull() else null
        for (message in BedsideMessageQueue.releasable(all, slots, releasing)) releaseKnownCaller(message, credential)
        val queue = BedsideMessageQueue.waiting(all, played)
        // Removed, expired and played messages leave the tablet too.
        val keep = queue.map { file(it).name }.toSet()
        val partial = downloading.toSet()
        folder.listFiles()?.filter { it.name !in keep && it.name.substringBefore('.') !in partial }?.forEach { it.delete() }
        val nowReady = queue.filter { file(it).exists() }
        if (nowReady != ready) ready = nowReady
        for (id in unreported.toList()) report(id, credential)
        // Don't compete with a call for bandwidth.
        if (state.busy) return
        val now = SystemClock.elapsedRealtime()
        for (message in queue) {
            if (message.id in downloading || file(message).exists() || (retryAfter[message.id] ?: 0) > now) continue
            download(message, credential)
        }
    }

    /** Played to the end: it leaves the queue for good, and the sender sees it was played. */
    fun markPlayed(message: FamilyMessage) {
        played += message.id
        app.device.credential(PorchExperience.BEDSIDE)?.let { report(message.id, it) }
        sync()
    }

    /** What a tablet set up as a new Porch leaves behind: the old household's messages. */
    fun forget() {
        playback?.stop()
        ready = emptyList()
        downloading.clear(); retryAfter.clear(); played.clear(); unreported.clear(); releasing.clear()
        folder.deleteRecursively()
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
                if (!stillPaired(credential)) return@launch
                runCatching { app.service(credential).send("messageDelivered", mapOf("messageID" to JsonPrimitive(message.id))) }
                sync()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w("Porch", "Couldn't download message ${message.id}: ${e.message}")
                downloading -= message.id
                retryAfter[message.id] = SystemClock.elapsedRealtime() + 60_000
            }
        }
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

        /** Who it's from, as the bedside shows and says it, in its own language for an unknown caller. */
        fun sender(app: PorchApplication, message: FamilyMessage, slots: CallSlots): Pair<String, MessageSender> {
            val sender = BedsideMessageQueue.sender(message, slots, ::displayNumber)
            return (sender.name ?: BedsideText.string(app, "Unknown caller")) to sender
        }

        /** "Message from Ethan. Sent today at 3:05 PM.", as the bedside says it before playing. */
        fun announcement(app: PorchApplication, message: FamilyMessage, slots: CallSlots) = BedsideText.string(app,
            if (message.kind == "voicemail") "Voicemail from %@. Sent %@." else "Message from %@. Sent %@.", sender(app, message, slots).first,
            sentText(app, message.sentAt))

        /** When it was sent, in the bedside's language: today and yesterday by name, as iOS's relative formatting does. */
        fun sentText(app: PorchApplication, sentAt: Long): String {
            val locale = ULocale.forLocale(BedsideText.language(app).locale)
            return DateFormat.getDateTimeInstance(DateFormat.RELATIVE_MEDIUM, DateFormat.SHORT, locale).format(Date(sentAt * 1_000))
        }
    }
}
