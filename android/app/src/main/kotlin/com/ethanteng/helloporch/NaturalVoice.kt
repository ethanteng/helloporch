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

    /** The clip for `text` if it's here, or arrives within `millis`. One that arrives later is kept for next time. */
    suspend fun clip(app: PorchApplication, text: String, language: BedsideLanguage, voiceID: String, millis: Long): File? {
        cached(app, text, language, voiceID)?.let { return it }
        if (millis <= 0) return null
        val pending = app.scope.async { load(app, text, language, voiceID) }
        return withTimeoutOrNull(millis) { pending.await() }
    }

    /**
     * Prepares what the bedside may say next, one sentence at a time: drop-in announcements for everyone who may drop
     * in, and who it's calling for everyone it can call. Messages' sentences come with messages (phase 5).
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
        // Until caregiver mode puts people on keys, the people screen calls family members who aren't on one too.
        state.people.filter { it.role == PorchExperience.FAMILY }.forEach { texts += Announcer.callingMessage(app, it.name) }
        val now = SystemClock.elapsedRealtime()
        val pending = texts.distinct().filter { text ->
            val key = file(app, text, language, voiceID).name
            !file(app, text, language, voiceID).exists() && attempted[key]?.let { now - it > 600_000 } != false
        }
        if (pending.isEmpty()) return
        pending.forEach { attempted[file(app, it, language, voiceID).name] = now }
        prefetching = app.scope.launch {
            for (text in pending) load(app, text, language, voiceID)
            if (prefetchAgain) {
                prefetchAgain = false
                app.coordinator.links.value.state?.let { prefetch(app, it, slots) }
            }
        }
    }

    /** Asks the server to read `text` and keeps the clip. Null when it isn't available. */
    private suspend fun load(app: PorchApplication, text: String, language: BedsideLanguage, voiceID: String): File? {
        val destination = file(app, text, language, voiceID)
        if (destination.exists()) return destination
        val credential = app.device.credential(PorchExperience.BEDSIDE) ?: return null
        return try {
            val response = app.service(credential).send("speech", mapOf("language" to JsonPrimitive(language.code),
                "text" to JsonPrimitive(text), "voiceID" to JsonPrimitive(voiceID)))
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
