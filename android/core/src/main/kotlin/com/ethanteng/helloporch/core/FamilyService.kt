package com.ethanteng.helloporch.core

import java.io.IOException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

@Serializable
data class FamilyResponse(
    val pushReady: Boolean? = null,
    val pinConfigured: Boolean? = null,
    val state: FamilySnapshot? = null,
    val credential: String? = null,
    val role: PorchExperience? = null,
    val code: String? = null,
    val invitationID: String? = null,
    val expiresAt: Long? = null,
    val token: String? = null,
    val serverUrl: String? = null,
    val admin: FamilyAdminState? = null,
    /** Family devices only: this device's sent messages (`listMessages`). */
    val messages: List<SentMessage>? = null,
    /** Family devices only: messages the bedside left for this device (`listMessages`). */
    val received: List<ReceivedMessage>? = null,
    val alertsReady: Boolean? = null,
    val message: SentMessage? = null,
    val upload: MessageUploadTarget? = null,
    val media: MessageMediaURL? = null,
    /** Where an uploaded profile photo goes (`profilePhotoUpload`, `overridePhotoUpload`). */
    val pathname: String? = null,
    /** A family member's photo (`profilePhoto`, `caregiverProfilePhoto`). */
    val photo: ProfilePhotoURL? = null,
    /** A sentence read in the household's natural voice (`speech`). */
    val clip: SpeechClip? = null,
    /** A text to show and read on the bedside (`textMessage`). */
    val text: ReceivedText? = null,
    /** Waiting texts with their words, for caregiver review (`caregiverTexts`). */
    val texts: List<FamilyText>? = null,
    /** The phone this caregiver just added to their call (`addPhoneGuest`). */
    val phoneGuest: FamilyPhoneGuest? = null,
    /** The family member just rung into the call (`addPorchGuest`). */
    val porchGuest: FamilyPorchGuest? = null,
    /** Calls to and from the bedside, newest first (`callHistory`). */
    val calls: List<CallHistoryEntry>? = null,
    /** The household's number once it's set up (`assignPhoneNumber`), or `pending` while Porch keeps trying. */
    val porchNumber: String? = null,
    val pending: Boolean? = null,
    /** The area code suggested from where the iPad is, and others near it (`phoneNumberOptions`). None outside the US. */
    val areaCode: String? = null,
    val nearby: List<String>? = null,
)

/** A short-lived link to an announcement clip, and the voice that read it. */
@Serializable
data class SpeechClip(val voiceID: String, val url: String, val expiresAt: Long)

/** A presigned upload: send the file as the body with exactly these headers. */
@Serializable
data class MessageUploadTarget(val url: String, val method: String, val headers: Map<String, String>, val expiresAt: Long)

/** A short-lived link to one message's audio or video. */
@Serializable
data class MessageMediaURL(val url: String, val expiresAt: Long, val contentType: String)

/** A short-lived link to a family member's photo, with the content ID its bytes must match. */
@Serializable
data class ProfilePhotoURL(val id: String, val url: String, val expiresAt: Long)

/** Status 0: the server couldn't be reached. */
class FamilyServiceException(override val message: String, val status: Int, val code: String? = null) : Exception(message)

class FamilyService(val origin: String, val credential: String?, private val transport: FamilyTransport) {
    constructor(credential: FamilyCredential, transport: FamilyTransport) : this(credential.origin, credential.credential, transport)

    suspend fun send(
        action: String,
        values: Map<String, JsonElement> = emptyMap(),
        pin: String? = null,
        timeoutSeconds: Long = timeoutFor(action),
    ): FamilyResponse {
        val body = JsonObject(mapOf("action" to JsonPrimitive(action)) + values.filterKeys { it != "action" })
        // No Origin header: the server turns away cross-origin requests.
        val headers = buildMap {
            put("Content-Type", "application/json")
            credential?.let { put("Authorization", "Bearer $it") }
            pin?.let { put("X-Porch-Setup-Code", it) }
        }
        val response = try {
            transport.post("${origin.removeSuffix("/")}/api/family", headers, body.toString(), timeoutSeconds * 1000)
        } catch (_: IOException) {
            // A request cut off because it was cancelled is cancelled, not unreachable.
            currentCoroutineContext().ensureActive()
            throw FamilyServiceException(unreachable, 0)
        }
        currentCoroutineContext().ensureActive()
        if (response.status != 200) {
            val failure = decodedOrNull(Failure.serializer(), response.body)
            throw FamilyServiceException(failure?.error ?: unreachable, response.status, failure?.errorCode)
        }
        return decodedOrNull(FamilyResponse.serializer(), response.body) ?: throw FamilyServiceException(unreachable, response.status)
    }

    @Serializable
    private class Failure(val error: String, val errorCode: String? = null)

    private fun <T> decodedOrNull(serializer: KSerializer<T>, body: String): T? =
        try { PorchJson.decodeFromString(serializer, body) } catch (_: IllegalArgumentException) { null }

    companion object {
        internal const val unreachable = "Couldn't reach Porch. Check the connection and try again."

        /** Seconds to wait for each action's answer. */
        fun timeoutFor(action: String): Long = when (action) {
            "addPhoneGuest" -> 25
            "speech" -> 30
            "textMessage" -> 40
            "assignPhoneNumber" -> 45
            else -> 12
        }
    }
}
