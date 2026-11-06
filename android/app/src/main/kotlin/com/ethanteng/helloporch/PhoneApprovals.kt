package com.ethanteng.helloporch

import com.ethanteng.helloporch.core.FamilyServiceException
import com.ethanteng.helloporch.core.PorchExperience
import com.ethanteng.helloporch.core.PorchJson
import com.ethanteng.helloporch.core.SecretStore
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * The server's approval for Porch to call a keypad number when Porch isn't answered, as iOS's
 * `NativeCallSettings.authorizePhone` gets it: the server checks the caregiver PIN and that it can call that country,
 * and signs the number for 30 days. Saving a number gets a new one, so a number it can't call is refused while the
 * caregiver is there to hear why. Phone fallback sends it when it calls (android/PLAN.md, phase 3). Approvals are kept
 * with the PIN, readable only while the tablet is unlocked.
 */
object PhoneApprovals {
    private class Approval(val authorization: String, val expiresAt: Long) {
        fun encoded() = JsonObject(mapOf("authorization" to JsonPrimitive(authorization), "expiresAt" to JsonPrimitive(expiresAt))).toString()

        companion object {
            fun decoded(text: String): Approval? = runCatching {
                val json = PorchJson.parseToJsonElement(text).jsonObject
                Approval(json.getValue("authorization").jsonPrimitive.content, json.getValue("expiresAt").jsonPrimitive.long)
            }.getOrNull()
        }
    }

    private val client by lazy { OkHttpClient.Builder().callTimeout(20, TimeUnit.SECONDS).build() }

    /** The approval for `number`, a new one when `refresh` is set or the saved one has less than five minutes left. */
    suspend fun authorize(app: PorchApplication, number: String, refresh: Boolean = false): String {
        val credential = app.device.credential(PorchExperience.BEDSIDE) ?: throw FamilyServiceException("Open caregiver mode to finish setup.", 409)
        val pin = app.caregiverPIN
        // One approval per server, pairing, PIN and number, as iOS names its Keychain items.
        val scope = JsonArray(listOf(credential.origin, credential.credential, pin, number).map(::JsonPrimitive)).toString()
        val account = "porch.phone-approval." + MessageDigest.getInstance("SHA-256").digest(scope.toByteArray()).joinToString("") { "%02x".format(it) }
        val now = System.currentTimeMillis() / 1000
        if (!refresh) {
            val saved = app.secrets.read(account)?.let { Approval.decoded(it.decodeToString()) }
            if (saved != null && saved.expiresAt > now + 300) return saved.authorization
        }
        if (pin.isEmpty()) throw FamilyServiceException("Set your caregiver PIN before adding phone numbers.", 403)
        val (status, body) = withContext(Dispatchers.IO) {
            val request = Request.Builder().url("${credential.origin}/api/calls/contacts/authorize")
                .header("Authorization", "Bearer ${credential.credential}")
                .header("X-Porch-Setup-Code", pin)
                .post(JsonObject(mapOf("phoneNumber" to JsonPrimitive(number))).toString().toRequestBody("application/json".toMediaType()))
                .build()
            try {
                client.newCall(request).execute().use { it.code to it.body.string() }
            } catch (_: IOException) {
                throw FamilyServiceException("Couldn't save this number. Check your internet and try again.", 0)
            }
        }
        if (status != 200) {
            val reason = runCatching { PorchJson.parseToJsonElement(body).jsonObject.getValue("error").jsonPrimitive.content }.getOrNull()
            throw FamilyServiceException(reason ?: "Couldn't save this number. Check your internet and try again.", status)
        }
        val approval = Approval.decoded(body)
        if (approval == null || approval.authorization.isEmpty() || approval.authorization.length > 1000 ||
            approval.expiresAt <= now + 300 || approval.expiresAt > now + 31 * 24 * 60 * 60) {
            throw FamilyServiceException("The calling server returned an invalid phone approval.", 502)
        }
        app.secrets.write(account, approval.encoded().encodeToByteArray(), SecretStore.Access.WHEN_UNLOCKED)
        return approval.authorization
    }
}
