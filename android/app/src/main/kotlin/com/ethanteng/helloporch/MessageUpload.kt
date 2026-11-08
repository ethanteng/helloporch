package com.ethanteng.helloporch

import com.ethanteng.helloporch.core.FamilyCredential
import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.MessageRecordingCheck
import com.ethanteng.helloporch.core.MessageUploadTarget
import com.ethanteng.helloporch.core.SentMessage
import java.io.File
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody

/** A recorded message: its file, "audio" or "video", its content type, and its length in seconds. */
class MessageRecording(val file: File, val mode: String, val contentType: String, val durationSeconds: Double)

/**
 * Sends a recording as iOS's MessageUploader does: the server signs a one-time upload URL and the file goes straight to
 * storage, then the message is completed. A retry reuses the same message, so a dropped connection doesn't use up
 * another place in the queue, and an upload that already finished is only completed. Main thread only.
 */
class MessageUpload {
    private class Pending(val file: File, val message: SentMessage, val target: MessageUploadTarget, var uploaded: Boolean = false)
    private var pending: Pending? = null

    /** `kind` is "message" or "voicemail". `to` names the family member a bedside message is for; family devices always
     * send to the bedside. Throws with the reason it didn't go: code "upload" when storage turned the file away. */
    suspend fun send(app: PorchApplication, recording: MessageRecording, kind: String, credential: FamilyCredential, to: String? = null): SentMessage {
        val service = app.service(credential)
        val now = System.currentTimeMillis() / 1_000
        val current = pending
        // A new recording, or an upload link that's about to expire before the file went up, needs a new message.
        if (current == null || current.file != recording.file || (!current.uploaded && current.target.expiresAt < now + 60)) {
            val size = withContext(Dispatchers.IO) { recording.file.length() }
            val values = buildMap<String, JsonElement> {
                put("mode", JsonPrimitive(recording.mode))
                put("kind", JsonPrimitive(kind))
                put("contentType", JsonPrimitive(recording.contentType))
                put("sizeBytes", JsonPrimitive(size))
                put("durationSeconds", JsonPrimitive(recording.durationSeconds.coerceIn(1.0, MessageRecordingCheck.MAX_SECONDS)))
                to?.let { put("to", JsonPrimitive(it)) }
            }
            val created = service.send("createMessage", values)
            val message = created.message
            val target = created.upload
            if (message == null || target == null) throw FamilyServiceException("Couldn't send the message. Try again.", 503)
            pending = Pending(recording.file, message, target)
        }
        val upload = pending ?: throw FamilyServiceException("Couldn't send the message. Try again.", 503)
        // The signed URL never overwrites, so a finished upload is only completed on retry.
        if (!upload.uploaded) {
            val status = withContext(Dispatchers.IO) {
                val body = recording.file.asRequestBody(recording.contentType.toMediaTypeOrNull())
                val request = Request.Builder().url(upload.target.url).method(upload.target.method, body)
                // Exactly the headers the server signed, Content-Type among them.
                upload.target.headers.forEach { (name, value) -> request.header(name, value) }
                client.newCall(request.build()).execute().use { it.code }
            }
            if (status !in 200..299) throw FamilyServiceException("The upload didn't finish. Check the connection and try again.", status, "upload")
            upload.uploaded = true
        }
        val sent = try {
            service.send("completeMessage", mapOf("messageID" to JsonPrimitive(upload.message.id))).message ?: upload.message
        } catch (e: FamilyServiceException) {
            // Gone, unsent, expired, or a recording the server rejected ("Record the message again"): that id can't be
            // completed, so sending again starts a new one. A full inbox, a blob not visible yet, or a busy server still
            // can, and another message would use up a place in the queue. Those stay pending and are only completed.
            if (e.status == 404 || "Record the message again" in e.message) pending = null
            throw e
        }
        pending = null
        return sent
    }

    private companion object {
        /** Up to ten minutes for a two-minute video on a slow connection, as on iOS. */
        val client: OkHttpClient by lazy { OkHttpClient.Builder().callTimeout(600, TimeUnit.SECONDS).build() }
    }
}
