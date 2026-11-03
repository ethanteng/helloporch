package com.ethanteng.helloporch.core

import java.io.File
import java.nio.file.Files
import java.util.UUID
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.decodeFromJsonElement

/** What the model and keypad tests build from: JSON made from plain values, as the iOS tests make it from dictionaries,
 * and settings with a photo folder of their own. */
internal object ModelFixtures {
    const val bedsideID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

    /** A store for tests that never save a photo. */
    val noPhotos = ContactPhotoStore(File("/nonexistent/porch-test-photos"))

    fun json(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is JsonElement -> value
        is String -> JsonPrimitive(value)
        is Number -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
        is Map<*, *> -> JsonObject(value.entries.associate { (key, item) -> key as String to json(item) })
        is List<*> -> JsonArray(value.map(::json))
        else -> error("Not JSON: $value")
    }

    inline fun <reified T> decoded(value: Any?): T = PorchJson.decodeFromJsonElement(json(value))
    inline fun <reified T> parsed(text: String): T = PorchJson.decodeFromString(text)

    fun snapshot(people: List<Any?> = emptyList(), me: String = bedsideID, role: String = "bedside", householdName: String = "Pat",
        dropInEnabled: Boolean = false, extra: Map<String, Any?> = emptyMap()): FamilySnapshot =
        decoded(mapOf("householdID" to "home", "householdName" to householdName, "dropInEnabled" to dropInEnabled,
            "me" to mapOf("id" to me, "name" to householdName, "role" to role, "permissions" to mapOf("audio" to false, "video" to false), "online" to true),
            "people" to people, "busy" to false, "serverTime" to 1) + extra)

    fun person(id: String, name: String, invitationID: String? = null, photoID: String? = null, dropIns: Boolean = false): Map<String, Any?> =
        mapOf("id" to id, "invitationID" to invitationID, "name" to name, "role" to "family", "photoID" to photoID,
            "permissions" to mapOf("audio" to dropIns, "video" to dropIns), "online" to true)

    /** Settings, and a photo store in a folder that doesn't exist until a photo is saved. Both go afterwards. */
    fun withStore(body: (MemorySettings, ContactPhotoStore) -> Unit) {
        val directory = Files.createTempDirectory("porch-core").toFile()
        try { body(MemorySettings(), ContactPhotoStore(File(directory, "ContactPhotos"))) } finally { directory.deleteRecursively() }
    }

    /** A new ID, written as iOS writes them. */
    fun uuid(): String = UUID.randomUUID().toString().uppercase()
}
