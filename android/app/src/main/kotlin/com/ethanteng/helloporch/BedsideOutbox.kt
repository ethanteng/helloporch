package com.ethanteng.helloporch

import android.util.Log
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.MessageOutbox
import com.ethanteng.helloporch.core.OutboxItem
import com.ethanteng.helloporch.core.OutboxOutcome
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.PorchJson
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer

/**
 * Messages the bedside left for family, kept on the tablet until they're sent, as iOS's BedsideOutbox keeps them. Mom
 * goes back to the clock right away, and uploads retry on their own, so a dropped connection doesn't lose a message.
 * Main thread only.
 */
class BedsideOutbox(private val app: PorchApplication) {
    private val folder = File(app.filesDir, "PorchOutbox")
    private val manifest = File(folder, "outbox.json")
    private var items = mutableListOf<OutboxItem>()
    private val uploads = mutableMapOf<String, MessageUpload>()
    private var sending = false
    private var started = false

    /** Reads what's waiting and sends what's due. A message whose recording is gone is dropped. */
    fun start() {
        if (started) return
        started = true
        items = runCatching { PorchJson.decodeFromString(ListSerializer(OutboxItem.serializer()), manifest.readText()) }.getOrDefault(emptyList())
            .filter { file(it).exists() }.toMutableList()
        send()
    }

    /** Keeps `recording` for each of `memberIDs`, such as both people on a group key, and sends it. A message has one
     * recipient, so each gets a copy of their own, which goes once it's sent. Throws when it can't be kept. */
    fun add(recording: MessageRecording, memberIDs: List<String>) {
        start()
        folder.mkdirs()
        val added = mutableListOf<OutboxItem>()
        try {
            memberIDs.forEachIndexed { index, memberID ->
                val id = UUID.randomUUID().toString()
                val name = "$id.${recording.file.extension}"
                val kept = File(folder, name)
                if (index < memberIDs.lastIndex) recording.file.copyTo(kept, overwrite = true)
                else if (!recording.file.renameTo(kept)) {
                    recording.file.copyTo(kept, overwrite = true)
                    recording.file.delete()
                }
                added += OutboxItem(id, name, memberID, recording.mode, recording.contentType, recording.durationSeconds, now())
            }
        } catch (e: Exception) {
            // None of it is kept, so no copy is left in the folder without its message.
            added.forEach { file(it).delete() }
            throw e
        }
        items += added
        save()
        send()
    }

    /**
     * Drops every message still waiting, when this tablet stops being their bedside: they're for a household it's no
     * longer in. An upload already under way finds its message gone. If the folder is still there, the empty list is
     * written down, so a later start doesn't send those recordings on.
     */
    fun discardAll() {
        items.clear()
        uploads.clear()
        folder.deleteRecursively()
        if (folder.exists()) save()
    }

    /** Sends the next message that's due, one at a time. Runs again after each check-in. */
    fun send() {
        if (sending || !started || app.device.experience != PorchExperience.BEDSIDE) return
        val credential = app.device.credential(PorchExperience.BEDSIDE) ?: return
        // Don't compete with a call for bandwidth.
        if (app.calls.busy || app.coordinator.links.value.state?.busy == true) return
        val item = MessageOutbox.next(items, now()) ?: return
        sending = true
        val upload = uploads.getOrPut(item.id) { MessageUpload() }
        val recording = MessageRecording(file(item), item.mode, item.contentType, item.durationSeconds)
        app.scope.launch {
            var failure: Exception? = null
            try {
                upload.send(app, recording, "voicemail", credential, to = item.to)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failure = e
            }
            finished(item, failure)
        }
    }

    private fun finished(item: OutboxItem, failure: Exception?) {
        sending = false
        val error = failure as? FamilyServiceException
        failure?.let { Log.w("Porch", "A message for family didn't send: ${it.message}") }
        val index = items.indexOfFirst { it.id == item.id }
        // Discarded while it was sending.
        if (index < 0) return
        when (MessageOutbox.outcome(item, failure != null, error?.status, error?.code, now())) {
            OutboxOutcome.SENT, OutboxOutcome.DROPPED -> {
                file(item).delete()
                items.removeAt(index)
                uploads.remove(item.id)
            }
            OutboxOutcome.RETRY_NEW_UPLOAD -> {
                uploads.remove(item.id)
                items[index] = MessageOutbox.retried(items[index], now())
            }
            OutboxOutcome.RETRY -> items[index] = MessageOutbox.retried(items[index], now())
        }
        save()
        send()
    }

    private fun file(item: OutboxItem) = File(folder, item.file)

    private fun save() {
        try {
            folder.mkdirs()
            val temporary = File(folder, "outbox.json.tmp")
            temporary.writeText(PorchJson.encodeToString(ListSerializer(OutboxItem.serializer()), items))
            if (!temporary.renameTo(manifest)) { manifest.delete(); temporary.renameTo(manifest) }
        } catch (e: Exception) {
            Log.w("Porch", "Couldn't save the outbox: ${e.message}")
        }
    }

    private fun now() = System.currentTimeMillis() / 1_000
}
