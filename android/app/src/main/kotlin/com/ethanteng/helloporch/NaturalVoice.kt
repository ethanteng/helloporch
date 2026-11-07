package com.ethanteng.helloporch

import android.os.SystemClock
import com.ethanteng.helloporch.core.BedsideLanguage
import com.ethanteng.helloporch.core.CallSlots
import com.ethanteng.helloporch.core.FamilySnapshot
import com.ethanteng.helloporch.core.PorchExperience
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * The household's natural announcement voice: the server reads each sentence in the voice a caregiver chose
 * (lib/family/speech.ts) and this tablet keeps the clip, named for the voice, the language and the words, as iOS keeps
 * them. Until a clip is here, announcements use text-to-speech. A call or a drop-in never waits for one, so [prefetch]
 * is how they get the natural voice. Main thread only, apart from the downloads.
 */
object NaturalVoice {
    private val client by lazy {
        OkHttpClient.Builder().callTimeout(15, TimeUnit.SECONDS).followRedirects(false).build()
    }
    /** When each sentence was last fetched, so one that couldn't be is tried again only after ten minutes. */
    private val attempted = mutableMapOf<String, Long>()
    private var prefetching: Job? = null
    private var prefetchAgain = false

    /** The household's natural voice for a language, when this paired bedside has one. */
    fun selected(app: PorchApplication, language: BedsideLanguage): String? {
        if (app.device.experience != PorchExperience.BEDSIDE) return null
        return app.coordinator.links.value.state?.speech?.choices(language)?.selected
    }

    /** The clip for `text`, if this tablet has it. */
    fun cached(app: PorchApplication, text: String, language: BedsideLanguage, voiceID: String): File? =
        file(app, text, language, voiceID).takeIf { it.exists() }

    /** The clip for `text` if it's here, or arrives within `millis`. One that arrives later is kept for next time.
     * `textID` names the text whose words these are, which the server reads though they're longer than an announcement. */
    suspend fun clip(app: PorchApplication, text: String, language: BedsideLanguage, voiceID: String, millis: Long, textID: String? = null): File? {
        cached(app, text, language, voiceID)?.let { return it }
        if (millis <= 0) return null
        val pending = app.scope.async { load(app, text, language, voiceID, textID) }
        return withTimeoutOrNull(millis) { pending.await() }
    }

    /**
     * Prepares what the bedside may say next, one sentence at a time: drop-in announcements for everyone who may drop
     * in, who it's calling for everyone it can call, and who each waiting message is from. Texts and the voicemail
     * recorder's prompts come with their parts of phase 5.
     */
    fun prefetch(app: PorchApplication, state: FamilySnapshot, slots: CallSlots) {
        val language = BedsideText.language(app)
        val voiceID = state.speech?.choices(language)?.selected ?: return
        // A snapshot that arrives while a pass is reading sentences runs it once more afterwards.
        if (prefetching?.isActive == true) { prefetchAgain = true; return }
        val contacts = slots.contacts.filterNotNull()
        val texts = mutableListOf<String>()
        if (state.dropInEnabled) {
            for (person in state.people.filter { it.role == PorchExperience.FAMILY }) {
                val name = contacts.firstOrNull { it.familyMemberID == person.id }?.name ?: person.name
                if (person.permissions.video) texts += Announcer.dropInMessage(app, name, video = true)
                if (person.permissions.audio) texts += Announcer.dropInMessage(app, name, video = false)
            }
            for (approval in state.phoneDropIns.orEmpty()) {
                val name = contacts.firstOrNull { approval.number in it.phoneNumbers }?.name ?: approval.name
                texts += Announcer.dropInMessage(app, name, video = false)
            }
        }
        contacts.forEach { texts += Announcer.callingMessage(app, it.name) }
        /** A text's words, read with its ID: they can be longer than an announcement. */
        val words = mutableListOf<Pair<String, String>>()
        if (state.messagesEnabled != false) {
            for (message in state.messages.orEmpty().filter { it.held != true }) texts += BedsideMessages.announcement(app, message, slots)
            for (text in state.texts.orEmpty().filter { !it.held }) texts += BedsideMessages.textAnnouncement(app, text.from, text.sentAt, slots)
            // The server reads up to 600 characters of a text's words in a natural voice (`textLimits.spokenCharacters`).
            for (text in app.messages.readyTexts) {
                BedsideMessages.attachmentSentence(app, text)?.let { texts += it }
                if (text.text.isNotEmpty() && text.text.length <= 600 && !BedsideMessages.knownForeign(text)) words += text.text to text.id
            }
        }
        val now = SystemClock.elapsedRealtime()
        val pending = (texts.map { it to null } + words).distinctBy { it.first }.filter { (text, _) ->
            val key = file(app, text, language, voiceID).name
            !file(app, text, language, voiceID).exists() && attempted[key]?.let { now - it > 600_000 } != false
        }
        if (pending.isEmpty()) return
        pending.forEach { attempted[file(app, it.first, language, voiceID).name] = now }
        prefetching = app.scope.launch {
            for ((text, textID) in pending) load(app, text, language, voiceID, textID)
            if (prefetchAgain) {
                prefetchAgain = false
                app.coordinator.links.value.state?.let { prefetch(app, it, slots) }
            }
        }
    }

    /** A text's readings in every voice, once the text is read or gone: they're its words. */
    fun forget(app: PorchApplication, text: String, language: BedsideLanguage) {
        for (voice in app.coordinator.links.value.state?.speech?.choices(language)?.voices.orEmpty()) file(app, text, language, voice.id).delete()
    }

    /** Asks the server to read `text` and keeps the clip. Null when it isn't available. */
    private suspend fun load(app: PorchApplication, text: String, language: BedsideLanguage, voiceID: String, textID: String? = null): File? {
        val destination = file(app, text, language, voiceID)
        if (destination.exists()) return destination
        val credential = app.device.credential(PorchExperience.BEDSIDE) ?: return null
        return try {
            val values = buildMap {
                put("language", JsonPrimitive(language.code)); put("text", JsonPrimitive(text)); put("voiceID", JsonPrimitive(voiceID))
                textID?.let { put("textID", JsonPrimitive(it)) }
            }
            val response = app.service(credential).send("speech", values)
            val clip = response.clip ?: return null
            if (clip.voiceID != voiceID || !clip.url.startsWith("https://")) return null
            withContext(Dispatchers.IO) {
                client.newCall(Request.Builder().url(clip.url).build()).execute().use { http ->
                    val bytes = http.body.bytes()
                    if (http.code != 200 || bytes.isEmpty() || bytes.size > 2_000_000) return@withContext null
                    destination.parentFile?.mkdirs()
                    val partial = File(destination.path + ".part")
                    partial.writeBytes(bytes)
                    if (partial.renameTo(destination)) destination else null
                }
            }?.let { saved ->
                // Read, removed, or fetched again while this ran. The clip is named for the words and the voice, so a text
                // that left, or whose wording changed, mustn't keep it.
                if (textID == null) return@let saved
                val prepared = app.messages.preparedText(textID)
                if (prepared?.language == language.code && prepared.text == text) saved else { saved.delete(); null }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
    }

    private fun file(app: PorchApplication, text: String, language: BedsideLanguage, voiceID: String): File {
        val key = MessageDigest.getInstance("SHA-256").digest("$voiceID|${language.code}|$text".toByteArray())
            .joinToString("") { "%02x".format(it) }
        return File(File(app.cacheDir, "PorchSpeech"), "$key.mp3")
    }
}
