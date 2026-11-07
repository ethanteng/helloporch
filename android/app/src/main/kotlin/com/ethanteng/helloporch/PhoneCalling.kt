package com.ethanteng.helloporch

import com.ethanteng.helloporch.core.LiveKitAddress
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.PorchJson
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * The bedside calling a regular phone, through the server's `/api/calls/phone` (lib/calls/phone.ts), as iOS's
 * NativeCallViewController.phoneRequest does: `prepare` gives a room for the phone's leg and a control token, `start`
 * dials once the bedside is in that room, and `end` hangs the phone up, even with a token that has since expired. The
 * bedside's own pairing authorizes them. A family phone can't use them.
 */
object PhoneCalling {
    class Prepared(val token: String, val serverUrl: String, val controlToken: String)

    class PhoneCallException(message: String) : Exception(message)

    private val client by lazy { OkHttpClient.Builder().callTimeout(25, TimeUnit.SECONDS).build() }
    private const val unreachable = "Couldn't reach the phone calling server. Check your connection and try again."

    /** A room for a call to `phoneNumber`. `contactAuthorization` is the caregiver's approval of the number (PhoneApprovals). */
    suspend fun prepare(app: PorchApplication, phoneNumber: String, name: String, contactAuthorization: String?): Prepared {
        val values = buildMap<String, JsonElement> {
            put("phoneNumber", JsonPrimitive(phoneNumber))
            put("name", JsonPrimitive(name))
            // The bedside plays ringback itself, so the phone's own ringing tone isn't sent.
            put("localRingback", JsonPrimitive(true))
            contactAuthorization?.let { put("contactAuthorization", JsonPrimitive(it)) }
        }
        val json = request(app, "prepare", JsonObject(values))
        val token = json.text("token")
        val url = json.text("serverUrl")
        val control = json.text("controlToken")
        // A phone's audio only ever goes over a secure address.
        if (token == null || control == null || url == null || !url.startsWith("wss://") || !LiveKitAddress.isAllowed(url)) {
            throw PhoneCallException("The calling server returned invalid phone call settings.")
        }
        return Prepared(token, url, control)
    }

    /** Rings their phone. Never repeated automatically: a new attempt prepares a new room. */
    suspend fun start(app: PorchApplication, controlToken: String) { request(app, "start", control(controlToken)) }

    /** Hangs their phone up and closes the room. */
    suspend fun end(app: PorchApplication, controlToken: String) { request(app, "end", control(controlToken)) }

    private fun control(token: String) = JsonObject(mapOf("controlToken" to JsonPrimitive(token)))

    private fun JsonObject.text(name: String): String? = runCatching { get(name)?.jsonPrimitive?.contentOrNull }.getOrNull()

    private suspend fun request(app: PorchApplication, action: String, body: JsonObject): JsonObject {
        val credential = app.device.credential(PorchExperience.BEDSIDE)
            ?: throw PhoneCallException("Go back to the clock and open caregiver mode to finish setup.")
        val (status, text) = withContext(Dispatchers.IO) {
            val request = Request.Builder().url("${credential.origin}/api/calls/phone/$action")
                .header("Authorization", "Bearer ${credential.credential}")
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .build()
            try {
                client.newCall(request).execute().use { it.code to it.body.string() }
            } catch (_: IOException) {
                throw PhoneCallException(unreachable)
            }
        }
        val json = runCatching { PorchJson.parseToJsonElement(text).jsonObject }.getOrNull()
        if (status != 200) throw PhoneCallException(json?.text("error") ?: unreachable)
        return json ?: throw PhoneCallException("The calling server returned invalid phone call settings.")
    }
}
